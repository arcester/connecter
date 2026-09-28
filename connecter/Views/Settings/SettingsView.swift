import SwiftUI

struct SettingsTab: View {
    @EnvironmentObject private var loginItemManager: LoginItemManager
    @ObservedObject private var settings = AppSettings.shared
    @State private var recoveryMessage: String?

    var body: some View {
        NavigationStack {
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
                } header: {
                    Text("General")
                }

                Section {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Recover shares")
                                .font(.body)
                            Text("Shares saved with a password can be restored from the macOS Keychain, also on another Mac with iCloud Keychain.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Recover…") {
                            recoveryMessage = MountManager.shared.recoverSharesFromKeychain().message
                        }
                        .controlSize(.small)
                    }
                } header: {
                    Text("Keychain")
                }

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
                } header: {
                    Text("Appearance")
                }

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
                } header: {
                    Text("Monitoring")
                } footer: {
                    Text("Backoff: after each failure the next check is delayed (×2, ×4, then 5 min).")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
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
            .formStyle(.grouped)
            .scrollDisabled(true)
            .navigationTitle("Settings")
        }
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .modalWindowStyle()
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
