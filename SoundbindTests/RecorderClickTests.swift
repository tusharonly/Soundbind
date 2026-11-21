import AppKit
import KeyboardShortcuts
import SwiftUI
import XCTest
@testable import Soundbind

/// Drives the real shortcut recorder, inside a real row, with synthetic mouse and key events.
///
/// Regression test: with KeyboardShortcuts 2.4 on macOS 26 and later, clicking the recorder
/// focused it without starting a recording, so the first key combination was ignored (and a
/// plain letter was typed into the field instead). Fixed upstream in KeyboardShortcuts 3.1.
@MainActor
final class RecorderClickTests: XCTestCase {
    func testShortcutPressedRightAfterClickingTheRecorderIsRecorded() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "RecorderClickTests-\(UUID().uuidString)"))
        defaults.set(true, forKey: "hasSeenFirstRunHint")
        let library = SoundLibrary(rootURL: try makeTemporaryDirectory(), saveDebounce: .seconds(60))
        library.load()
        let model = AppModel(library: library, settings: AppSettings(defaults: defaults, recordLaunch: false))
        let item = try await library.importFile(at: try TestAudio.writeTone(to: try makeTemporaryDirectory(), name: "Horn.wav"))

        // The recorder stores into the real shortcut store, so clean up whatever it records.
        let name = KeyboardShortcuts.Name(HotkeyOwner.sound(item.id).key)
        defer { KeyboardShortcuts.setShortcut(nil, for: name) }

        let window = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 560, height: 420),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: MainWindowView().environment(model))
        window.setContentSize(NSSize(width: 560, height: 420))
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(900))
        try XCTSkipUnless(window.isKeyWindow, "needs a GUI session where the test window can become key")

        let recorder = try XCTUnwrap(firstDescendant(of: KeyboardShortcuts.RecorderCocoa.self, in: try XCTUnwrap(window.contentView)))
        let point = recorder.convert(NSPoint(x: recorder.bounds.midX, y: recorder.bounds.midY), to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let click = try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            NSApp.postEvent(click, atStart: false)
        }
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertNotNil(recorder.currentEditor(), "clicking the recorder should focus it")

        // Control-P: key code 35.
        let controlP = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.control], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: "\u{10}", charactersIgnoringModifiers: "p",
            isARepeat: false, keyCode: 35))
        NSApp.postEvent(controlP, atStart: false)
        try await Task.sleep(for: .milliseconds(500))

        XCTAssertEqual(KeyboardShortcuts.getShortcut(for: name), KeyboardShortcuts.Shortcut(.p, modifiers: [.control]))
    }

    private func firstDescendant<T: NSView>(of type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        for subview in view.subviews {
            if let match = firstDescendant(of: type, in: subview) { return match }
        }
        return nil
    }
}
