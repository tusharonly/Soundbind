import Foundation
import Observation

/// Small preferences, stored in `UserDefaults`.
@MainActor
@Observable
final class AppSettings {
    private enum Key {
        static let masterVolume = "masterVolume"
        static let showDockIcon = "showDockIcon"
        static let keepsEngineWarm = "keepsEngineWarm"
        static let hasSeenHint = "hasSeenFirstRunHint"
        static let hasLaunchedBefore = "hasLaunchedBefore"
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// True only for the very first launch of the app.
    let isFirstLaunch: Bool

    var masterVolume: Float {
        didSet { defaults.set(masterVolume, forKey: Key.masterVolume) }
    }

    var showDockIcon: Bool {
        didSet { defaults.set(showDockIcon, forKey: Key.showDockIcon) }
    }

    var keepsEngineWarm: Bool {
        didSet { defaults.set(keepsEngineWarm, forKey: Key.keepsEngineWarm) }
    }

    var hasSeenHint: Bool {
        didSet { defaults.set(hasSeenHint, forKey: Key.hasSeenHint) }
    }

    init(defaults: UserDefaults = .standard, recordLaunch: Bool = true) {
        self.defaults = defaults
        isFirstLaunch = !defaults.bool(forKey: Key.hasLaunchedBefore)
        masterVolume = defaults.object(forKey: Key.masterVolume) as? Float ?? 1
        showDockIcon = defaults.bool(forKey: Key.showDockIcon)
        keepsEngineWarm = defaults.bool(forKey: Key.keepsEngineWarm)
        hasSeenHint = defaults.bool(forKey: Key.hasSeenHint)
        if recordLaunch {
            defaults.set(true, forKey: Key.hasLaunchedBefore)
        }
    }
}

enum AppEnvironment {
    /// The app is only acting as a host for unit tests; skip all side effects.
    static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
}
