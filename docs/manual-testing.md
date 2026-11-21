# Manual test checklist

The unit tests cover the library, hotkey bookkeeping and audio engine. Everything below depends on a real GUI session, real hardware or assistive features, and has no automated coverage. Run through the relevant items before a release, and after changing the area they touch.

1. **Global hotkeys end to end:** recording a shortcut in the real recorder and triggering it from another app with the window closed. The registration logic is tested against a fake backend only.
2. **Row flash and menu bar icon pulse** when a hotkey fires. The menu bar glyph swaps to its solid-tile variant for about half a second; check that the status item redraws it promptly.
3. **Drag and drop** from Finder, including several files at once and the drop highlight.
4. **File picker flows:** toolbar button, `⌘O` (including while the app has no Dock icon), and Relocate.
5. **Keyboard navigation and focus:** arrows, Space, Return, Delete, Esc, Tab order, and the name field taking focus with its text selected right after an import.
6. **Undo and redo** through `⌘Z` / `⇧⌘Z` and the toast's Undo button.
7. **Recorder alerts** for system-reserved shortcuts, and the accent-coloured placeholder returning after a recording is cancelled.
8. **Audio route changes:** unplugging headphones or switching output device during playback. The handler resets voices and restarts the engine, and engine calls are wrapped so an Objective-C exception cannot crash the app, but none of this was exercised with real hardware changes.
9. **Launch at login** (`SMAppService`), including the "requires approval" state. It generally needs a properly signed app in `/Applications`.
10. **Show Dock icon** toggle, and reopening the window by clicking the Dock icon.
11. **Menu bar popover behaviour:** dismissal when opening the main window or Settings, the tooltip, and template rendering on light and dark menu bars.
12. **Animations, Reduce Motion, VoiceOver and larger text sizes.** Labels and reduced-motion paths are in the code but were not experienced with the real assistive features on.
13. **Search field** appearing past 8 sounds. Adding the ninth sound rebuilds the window content once, which may briefly drop keyboard focus.
14. **macOS 14 and 15.** Development happened on macOS 27.2 only, so the macOS 14 window-closing fallback in particular needs a real run.
15. **MP3, M4A, AAC, AIFF and CAF with real-world files.** Tests use generated WAV and CAF tones.
