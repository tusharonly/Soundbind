import SwiftUI

/// Entry point. `defaultLaunchBehavior` only exists on macOS 15+, and scene builders can't
/// branch on availability, so each OS generation gets its own tiny `App` type.
@main
enum SoundbindMain {
    static func main() {
        if #available(macOS 15.0, *) {
            SoundbindApp.main()
        } else {
            SoundbindLegacyApp.main()
        }
    }
}

@available(macOS 15.0, *)
struct SoundbindApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared

    var body: some Scene {
        // The main window opens by itself only on first launch; afterwards it is opened
        // from the menu bar item. Hotkeys work either way.
        SoundbindScenes.mainWindow(model)
            .defaultLaunchBehavior(SoundbindScenes.opensWindowAtLaunch(model) ? .presented : .suppressed)
        SoundbindScenes.menuBarExtra(model)
        SoundbindScenes.settings(model)
    }
}

/// macOS 14: the window is closed again in `AppDelegate` on launches after the first.
struct SoundbindLegacyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared

    var body: some Scene {
        SoundbindScenes.mainWindow(model)
        SoundbindScenes.menuBarExtra(model)
        SoundbindScenes.settings(model)
    }
}

@MainActor
enum SoundbindScenes {
    static func opensWindowAtLaunch(_ model: AppModel) -> Bool {
        model.settings.isFirstLaunch && !AppEnvironment.isRunningTests
    }

    static func mainWindow(_ model: AppModel) -> some Scene {
        Window("Soundbind", id: AppModel.mainWindowID) {
            MainWindowView()
                .environment(model)
        }
        .defaultSize(width: 520, height: 640)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
            SoundbindCommands(model: model)
        }
    }

    static func menuBarExtra(_ model: AppModel) -> some Scene {
        MenuBarExtra {
            MenuBarPopoverView()
                .environment(model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }

    static func settings(_ model: AppModel) -> some Scene {
        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

struct SoundbindCommands: Commands {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add Sound…") {
                openWindow(id: AppModel.mainWindowID)
                model.presentAddImporter()
            }
            .keyboardShortcut("o", modifiers: .command)
        }
        CommandMenu("Playback") {
            Button("Play or Stop Selected Sound") {
                model.toggleSelectionPlayback()
            }
            .disabled(model.selection == nil)
            Button("Stop All Sounds") {
                model.stopAll()
            }
            .keyboardShortcut(".", modifiers: .command)
        }
    }
}
