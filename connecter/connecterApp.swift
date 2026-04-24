//
//  connecterApp.swift
//  connecter
//
//  Created by J. Guzmán Arce Sáez on 13/04/2026.
//

import SwiftUI

extension Notification.Name {
    static let showMainWindow = Notification.Name("connecter.showMainWindow")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if !AppSettings.shared.showOnLaunch {
            // Defer so SwiftUI has time to create the window before we hide it.
            DispatchQueue.main.async {
                NSApp.windows.forEach { $0.orderOut(nil) }
            }
        }
    }
}

@main
struct connecterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var mountManager = MountManager()
    @StateObject private var loginItemManager = LoginItemManager()
    @Environment(\.openWindow) private var openWindow

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
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
                .onReceive(NotificationCenter.default.publisher(for: .showMainWindow)) { _ in
                    let regularWindows = NSApp.windows.filter { !($0 is NSPanel) && $0.canBecomeMain }
                    if let window = regularWindows.first {
                        window.makeKeyAndOrderFront(nil)
                    } else {
                        openWindow(id: "main")
                    }
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .menuBarExtraStyle(.menu)
    }

    private var menuBarStatus: MenuBarStatus {
        let enabled = mountManager.configs.filter(\.isEnabled)
        guard !enabled.isEmpty else { return .disabled }
        let statuses = enabled.map(\.connectionStatus)
        if statuses.contains(.connecting) || statuses.contains(.disconnecting) { return .busy }
        if statuses.allSatisfy({ $0 == .connected }) { return .allConnected }
        if statuses.contains(.connected)              { return .partial }
        return .noneConnected
    }
}

// MARK: - Dynamic menu bar icon

private struct MenuBarIcon: View {
    let status: MenuBarStatus
    @State private var rotation: Double = 0

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: status == .busy ? "folder.fill" : status.iconName)
                .foregroundStyle(status.color)

            if status == .busy {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 7, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(1.5)
                    .background(Circle().fill(Color.orange))
                    .rotationEffect(.degrees(rotation))
                    .offset(x: 5, y: 5)
                    .onAppear {
                        withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                            rotation = 360
                        }
                    }
            }
        }
    }
}
