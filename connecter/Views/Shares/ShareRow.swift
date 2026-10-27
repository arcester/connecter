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

    private var isConnected: Bool {
        config.isEnabled && !isPaused && config.connectionStatus == .connected
    }

    /// Mounted shares take the accent colour; orange and red are reserved for
    /// transitions and errors, so anything that isn't the accent needs a look.
    private var glyphColor: Color {
        guard config.isEnabled, !isPaused else { return .secondary }
        switch config.connectionStatus {
        case .connected:                 return accent
        case .connecting, .disconnecting: return .orange
        case .error:                     return .red
        case .disconnected, .offline, .unreachable: return .secondary
        }
    }

    /// States that get a status capsule; `.disconnected` shows nothing and
    /// `.error` shows the retry button instead.
    private var showsStatusBadge: Bool {
        switch config.connectionStatus {
        case .connecting, .connected, .disconnecting, .offline, .unreachable: true
        case .disconnected, .error: false
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            // Network-drive glyph tinted by state — accent when mounted, orange/red when not
            Image(systemName: "externaldrive.connected.to.line.below")
                .font(.system(size: 15))
                .foregroundStyle(glyphColor)
                .frame(width: 22)
                .accessibilityHidden(true)

            // Name + URL — click to edit
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(config.displayName)
                        .font(.body.weight(.medium))
                        .foregroundStyle(config.isEnabled ? Color.primary : Color.secondary)
                    Text(config.smbURLString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

            // Status (dot + label) or retry button
            if config.isEnabled {
                if isPaused {
                    StatusLabel(text: String(localized: "Paused"), color: .secondary)
                } else if config.connectionStatus == .error {
                    Button(action: onRetry) {
                        Label("Retry", systemImage: "arrow.clockwise")
                            .font(.caption)
                            .foregroundStyle(Color.red)
                    }
                    .buttonStyle(.plain)
                    .help("Retry connection")
                    .accessibilityLabel(Text("Retry connection"))
                } else if showsStatusBadge {
                    StatusLabel(text: config.connectionStatus.label, color: config.connectionStatus.color)
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

/// Small coloured dot followed by a state label.
private struct StatusLabel: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
