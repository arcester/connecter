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
            MenuBarIcon()
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

private struct MenuBarIcon: View {
    var body: some View {
        Image(systemName: "folder")
            .accessibilityLabel(Text("Connecter"))
    }
}
