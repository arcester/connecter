import SwiftUI

// MARK: - Menu bar content view

struct MenuBarMenuView: View {
    @EnvironmentObject private var mountManager: MountManager

    var body: some View {
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
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(config.displayName)
                    Text(config.smbURLString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: config.connectionStatus.menuIconName)
                    .foregroundStyle(config.connectionStatus.color)
            }
        }
        .disabled(config.isBusy)
        .help(config.connectionStatus == .connected ? "Click to unmount and disable"
              : config.connectionStatus == .connecting ? "Connecting…"
              : config.isEnabled ? "Click to mount"
              : "Click to enable and mount")
    }
}
