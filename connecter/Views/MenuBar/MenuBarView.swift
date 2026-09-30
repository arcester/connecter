import SwiftUI

// MARK: - Menu bar content view

struct MenuBarMenuView: View {
    @EnvironmentObject private var mountManager: MountManager

    var body: some View {
        // Summary line: how many enabled shares are mounted, or what is wrong
        let enabled = mountManager.configs.filter(\.isEnabled)
        let mounted = enabled.filter { $0.connectionStatus == .connected }.count
        Button {} label: {
            if mountManager.netAuthSuspected {
                Label("Mount requests are stuck", systemImage: "exclamationmark.triangle.fill")
            } else if enabled.isEmpty {
                Label(mountManager.overallStatus.summary, systemImage: "folder")
            } else {
                Label("\(mounted) of \(enabled.count) mounted", systemImage: mountManager.overallStatus.menuSymbol)
            }
        }
        .disabled(true)
        Divider()

        // One item per share — click to mount/unmount
        let sorted = mountManager.configs.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        if sorted.isEmpty {
            Text("No shares configured")
                .foregroundStyle(.secondary)
        } else {
            ForEach(sorted) { config in
                ShareMenuItem(config: config)
            }
        }

        if mountManager.netAuthSuspected {
            Divider()
            if AppEnvironment.isSandboxed {
                // The sandboxed build can't restart NetAuth; the main window explains how.
                Button {
                    NotificationCenter.default.post(name: .showMainWindow, object: nil)
                } label: {
                    Label("Mount requests are stuck…", systemImage: "exclamationmark.triangle.fill")
                }
            } else {
                Button {
                    Task { try? await mountManager.restartNetAuth() }
                } label: {
                    Label("Restart NetAuth…", systemImage: "exclamationmark.triangle.fill")
                }
            }
        }

        Divider()

        Button("Open Connecter…") {
            NotificationCenter.default.post(name: .showMainWindow, object: nil)
        }
        .keyboardShortcut("o", modifiers: .command)

        Divider()

        Button("Quit") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}

// MARK: - Per-share menu item with mount/unmount action

private struct ShareMenuItem: View {
    @EnvironmentObject private var mountManager: MountManager
    let config: ShareConfig

    var body: some View {
        Button {
            Task {
                if !config.isEnabled {
                    // Re-enable — task starts immediately and tries to connect
                    mountManager.setEnabled(true, forID: config.id)
                } else if config.connectionStatus == .connected {
                    // Block interaction immediately before the async unmount begins.
                    mountManager.markDisconnecting(id: config.id)
                    try? await mountManager.unmount(config)
                    mountManager.setEnabled(false, forID: config.id)
                } else {
                    // Goes through the per-share guard, so it can't overlap a running attempt.
                    await mountManager.retryShare(id: config.id)
                }
            }
        } label: {
            // A MenuBarExtra menu bridges this to a plain NSMenuItem: one line of
            // text, and no icon (label images aren't drawn in these rows). So the
            // status goes into the text itself — see ConnectionStatusStyle.menuDot.
            let row = self.row
            let dot = Text(Image(nsImage: row.dot)).baselineOffset(MenuDot.baselineOffset)
            Text("\(dot) \(row.text)")
        }
        .disabled(config.isBusy)
        .help("\(config.smbURLString) — \(clickHint)")
    }

    /// Green dot + name when mounted, light grey dot + name when disabled or
    /// idle; any other state adds its label, e.g. "(red dot) video — Error".
    private var row: (dot: NSImage, text: String) {
        let name = config.displayName
        if mountManager.mountPoint(for: config) != nil {
            return (MenuDot.mounted, name)
        }
        let status = config.connectionStatus
        if !config.isEnabled || status == .disconnected {
            return (MenuDot.idle, name)
        }
        return (MenuDot.image(for: status), "\(name) — \(status.label)")
    }

    private var clickHint: String {
        if config.connectionStatus == .connected {
            String(localized: "Click to unmount and disable")
        } else if config.connectionStatus == .connecting {
            String(localized: "Connecting…")
        } else if config.isEnabled {
            String(localized: "Click to mount")
        } else {
            String(localized: "Click to enable and mount")
        }
    }
}

private extension MountManager.OverallStatus {
    var menuSymbol: String {
        switch self {
        case .idle:       "folder"
        case .allMounted: "checkmark.circle.fill"
        case .partial:    "circle.lefthalf.filled"
        case .error:      "xmark.circle.fill"
        }
    }
}
