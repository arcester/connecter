import SwiftUI

struct SharesBody: View {
    @EnvironmentObject private var mountManager: MountManager
    @Binding var editingConfig: ShareConfig?

    private var sortedConfigs: [ShareConfig] {
        mountManager.configs.sorted {
            ($0.name.isEmpty ? $0.host : $0.name).localizedCaseInsensitiveCompare(
                $1.name.isEmpty ? $1.host : $1.name
            ) == .orderedAscending
        }
    }

    var body: some View {
        if mountManager.configs.isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(Array(sortedConfigs.enumerated()), id: \.element.id) { index, config in
                        ShareCard(index: index, config: config) { enabled in
                            if !enabled && mountManager.isMounted(config) {
                                mountManager.markDisconnecting(id: config.id)
                                Task {
                                    try? await mountManager.unmount(config)
                                    mountManager.setEnabled(false, forID: config.id)
                                }
                            } else {
                                mountManager.setEnabled(enabled, forID: config.id)
                            }
                        } onTap: {
                            editingConfig = config
                        } onRetry: {
                            Task { await mountManager.retryShare(id: config.id) }
                        }
                        .contextMenu {
                            Button {
                                editingConfig = config
                            } label: {
                                Label("Edit…", systemImage: "pencil")
                            }
                            if let mountPoint = mountManager.mountPoint(for: config) {
                                Button {
                                    NSWorkspace.shared.open(URL(fileURLWithPath: mountPoint))
                                } label: {
                                    Label("Open in Finder", systemImage: "folder")
                                }
                            }
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(
                                    "smb://\(config.host)/\(config.path)", forType: .string
                                )
                            } label: {
                                Label("Copy SMB URL", systemImage: "doc.on.doc")
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.questionmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .padding(24)
                .glassEffect(in: Circle())
            Text("No shares configured")
                .font(.headline)
            Text("Press + to add an SMB share.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
