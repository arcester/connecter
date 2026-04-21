import SwiftUI

struct SettingsTab: View {
    @EnvironmentObject private var loginItemManager: LoginItemManager
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Launch at Login")
                            .font(.body)
                        Text("Connectar will open automatically on login.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
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
                    Toggle("", isOn: $settings.showOnLaunch)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            } header: {
                Text("General")
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
                    Slider(value: $settings.monitorInterval, in: 15...300, step: 15)
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
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }
}
