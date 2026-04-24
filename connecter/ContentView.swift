import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var mountManager: MountManager
    @EnvironmentObject private var loginItemManager: LoginItemManager
    @Environment(\.openWindow) private var openWindow
    @State private var showAddSheet = false
    @State private var editingConfig: ShareConfig?
    @State private var refreshRotation = 0.0

    var body: some View {
        NavigationStack {
            SharesBody(editingConfig: $editingConfig)
                .onPreferenceChange(ShareListHeightKey.self) { h in
                    if h > 0 { measuredListHeight = h }
                }
                .navigationTitle("Connecter")
                .toolbar {
                    ToolbarItemGroup(placement: .automatic) {
                        Button { showAddSheet = true } label: {
                            Image(systemName: "plus")
                                .foregroundStyle(.green)
                        }
                        .help("Add share")

                        Button {
                            withAnimation(.linear(duration: 0.5)) {
                                refreshRotation += 360
                            }
                            let ids = mountManager.configs.filter(\.isEnabled).map(\.id)
                            Task {
                                await withTaskGroup(of: Void.self) { group in
                                    for id in ids {
                                        group.addTask { await mountManager.refreshShare(id: id) }
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .rotationEffect(.degrees(refreshRotation))
                        }
                        .help("Refresh shares")

                        Button { openWindow(id: "settings") } label: {
                            Label("Settings", systemImage: "gear")
                        }

                        Button { openWindow(id: "activity-log") } label: {
                            Label("Log", systemImage: "terminal")
                        }
                    }
                }
        }
        .frame(width: 440, height: desiredContentHeight)
        .background(WindowResizer(width: 440, height: desiredContentHeight))
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

    // Measured from real rendered content via ShareListHeightKey preference.
    @State private var measuredListHeight: CGFloat = 0

    // Fallback constants used only before first measurement.
    private static let toolbarHeight: CGFloat = 40
    private static let cardSpacing: CGFloat = 10
    private static let listPadding: CGFloat = 32
    private static let fallbackCardHeight: CGFloat = 52
    private static let minVisible = 2
    private static let maxVisible = 8

    private var desiredContentHeight: CGFloat {
        let count = mountManager.configs.count

        // measuredListHeight = listPadding + count*cardH + (count-1)*spacing
        // → cardH = (measuredListHeight - listPadding - (count-1)*spacing) / count
        let cardH: CGFloat
        if measuredListHeight > 0, count > 0 {
            cardH = (measuredListHeight - Self.listPadding
                     - CGFloat(count - 1) * Self.cardSpacing) / CGFloat(count)
        } else {
            cardH = Self.fallbackCardHeight
        }

        let visible = max(Self.minVisible, min(count, Self.maxVisible))
        let listH = Self.listPadding
            + CGFloat(visible) * cardH
            + CGFloat(visible - 1) * Self.cardSpacing
        return Self.toolbarHeight + listH
    }
}
