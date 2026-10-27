import SwiftUI
import AppKit

// MARK: - Section panel

/// Section container: caption label over flat content with a hairline border.
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
        .outlinedBox()
    }
}

// MARK: - Outlined box

extension View {
    /// Flat panel with a hairline border — the app's container style.
    func outlinedBox(cornerRadius: CGFloat = 8) -> some View {
        background(.background.secondary, in: .rect(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(.separator))
    }
}

// MARK: - Primary button

/// Prominent button style.
struct PrimaryButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.buttonStyle(.borderedProminent)
    }
}

// MARK: - NetAuth warning banner

/// Warns that macOS's NetAuth service stopped answering mount requests.
/// Non-sandboxed builds offer to restart it; the sandboxed App Store build
/// opens step-by-step instructions instead. Fixed height so the window size
/// stays deterministic.
struct NetAuthBanner: View {
    static let height: CGFloat = 74

    let isRestarting: Bool
    let onPrimaryAction: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Mount requests are stuck")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("macOS's NetAuth service is not responding. Restart it to recover the mounts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onPrimaryAction) {
                if isRestarting {
                    ProgressView().controlSize(.small)
                } else if AppEnvironment.isSandboxed {
                    Text("How to Fix…")
                } else {
                    Text("Restart NetAuth")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRestarting)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
            .accessibilityLabel(Text("Dismiss"))
        }
        .padding(.horizontal, 14)
        .frame(height: Self.height)
        .background(.orange.opacity(0.1), in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.orange.opacity(0.5)))
    }
}
