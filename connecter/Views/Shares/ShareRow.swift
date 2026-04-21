import SwiftUI

struct ShareCard: View {
    let config: ShareConfig
    let onEnable: (Bool) -> Void
    let onTap: () -> Void
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Drive icon reflects connection state
            Image(systemName: config.isEnabled ? config.connectionStatus.iconName : "externaldrive")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(config.isEnabled ? config.connectionStatus.color : Color.secondary)
                .frame(width: 30)
                .symbolEffect(.pulse, options: .repeating, isActive: config.isBusy)

            // Name + URL — tap anywhere here to open edit sheet
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(config.name.isEmpty ? config.host : config.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(config.isEnabled ? Color.primary : Color.secondary)
                    Text("smb://\(config.host)/\(config.path)")
                        .font(.caption)
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Tap to edit")

            // Retry button (error state) or status badge
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
                }
            }

            // Enable / disable toggle
            Toggle("", isOn: Binding(
                get: { config.isEnabled },
                set: { onEnable($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(config.isBusy)
            .labelsHidden()
            .help(config.isEnabled ? "Disable this share" : "Enable this share")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
    }
}
