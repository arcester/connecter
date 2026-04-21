import SwiftUI

struct ShareRow: View {
    let config: ShareConfig
    let onEnable: (Bool) -> Void
    let onTap: () -> Void
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(config.name.isEmpty ? config.host : config.name)
                        .font(.headline)
                        .foregroundStyle(config.isEnabled ? .primary : .secondary)
                    Text("smb://\(config.host)/\(config.path)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Tap to edit")

            if config.isEnabled {
                if config.connectionStatus == .error {
                    Button(action: onRetry) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .foregroundStyle(.red)
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .help("Retry connection")
                } else {
                    Text(config.connectionStatus.label)
                        .font(.caption)
                        .foregroundStyle(config.connectionStatus.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .modifier(GlassBadge(tint: config.connectionStatus.color))
                }
            }

            Toggle("", isOn: Binding(get: { config.isEnabled }, set: { onEnable($0) }))
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(config.isBusy)
                .help(config.isEnabled ? "Disable this share" : "Enable this share")
        }
        .padding(.vertical, 4)
    }
}
