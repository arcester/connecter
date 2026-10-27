import SwiftUI

struct SharesBody: View {
    @EnvironmentObject private var mountManager: MountManager
    @Binding var editingConfig: ShareConfig?
    /// Opens the new-share sheet with the given host filled in.
    let onAddShare: (String) -> Void
    /// Shares that have a password in the Keychain and could be restored.
    @State private var recoverableShares = 0
    @State private var recoveryMessage: String?
    @State private var editingServer: MountManager.ServerGroup?

    /// Layout constants shared with the window-height calculation in ContentView.
    static let groupSpacing: CGFloat = 16
    static let headerSpacing: CGFloat = 4

    var body: some View {
        if mountManager.configs.isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(spacing: Self.groupSpacing) {
                    ForEach(mountManager.serverGroups) { group in
                        VStack(spacing: Self.headerSpacing) {
                            ServerHeader(group: group) {
                                editingServer = group
                            } onAddShare: {
                                onAddShare(group.host)
                            }
                            // The server's shares in one outlined box, separated by hairlines
                            VStack(spacing: 0) {
                                ForEach(group.shares) { config in
                                    if config.id != group.shares.first?.id {
                                        Divider().padding(.leading, 44)
                                    }
                                    ShareCard(config: config, isPaused: mountManager.isPaused(config)) { enabled in
                                        setEnabled(enabled, for: config)
                                    } onTap: {
                                        editingConfig = config
                                    } onRetry: {
                                        Task { await mountManager.retryShare(id: config.id) }
                                    }
                                    .contextMenu { contextMenu(for: config) }
                                }
                            }
                            .outlinedBox()
                        }
                    }
                }
                .padding(16)
            }
            .sheet(item: $editingServer) { group in
                ServerCredentialsSheet(host: group.host)
            }
        }
    }

    // MARK: - Actions

    private func setEnabled(_ enabled: Bool, for config: ShareConfig) {
        if !enabled && mountManager.isMounted(config) {
            mountManager.markDisconnecting(id: config.id)
            Task {
                try? await mountManager.unmount(config)
                mountManager.setEnabled(false, forID: config.id)
            }
        } else {
            mountManager.setEnabled(enabled, forID: config.id)
        }
    }

    @ViewBuilder
    private func contextMenu(for config: ShareConfig) -> some View {
        // Status line: mounted (with its path) or the current state
        let mountPoint = mountManager.mountPoint(for: config)
        Button {} label: {
            if let mountPoint {
                Label("Mounted at \(mountPoint)", systemImage: "checkmark.circle.fill")
            } else if config.isEnabled && mountManager.isPaused(config) {
                Label("Paused", systemImage: "pause.circle")
            } else if config.isEnabled {
                Label(config.connectionStatus.label, systemImage: config.connectionStatus.menuIconName)
            } else {
                Label("Disabled", systemImage: "circle.slash")
            }
        }
        .disabled(true)
        Divider()

        Button {
            editingConfig = config
        } label: {
            Label("Edit…", systemImage: "pencil")
        }
        if let mountPoint {
            Button {
                openInFinder(config, mountPoint: mountPoint)
            } label: {
                Label("Open in Finder", systemImage: "folder")
            }
        }
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(config.smbURLString, forType: .string)
        } label: {
            Label("Copy SMB URL", systemImage: "doc.on.doc")
        }
    }

    /// A sandboxed app may not open arbitrary paths under /Volumes, but Finder
    /// opens the share's smb:// URL and reuses the existing mount.
    private func openInFinder(_ config: ShareConfig, mountPoint: String) {
        if AppEnvironment.isSandboxed, let url = URL(string: config.smbURLString) {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: mountPoint))
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.questionmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .padding(24)
                .accessibilityHidden(true)
            Text("No shares configured")
                .font(.headline)
            Text("Press + to add an SMB share.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if recoverableShares > 0 {
                Button {
                    let result = mountManager.recoverSharesFromKeychain()
                    if result.added == 0 { recoveryMessage = result.message }
                } label: {
                    Label("Recover from Keychain", systemImage: "key")
                }
                .buttonStyle(.borderedProminent)
                .help("Restore the shares whose passwords are saved in your Keychain")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { recoverableShares = KeychainManager.storedShares().count }
        .alert(
            "Recover from Keychain",
            isPresented: Binding(
                get: { recoveryMessage != nil },
                set: { if !$0 { recoveryMessage = nil } }
            )
        ) {
            Button("OK") {}
        } message: {
            Text(recoveryMessage ?? "")
        }
    }
}

// MARK: - Server header

/// Title of a server's group: host, how many of its shares are mounted, and
/// the pause / credentials / add-share actions that apply to all of them.
struct ServerHeader: View {
    static let height: CGFloat = 28

    @EnvironmentObject private var mountManager: MountManager
    let group: MountManager.ServerGroup
    let onEditCredentials: () -> Void
    let onAddShare: () -> Void

    private var isPaused: Bool { mountManager.settings(forHost: group.host).isPaused }

    var body: some View {
        let enabled = group.shares.filter(\.isEnabled)
        let mounted = enabled.filter { $0.connectionStatus == .connected }.count
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor(mounted: mounted, enabled: enabled.count))
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(group.host)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            if isPaused || !enabled.isEmpty {
                Text(isPaused ? String(localized: "Paused") : String(localized: "\(mounted) of \(enabled.count) mounted"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button {
                Task { await mountManager.setPaused(!isPaused, host: group.host) }
            } label: {
                Image(systemName: isPaused ? "play.circle" : "pause.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(isPaused ? "Resume this server" : "Pause this server: unmount its shares and stop reconnecting them")
            .accessibilityLabel(Text(isPaused ? "Resume this server" : "Pause this server"))
            Menu {
                Button("Server Credentials…", systemImage: "key", action: onEditCredentials)
                Button("Add Share on This Server…", systemImage: "plus", action: onAddShare)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .foregroundStyle(.secondary)
            .fixedSize()
            .accessibilityLabel(Text("Server actions"))
        }
        .padding(.horizontal, 4)
        .frame(height: Self.height)
    }

    /// Green when every active share is mounted, orange when some are, red on
    /// an error, grey when paused or nothing is active.
    private func statusColor(mounted: Int, enabled: Int) -> Color {
        if isPaused || enabled == 0 { return .secondary }
        if group.shares.contains(where: { $0.isEnabled && $0.connectionStatus == .error }) { return .red }
        if mounted == enabled { return .green }
        return mounted > 0 ? .orange : .secondary
    }
}
