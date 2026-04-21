//
//  connecterApp.swift
//  connecter
//
//  Created by J. Guzmán Arce Sáez on 13/04/2026.
//

import SwiftUI

private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide windows on launch if showOnLaunch is disabled.
        if !AppSettings.shared.showOnLaunch {
            NSApp.windows.forEach { $0.orderOut(nil) }
        }
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
