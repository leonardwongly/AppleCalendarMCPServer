import SwiftUI

// MARK: - Liquid Glass helpers
//
// Liquid Glass (the `glassEffect`, `Glass`, `GlassEffectContainer`, and
// `.buttonStyle(.glass*)` APIs) is available on macOS 26.0+. This package still
// targets macOS 13, so every adoption is guarded by `#available` and degrades to
// a system-material / bordered appearance on older systems. Keeping these helpers
// in one place means the views stay declarative and the fallback logic lives once.

extension View {
    /// Applies a Liquid Glass effect clipped to `shape` on macOS 26+, falling back
    /// to a `.regularMaterial` background on earlier systems.
    @ViewBuilder
    func liquidGlass(
        in shape: some Shape,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        if #available(macOS 26.0, *) {
            modifier(LiquidGlassModifier(shape: shape, tint: tint, interactive: interactive))
        } else {
            background(.regularMaterial, in: shape)
        }
    }

    /// A rounded (continuous-corner) Liquid Glass card. Corner radius uses the
    /// continuous style so nested shapes read as concentric.
    func glassCard(
        cornerRadius: CGFloat = 16,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        liquidGlass(
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
            tint: tint,
            interactive: interactive
        )
    }

    /// Prominent (accent-filled) glass button style on macOS 26+, `.borderedProminent` otherwise.
    @ViewBuilder
    func glassProminentButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }

    /// Standard glass button style on macOS 26+, `.bordered` otherwise.
    @ViewBuilder
    func glassButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }
}

@available(macOS 26.0, *)
private struct LiquidGlassModifier<S: Shape>: ViewModifier {
    let shape: S
    let tint: Color?
    let interactive: Bool

    func body(content: Content) -> some View {
        var glass: Glass = .regular
        if let tint {
            glass = glass.tint(tint)
        }
        if interactive {
            glass = glass.interactive()
        }
        return content.glassEffect(glass, in: shape)
    }
}

/// Groups adjacent Liquid Glass elements so they blend/merge correctly (and can
/// morph together). On macOS < 26 it is a transparent pass-through.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat?
    @ViewBuilder var content: Content

    init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

/// A titled, frosted content card. Cards sit on the *content* layer, so they use
/// a soft material rather than Liquid Glass (glass is reserved for the floating /
/// interactive layer per the Liquid Glass HIG), with a hairline border and
/// continuous corners for a modern, concentric look.
struct SectionCard<Content: View>: View {
    let title: String
    let systemImage: String
    var content: Content

    init(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .labelStyle(.titleAndIcon)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        )
    }
}

/// A large, leading-aligned title used at the top of a detail pane.
struct PaneHeader: View {
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.largeTitle.weight(.semibold))
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
