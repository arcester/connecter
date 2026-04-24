import ServiceManagement
import Combine

/// Manages registration of the app as a Login Item using SMAppService.
@MainActor
final class LoginItemManager: ObservableObject {

    static let shared = LoginItemManager()

    @Published private(set) var status: SMAppService.Status = .notRegistered

    private let service = SMAppService.mainApp

    init() {
        refreshStatus()
    }

    // MARK: - State

    var isEnabled: Bool { status == .enabled }

    /// True when the system requires the user to approve the login item in System Settings.
    var requiresApproval: Bool { status == .requiresApproval }

    func refreshStatus() {
        status = service.status
    }

    // MARK: - Enable / disable

    func toggle() {
        if isEnabled { disable() } else { enable() }
    }

    func enable() {
        do {
            try service.register()
        } catch {
            // kSMErrorAlreadyRegistered is not a real error
            guard (error as NSError).code == kSMErrorAlreadyRegistered else {
                LogManager.shared.error("[LoginItem] Registration failed: \(error.localizedDescription)")
                return
            }
        }
        refreshStatus()
    }

    func disable() {
        do {
            try service.unregister()
        } catch {
            LogManager.shared.error("[LoginItem] Unregistration failed: \(error.localizedDescription)")
        }
        refreshStatus()
    }

    /// Opens System Settings → General → Login Items for user approval.
    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
