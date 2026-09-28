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
        // Start share monitoring unconditionally — must not depend on the main
        // window's onAppear, which never fires if the window starts hidden.
        MountManager.shared.startMonitoring()

        // Notification permission must be requested once the app has finished
        // launching; asking from App.init() fails with "not allowed for this application".
        NotificationManager.shared.requestAuthorization()

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
    @StateObject private var mountManager = MountManager.shared
    @StateObject private var loginItemManager = LoginItemManager()
    @Environment(\.openWindow) private var openWindow

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(mountManager)
                .environmentObject(loginItemManager)
        }
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
                .environmentObject(loginItemManager)
        }

        Window("Activity Log", id: "activity-log") {
            LogView()
        }
        .defaultSize(width: 560, height: 440)

        MenuBarExtra {
            MenuBarMenuView()
                .environmentObject(mountManager)
        } label: {
            MenuBarIcon(status: mountManager.overallStatus)
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
}

// MARK: - Menu bar icon

/// Folder glyph with a small colour dot summarising every enabled share:
/// green = all mounted, orange = some connecting or partially mounted,
/// red = an error or a stuck NetAuth. No dot when nothing is enabled.
private struct MenuBarIcon: View {
    let status: MountManager.OverallStatus

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: "folder")
                .foregroundStyle(.primary)
            if let color = dotColor {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                    .overlay(Circle().strokeBorder(.background, lineWidth: 1))
                    .offset(x: 1, y: 1)
            }
        }
        .accessibilityLabel(Text("Connecter"))
        .accessibilityValue(Text(statusDescription))
    }

    private var dotColor: Color? {
        switch status {
        case .idle:      nil
        case .allMounted: .green
        case .partial:   .orange
        case .error:     .red
        }
    }

    private var statusDescription: String {
        switch status {
        case .idle:       String(localized: "No active shares")
        case .allMounted: String(localized: "All connected")
        case .partial:    String(localized: "Partial connection")
        case .error:      String(localized: "Not connected")
        }
    }
}
