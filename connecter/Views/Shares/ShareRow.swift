import SwiftUI

struct ShareCard: View {
    let index: Int
    let config: ShareConfig
    let onEnable: (Bool) -> Void
    let onTap: () -> Void
    let onRetry: () -> Void

    @ObservedObject private var settings = AppSettings.shared
    private var accent: Color { settings.accentColor }

    private var isConnected: Bool {
        config.isEnabled && config.connectionStatus == .connected
    }

    var body: some View {
        HStack(spacing: 14) {
            // Numbered circle badge
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.07))
                    .frame(width: 30, height: 30)
                Text("\(index + 1)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(config.isEnabled ? accent : Color.secondary)
            }

            // Name + URL — tap to edit
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(config.name.isEmpty ? config.host : config.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(config.isEnabled ? accent : Color.secondary)
                    Text("smb://\(config.host)/\(config.path)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Tap to edit")

            // Status badge or retry button
            if config.isEnabled {
                if config.connectionStatus == .error {
                    Button(action: onRetry) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.red)
                    }
                    .buttonStyle(.plain)
                    .help("Retry connection")
                } else if config.connectionStatus != .disconnected {
                    Text(config.connectionStatus.label)
                        .font(.caption)
                        .foregroundStyle(config.connectionStatus.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .glassEffect(
                            .regular.tint(config.connectionStatus.color.opacity(0.25)),
                            in: Capsule()
                        )
                        .symbolEffect(.pulse, options: .repeating, isActive: config.isBusy)
                }
            }

            // Enable / disable toggle
            Toggle("", isOn: Binding(
                get: { config.isEnabled },
                set: { onEnable($0) }
            ))
            .toggleStyle(.switch)
            .tint(accent)
            .controlSize(.small)
            .disabled(config.isBusy)
            .labelsHidden()
            .help(config.isEnabled ? "Disable this share" : "Enable this share")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    isConnected ? accent.opacity(0.35) : Color.primary.opacity(0.06),
                    lineWidth: 1
                )
        )
    }
}
