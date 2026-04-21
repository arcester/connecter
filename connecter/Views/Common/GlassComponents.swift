import SwiftUI

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
