import AppKit
import KeyboardShortcuts
import Observation
import SwiftUI

struct Notice: Identifiable, Equatable {
    enum Kind { case error, warning, info }

    let id = UUID()
    let kind: Kind
    let text: String
}

struct Toast: Identifiable {
    let id = UUID()
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?
}

enum ImporterMode: Equatable {
    case add
    case relocate(UUID)
}

/// Coordinates the services and holds UI state, so views stay declarative.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()
    static let mainWindowID = "main"
    /// The search field appears once the library grows past this many sounds.
    static let searchThreshold = 8

    let library: SoundLibrary
    let audio: AudioEngineService
    let hotkeys: HotkeyService
    let launchAtLogin: LaunchAtLoginService
    let settings: AppSettings

    // MARK: UI state

    var selection: UUID?
    var editingID: UUID?
    var searchText = ""
    var isImporterPresented = false
    private(set) var importerMode: ImporterMode = .add
    private(set) var expandedIDs: Set<UUID> = []
    private(set) var notices: [Notice] = []
    private(set) var toast: Toast?
    private(set) var isImporting = false
    /// Bumped each time a sound's global hotkey fires; rows flash when their value changes.
    private(set) var flashTokens: [UUID: Int] = [:]
    /// Briefly true after a hotkey fires, to pulse the menu bar icon.
    private(set) var isMenuBarPulsing = false

    @ObservationIgnored private var didBootstrap = false
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var pulseTask: Task<Void, Never>?

    init(
        library: SoundLibrary? = nil,
        audio: AudioEngineService? = nil,
        hotkeys: HotkeyService? = nil,
        launchAtLogin: LaunchAtLoginService? = nil,
        settings: AppSettings? = nil
    ) {
        self.library = library ?? SoundLibrary()
        self.audio = audio ?? AudioEngineService()
        self.hotkeys = hotkeys ?? HotkeyService()
        self.launchAtLogin = launchAtLogin ?? LaunchAtLoginService()
        self.settings = settings ?? AppSettings()
    }

    // MARK: - Launch

    func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true

        applyDockIconPolicy()
        library.load()
        if let issue = library.loadIssue {
            post(.warning, issue, autoDismiss: false)
        }

        hotkeys.onTrigger = { [weak self] id in self?.hotkeyFired(id) }
        hotkeys.onStopAll = { [weak self] in self?.stopAll() }
        hotkeys.sync(with: library.items)
        hotkeys.purgeOrphans()

        audio.setMasterVolume(settings.masterVolume)
        audio.setKeepsEngineWarm(settings.keepsEngineWarm)
        let playable = library.items.filter { !library.isMissing($0.id) }
        Task {
            for item in playable {
                await audio.preload(item, url: library.fileURL(for: item))
            }
        }
    }

    func prepareForTermination() {
        library.saveNow()
    }

    // MARK: - Derived state

    var showsSearch: Bool { library.items.count > Self.searchThreshold }

    var visibleItems: [SoundItem] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard showsSearch, !query.isEmpty else { return library.items }
        return library.items.filter { $0.displayName.localizedCaseInsensitiveContains(query) }
    }

    var showsFirstRunHint: Bool { !settings.hasSeenHint }

    func shortcutText(for owner: HotkeyOwner) -> String? {
        hotkeys.shortcuts[owner]?.description
    }

    func name(of owner: HotkeyOwner) -> String {
        switch owner {
        case .sound(let id): "“\(library.item(id)?.displayName ?? "another sound")”"
        case .stopAll: "Stop All Sounds"
        }
    }

    // MARK: - Import

    func presentAddImporter() {
        importerMode = .add
        isImporterPresented = true
    }

    func presentRelocateImporter(for id: UUID) {
        importerMode = .relocate(id)
        isImporterPresented = true
    }

    func handleImporterResult(_ result: Result<[URL], Error>) {
        let mode = importerMode
        switch result {
        case .success(let urls):
            switch mode {
            case .add:
                importFiles(urls)
            case .relocate(let id):
                if let url = urls.first { relocate(id, from: url) }
            }
        case .failure(let error):
            post(.error, "The file picker failed: \(error.localizedDescription)")
        }
    }

    /// Entry point for the toolbar button, ⌘O, and drag-and-drop.
    func importFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        Task { await performImport(urls) }
    }

    func performImport(_ urls: [URL]) async {
        isImporting = true
        defer { isImporting = false }

        let report = await library.importFiles(urls)
        for item in report.added {
            await audio.preload(item, url: library.fileURL(for: item))
        }
        hotkeys.sync(with: library.items)

        for message in Self.failureMessages(for: report.failures) {
            post(.error, message)
        }
        for item in report.added where item.isLong {
            post(.warning, Self.longSoundMessage(for: item))
        }

        if let last = report.added.last {
            // Make sure the new row is visible, then let the user name it straight away.
            searchText = ""
            selection = last.id
            editingID = report.added.count == 1 ? last.id : nil
            if report.added.count > 1 {
                showToast("Added \(report.added.count) sounds")
            }
        }
    }

    static func failureMessages(for failures: [SoundImportError]) -> [String] {
        var messages: [String] = []
        let unsupported = failures.filter { if case .unsupportedType = $0 { true } else { false } }
        if unsupported.count == 1, let message = unsupported[0].errorDescription {
            messages.append(message)
        } else if unsupported.count > 1 {
            messages.append("\(unsupported.count) files were skipped because they aren’t supported audio. Soundbind accepts \(SoundLibrary.supportedFormatsText).")
        }
        for failure in failures where !unsupported.contains(failure) {
            if let message = failure.errorDescription { messages.append(message) }
        }
        return messages
    }

    static func longSoundMessage(for item: SoundItem) -> String {
        let length = item.duration.soundDurationText
        if item.isStreamed {
            return "“\(item.displayName)” is \(length) long, so it will stream from disk instead of loading into memory. It may start a touch later than short sounds."
        }
        return "“\(item.displayName)” is \(length) long. That works, but shortcuts feel snappiest with short clips."
    }

    private func relocate(_ id: UUID, from url: URL) {
        Task {
            do {
                try await library.relocate(id: id, from: url)
                if let item = library.item(id) {
                    await audio.preload(item, url: library.fileURL(for: item))
                    showToast("Relocated “\(item.displayName)”")
                }
            } catch {
                post(.error, error.localizedDescription)
            }
        }
    }

    // MARK: - Editing

    func select(_ id: UUID?) {
        if editingID != nil, editingID != id { editingID = nil }
        selection = id
    }

    func beginRenaming(_ id: UUID) {
        selection = id
        editingID = id
    }

    func commitRename(_ id: UUID, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            library.update(id) { $0.displayName = trimmed }
        }
        if editingID == id { editingID = nil }
    }

    func cancelRename(_ id: UUID) {
        if editingID == id { editingID = nil }
    }

    func setVolume(_ volume: Float, for id: UUID) {
        let clamped = min(max(volume, 0), 1)
        library.update(id) { $0.volume = clamped }
        audio.setVolume(clamped, for: id)
    }

    func setRetriggerMode(_ mode: RetriggerMode, for id: UUID) {
        library.update(id) { $0.retriggerMode = mode }
    }

    func setEnabled(_ enabled: Bool, for id: UUID) {
        library.update(id) { $0.isEnabled = enabled }
        hotkeys.sync(with: library.items)
    }

    func isExpanded(_ id: UUID) -> Bool { expandedIDs.contains(id) }

    func toggleExpanded(_ id: UUID) {
        if expandedIDs.contains(id) {
            expandedIDs.remove(id)
        } else {
            expandedIDs.insert(id)
        }
    }

    func duplicate(_ id: UUID) {
        guard let copy = library.duplicate(id: id) else {
            post(.error, "That sound couldn’t be duplicated because its file is missing.")
            return
        }
        hotkeys.sync(with: library.items)
        selection = copy.id
        Task { await audio.preload(copy, url: library.fileURL(for: copy)) }
    }

    func revealInFinder(_ id: UUID) {
        guard let item = library.item(id) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([library.fileURL(for: item)])
    }

    // MARK: - Delete / undo

    func deleteSelection(undoManager: UndoManager?) {
        guard let id = selection else { return }
        delete(id, undoManager: undoManager)
    }

    func delete(_ id: UUID, undoManager: UndoManager?) {
        // Pick the neighbour to select next before the row disappears.
        let visible = visibleItems
        var nextSelection: UUID?
        if selection == id, let index = visible.firstIndex(where: { $0.id == id }) {
            nextSelection = visible[safe: index + 1]?.id ?? visible[safe: index - 1]?.id
        } else {
            nextSelection = selection
        }

        guard let removed = library.remove(id: id) else { return }
        audio.unload(id)
        hotkeys.sync(with: library.items)
        expandedIDs.remove(id)
        if editingID == id { editingID = nil }
        selection = nextSelection

        let name = removed.item.displayName
        undoManager?.registerUndo(withTarget: self) { [weak undoManager] model in
            model.restore(removed, undoManager: undoManager)
        }
        undoManager?.setActionName("Delete “\(name)”")

        showToast("Deleted “\(name)”", actionTitle: "Undo") { [weak self, weak undoManager] in
            // Prefer the real undo stack so ⌘Z and the toast stay in step.
            if let undoManager, undoManager.canUndo, undoManager.undoActionName == "Delete “\(name)”" {
                undoManager.undo()
            } else {
                self?.restore(removed, undoManager: nil)
            }
        }
    }

    private func restore(_ removed: RemovedSound, undoManager: UndoManager?) {
        library.restore(removed)
        hotkeys.sync(with: library.items)
        let item = removed.item
        selection = item.id
        if !library.isMissing(item.id) {
            Task { await audio.preload(item, url: library.fileURL(for: item)) }
        }
        undoManager?.registerUndo(withTarget: self) { [weak undoManager] model in
            model.delete(item.id, undoManager: undoManager)
        }
        undoManager?.setActionName("Delete “\(item.displayName)”")
        dismissToast()
    }

    // MARK: - Playback

    /// Play/stop from the UI: a second press stops the sound.
    func togglePlayback(_ id: UUID) {
        guard let item = library.item(id) else { return }
        if audio.isPlaying(id) {
            audio.stop(id)
        } else {
            play(item)
        }
    }

    func toggleSelectionPlayback() {
        if let id = selection { togglePlayback(id) }
    }

    func stopAll() {
        audio.stopAll()
    }

    private func hotkeyFired(_ id: UUID) {
        guard let item = library.item(id), item.isEnabled else { return }
        play(item)
        flashTokens[id, default: 0] += 1
        pulseMenuBarIcon()
    }

    private func play(_ item: SoundItem) {
        guard !library.isMissing(item.id) else {
            post(.error, "“\(item.displayName)” can’t play because its file is missing. Use Relocate to pick it again.")
            return
        }
        let wasPlaying = audio.isPlaying(item.id)
        if !audio.play(item), !(wasPlaying && item.retriggerMode == .ignore) {
            post(.error, "“\(item.displayName)” couldn’t be played. Check that an audio output device is connected.")
        }
    }

    private func pulseMenuBarIcon() {
        pulseTask?.cancel()
        isMenuBarPulsing = true
        pulseTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            self?.isMenuBarPulsing = false
        }
    }

    // MARK: - Keyboard navigation

    func moveSelection(by offset: Int) {
        let visible = visibleItems
        guard !visible.isEmpty else { return }
        guard let current = selection, let index = visible.firstIndex(where: { $0.id == current }) else {
            select(offset >= 0 ? visible.first?.id : visible.last?.id)
            return
        }
        let target = min(max(index + offset, 0), visible.count - 1)
        select(visible[target].id)
    }

    // MARK: - Shortcuts

    func shortcutRecorded(_ shortcut: KeyboardShortcuts.Shortcut?, for owner: HotkeyOwner) {
        hotkeys.shortcutRecorded(shortcut, for: owner)
        if case .sound = owner, hotkeys.shortcuts[owner] != nil {
            settings.hasSeenHint = true
        }
    }

    func replaceConflictingShortcut(for owner: HotkeyOwner) {
        hotkeys.resolveConflictByReplacing(for: owner)
        if case .sound = owner { settings.hasSeenHint = true }
    }

    func dismissHint() {
        settings.hasSeenHint = true
    }

    // MARK: - Settings

    func setMasterVolume(_ volume: Float) {
        settings.masterVolume = volume
        audio.setMasterVolume(volume)
    }

    func setKeepsEngineWarm(_ keepWarm: Bool) {
        settings.keepsEngineWarm = keepWarm
        audio.setKeepsEngineWarm(keepWarm)
    }

    func setShowDockIcon(_ show: Bool) {
        settings.showDockIcon = show
        applyDockIconPolicy()
        // Switching policy deactivates the app; bring its windows back to the front.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func applyDockIconPolicy() {
        NSApp.setActivationPolicy(settings.showDockIcon ? .regular : .accessory)
    }

    // MARK: - Notices & toasts

    func post(_ kind: Notice.Kind, _ text: String, autoDismiss: Bool = true) {
        guard !notices.contains(where: { $0.text == text }) else { return }
        let notice = Notice(kind: kind, text: text)
        notices.append(notice)
        if notices.count > 4 { notices.removeFirst(notices.count - 4) }
        AccessibilityNotification.Announcement(text).post()
        guard autoDismiss else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(kind == .error ? 10 : 8))
            self?.dismissNotice(notice.id)
        }
    }

    func dismissNotice(_ id: UUID) {
        notices.removeAll { $0.id == id }
    }

    func showToast(_ message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        toastTask?.cancel()
        let toast = Toast(message: message, actionTitle: actionTitle, action: action)
        self.toast = toast
        AccessibilityNotification.Announcement(message).post()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(actionTitle == nil ? 2.5 : 5))
            guard !Task.isCancelled, self?.toast?.id == toast.id else { return }
            self?.toast = nil
        }
    }

    func dismissToast() {
        toastTask?.cancel()
        toast = nil
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
