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
    /// Set when another copy of Connecter is already running: this process
    /// only hands over to it and quits, without touching shares or windows.
    private var isHandingOver = false
    /// The menu bar icon MenuBarExtra created, and its menu, kept aside so
    /// that it opens only when the click setting says so.
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?

    func applicationWillFinishLaunching(_ notification: Notification) {
        deferToRunningInstanceIfNeeded()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if isHandingOver {
            NSApp.windows.forEach { $0.orderOut(nil) }
            return
        }

        AppSettings.apply(appearance: AppSettings.shared.appearance)
        // MenuBarExtra creates its icon once the scene is up.
        DispatchQueue.main.async { self.takeOverStatusItemClicks() }

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

    /// The main window, whether shown or not. SwiftUI names it "main-…";
    /// otherwise the first ordinary window, as before.
    static var mainWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("main") == true }
            ?? NSApp.windows.first { !($0 is NSPanel) && $0.canBecomeMain }
    }

    /// Clicks on the menu bar icon show or hide the main window or open the
    /// menu, as chosen in Settings (`AppSettings.iconClick`). MenuBarExtra
    /// gives its icon a menu, which opens on any click, so the menu is taken
    /// off the icon and shown only when wanted. If the icon can't be found,
    /// every click keeps opening the menu.
    private func takeOverStatusItemClicks() {
        // shortcut: reads AppKit's private `_statusItem` of its status bar window
        // (checked first, so a macOS without it only keeps MenuBarExtra's clicks).
        let items = NSApp.windows
            .filter { $0.className == "NSStatusBarWindow" && class_getInstanceVariable(type(of: $0), "_statusItem") != nil }
            .compactMap { $0.value(forKey: "statusItem") as? NSStatusItem }
        guard let item = items.first(where: { $0.menu != nil }), let button = item.button else {
            LogManager.shared.warning("Menu bar icon not found — clicks open the menu")
            return
        }
        statusItem = item
        statusMenu = item.menu
        item.menu = nil
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        let isRight = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        let opensMenu: Bool = switch AppSettings.shared.iconClick {
            case .leftWindow:  isRight
            case .rightWindow: !isRight
            case .menu:        true
        }
        guard opensMenu else {
            Self.toggleMainWindow()
            return
        }
        guard let button = statusItem?.button, let menu = statusMenu else { return }
        // Just below the icon, like a menu bar menu.
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 5), in: button)
    }

    /// Hides the main window when it can be seen; brings it up when it is
    /// hidden or fully covered. Not "is it in front": an agent app clicked from
    /// the menu bar is often not the active one, and macOS reorders its windows.
    private static func toggleMainWindow() {
        if let window = mainWindow, window.isVisible, window.occlusionState.contains(.visible) {
            window.orderOut(nil)
        } else {
            NotificationCenter.default.post(name: .showMainWindow, object: nil)
        }
    }

    /// Reopen (Finder double-click, Launchpad, `open -a`, or a second copy
    /// handing over): show the main window instead of doing nothing.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NotificationCenter.default.post(name: .showMainWindow, object: nil)
        return false
    }

    /// Only one Connecter at a time. If another copy is running (for example an
    /// installed build while a new one is launched from Xcode), ask Launch
    /// Services to activate it — which delivers a reopen event, so it shows its
    /// window — and quit this process.
    private func deferToRunningInstanceIfNeeded() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let me = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != me && !$0.isTerminated }
        guard let other = others.first else { return }

        isHandingOver = true
        LogManager.shared.warning("Another instance is already running (pid \(other.processIdentifier)) — showing it and quitting this one")

        if let url = other.bundleURL {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
        } else {
            other.activate()
            NSApp.terminate(nil)
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
                    if let window = AppDelegate.mainWindow {
                        window.makeKeyAndOrderFront(nil)
                        // Up front even if macOS doesn't let the app become active.
                        window.orderFrontRegardless()
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

/// Menu bar label: folder plus a colour dot summarising every enabled share
/// (see `StatusBarIcon`). The image is a single `Image(nsImage:)`, which is
/// the one form of label whose colours `MenuBarExtra` preserves.
private struct MenuBarIcon: View {
    let status: MountManager.OverallStatus

    var body: some View {
        Image(nsImage: StatusBarIcon.image(for: status))
            .accessibilityLabel(Text("Connecter"))
            .accessibilityValue(Text(status.summary))
    }
}
