import Foundation
import Observation
import OSLog
import UniformTypeIdentifiers

enum SoundImportError: LocalizedError, Equatable {
    case unsupportedType(fileName: String)
    case unreadable(fileName: String)
    case copyFailed(fileName: String)

    var fileName: String {
        switch self {
        case .unsupportedType(let name), .unreadable(let name), .copyFailed(let name): name
        }
    }

    var errorDescription: String? {
        switch self {
        case .unsupportedType(let name):
            "“\(name)” isn’t a supported audio file. Soundbind accepts \(SoundLibrary.supportedFormatsText)."
        case .unreadable(let name):
            "“\(name)” couldn’t be read as audio. The file may be damaged."
        case .copyFailed(let name):
            "“\(name)” couldn’t be copied into the Soundbind library."
        }
    }
}

struct ImportReport: Equatable {
    var added: [SoundItem] = []
    var failures: [SoundImportError] = []
}

/// A deleted sound, kept so the deletion can be undone.
struct RemovedSound: Equatable {
    let item: SoundItem
    let index: Int
}

/// Owns the list of sounds, their files on disk, and the JSON store.
@MainActor
@Observable
final class SoundLibrary {
    nonisolated static let supportedExtensions: Set<String> = ["mp3", "wav", "m4a", "aac", "aiff", "aif", "caf"]
    nonisolated static let supportedFormatsText = "MP3, WAV, M4A, AAC, AIFF and CAF"

    nonisolated static var supportedContentTypes: [UTType] {
        supportedExtensions.sorted().compactMap { UTType(filenameExtension: $0) }
    }

    nonisolated static var defaultRootURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let bundleID = Bundle.main.bundleIdentifier ?? "io.github.tusharonly.soundbind"
        return base.appendingPathComponent(bundleID, isDirectory: true)
    }

    private(set) var items: [SoundItem] = []
    /// Sounds whose audio file is no longer on disk.
    private(set) var missingFileIDs: Set<UUID> = []
    /// Set when the store existed but could not be decoded.
    private(set) var loadIssue: String?

    let rootURL: URL
    var soundsURL: URL { rootURL.appendingPathComponent("Sounds", isDirectory: true) }
    var trashURL: URL { rootURL.appendingPathComponent("Trash", isDirectory: true) }
    var storeURL: URL { rootURL.appendingPathComponent("library.json") }

    @ObservationIgnored private let saveDebounce: Duration
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let fileManager = FileManager.default
    @ObservationIgnored private let log = Logger(subsystem: "Soundbind", category: "SoundLibrary")

    init(rootURL: URL = SoundLibrary.defaultRootURL, saveDebounce: Duration = .milliseconds(500)) {
        self.rootURL = rootURL
        self.saveDebounce = saveDebounce
    }

    // MARK: - Loading

    /// Loads the store. A missing file yields an empty library; a corrupt file is
    /// moved aside as a backup and the library starts empty.
    func load() {
        createDirectories()
        purgeTrash()
        loadIssue = nil

        guard fileManager.fileExists(atPath: storeURL.path) else {
            items = []
            missingFileIDs = []
            return
        }

        do {
            let data = try Data(contentsOf: storeURL)
            items = try Self.makeDecoder().decode(LibrarySnapshot.self, from: data).items
        } catch {
            log.error("Library store unreadable: \(error.localizedDescription, privacy: .public)")
            let stamp = Int(Date().timeIntervalSince1970)
            let backup = rootURL.appendingPathComponent("library.corrupt-\(stamp).json")
            try? fileManager.moveItem(at: storeURL, to: backup)
            items = []
            loadIssue = "Your sound library couldn’t be read, so Soundbind started fresh. The old file was kept as “\(backup.lastPathComponent)”."
        }
        refreshMissingFiles()
    }

    func refreshMissingFiles() {
        missingFileIDs = Set(items.filter { !fileManager.fileExists(atPath: fileURL(for: $0).path) }.map(\.id))
    }

    // MARK: - Queries

    func item(_ id: UUID) -> SoundItem? {
        items.first { $0.id == id }
    }

    func fileURL(for item: SoundItem) -> URL {
        soundsURL.appendingPathComponent(item.fileName)
    }

    func isMissing(_ id: UUID) -> Bool {
        missingFileIDs.contains(id)
    }

    // MARK: - Import

    /// Copies the file into the library, validates it as audio, and appends a new item.
    /// If the audio can't be decoded, the copy is removed again.
    @discardableResult
    func importFile(at sourceURL: URL) async throws -> SoundItem {
        let originalName = sourceURL.lastPathComponent
        let stored = try copyIntoLibrary(sourceURL)

        do {
            let analysis = try await analyze(stored.url)
            let baseName = sourceURL.deletingPathExtension().lastPathComponent
            let item = SoundItem(
                id: stored.id,
                displayName: baseName.isEmpty ? "Untitled" : baseName,
                fileName: stored.url.lastPathComponent,
                duration: analysis.duration,
                waveform: analysis.waveform
            )
            items.append(item)
            scheduleSave()
            return item
        } catch {
            try? fileManager.removeItem(at: stored.url)
            throw SoundImportError.unreadable(fileName: originalName)
        }
    }

    func importFiles(_ urls: [URL]) async -> ImportReport {
        var report = ImportReport()
        for url in urls {
            do {
                report.added.append(try await importFile(at: url))
            } catch let error as SoundImportError {
                report.failures.append(error)
            } catch {
                report.failures.append(.unreadable(fileName: url.lastPathComponent))
            }
        }
        return report
    }

    /// Points an existing item at a new source file (used when its file went missing).
    func relocate(id: UUID, from sourceURL: URL) async throws {
        guard let existing = item(id) else { return }
        let stored = try copyIntoLibrary(sourceURL)
        do {
            let analysis = try await analyze(stored.url)
            let oldURL = fileURL(for: existing)
            update(id) {
                $0.fileName = stored.url.lastPathComponent
                $0.duration = analysis.duration
                $0.waveform = analysis.waveform
            }
            if oldURL != stored.url { try? fileManager.removeItem(at: oldURL) }
            missingFileIDs.remove(id)
        } catch {
            try? fileManager.removeItem(at: stored.url)
            throw SoundImportError.unreadable(fileName: sourceURL.lastPathComponent)
        }
    }

    private func copyIntoLibrary(_ sourceURL: URL) throws -> (id: UUID, url: URL) {
        let originalName = sourceURL.lastPathComponent
        let ext = sourceURL.pathExtension.lowercased()
        guard Self.supportedExtensions.contains(ext) else {
            throw SoundImportError.unsupportedType(fileName: originalName)
        }

        createDirectories()
        let id = UUID()
        let destination = soundsURL.appendingPathComponent("\(id.uuidString).\(ext)")

        let scoped = sourceURL.startAccessingSecurityScopedResource()
        defer { if scoped { sourceURL.stopAccessingSecurityScopedResource() } }
        do {
            try fileManager.copyItem(at: sourceURL, to: destination)
        } catch {
            log.error("Copy failed: \(error.localizedDescription, privacy: .public)")
            throw SoundImportError.copyFailed(fileName: originalName)
        }
        return (id, destination)
    }

    private func analyze(_ url: URL) async throws -> AudioAnalysis {
        try await Task.detached(priority: .userInitiated) {
            try AudioAnalyzer.analyze(url: url)
        }.value
    }

    // MARK: - Editing

    func update(_ id: UUID, _ mutate: (inout SoundItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var copy = items[index]
        mutate(&copy)
        guard copy != items[index] else { return }
        items[index] = copy
        scheduleSave()
    }

    /// Makes an independent copy of a sound (including its audio file), placed right after it.
    @discardableResult
    func duplicate(id: UUID) -> SoundItem? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        let original = items[index]
        let newID = UUID()
        let ext = (original.fileName as NSString).pathExtension
        let newFileName = ext.isEmpty ? newID.uuidString : "\(newID.uuidString).\(ext)"
        do {
            try fileManager.copyItem(at: fileURL(for: original), to: soundsURL.appendingPathComponent(newFileName))
        } catch {
            log.error("Duplicate failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        let copy = SoundItem(
            id: newID,
            displayName: "\(original.displayName) copy",
            fileName: newFileName,
            volume: original.volume,
            isEnabled: original.isEnabled,
            retriggerMode: original.retriggerMode,
            duration: original.duration,
            waveform: original.waveform
        )
        items.insert(copy, at: index + 1)
        scheduleSave()
        return copy
    }

    // MARK: - Delete / restore

    /// Removes the item and parks its file in `Trash` so the deletion can be undone.
    /// The trash is emptied the next time the library loads.
    @discardableResult
    func remove(id: UUID) -> RemovedSound? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        let item = items.remove(at: index)
        missingFileIDs.remove(id)
        createDirectories()
        try? fileManager.moveItem(at: fileURL(for: item), to: trashURL.appendingPathComponent(item.fileName))
        scheduleSave()
        return RemovedSound(item: item, index: index)
    }

    func restore(_ removed: RemovedSound) {
        guard !items.contains(where: { $0.id == removed.item.id }) else { return }
        try? fileManager.moveItem(
            at: trashURL.appendingPathComponent(removed.item.fileName),
            to: fileURL(for: removed.item)
        )
        items.insert(removed.item, at: min(removed.index, items.count))
        if !fileManager.fileExists(atPath: fileURL(for: removed.item).path) {
            missingFileIDs.insert(removed.item.id)
        }
        scheduleSave()
    }

    // MARK: - Persistence

    var hasPendingSave: Bool { saveTask != nil }

    /// Coalesces bursts of edits (slider drags, typing) into one write.
    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self, saveDebounce] in
            try? await Task.sleep(for: saveDebounce)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    @discardableResult
    func saveNow() -> Bool {
        saveTask?.cancel()
        saveTask = nil
        do {
            createDirectories()
            let data = try Self.makeEncoder().encode(LibrarySnapshot(items: items))
            try data.write(to: storeURL, options: .atomic)
            return true
        } catch {
            log.error("Saving library failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: - Helpers

    private func createDirectories() {
        for url in [soundsURL, trashURL] {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    private func purgeTrash() {
        let contents = (try? fileManager.contentsOfDirectory(at: trashURL, includingPropertiesForKeys: nil)) ?? []
        for url in contents { try? fileManager.removeItem(at: url) }
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
