import UserNotifications

/// Sends local system notifications for share mount events.
final class NotificationManager {

    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()

    private init() {}

    // MARK: - Authorization

    /// Requests notification permission. Call once at app launch.
    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error {
                Task { @MainActor in
                    LogManager.shared.error("[Notifications] Authorization failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Events

    /// Notifies that a share was mounted successfully.
    func sendMounted(config: ShareConfig) {
        guard AppSettings.shared.notificationsEnabled else { return }
        send(
            id: "mounted-\(config.id)",
            title: String(localized: "Share mounted"),
            body: String(localized: "\"\(config.displayName)\" is available in /Volumes/"),
            sound: .default
        )
    }

    /// Notifies that a share dropped (no longer mounted).
    func sendUnmounted(config: ShareConfig) {
        guard AppSettings.shared.notificationsEnabled else { return }
        send(
            id: "unmounted-\(config.id)",
            title: String(localized: "Share disconnected"),
            body: String(localized: "\"\(config.displayName)\" is no longer available. Reconnecting…"),
            sound: .defaultCritical
        )
    }

    /// Notifies that a reconnection attempt failed.
    func sendError(config: ShareConfig) {
        guard AppSettings.shared.notificationsEnabled else { return }
        send(
            id: "error-\(config.id)",
            title: String(localized: "Mount error"),
            body: String(localized: "Could not reconnect \"\(config.displayName)\". Check the network or credentials."),
            sound: .defaultCritical
        )
    }

    /// Notifies that a share was switched off after repeated failures, so the
    /// user knows why it stopped reconnecting.
    func sendAutoDisabled(config: ShareConfig, failures: Int) {
        guard AppSettings.shared.notificationsEnabled else { return }
        send(
            id: "disabled-\(config.id)",
            title: String(localized: "Share disabled"),
            body: String(localized: "\"\(config.displayName)\" was disabled after \(failures) failed attempts. Turn it on again in Connecter to retry."),
            sound: .defaultCritical
        )
    }

    /// Notifies that macOS's NetAuth agent stopped answering mount requests.
    func sendNetAuthNotResponding() {
        guard AppSettings.shared.notificationsEnabled else { return }
        send(
            id: "netauth-not-responding",
            title: String(localized: "macOS is not responding to mount requests"),
            body: AppEnvironment.isSandboxed
                ? String(localized: "Open Connecter for instructions to recover the mounts.")
                : String(localized: "Open Connecter and choose “Restart NetAuth” to fix it."),
            sound: .defaultCritical
        )
    }

    // MARK: - Private

    private func send(id: String, title: String, body: String, sound: UNNotificationSound?) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = sound

        // nil trigger = deliver immediately
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        center.add(request) { error in
            if let error {
                Task { @MainActor in
                    LogManager.shared.error("[Notifications] Failed to deliver '\(id)': \(error.localizedDescription)")
                }
            }
        }
    }
}
