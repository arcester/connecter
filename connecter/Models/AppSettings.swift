import Foundation
import Combine
import SwiftUI
import AppKit

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

    /// Name of the accent color used across the share list UI.
    @Published var accentColorName: String {
        didSet { UserDefaults.standard.set(accentColorName, forKey: Keys.accentColorName) }
    }

    /// "system", "light" or "dark" — the app's colour scheme.
    @Published var appearance: String {
        didSet {
            UserDefaults.standard.set(appearance, forKey: Keys.appearance)
            Self.apply(appearance: appearance)
        }
    }

    /// Sets the appearance of every window and menu; `nil` follows the system.
    static func apply(appearance: String) {
        NSApp.appearance = switch appearance {
        case "light": NSAppearance(named: .aqua)
        case "dark":  NSAppearance(named: .darkAqua)
        default:      nil
        }
    }

    var accentColor: Color {
        Self.colorOptions.first { $0.name == accentColorName }?.color ?? .accentColor
    }

    /// "system" follows the accent colour chosen in System Settings.
    static let colorOptions: [(name: String, color: Color)] = [
        ("system",   .accentColor),
        ("blue",     .blue),
        ("purple",   .purple),
        ("pink",     Color(hue: 0.92, saturation: 0.65, brightness: 0.90)),
        ("red",      .red),
        ("orange",   .orange),
        ("yellow",   .yellow),
        ("green",    .green),
        ("graphite", Color(white: 0.55)),
    ]

    /// User-facing name of one of `colorOptions`.
    static func localizedColorName(_ name: String) -> String {
        switch name {
        case "system":   String(localized: "System")
        case "blue":     String(localized: "Blue")
        case "purple":   String(localized: "Purple")
        case "pink":     String(localized: "Pink")
        case "red":      String(localized: "Red")
        case "orange":   String(localized: "Orange")
        case "yellow":   String(localized: "Yellow")
        case "green":    String(localized: "Green")
        case "graphite": String(localized: "Graphite")
        default:         name.capitalized
        }
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
        static let accentColorName       = "app.accentColorName"
        static let appearance            = "app.appearance"
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

        accentColorName = d.string(forKey: Keys.accentColorName) ?? "system"
        appearance = d.string(forKey: Keys.appearance) ?? "system"

        // iCloudSync = d.bool(forKey: Keys.iCloudSync)
    }
}
