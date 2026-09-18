import SwiftUI
import AppKit

// MARK: - Window button configuration

/// Removes the minimize (amber) button from the host NSWindow.
private struct MiniaturizeDisabler: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { configure(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard nsView.window != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { configure(nsView.window) }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.styleMask.remove(.miniaturizable)
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.superview?.needsDisplay = true
    }
}

extension View {
    /// Hides the amber (minimize) traffic-light button on the containing NSWindow.
    func disableMiniaturize() -> some View {
        background(MiniaturizeDisabler())
    }
}

// MARK: - Section panel

/// Glass-styled section container.
struct GlassSection<Content: View>: View {
    let label: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)
            content
        }
        .padding(12)
        .glassEffect(in: .rect(cornerRadius: 12))
    }
}

// MARK: - Status badge

/// Tinted glass capsule for connection status labels.
struct GlassBadge: ViewModifier {
    let tint: Color
    func body(content: Content) -> some View {
        content.glassEffect(.regular.tint(tint.opacity(0.35)), in: Capsule())
    }
}

// MARK: - Primary button

/// Glass-prominent button style.
struct PrimaryButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.buttonStyle(.glassProminent)
    }
}

// MARK: - NetAuth warning banner

/// Warns that macOS's NetAuth service stopped answering mount requests and
/// offers to restart it. Fixed height so the window size stays deterministic.
struct NetAuthBanner: View {
    static let height: CGFloat = 74

    let isRestarting: Bool
    let onRestart: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Mount requests are stuck")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("macOS's NetAuth service is not responding. Restarting it needs an administrator password.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onRestart) {
                if isRestarting {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Restart NetAuth")
                }
            }
            .buttonStyle(.glassProminent)
            .disabled(isRestarting)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, 14)
        .frame(height: Self.height)
        .glassEffect(.regular.tint(.orange.opacity(0.18)), in: .rect(cornerRadius: 14))
    }
}

// MARK: - Global status banner

/// Full-width pill that reflects the overall connection state across all shares.
struct GlobalStatusBanner: View {
    let status: MenuBarStatus

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: status.iconName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(status.color)
                .symbolEffect(
                    .pulse,
                    options: .repeating,
                    isActive: status == .noneConnected || status == .partial
                )
            Text(status.label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(status.color)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .glassEffect(.regular.tint(status.color.opacity(0.18)), in: .rect(cornerRadius: 10))
    }
}
