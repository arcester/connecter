import SwiftUI

struct SharesTab: View {
    @EnvironmentObject private var mountManager: MountManager
    @State private var showAddSheet = false
    @State private var editingConfig: ShareConfig? = nil

    private var sortedConfigs: [ShareConfig] {
        mountManager.configs.sorted {
            ($0.name.isEmpty ? $0.host : $0.name).localizedCaseInsensitiveCompare(
                $1.name.isEmpty ? $1.host : $1.name
            ) == .orderedAscending
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if mountManager.configs.isEmpty {
                    emptyState
                } else {
                    shareList
                }
            }
            .navigationTitle("Shares")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Label("Add share", systemImage: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            ShareFormSheet(existing: nil) { newConfig in
                var configs = mountManager.configs
                configs.append(newConfig)
                ShareConfig.saveAll(configs)
                mountManager.reloadConfigs()
            }
        }
        .sheet(item: $editingConfig) { config in
            ShareFormSheet(existing: config) { updated in
                var configs = mountManager.configs
                if let index = configs.firstIndex(where: { $0.id == updated.id }) {
                    configs[index] = updated
                }
                ShareConfig.saveAll(configs)
                mountManager.reloadConfigs()
            } onDelete: {
                var configs = mountManager.configs
                configs.removeAll { $0.id == config.id }
                ShareConfig.saveAll(configs)
                mountManager.reloadConfigs()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.questionmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .padding(24)
                .modifier(GlassIconBackground())
            Text("No shares configured")
                .font(.headline)
            Text("Press + to add an SMB share.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Add share") { showAddSheet = true }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var shareList: some View {
        List {
            ForEach(sortedConfigs) { config in
                ShareRow(config: config) { enabled in
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
            }
        }
        .listStyle(.inset)
    }
}
