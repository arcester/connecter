import SwiftUI

/// Settings window: one tab per topic, so each pane stays short.
/// Hosted by the `Settings` scene, which provides ⌘, and per-tab sizing.
struct SettingsView: View {
    @EnvironmentObject private var loginItemManager: LoginItemManager

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsPane()
                    .environmentObject(loginItemManager)
            }
            Tab("Appearance", systemImage: "paintpalette") {
                AppearanceSettingsPane()
            }
            Tab("Monitoring", systemImage: "waveform.path.ecg") {
                MonitoringSettingsPane()
            }
            Tab("Keychain", systemImage: "key") {
                KeychainSettingsPane()
            }
        }
        .frame(width: 440)
        .modalWindowStyle()
    }
}

// MARK: - General

private struct GeneralSettingsPane: View {
    @EnvironmentObject private var loginItemManager: LoginItemManager
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Launch at Login")
                            .font(.body)
                        Text("Connecter will open automatically on login.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("Launch at Login", isOn: Binding(
                        get: { loginItemManager.isEnabled },
                        set: { _ in loginItemManager.toggle() }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }

                if loginItemManager.requiresApproval {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .accessibilityHidden(true)
                        Text("Requires approval in System Settings.")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Spacer()
                        Button("Approve…") {
                            loginItemManager.openSystemSettings()
                        }
                        .controlSize(.small)
                    }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Show on Launch")
                            .font(.body)
                        Text("Display the main window when the app starts.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("Show on Launch", isOn: $settings.showOnLaunch)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }

            Section {
                HStack {
                    Spacer()
                    Text("Connecter \(AppEnvironment.shortVersion) (\(AppEnvironment.buildNumber))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }
        }
        .settingsPane()
    }
}

// MARK: - Appearance

private struct AppearanceSettingsPane: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Accent Color")
                            .font(.body)
                        Text("Color used for share names, numbers, and toggles.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 10) {
                        ForEach(AppSettings.colorOptions, id: \.name) { option in
                            let title = AppSettings.localizedColorName(option.name)
                            Button {
                                settings.accentColorName = option.name
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(option.color)
                                        .frame(width: 26, height: 26)
                                    if settings.accentColorName == option.name {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .help(title)
                            .accessibilityLabel(Text(title))
                            .accessibilityAddTraits(settings.accentColorName == option.name ? .isSelected : [])
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .settingsPane()
    }
}

// MARK: - Monitoring

private struct MonitoringSettingsPane: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Check interval")
                        Spacer()
                        Text("\(Int(settings.monitorInterval)) s")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $settings.monitorInterval, in: 15...300, step: 15) {
                        Text("Check interval")
                    }
                    .labelsHidden()
                }

                Stepper(
                    "Disable after \(settings.maxFailuresBeforeDisable) consecutive failure(s)",
                    value: $settings.maxFailuresBeforeDisable,
                    in: 1...10
                )

                Toggle("Enable mount/unmount notifications", isOn: $settings.notificationsEnabled)
            } footer: {
                Text("Backoff: after each failure the next check is delayed (×2, ×4, then 5 min).")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .settingsPane()
    }
}

// MARK: - Keychain

private struct KeychainSettingsPane: View {
    @ObservedObject private var mountManager = MountManager.shared
    @State private var keychainMessage: String?
    @State private var storedShares: [KeychainManager.StoredShare] = []

    var body: some View {
        Form {
            Section {
                Text("Every share is backed up in the macOS Keychain: name, server, path, user and password. Use it to restore the list on this Mac or, with iCloud Keychain, on another one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if storedShares.isEmpty {
                    Text("No shares saved in the Keychain yet.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(storedShares) { stored in
                                storedShareRow(stored)
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                }

                HStack {
                    Button("Save Now") {
                        let written = mountManager.backUpSharesToKeychain()
                        keychainMessage = written > 0
                            ? String(localized: "\(written) shares saved to the Keychain")
                            : String(localized: "All shares were already saved in the Keychain.")
                        refreshStoredShares()
                    }
                    .help("Write every share in the list to the Keychain now")
                    Spacer()
                    Button("Recover All") {
                        keychainMessage = mountManager.recoverSharesFromKeychain().message
                        refreshStoredShares()
                    }
                    .disabled(!storedShares.contains { !isInList($0) })
                    .help("Add every saved share that is missing from the list")
                }
                .controlSize(.small)
            }
        }
        .settingsPane()
        .onAppear(perform: refreshStoredShares)
        .onChange(of: mountManager.configs.count) { _, _ in refreshStoredShares() }
        .alert(
            "Keychain",
            isPresented: Binding(
                get: { keychainMessage != nil },
                set: { if !$0 { keychainMessage = nil } }
            )
        ) {
            Button("OK") {}
        } message: {
            Text(keychainMessage ?? "")
        }
    }

    private func refreshStoredShares() {
        storedShares = KeychainManager.storedShares()
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private func isInList(_ stored: KeychainManager.StoredShare) -> Bool {
        mountManager.configs.contains { stored.matches($0) }
    }

    @ViewBuilder
    private func storedShareRow(_ stored: KeychainManager.StoredShare) -> some View {
        let inList = isInList(stored)
        HStack(spacing: 10) {
            Image(systemName: inList ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(inList ? Color.green : Color.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(stored.displayName)
                    .font(.callout.weight(.medium))
                Text(stored.username.isEmpty ? stored.smbURLString : "\(stored.smbURLString) · \(stored.username)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if !stored.hasPassword {
                Text("No password")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if inList {
                Text("In list")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button("Add") {
                    keychainMessage = mountManager.recoverSharesFromKeychain(only: [stored.id]).message
                    refreshStoredShares()
                }
                .controlSize(.small)
                .help("Add this saved share to the list")
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(inList ? "In list" : "Not in list"))
    }
}

// MARK: - Shared pane styling

private extension View {
    /// Grouped form that sizes the window to its content instead of scrolling.
    func settingsPane() -> some View {
        self
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)
    }
}
