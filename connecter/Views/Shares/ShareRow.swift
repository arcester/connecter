import SwiftUI

struct ShareCard: View {
    static let cardHeight: CGFloat = 56

    let config: ShareConfig
    let onEnable: (Bool) -> Void
    let onTap: () -> Void
    let onRetry: () -> Void

    @ObservedObject private var settings = AppSettings.shared
    private var accent: Color { settings.accentColor }

    private var isConnected: Bool {
        config.isEnabled && config.connectionStatus == .connected
    }

    private var glyphColor: Color {
        guard config.isEnabled else { return .secondary }
        switch config.connectionStatus {
        case .connected:                 return .green
        case .connecting, .disconnecting: return .orange
        case .error:                     return .red
        case .disconnected, .offline:    return .secondary
        }
    }

    /// States that get a status capsule; `.disconnected` shows nothing and
    /// `.error` shows the retry button instead.
    private var showsStatusBadge: Bool {
        switch config.connectionStatus {
        case .connecting, .connected, .disconnecting, .offline: true
        case .disconnected, .error: false
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            // Folder glyph tinted by state — a quick scan of the list shows what is mounted
            Image(systemName: isConnected ? "folder.fill" : "folder")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(glyphColor)
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)

            // Name + URL — click to edit
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(config.displayName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(config.isEnabled ? Color.primary : Color.secondary)
                    Text(config.smbURLString)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Click to edit")
            .accessibilityLabel(Text(config.displayName))
            .accessibilityValue(Text(config.isEnabled ? config.connectionStatus.label : String(localized: "Disabled")))
            .accessibilityHint(Text("Click to edit"))

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
                    .accessibilityLabel(Text("Retry connection"))
                } else if showsStatusBadge {
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
            Toggle("Enabled", isOn: Binding(
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
        .frame(height: Self.cardHeight)
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
