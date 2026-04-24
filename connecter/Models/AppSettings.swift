import Foundation
import Combine

/// Persisted user-configurable settings.
/// Singleton — access via AppSettings.shared.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    /// How often (in seconds) each share's mount state is checked.
    @Published var monitorInterval: Double {
        didSet { UserDefaults.standard.set(monitorInterval, forKey: Keys.monitorInterval) }
    }

    /// Number of consecutive mount failures before the share is automatically disabled.
    @Published var maxFailuresBeforeDisable: Int {
        didSet { UserDefaults.standard.set(maxFailuresBeforeDisable, forKey: Keys.maxFailures) }
    }

    /// Whether system notifications are sent for mount/unmount events.
    @Published var notificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: Keys.notificationsEnabled) }
    }

    /// Whether to show the main window when the app launches.
    @Published var showOnLaunch: Bool {
        didSet { UserDefaults.standard.set(showOnLaunch, forKey: Keys.showOnLaunch) }
    }

    // TODO: iCloud sync — descomentar cuando haya cuenta de desarrollador con iCloud habilitado
    // @Published var iCloudSync: Bool {
    //     didSet {
    //         UserDefaults.standard.set(iCloudSync, forKey: Keys.iCloudSync)
    //         ShareConfig.migrateStorage(toCloud: iCloudSync)
    //         if iCloudSync {
    //             MountManager.shared.startCloudObserver()
    //         } else {
    //             MountManager.shared.stopCloudObserver()
    //         }
    //     }
    // }
    @Published var iCloudSync: Bool = false

    private enum Keys {
        static let monitorInterval       = "app.monitorInterval"
        static let maxFailures           = "app.maxFailuresBeforeDisable"
        static let notificationsEnabled  = "app.notificationsEnabled"
        static let showOnLaunch          = "app.showOnLaunch"
        static let iCloudSync            = "app.iCloudSync"
    }

    private init() {
        let d = UserDefaults.standard

        let interval = d.double(forKey: Keys.monitorInterval)
        monitorInterval = interval >= 15 ? interval : 30

        let failures = d.integer(forKey: Keys.maxFailures)
        maxFailuresBeforeDisable = failures > 0 ? failures : 5

        if d.object(forKey: Keys.notificationsEnabled) == nil {
            notificationsEnabled = true
        } else {
            notificationsEnabled = d.bool(forKey: Keys.notificationsEnabled)
        }

        if d.object(forKey: Keys.showOnLaunch) == nil {
            showOnLaunch = true
        } else {
            showOnLaunch = d.bool(forKey: Keys.showOnLaunch)
        }

        // iCloudSync = d.bool(forKey: Keys.iCloudSync)
    }
}
