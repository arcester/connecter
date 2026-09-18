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
            body: String(format: String(localized: "\"%@\" is available in /Volumes/"), config.displayName),
            sound: .default
        )
    }

    /// Notifies that a share dropped (no longer mounted).
    func sendUnmounted(config: ShareConfig) {
        guard AppSettings.shared.notificationsEnabled else { return }
        send(
            id: "unmounted-\(config.id)",
            title: String(localized: "Share disconnected"),
            body: String(format: String(localized: "\"%@\" is no longer available. Reconnecting\u{2026}"), config.displayName),
            sound: .defaultCritical
        )
    }

    /// Notifies that a reconnection attempt failed.
    func sendError(config: ShareConfig) {
        guard AppSettings.shared.notificationsEnabled else { return }
        send(
            id: "error-\(config.id)",
            title: String(localized: "Mount error"),
            body: String(format: String(localized: "Could not reconnect \"%@\". Check the network or credentials."), config.displayName),
            sound: .defaultCritical
        )
    }

    /// Notifies that macOS's NetAuth agent stopped answering mount requests.
    func sendNetAuthNotResponding() {
        guard AppSettings.shared.notificationsEnabled else { return }
        send(
            id: "netauth-not-responding",
            title: String(localized: "macOS is not responding to mount requests"),
            body: String(localized: "Open Connecter and choose “Restart NetAuth” to fix it."),
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
