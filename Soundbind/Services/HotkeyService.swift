import Foundation
import KeyboardShortcuts
import Observation

/// Something a global shortcut can be bound to.
enum HotkeyOwner: Hashable, Sendable {
    case sound(UUID)
    case stopAll

    static let soundKeyPrefix = "sound-"

    /// Name under which the shortcut is stored by KeyboardShortcuts.
    var key: String {
        switch self {
        case .sound(let id): Self.soundKeyPrefix + id.uuidString
        case .stopAll: "stopAllSounds"
        }
    }
}

struct ShortcutConflict: Equatable {
    /// The shortcut the user tried to record.
    let shortcut: KeyboardShortcuts.Shortcut
    /// Who already uses it.
    let holder: HotkeyOwner
}

/// The slice of KeyboardShortcuts that `HotkeyService` needs, so tests can substitute a fake.
@MainActor
protocol HotkeyBackend: AnyObject {
    func shortcut(for key: String) -> KeyboardShortcuts.Shortcut?
    func setShortcut(_ shortcut: KeyboardShortcuts.Shortcut?, for key: String)
    func addHandler(for key: String, action: @escaping () -> Void)
    func removeHandler(for key: String)
    /// Makes sure the stored shortcut for `key` is registered with the system.
    func enable(_ key: String)
    /// Every key that currently has a stored shortcut.
    func storedKeys() -> [String]
}

@MainActor
final class SystemHotkeyBackend: HotkeyBackend {
    private static let defaultsPrefix = "KeyboardShortcuts_"

    private func name(_ key: String) -> KeyboardShortcuts.Name { .init(key) }

    func shortcut(for key: String) -> KeyboardShortcuts.Shortcut? {
        KeyboardShortcuts.getShortcut(for: name(key))
    }

    func setShortcut(_ shortcut: KeyboardShortcuts.Shortcut?, for key: String) {
        KeyboardShortcuts.setShortcut(shortcut, for: name(key))
    }

    func addHandler(for key: String, action: @escaping () -> Void) {
        KeyboardShortcuts.onKeyDown(for: name(key), action: action)
    }

    func removeHandler(for key: String) {
        KeyboardShortcuts.removeHandler(for: name(key))
    }

    func enable(_ key: String) {
        KeyboardShortcuts.enable(name(key))
    }

    func storedKeys() -> [String] {
        UserDefaults.standard.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(Self.defaultsPrefix) }
            .map { String($0.dropFirst(Self.defaultsPrefix.count)) }
    }
}

/// Keeps global hotkeys in step with the library and guards against two things
/// sharing one shortcut.
@MainActor
@Observable
final class HotkeyService {
    /// Current shortcut of every live owner. Views read this for badges and placeholders.
    private(set) var shortcuts: [HotkeyOwner: KeyboardShortcuts.Shortcut] = [:]
    /// Recordings that were held back because the shortcut is already taken.
    private(set) var pendingConflicts: [HotkeyOwner: ShortcutConflict] = [:]

    @ObservationIgnored var onTrigger: ((UUID) -> Void)?
    @ObservationIgnored var onStopAll: (() -> Void)?

    @ObservationIgnored private let backend: HotkeyBackend
    /// Owners that currently have a key-down handler installed (guards double registration).
    @ObservationIgnored private var registered: Set<HotkeyOwner> = []
    /// Owners that exist, in priority order: on a clash, earlier owners keep their shortcut.
    @ObservationIgnored private var liveOwners: [HotkeyOwner] = [.stopAll]

    init(backend: HotkeyBackend? = nil) {
        self.backend = backend ?? SystemHotkeyBackend()
    }

    var registeredOwners: Set<HotkeyOwner> { registered }

    // MARK: - Registration

    /// Brings handlers in line with the library: registers new enabled sounds, unregisters
    /// deleted or disabled ones. Safe to call repeatedly.
    func sync(with items: [SoundItem]) {
        let sounds = items.map { HotkeyOwner.sound($0.id) }
        // Owners already known keep priority over ones that just (re)appeared, so a sound
        // restored by Undo can't steal a shortcut that was reassigned in the meantime.
        let known = Set(liveOwners)
        liveOwners = [.stopAll] + sounds.filter(known.contains) + sounds.filter { !known.contains($0) }

        let desired = Set(items.filter(\.isEnabled).map { HotkeyOwner.sound($0.id) }).union([.stopAll])
        for owner in registered.subtracting(desired) {
            backend.removeHandler(for: owner.key)
            registered.remove(owner)
        }
        for owner in liveOwners where desired.contains(owner) {
            install(owner)
        }

        let live = Set(liveOwners)
        pendingConflicts = pendingConflicts.filter { live.contains($0.key) && live.contains($0.value.holder) }
        refresh()
    }

    private func install(_ owner: HotkeyOwner) {
        guard registered.insert(owner).inserted else { return }
        backend.addHandler(for: owner.key) { [weak self] in
            self?.fire(owner)
        }
    }

    private func fire(_ owner: HotkeyOwner) {
        guard registered.contains(owner) else { return }
        switch owner {
        case .sound(let id): onTrigger?(id)
        case .stopAll: onStopAll?()
        }
    }

    /// Re-reads stored shortcuts, drops duplicates, and re-asserts system registration.
    private func refresh() {
        var map: [HotkeyOwner: KeyboardShortcuts.Shortcut] = [:]
        var taken: Set<KeyboardShortcuts.Shortcut> = []
        for owner in liveOwners {
            guard let shortcut = backend.shortcut(for: owner.key) else { continue }
            if taken.insert(shortcut).inserted {
                map[owner] = shortcut
            } else {
                backend.setShortcut(nil, for: owner.key)
            }
        }
        shortcuts = map
        // KeyboardShortcuts unregisters a key combo whenever *any* name holding it changes,
        // so make sure every owner that should be live still is.
        for owner in registered {
            backend.enable(owner.key)
        }
    }

    // MARK: - Conflicts

    /// Who (other than `owner`) already uses `shortcut`, if anyone.
    func conflict(for shortcut: KeyboardShortcuts.Shortcut, excluding owner: HotkeyOwner) -> HotkeyOwner? {
        liveOwners.first { $0 != owner && shortcuts[$0] == shortcut }
    }

    /// Call after the recorder stored a new shortcut for `owner`. If someone else already
    /// has it, the recording is rolled back and parked as a pending conflict instead of
    /// silently stealing the shortcut.
    func shortcutRecorded(_ shortcut: KeyboardShortcuts.Shortcut?, for owner: HotkeyOwner) {
        pendingConflicts[owner] = nil
        if let shortcut, let holder = conflict(for: shortcut, excluding: owner) {
            backend.setShortcut(shortcuts[owner], for: owner.key)
            pendingConflicts[owner] = ShortcutConflict(shortcut: shortcut, holder: holder)
        }
        refresh()
    }

    /// "Replace": take the shortcut away from its current holder and give it to `owner`.
    func resolveConflictByReplacing(for owner: HotkeyOwner) {
        guard let conflict = pendingConflicts.removeValue(forKey: owner) else { return }
        backend.setShortcut(nil, for: conflict.holder.key)
        backend.setShortcut(conflict.shortcut, for: owner.key)
        refresh()
    }

    func cancelConflict(for owner: HotkeyOwner) {
        pendingConflicts[owner] = nil
    }

    func clearShortcut(for owner: HotkeyOwner) {
        backend.setShortcut(nil, for: owner.key)
        pendingConflicts[owner] = nil
        refresh()
    }

    /// Forgets stored shortcuts that belong to sounds no longer in the library
    /// (kept around after deletion so Undo can bring them back).
    func purgeOrphans() {
        let live = Set(liveOwners.map(\.key))
        for key in backend.storedKeys() where key.hasPrefix(HotkeyOwner.soundKeyPrefix) && !live.contains(key) {
            backend.setShortcut(nil, for: key)
        }
        refresh()
    }
}
