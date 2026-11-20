import AppKit
import SwiftUI

/// Soundbind's visual language: warm paper background, near-black ink, a fuchsia
/// "marker" highlight, teal controls, and large soft squircles. Every colour has a
/// light and a dark variant.
enum Theme {
    // MARK: Colours

    /// Window background: warm cream, or warm near-black in dark mode.
    static let background = Color(light: 0xFFF7ED, dark: 0x1C1917)
    /// Primary text and solid buttons.
    static let ink = Color(light: 0x292524, dark: 0xFFF7ED)
    /// Text on top of `ink` fills.
    static let onInk = Color(light: 0xFFF7ED, dark: 0x292524)
    static let secondaryInk = Color(light: 0x78716C, dark: 0xA8A29E)
    static let tertiaryInk = Color(light: 0xA8A29E, dark: 0x78716C)
    /// Marker-pen highlight: selection, hotkey flash, headline emphasis.
    static let highlight = Color(light: 0xF0ABFC, dark: 0xC26BD6)
    /// Interactive tint: sliders, toggles, progress, links.
    static let accent = Color(light: 0x00A896, dark: 0x00D5BE)
    static let accentNSColor = NSColor(light: 0x00A896, dark: 0x00D5BE)

    /// Resting card fill (ink at a few percent).
    static let surface = ink.opacity(0.045)
    static let surfaceHover = ink.opacity(0.08)
    static let surfaceStrong = ink.opacity(0.10)
    static let hairline = ink.opacity(0.10)

    // MARK: Shape

    static let cardRadius: CGFloat = 16
    static let controlRadius: CGFloat = 12

    static func card(_ radius: CGFloat = cardRadius) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    // MARK: Type

    static let rowTitle = Font.body.weight(.semibold)
    static let sectionLabel = Font.subheadline.weight(.semibold)
}

extension NSColor {
    convenience init(light: UInt32, dark: UInt32) {
        self.init(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        }
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(light: light, dark: dark))
    }
}

/// Solid ink button: the app's primary call to action.
struct InkButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.weight(.bold))
            .foregroundStyle(Theme.onInk)
            .padding(.horizontal, 20)
            .padding(.vertical, 13)
            .background(Theme.ink, in: Theme.card(16))
            .shadow(color: .black.opacity(0.22), radius: 14, y: 8)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.5)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Text with a marker-pen stroke across its lower half.
struct MarkedText: View {
    let text: String

    var body: some View {
        Text(text)
            .background(alignment: .bottom) {
                Rectangle()
                    .fill(Theme.highlight)
                    .frame(height: nil)
                    .scaleEffect(x: 1.04, y: 0.52, anchor: .bottom)
            }
    }
}

/// Small muted heading above a group, e.g. "Sounds".
struct SectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(Theme.sectionLabel)
            .foregroundStyle(Theme.secondaryInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

extension View {
    /// Applies the theme's ink, tint and background to a window's root view.
    func soundbindThemed() -> some View {
        self
            .foregroundStyle(Theme.ink)
            .tint(Theme.accent)
            .background(Theme.background.ignoresSafeArea())
            .modifier(WindowBackground())
    }
}

/// On macOS 15+ this colours the whole window, title bar included.
private struct WindowBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.containerBackground(Theme.background, for: .window)
        } else {
            content
        }
    }
}
