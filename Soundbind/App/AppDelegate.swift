import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !AppEnvironment.isRunningTests else { return }
        let model = AppModel.shared
        model.bootstrap()

        DispatchQueue.main.async {
            // macOS 14 has no scene API to keep the main window closed at launch,
            // so close it here on every launch after the first.
            if #unavailable(macOS 15.0), !model.settings.isFirstLaunch {
                for window in NSApp.windows where window.identifier?.rawValue.hasPrefix(AppModel.mainWindowID) == true {
                    window.close()
                }
            }
            Self.applyStatusItemToolTip()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard !AppEnvironment.isRunningTests else { return }
        AppModel.shared.prepareForTermination()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// `MenuBarExtra` has no tooltip API; set it on the underlying status bar button.
    private static func applyStatusItemToolTip() {
        for window in NSApp.windows {
            guard let button = window.contentView?.firstDescendant(ofType: NSStatusBarButton.self)
                ?? (window.contentView as? NSStatusBarButton) else { continue }
            button.toolTip = "Soundbind"
        }
    }
}

private extension NSView {
    func firstDescendant<T: NSView>(ofType type: T.Type) -> T? {
        for subview in subviews {
            if let match = subview as? T { return match }
            if let match = subview.firstDescendant(ofType: type) { return match }
        }
        return nil
    }
}
