import Observation
import OSLog
import ServiceManagement

@MainActor
@Observable
final class LaunchAtLoginService {
    private(set) var isEnabled = false
    /// The user must approve the login item in System Settings before it takes effect.
    private(set) var requiresApproval = false
    private(set) var lastError: String?

    @ObservationIgnored private let log = Logger(subsystem: "Soundbind", category: "LaunchAtLogin")

    init() {
        refresh()
    }

    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled || status == .requiresApproval
        requiresApproval = status == .requiresApproval
    }

    func setEnabled(_ enabled: Bool) {
        lastError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            log.error("Launch at login change failed: \(error.localizedDescription, privacy: .public)")
            lastError = "Couldn’t \(enabled ? "enable" : "disable") launch at login. \(error.localizedDescription)"
        }
        refresh()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
