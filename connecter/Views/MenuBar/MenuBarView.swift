import SwiftUI
import ServiceManagement

// MARK: - Menu bar content view

struct MenuBarMenuView: View {
    @EnvironmentObject private var mountManager: MountManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // One item per share — tap to mount/unmount
        let sorted = mountManager.configs.sorted {
            ($0.name.isEmpty ? $0.host : $0.name).localizedCaseInsensitiveCompare(
                $1.name.isEmpty ? $1.host : $1.name
            ) == .orderedAscending
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
            Button {
                Task { try? await mountManager.restartNetAuth() }
            } label: {
                Label("Restart NetAuth…", systemImage: "exclamationmark.triangle.fill")
            }
        }

        Divider()

        Button("Open Connecter…") {
            NotificationCenter.default.post(name: .showMainWindow, object: nil)
        }
        .keyboardShortcut("o", modifiers: .command)

        Button("Settings…") {
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",", modifiers: .command)

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
                    try? await mountManager.mount(config)
                    await mountManager.refreshShare(id: config.id)
                }
            }
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(config.name.isEmpty ? config.host : config.name)
                    Text("smb://\(config.host)/\(config.path)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: config.connectionStatus.menuIconName)
                    .foregroundStyle(config.connectionStatus.menuColor)
            }
        }
        .disabled(config.isBusy)
        .help(config.connectionStatus == .connected ? "Tap to unmount and disable"
              : config.connectionStatus == .connecting ? "Connecting…"
              : config.isEnabled ? "Tap to mount"
              : "Tap to enable and mount")
    }
}

// MARK: - ConnectionStatus display for menu

extension ShareConfig.ConnectionStatus {
    var menuIconName: String {
        switch self {
        case .disconnected:   "circle"
        case .connecting:     "arrow.trianglehead.2.clockwise"
        case .connected:      "checkmark.circle.fill"
        case .disconnecting:  "arrow.trianglehead.2.clockwise"
        case .error:          "xmark.circle.fill"
        }
    }

    var menuColor: Color {
        switch self {
        case .disconnected:   .secondary
        case .connecting:     .orange
        case .connected:      .green
        case .disconnecting:  .orange
        case .error:          .red
        }
    }
}
