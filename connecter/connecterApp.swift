//
//  connecterApp.swift
//  connecter
//
//  Created by J. Guzmán Arce Sáez on 13/04/2026.
//

import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if !AppSettings.shared.showOnLaunch {
            NSApp.windows.forEach { $0.orderOut(nil) }
        }
    }

    static func showMainWindow() {
        NSApp.windows.first { $0.title == "Connecter" }?.makeKeyAndOrderFront(nil)
        ?? NSApp.windows.first?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct connecterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var mountManager = MountManager()
    @StateObject private var loginItemManager = LoginItemManager()

    init() {
        NotificationManager.shared.requestAuthorization()
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(mountManager)
                .environmentObject(loginItemManager)
        }
        .windowResizability(.contentMinSize)

        Window("Settings", id: "settings") {
            SettingsTab()
                .environmentObject(loginItemManager)
        }
        .windowResizability(.contentSize)

        Window("Activity Log", id: "activity-log") {
            LogView()
        }
        .defaultSize(width: 560, height: 440)

        MenuBarExtra {
            MenuBarMenuView()
                .environmentObject(mountManager)
        } label: {
            MenuBarIcon(status: menuBarStatus)
        }
        .menuBarExtraStyle(.menu)
    }

    private var menuBarStatus: MenuBarStatus {
        let enabled = mountManager.configs.filter(\.isEnabled)
        guard !enabled.isEmpty else { return .disabled }
        let statuses = enabled.map(\.connectionStatus)
        if statuses.allSatisfy({ $0 == .connected }) { return .allConnected }
        if statuses.contains(.connected)              { return .partial }
        return .noneConnected
    }
}

// MARK: - Dynamic menu bar icon

private struct MenuBarIcon: View {
    let status: MenuBarStatus

    var body: some View {
        Image(systemName: status.iconName)
            .symbolRenderingMode(.multicolor)
            .foregroundStyle(status.color)
    }
}
