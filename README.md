# Soundbind

A native macOS menu bar app: import audio files, bind each one to a global keyboard shortcut, and play it from anywhere, even with the window closed.

- macOS 14 (Sonoma) or later, SwiftUI-first, sandboxed
- No account, no network access, no analytics
- Free and open source under the [MIT License](LICENSE)

There are no prebuilt downloads yet, so for now you build it from source.
- Global hotkeys via [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts), with no Accessibility permission needed
- `AVAudioEngine` playback with sounds preloaded into memory

## Build and run

Requirements: Xcode 16.3 or later (KeyboardShortcuts 2.4 needs the Swift 6.1 toolchain; the app itself compiles in Swift 5 mode and was developed with Xcode 27.2) and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen          # once
xcodegen generate              # creates Soundbind.xcodeproj from project.yml
xcodebuild -scheme Soundbind build
xcodebuild -scheme Soundbind test
```

To run the built app:

```sh
xcodebuild -scheme Soundbind -derivedDataPath build build
open build/Build/Products/Debug/Soundbind.app
```

Or open `Soundbind.xcodeproj` in Xcode and press Run.

`Soundbind.xcodeproj` is generated and not checked in. Re-run `xcodegen generate` after adding or removing files.

### Signing and forks

- **Signing is ad hoc** (`CODE_SIGN_IDENTITY: "-"`, no team) so it builds on any Mac without an Apple developer account. An ad hoc build runs on the machine that built it; to distribute a build, set `DEVELOPMENT_TEAM` and a real identity in `project.yml` and notarize it.
- **Bundle ID is `io.github.tusharonly.soundbind`.** If you publish your own fork, change `bundleIdPrefix` and both `PRODUCT_BUNDLE_IDENTIFIER` values in `project.yml`. The library folder name follows the bundle ID.
- **The app icon and menu bar glyph are drawn in code.** The icon (a key throwing sound waves across a fuchsia tile) is regenerated with `swift scripts/generate_icon.swift Soundbind/Resources/Assets.xcassets/AppIcon.appiconset`; the menu bar glyph lives in `Soundbind/Views/MenuBarIcon.swift`.

## Using it

1. Click the key-and-sound-waves icon in the menu bar and choose **Open Soundbind…** (the window opens by itself on first launch only).
2. Add sounds with the **+** toolbar button, `⌘O`, or by dragging files onto the window. MP3, WAV, M4A, AAC, AIFF and CAF are accepted.
3. Click **Click to record shortcut** on a row and press a key combination.

| In the sound list | |
|---|---|
| `↑` / `↓` | Move the selection |
| `Space` | Play or stop the selected sound |
| `Return` | Rename (or double-click the name) |
| `Delete` | Delete, with Undo (`⌘Z` or the toast) |
| `Esc` | Clear the selection |
| `⌘.` | Stop all sounds |

The speaker button on a row reveals its volume slider and retrigger mode (Restart, Ignore, Overlap). The `…` menu has Rename, Reveal in Finder, Duplicate, Shortcut Enabled, Clear Shortcut and Delete.

Settings (`⌘,`): launch at login, Dock icon, master volume, a global **Stop All Sounds** shortcut, and whether to keep the audio engine running.

## Where things live

```
project.yml                 XcodeGen project definition
Soundbind/
  App/                      Entry point, AppDelegate, AppModel (coordinator + UI state)
  Models/                   SoundItem, RetriggerMode
  Services/                 SoundLibrary, AudioEngineService, AudioAnalyzer,
                            HotkeyService, LaunchAtLoginService, AppSettings
  Views/                    Small SwiftUI views
  Support/                  Objective-C exception catcher for AVAudioEngine
  Resources/                Info.plist, entitlements, asset catalog
SoundbindTests/             Unit tests
scripts/generate_icon.swift Icon generator
docs/manual-testing.md      Checklist for what the unit tests can't cover
```

User data is in the sandbox container, under `~/Library/Containers/<bundle id>/Data/Library/Application Support/<bundle id>/`:

- `library.json`: the single Codable store
- `Sounds/`: imported audio, copied in and named by UUID
- `Trash/`: files of deleted sounds, kept until the next launch so delete can be undone

Shortcuts are stored by KeyboardShortcuts in `UserDefaults`.

## Design

The look is defined in `Soundbind/Views/Theme.swift`: a warm cream background, near-black "ink" text and buttons, a fuchsia marker highlight for selection and hotkey flashes, teal for interactive controls, and large soft squircle cards. Each colour has a light and a dark variant. This replaces the system accent colour and default materials on purpose, so the app no longer follows the user's accent colour setting.

## Decisions worth knowing about

- **Extra fields on `SoundItem`.** `duration` and `waveform` (40 normalised peaks) are stored on each item, so rows never reopen the audio file.
- **Canonical audio format.** Preloaded sounds are converted once to 48 kHz stereo float. Every pooled `AVAudioPlayerNode` is connected in that format up front, so a trigger is only "schedule buffer, play". Up to 24 voices can sound at once; beyond that the oldest is reused.
- **Long files.** Over 30 s shows a warning. Over 60 s the file is streamed from disk on its own player node rather than preloaded, so it can start slightly later.
- **Engine idle behaviour.** A running engine keeps the output device open, which stops the Mac from idle-sleeping. By default the engine pauses after 30 s of silence, so the first trigger after a quiet spell pays a small wake-up cost. **Settings > Keep audio engine running** trades that for constant lowest latency.
- **Shortcut conflicts.** Recording a combo already used by another sound, or by Stop All, rolls the recorder back and shows an inline warning with **Replace** and **Cancel**. System-reserved combos use the recorder's own alert.
- **Disabled sounds keep their shortcut reserved** but do not respond to it.
- **Delete and Undo.** A deleted sound's file and shortcut are kept until the next launch. If its shortcut was given to another sound in the meantime, the restored sound comes back without one.
- **Renaming after import.** Importing one file puts its name straight into edit mode. Importing several selects the last one and shows a toast instead, since picking one of many to rename would be arbitrary.
- **Search field** appears once there are more than 8 sounds.
- **Corrupt `library.json`** is renamed to `library.corrupt-<timestamp>.json` and the app starts empty with a notice. Audio files already in `Sounds/` are left on disk but are not re-adopted automatically.
- **Custom list instead of `List`.** Rows are drawn in a `ScrollView` for control over hover, selection and flash styling and for spring transitions. Drag-to-reorder is not implemented.
- **AppKit is used in a few places:** the recorder (`KeyboardShortcuts.RecorderCocoa`, to customise the placeholder and width), the activation policy for the Dock icon toggle, the menu bar glyph and its tooltip, and reopening the main window when the app is launched while already running.
- **KeyboardShortcuts is pinned to 2.4.x** in `project.yml`.
- **Private notification name.** The recorder placeholder is restored by observing `KeyboardShortcuts_recorderActiveStatusDidChange`, which is internal to KeyboardShortcuts 2.4. If a later version renames it, the placeholder falls back to the library's "Record Shortcut" text; nothing else breaks.
- **macOS 15+ sandbox limit.** Apple no longer allows sandboxed apps to register Option-only or Option+Shift-only shortcuts. The recorder explains this when you try one.
- **Launch behaviour on macOS 14.** There is no scene API to keep the window closed at launch before macOS 15, so on 14 the window is closed again right after launch on every run after the first.

## Tests

49 unit tests, run with `xcodebuild -scheme Soundbind test`:

- `SoundLibraryTests`: import (copy, UUID naming, survives the original being deleted), unsupported and corrupt files (including cleanup of the copy), delete and restore, persistence round trip, debounced save, missing store, corrupt JSON, missing sound files and relocate, duplicate.
- `HotkeyServiceTests`: conflict detection (other sounds, self, Stop All, deleted sounds), the record, roll back, Replace and Cancel flow, single registration across repeated syncs, unregistering on delete, disabled sounds, restore after undo.
- `AudioEngineServiceTests`: real `AVAudioEngine` playback at zero volume, covering preload, natural finish, Restart, Ignore, Overlap, voice pool cap, Stop All and streaming of a 61 s file. Skipped automatically when there is no output device.
- `AudioAnalyzerTests`: duration, waveform, resampling to the canonical format.

Anything that needs a real GUI session, real audio hardware or assistive features is listed in [docs/manual-testing.md](docs/manual-testing.md).

## Contributing

Issues and pull requests are welcome. This is a small side project, so replies may take a while.

- Run `xcodegen generate` after adding or removing files, and `xcodebuild -scheme Soundbind test` before opening a pull request.
- Keep the app sandboxed and free of permissions prompts; global hotkeys must keep working without Accessibility access.
- For anything visual, say which items of the manual checklist you ran.

## License

[MIT](LICENSE) © 2026 Tushar Ghige. Global shortcuts use [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) by Sindre Sorhus, also MIT.
