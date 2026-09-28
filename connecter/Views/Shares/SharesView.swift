import SwiftUI

struct SharesBody: View {
    @EnvironmentObject private var mountManager: MountManager
    @Binding var editingConfig: ShareConfig?
    /// Shares that have a password in the Keychain and could be restored.
    @State private var recoverableShares = 0
    @State private var recoveryMessage: String?

    private var sortedConfigs: [ShareConfig] {
        mountManager.configs.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    var body: some View {
        if mountManager.configs.isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(sortedConfigs) { config in
                        ShareCard(config: config) { enabled in
                            setEnabled(enabled, for: config)
                        } onTap: {
                            editingConfig = config
                        } onRetry: {
                            Task { await mountManager.retryShare(id: config.id) }
                        }
                        .contextMenu { contextMenu(for: config) }
                    }
                }
                .padding(16)
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
                .glassEffect(in: Circle())
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
                .buttonStyle(.glassProminent)
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
