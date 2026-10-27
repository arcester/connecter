import SwiftUI

// MARK: - Menu bar content view

struct MenuBarMenuView: View {
    @EnvironmentObject private var mountManager: MountManager

    var body: some View {
        // Summary line: how many enabled shares are mounted, or what is wrong
        let enabled = mountManager.configs.filter(mountManager.isActive)
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

        // One section per server, one item per share — click to mount/unmount
        let groups = mountManager.serverGroups
        if groups.isEmpty {
            Text("No shares configured")
                .foregroundStyle(.secondary)
        } else {
            ForEach(groups) { group in
                let isPaused = mountManager.settings(forHost: group.host).isPaused
                Section(group.host) {
                    ForEach(group.shares) { config in
                        ShareMenuItem(config: config, isPaused: isPaused)
                    }
                    Button(isPaused ? "Resume \(group.host)" : "Pause \(group.host)") {
                        Task { await mountManager.setPaused(!isPaused, host: group.host) }
                    }
                }
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
    /// Its server is paused: shown grey, and not clickable until resumed.
    let isPaused: Bool

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
            // text, and no icon (label images aren't drawn in these rows, and an
            // inline bitmap is rasterised at 1x and looks blurry). An SF Symbol
            // inside the text is drawn as a vector glyph, crisp at any scale, and
            // takes the colour of its text run.
            let row = self.row
            // The symbol follows its text's font: 9 pt makes the dot about 7 pt wide.
            let dot = Text(Image(systemName: "circle.fill"))
                .font(.system(size: 9))
                .foregroundStyle(row.color)
            Text("\(dot)  \(row.text)")
        }
        .disabled(config.isBusy || isPaused)
        .help("\(config.smbURLString) — \(clickHint)")
    }

    /// Green dot + name when mounted, light grey dot + name when disabled or
    /// idle; any other state adds its label, e.g. "(red dot) video — Error".
    private var row: (color: Color, text: String) {
        let name = config.displayName
        if config.connectionStatus == .connected || mountManager.mountPoint(for: config) != nil {
            return (Color(nsColor: .systemGreen), name)
        }
        if !config.isEnabled {
            return (Color(nsColor: .systemGray), name)
        }
        if isPaused {
            return (Color(nsColor: .systemGray), "\(name) — \(String(localized: "Paused"))")
        }
        let status = config.connectionStatus
        let color: Color = switch status {
        case .connected:                  Color(nsColor: .systemGreen)
        case .connecting, .disconnecting: Color(nsColor: .systemOrange)
        case .error:                      Color(nsColor: .systemRed)
        case .disconnected, .offline, .unreachable: Color(nsColor: .systemGray)
        }
        return (color, "\(name) — \(status.label)")
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
