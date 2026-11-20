import KeyboardShortcuts
import XCTest
@testable import Soundbind

@MainActor
private final class FakeHotkeyBackend: HotkeyBackend {
    var stored: [String: KeyboardShortcuts.Shortcut] = [:]
    var handlers: [String: [() -> Void]] = [:]
    var enabledKeys: [String] = []

    func shortcut(for key: String) -> KeyboardShortcuts.Shortcut? { stored[key] }
    func setShortcut(_ shortcut: KeyboardShortcuts.Shortcut?, for key: String) { stored[key] = shortcut }
    func addHandler(for key: String, action: @escaping () -> Void) { handlers[key, default: []].append(action) }
    func removeHandler(for key: String) { handlers[key] = nil }
    func enable(_ key: String) { enabledKeys.append(key) }
    func storedKeys() -> [String] { Array(stored.keys) }

    /// Simulates the user pressing a key combo system-wide.
    func press(_ shortcut: KeyboardShortcuts.Shortcut) {
        for (key, actions) in handlers where stored[key] == shortcut {
            actions.forEach { $0() }
        }
    }

    /// Simulates the recorder UI, which stores the shortcut before telling anyone.
    func record(_ shortcut: KeyboardShortcuts.Shortcut?, for owner: HotkeyOwner, in service: HotkeyService) {
        stored[owner.key] = shortcut
        service.shortcutRecorded(shortcut, for: owner)
    }
}

@MainActor
final class HotkeyServiceTests: XCTestCase {
    private let cmd1 = KeyboardShortcuts.Shortcut(.one, modifiers: [.command])
    private let cmd2 = KeyboardShortcuts.Shortcut(.two, modifiers: [.command])
    private let cmdShift1 = KeyboardShortcuts.Shortcut(.one, modifiers: [.command, .shift])

    private var backend: FakeHotkeyBackend!
    private var service: HotkeyService!
    private var triggered: [UUID] = []
    private var stopAllCount = 0

    private let a = SoundItem(displayName: "A", fileName: "a.wav")
    private let b = SoundItem(displayName: "B", fileName: "b.wav")

    override func setUp() async throws {
        backend = FakeHotkeyBackend()
        service = HotkeyService(backend: backend)
        triggered = []
        stopAllCount = 0
        service.onTrigger = { [unowned self] in self.triggered.append($0) }
        service.onStopAll = { [unowned self] in self.stopAllCount += 1 }
    }

    // MARK: Conflict detection

    func testNoConflictWhenShortcutIsUnused() {
        backend.stored[HotkeyOwner.sound(a.id).key] = cmd1
        service.sync(with: [a, b])

        XCTAssertNil(service.conflict(for: cmd2, excluding: .sound(b.id)))
        XCTAssertNil(service.conflict(for: cmdShift1, excluding: .sound(b.id)), "Modifiers are part of the identity")
    }

    func testConflictWithAnotherSound() {
        backend.stored[HotkeyOwner.sound(a.id).key] = cmd1
        service.sync(with: [a, b])

        XCTAssertEqual(service.conflict(for: cmd1, excluding: .sound(b.id)), .sound(a.id))
    }

    func testOwnShortcutIsNotAConflict() {
        backend.stored[HotkeyOwner.sound(a.id).key] = cmd1
        service.sync(with: [a, b])

        XCTAssertNil(service.conflict(for: cmd1, excluding: .sound(a.id)))
    }

    func testConflictWithStopAllShortcutAndViceVersa() {
        backend.stored[HotkeyOwner.stopAll.key] = cmd1
        backend.stored[HotkeyOwner.sound(a.id).key] = cmd2
        service.sync(with: [a])

        XCTAssertEqual(service.conflict(for: cmd1, excluding: .sound(a.id)), .stopAll)
        XCTAssertEqual(service.conflict(for: cmd2, excluding: .stopAll), .sound(a.id))
    }

    func testShortcutOfDeletedSoundIsNotAConflict() {
        backend.stored[HotkeyOwner.sound(a.id).key] = cmd1
        service.sync(with: [a, b])
        service.sync(with: [b]) // a deleted; its stored shortcut lingers for Undo

        XCTAssertNil(service.conflict(for: cmd1, excluding: .sound(b.id)))
    }

    // MARK: Recording flow

    func testRecordingFreeShortcutIsAccepted() {
        service.sync(with: [a, b])

        backend.record(cmd1, for: .sound(a.id), in: service)

        XCTAssertEqual(service.shortcuts[.sound(a.id)], cmd1)
        XCTAssertTrue(service.pendingConflicts.isEmpty)
    }

    func testRecordingTakenShortcutIsRolledBackAndParkedAsConflict() {
        service.sync(with: [a, b])
        backend.record(cmd1, for: .sound(a.id), in: service)
        backend.record(cmd2, for: .sound(b.id), in: service)

        backend.record(cmd1, for: .sound(b.id), in: service)

        XCTAssertEqual(service.pendingConflicts[.sound(b.id)], ShortcutConflict(shortcut: cmd1, holder: .sound(a.id)))
        XCTAssertEqual(backend.stored[HotkeyOwner.sound(a.id).key], cmd1, "Holder keeps its shortcut")
        XCTAssertEqual(backend.stored[HotkeyOwner.sound(b.id).key], cmd2, "Recorder is rolled back to the previous value")
        XCTAssertEqual(service.shortcuts[.sound(b.id)], cmd2)

        backend.press(cmd1)
        XCTAssertEqual(triggered, [a.id], "Nothing was silently overwritten")
    }

    func testRecordingTakenShortcutWithNoPreviousValueRollsBackToNone() {
        service.sync(with: [a, b])
        backend.record(cmd1, for: .sound(a.id), in: service)

        backend.record(cmd1, for: .sound(b.id), in: service)

        XCTAssertNil(backend.stored[HotkeyOwner.sound(b.id).key])
        XCTAssertNil(service.shortcuts[.sound(b.id)])
        XCTAssertNotNil(service.pendingConflicts[.sound(b.id)])
    }

    func testReplaceMovesShortcutToNewOwner() {
        service.sync(with: [a, b])
        backend.record(cmd1, for: .sound(a.id), in: service)
        backend.record(cmd1, for: .sound(b.id), in: service)

        service.resolveConflictByReplacing(for: .sound(b.id))

        XCTAssertTrue(service.pendingConflicts.isEmpty)
        XCTAssertNil(service.shortcuts[.sound(a.id)])
        XCTAssertEqual(service.shortcuts[.sound(b.id)], cmd1)
        backend.press(cmd1)
        XCTAssertEqual(triggered, [b.id])
    }

    func testCancelKeepsEverythingAsItWas() {
        service.sync(with: [a, b])
        backend.record(cmd1, for: .sound(a.id), in: service)
        backend.record(cmd1, for: .sound(b.id), in: service)

        service.cancelConflict(for: .sound(b.id))

        XCTAssertTrue(service.pendingConflicts.isEmpty)
        XCTAssertEqual(service.shortcuts[.sound(a.id)], cmd1)
        XCTAssertNil(service.shortcuts[.sound(b.id)])
    }

    func testRecordingADifferentShortcutClearsPendingConflict() {
        service.sync(with: [a, b])
        backend.record(cmd1, for: .sound(a.id), in: service)
        backend.record(cmd1, for: .sound(b.id), in: service)

        backend.record(cmd2, for: .sound(b.id), in: service)

        XCTAssertTrue(service.pendingConflicts.isEmpty)
        XCTAssertEqual(service.shortcuts[.sound(b.id)], cmd2)
    }

    func testStopAllRecorderConflictsWithSound() {
        service.sync(with: [a])
        backend.record(cmd1, for: .sound(a.id), in: service)

        backend.record(cmd1, for: .stopAll, in: service)

        XCTAssertEqual(service.pendingConflicts[.stopAll], ShortcutConflict(shortcut: cmd1, holder: .sound(a.id)))
        service.resolveConflictByReplacing(for: .stopAll)
        backend.press(cmd1)
        XCTAssertEqual(stopAllCount, 1)
        XCTAssertTrue(triggered.isEmpty)
    }

    func testConflictIsDroppedWhenHolderIsDeleted() {
        service.sync(with: [a, b])
        backend.record(cmd1, for: .sound(a.id), in: service)
        backend.record(cmd1, for: .sound(b.id), in: service)

        service.sync(with: [b])

        XCTAssertTrue(service.pendingConflicts.isEmpty)
    }

    // MARK: Registration

    func testSyncRegistersEachOwnerExactlyOnce() {
        backend.stored[HotkeyOwner.sound(a.id).key] = cmd1

        service.sync(with: [a, b])
        service.sync(with: [a, b])
        service.sync(with: [a, b])

        XCTAssertEqual(backend.handlers[HotkeyOwner.sound(a.id).key]?.count, 1)
        XCTAssertEqual(backend.handlers[HotkeyOwner.sound(b.id).key]?.count, 1)
        XCTAssertEqual(backend.handlers[HotkeyOwner.stopAll.key]?.count, 1)
        backend.press(cmd1)
        XCTAssertEqual(triggered, [a.id], "One press, one trigger")
    }

    func testDeletedSoundIsUnregistered() {
        backend.stored[HotkeyOwner.sound(a.id).key] = cmd1
        service.sync(with: [a, b])

        service.sync(with: [b])

        XCTAssertNil(backend.handlers[HotkeyOwner.sound(a.id).key])
        XCTAssertEqual(service.registeredOwners, [.sound(b.id), .stopAll])
        XCTAssertNil(service.shortcuts[.sound(a.id)])
        backend.press(cmd1)
        XCTAssertTrue(triggered.isEmpty)
    }

    func testDisabledSoundHasNoHandlerButKeepsItsShortcut() {
        var disabled = a
        disabled.isEnabled = false
        backend.stored[HotkeyOwner.sound(a.id).key] = cmd1

        service.sync(with: [disabled])

        XCTAssertNil(backend.handlers[HotkeyOwner.sound(a.id).key])
        XCTAssertEqual(service.shortcuts[.sound(a.id)], cmd1)
        XCTAssertEqual(service.conflict(for: cmd1, excluding: .stopAll), .sound(a.id), "Still reserved")

        service.sync(with: [a])
        backend.press(cmd1)
        XCTAssertEqual(triggered, [a.id])
    }

    func testRestoredSoundLosesShortcutThatWasReassignedMeanwhile() {
        service.sync(with: [a, b])
        backend.record(cmd1, for: .sound(a.id), in: service)
        service.sync(with: [b]) // delete a
        backend.record(cmd1, for: .sound(b.id), in: service)
        XCTAssertTrue(service.pendingConflicts.isEmpty)

        service.sync(with: [a, b]) // undo delete

        XCTAssertEqual(service.shortcuts[.sound(b.id)], cmd1)
        XCTAssertNil(service.shortcuts[.sound(a.id)])
        XCTAssertNil(backend.stored[HotkeyOwner.sound(a.id).key])
        backend.press(cmd1)
        XCTAssertEqual(triggered, [b.id])
    }

    func testRestoredSoundKeepsItsShortcutWhenStillFree() {
        service.sync(with: [a, b])
        backend.record(cmd1, for: .sound(a.id), in: service)
        service.sync(with: [b])

        service.sync(with: [a, b])

        XCTAssertEqual(service.shortcuts[.sound(a.id)], cmd1)
        backend.press(cmd1)
        XCTAssertEqual(triggered, [a.id])
    }

    func testLiveRegistrationsAreReassertedAfterChanges() {
        service.sync(with: [a, b])
        backend.record(cmd1, for: .sound(a.id), in: service)
        backend.enabledKeys.removeAll()

        backend.record(cmd1, for: .sound(b.id), in: service) // rolled back

        XCTAssertTrue(backend.enabledKeys.contains(HotkeyOwner.sound(a.id).key))
    }

    func testPurgeOrphansForgetsShortcutsOfSoundsNotInLibrary() {
        let ghost = HotkeyOwner.sound(UUID()).key
        backend.stored[ghost] = cmd2
        backend.stored[HotkeyOwner.sound(a.id).key] = cmd1
        backend.stored[HotkeyOwner.stopAll.key] = cmdShift1
        backend.stored["someOtherAppKey"] = cmd2
        service.sync(with: [a])

        service.purgeOrphans()

        XCTAssertNil(backend.stored[ghost])
        XCTAssertEqual(backend.stored[HotkeyOwner.sound(a.id).key], cmd1)
        XCTAssertEqual(backend.stored[HotkeyOwner.stopAll.key], cmdShift1)
        XCTAssertEqual(backend.stored["someOtherAppKey"], cmd2)
    }
}
