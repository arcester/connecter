import SwiftUI

struct ShareCard: View {
    static let cardHeight: CGFloat = 44

    let config: ShareConfig
    /// Its server is paused: the share is shown as such whatever its state.
    var isPaused = false
    let onEnable: (Bool) -> Void
    let onTap: () -> Void
    let onRetry: () -> Void

    @ObservedObject private var settings = AppSettings.shared
    private var accent: Color { settings.accentColor }

    /// The state shown as a tag next to the name: paused, or any state other
    /// than `.disconnected`. Disabled shares show none.
    private var statusTag: (text: String, color: Color)? {
        guard config.isEnabled else { return nil }
        if isPaused { return (String(localized: "Paused"), .secondary) }
        if config.connectionStatus == .disconnected { return nil }
        return (config.connectionStatus.label, config.connectionStatus.color)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "externaldrive.connected.to.line.below")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 22)
                .accessibilityHidden(true)

            // Name + state tag over the URL — click to edit
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(config.displayName)
                            .font(.body.weight(.bold))
                            .foregroundStyle(config.isEnabled ? Color.primary : Color.secondary)
                        if let tag = statusTag {
                            StatusTag(text: tag.text, color: tag.color)
                                .symbolEffect(.pulse, options: .repeating, isActive: config.isBusy)
                        }
                    }
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
            .accessibilityValue(Text(
                !config.isEnabled ? String(localized: "Disabled")
                    : isPaused ? String(localized: "Paused") : config.connectionStatus.label
            ))
            .accessibilityHint(Text("Click to edit"))

            if config.isEnabled && !isPaused && config.connectionStatus == .error {
                Button(action: onRetry) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Retry connection")
                .accessibilityLabel(Text("Retry connection"))
            }

            // Enable / disable toggle
            Toggle("Enabled", isOn: Binding(
                get: { config.isEnabled },
                set: { onEnable($0) }
            ))
            .toggleStyle(.switch)
            .tint(accent)
            .controlSize(.mini)
            .disabled(config.isBusy)
            .labelsHidden()
            .help(config.isEnabled ? "Disable this share" : "Enable this share")
        }
        .padding(.horizontal, 12)
        .frame(height: Self.cardHeight)
        .contentShape(Rectangle())
    }
}

/// State label on a pale capsule of its colour, e.g. a green "Mounted".
private struct StatusTag: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(color.opacity(0.15), in: Capsule())
    }
}
