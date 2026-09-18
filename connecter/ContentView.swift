import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var mountManager: MountManager
    @EnvironmentObject private var loginItemManager: LoginItemManager
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var settings = AppSettings.shared
    @State private var showAddSheet = false
    @State private var editingConfig: ShareConfig?
    @State private var refreshRotation = 0.0
    @State private var isRestartingNetAuth = false
    @State private var netAuthError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if mountManager.netAuthSuspected {
                    NetAuthBanner(
                        isRestarting: isRestartingNetAuth,
                        onRestart: restartNetAuth,
                        onDismiss: { mountManager.dismissNetAuthWarning() }
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
                SharesBody(editingConfig: $editingConfig)
            }
                .navigationTitle("Connecter")
                .toolbar {
                    ToolbarItemGroup(placement: .automatic) {
                        Button { showAddSheet = true } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(settings.accentColor)
                                .font(.title3)
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
        .frame(width: 440)
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
        .alert(
            "Could not restart NetAuth",
            isPresented: Binding(
                get: { netAuthError != nil },
                set: { if !$0 { netAuthError = nil } }
            )
        ) {
            Button("OK") {}
        } message: {
            Text(netAuthError ?? "")
        }
        .onAppear { mountManager.startMonitoring() }
    }

    private func restartNetAuth() {
        isRestartingNetAuth = true
        Task {
            do {
                try await mountManager.restartNetAuth()
            } catch MountError.netAuthRestartCancelled {
                // User dismissed the password dialog — nothing to report
            } catch {
                netAuthError = error.localizedDescription
            }
            isRestartingNetAuth = false
        }
    }

    private static let toolbarHeight: CGFloat = 55  // NavigationStack toolbar inside the frame
    private static let cardSpacing: CGFloat = 10
    private static let listPadding: CGFloat = 32
    private static let minVisible = 2

    private var desiredContentHeight: CGFloat {
        let count = mountManager.configs.count
        let cardH = ShareCard.cardHeight
        // Banner sits above the list with its own top padding
        let bannerH: CGFloat = mountManager.netAuthSuspected ? NetAuthBanner.height + 16 : 0

        let screenH = NSScreen.main?.visibleFrame.height ?? 900
        let maxContentH = screenH - 40
        let maxVisible = max(Self.minVisible,
            Int((maxContentH - Self.toolbarHeight - bannerH - Self.listPadding)
                / (cardH + Self.cardSpacing)))

        let visible = max(Self.minVisible, min(count, maxVisible))
        let listH = Self.listPadding
            + CGFloat(visible) * cardH
            + CGFloat(visible - 1) * Self.cardSpacing
        return min(Self.toolbarHeight + bannerH + listH, maxContentH)
    }
}
