//
//  Theme.swift
//  mac-prompt
//
//  Native adaptation of the "Prompt" design concept: the mockup's OKLCH violet/coral
//  palette and Space Grotesk/Plus Jakarta Sans type, reproduced with SwiftUI Color
//  literals and the system font's rounded design so the app has no font-bundling or
//  licensing dependencies.

import SwiftUI

struct Theme {
    var bg: Color
    var sidebar: Color
    var surface: Color
    var surface2: Color
    var border: Color
    var text: Color
    var textDim: Color
    var textFaint: Color
    var violet: Color
    var coral: Color
    var teal: Color
    var amber: Color
    var rec: Color

    var accent: LinearGradient {
        LinearGradient(colors: [violet, coral], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// The four folder/script accent colors, in round-robin assignment order.
    var accentPalette: [Color] { [violet, coral, teal, amber] }

    static let dark = Theme(
        bg: Color(red: 0.086, green: 0.078, blue: 0.106),
        sidebar: Color(red: 0.070, green: 0.063, blue: 0.090),
        surface: Color(red: 0.114, green: 0.104, blue: 0.145),
        surface2: Color(red: 0.141, green: 0.129, blue: 0.180),
        border: Color.white.opacity(0.08),
        text: Color(red: 0.965, green: 0.957, blue: 0.980),
        textDim: Color(red: 0.663, green: 0.643, blue: 0.741),
        textFaint: Color(red: 0.490, green: 0.467, blue: 0.576),
        violet: Color(red: 0.663, green: 0.494, blue: 0.878),
        coral: Color(red: 0.878, green: 0.541, blue: 0.361),
        teal: Color(red: 0.373, green: 0.788, blue: 0.788),
        amber: Color(red: 0.851, green: 0.714, blue: 0.290),
        rec: Color(red: 0.898, green: 0.325, blue: 0.294)
    )

    static let light = Theme(
        bg: Color(red: 0.969, green: 0.965, blue: 0.984),
        sidebar: Color(red: 0.937, green: 0.929, blue: 0.961),
        surface: Color.white,
        surface2: Color(red: 0.941, green: 0.933, blue: 0.965),
        border: Color.black.opacity(0.08),
        text: Color(red: 0.125, green: 0.110, blue: 0.169),
        textDim: Color(red: 0.357, green: 0.333, blue: 0.439),
        textFaint: Color(red: 0.545, green: 0.522, blue: 0.612),
        violet: Color(red: 0.482, green: 0.290, blue: 0.729),
        coral: Color(red: 0.741, green: 0.365, blue: 0.161),
        teal: Color(red: 0.145, green: 0.514, blue: 0.514),
        amber: Color(red: 0.616, green: 0.482, blue: 0.086),
        rec: Color(red: 0.784, green: 0.216, blue: 0.184)
    )

    static func resolved(for scheme: ColorScheme) -> Theme {
        scheme == .dark ? .dark : .light
    }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.dark
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

/// Injects `theme` into the environment from the current color scheme every frame,
/// so views just read `@Environment(\.theme)` instead of resolving it themselves.
struct ThemedRoot: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    func body(content: Content) -> some View {
        content.environment(\.theme, Theme.resolved(for: colorScheme))
    }
}

extension View {
    func themed() -> some View { modifier(ThemedRoot()) }
}

// MARK: - Fonts

extension Font {
    /// Space Grotesk stand-in: the system font's rounded design, for headings and numerals.
    static func heading(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

// MARK: - Shared components

struct GradientButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13.5, weight: .bold))
            .foregroundColor(Color(red: 0.10, green: 0.06, blue: 0.07))
            .padding(.vertical, 11)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(theme.accent)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: theme.violet.opacity(0.45), radius: configuration.isPressed ? 6 : 12, y: 4)
            .opacity(configuration.isPressed ? 0.9 : 1)
    }
}

struct NavItemStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    var isActive: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundColor(isActive ? theme.text : theme.textDim)
            .padding(.vertical, 9)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isActive ? theme.text.opacity(0.09) : (configuration.isPressed ? theme.text.opacity(0.045) : .clear))
            )
    }
}

struct GlassPill: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
    }
}

extension View {
    func glassPill() -> some View { modifier(GlassPill()) }
}

struct CardBackground: ViewModifier {
    @Environment(\.theme) private var theme
    func body(content: Content) -> some View {
        content
            .background(theme.surface)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(theme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

extension View {
    func cardBackground() -> some View { modifier(CardBackground()) }
}

/// A segmented pill toggle, matching the mockup's `.pill-toggle` / `.seg` component.
struct PillSegmentedControl<Option: Hashable & Identifiable>: View {
    @Environment(\.theme) private var theme
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                Button {
                    selection = option
                } label: {
                    Text(label(option))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(option == selection ? theme.text : theme.textFaint)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(option == selection ? theme.surface2 : .clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(theme.bg.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}
