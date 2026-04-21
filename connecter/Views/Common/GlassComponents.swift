import SwiftUI

/// Section panel: glass in macOS 26+, GroupBox on older versions.
struct GlassSection<Content: View>: View {
    let label: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        if #available(macOS 26, *) {
            VStack(alignment: .leading, spacing: 8) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 2)
                content
            }
            .padding(12)
            .glassEffect(in: .rect(cornerRadius: 12))
        } else {
            GroupBox(label) { content }
        }
    }
}

/// Status badge: tinted glass in macOS 26+, opaque background otherwise.
struct GlassBadge: ViewModifier {
    let tint: Color
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular.tint(tint.opacity(0.35)), in: Capsule())
        } else {
            content.background(tint.opacity(0.12), in: Capsule())
        }
    }
}

/// Circular glass background for empty-state icons.
struct GlassIconBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(in: Circle())
        } else {
            content
        }
    }
}

/// Primary button: glass-prominent in macOS 26+, bordered-prominent otherwise.
struct PrimaryButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.borderedProminent)
        }
    }
}
