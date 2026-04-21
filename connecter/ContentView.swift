import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var mountManager: MountManager
    @EnvironmentObject private var loginItemManager: LoginItemManager
    @State private var showSettings = false
    @State private var showLog = false
    @State private var showAddSheet = false
    @State private var editingConfig: ShareConfig?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !mountManager.configs.isEmpty {
                    GlobalStatusBanner(status: globalStatus)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                        .animation(.easeInOut, value: globalStatus)
                }
                SharesBody(editingConfig: $editingConfig)
            }
            .navigationTitle("Connecter")
            .toolbar {
                ToolbarItemGroup {
                    Button { showLog = true } label: {
                        Label("Log", systemImage: "terminal")
                    }
                    Button { showSettings = true } label: {
                        Label("Settings", systemImage: "gear")
                    }
                    Button { showAddSheet = true } label: {
                        Image(systemName: "plus")
                    }
                    .help("Add share")
                }
            }
        }
        .frame(width: 440, height: 520)
        .sheet(isPresented: $showSettings) {
            SettingsTab()
                .environmentObject(loginItemManager)
        }
        .sheet(isPresented: $showLog) {
            LogView()
                .frame(width: 560, height: 440)
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
                if let idx = configs.firstIndex(where: { $0.id == updated.id }) {
                    configs[idx] = updated
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
        .onAppear { mountManager.startMonitoring() }
    }

    private var globalStatus: MenuBarStatus {
        let enabled = mountManager.configs.filter(\.isEnabled)
        guard !enabled.isEmpty else { return .disabled }
        let statuses = enabled.map(\.connectionStatus)
        if statuses.allSatisfy({ $0 == .connected }) { return .allConnected }
        if statuses.contains(.connected) { return .partial }
        return .noneConnected
    }
}
