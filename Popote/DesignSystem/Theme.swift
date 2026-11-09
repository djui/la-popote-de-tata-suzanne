import SwiftUI
import UIKit

/// Design tokens carried over from the website (oklch values converted to sRGB),
/// with a dark palette designed for the app.
enum Palette {
    static let background = Color(light: 0xF7F1E6, dark: 0x11162A)
    static let foreground = Color(light: 0x3B2E25, dark: 0xF2EBDD)
    static let card = Color(light: 0xFDFAF3, dark: 0x1A2137)
    static let muted = Color(light: 0x857462, dark: 0xA79E8F)
    static let line = Color(light: 0xE6DBC8, dark: 0x283150)
    static let chip = Color(light: 0xEFE6D6, dark: 0x222A43)
    /// Primary action colour: navy on cream, lemon on navy.
    static let primary = Color(light: 0x1F3157, dark: 0xE8CF6E)
    static let onPrimary = Color(light: 0xFDFAF3, dark: 0x1A2036)
    static let tileTop = Color(light: 0x2B416E, dark: 0x2A3A63)
    static let tileBottom = Color(light: 0x18264A, dark: 0x1A2544)
    static let sage = Color(light: 0x7E9873, dark: 0x9DB492)
    static let lemon = Color(hex: 0xE8CF6E)
    static let destructive = Color(light: 0xC0453A, dark: 0xF07A6E)
    static let warning = Color(light: 0xE3B53C, dark: 0xE8CF6E)

    // Cook mode is always dark, like on the website.
    static let cookBackground = Color(hex: 0x121A33)
    static let cookCard = Color(hex: 0x1E2847)
    static let cookForeground = Color(hex: 0xF5EEDF)
    static let cookMuted = Color(hex: 0xA9A391)
    static let timerBackground = Color(hex: 0x2F4A35)
    static let timerForeground = Color(hex: 0xD6F0C9)

    static var tileGradient: LinearGradient {
        LinearGradient(colors: [tileTop, tileBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

enum AppFont {
    static func display(_ size: CGFloat, bold: Bool = true, relativeTo style: Font.TextStyle = .title) -> Font {
        .custom(bold ? "Fraunces-ExtraBold" : "Fraunces-SemiBold", size: size, relativeTo: style)
    }
    static func body(_ size: CGFloat = 16, weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        let name: String = switch weight {
        case .heavy, .black: "Nunito-ExtraBold"
        case .bold: "Nunito-Bold"
        case .semibold, .medium: "Nunito-SemiBold"
        default: "Nunito-Regular"
        }
        return .custom(name, size: size, relativeTo: style)
    }
    static func script(_ size: CGFloat, relativeTo style: Font.TextStyle = .largeTitle) -> Font {
        .custom("DancingScript-Bold", size: size, relativeTo: style)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }

    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255,
                           alpha: 1)
        })
    }
}

/// Configures UIKit appearance so navigation bars and large titles use the brand fonts.
@MainActor
enum Appearance {
    static func configure() {
        let large = UIFont(name: "Fraunces-ExtraBold", size: 34) ?? .systemFont(ofSize: 34, weight: .heavy)
        let inline = UIFont(name: "Fraunces-SemiBold", size: 17) ?? .systemFont(ofSize: 17, weight: .semibold)
        let fg = UIColor(Palette.foreground)
        let nav = UINavigationBar.appearance()
        nav.largeTitleTextAttributes = [.font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: large), .foregroundColor: fg]
        nav.titleTextAttributes = [.font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: inline), .foregroundColor: fg]
    }
}

// MARK: - Reusable styles

struct PrimaryButtonStyle: ButtonStyle {
    var compact = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.body(compact ? 14 : 16, weight: .heavy))
            .foregroundStyle(Palette.onPrimary)
            .frame(maxWidth: compact ? nil : .infinity)
            .padding(.horizontal, compact ? 16 : 20)
            .frame(minHeight: compact ? 40 : 50)
            .background(Palette.primary, in: Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.body(15, weight: .bold))
            .foregroundStyle(Palette.foreground)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(Palette.chip, in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var popotePrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
    static var popotePrimaryCompact: PrimaryButtonStyle { PrimaryButtonStyle(compact: true) }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var popoteSecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

struct CardBackground: ViewModifier {
    var radius: CGFloat = 18
    func body(content: Content) -> some View {
        content
            .background(Palette.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
    }
}

extension View {
    func popoteCard(radius: CGFloat = 18) -> some View { modifier(CardBackground(radius: radius)) }

    /// Standard screen background.
    func popoteBackground() -> some View {
        background(Palette.background.ignoresSafeArea())
    }
}

/// A capsule chip, e.g. category filter.
struct ChipView: View {
    let title: String
    var systemImage: String?
    var isOn = false
    var body: some View {
        HStack(spacing: 5) {
            if let systemImage { Image(systemName: systemImage).imageScale(.small) }
            Text(title)
        }
        .font(AppFont.body(13, weight: .bold))
        .padding(.horizontal, 12)
        .frame(minHeight: 32)
        .foregroundStyle(isOn ? Palette.onPrimary : Palette.foreground)
        .background(isOn ? Palette.primary : Palette.card, in: Capsule())
        .overlay(Capsule().strokeBorder(isOn ? .clear : Palette.line, lineWidth: 1))
        .contentShape(Capsule())
    }
}

/// The hand-written "La Popote de Tata Suzanne" wordmark with the lemon.
struct Wordmark: View {
    var size: CGFloat = 40
    var showLemon = true
    var body: some View {
        VStack(spacing: size * 0.25) {
            if showLemon {
                Image("Lemon")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(height: size * 1.3)
                    .foregroundStyle(Palette.primary)
                    .accessibilityHidden(true)
            }
            Text(verbatim: "La Popote\nde Tata Suzanne")
                .font(AppFont.script(size))
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.primary)
                .rotationEffect(.degrees(-5))
                .accessibilityLabel(Text(verbatim: "La Popote de Tata Suzanne"))
        }
    }
}
