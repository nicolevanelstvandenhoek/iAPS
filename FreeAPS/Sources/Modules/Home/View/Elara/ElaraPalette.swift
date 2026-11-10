import Observation
import SwiftUI
import UIKit

/// Colors and surfaces of the Elara skin. The accents are Elara's own Display P3 colors, so the
/// skin looks the same as in Trio and leaves the color assets of the iAPS skin untouched.
enum ElaraPalette {
    static let green = Color(.displayP3, red: 0.401, green: 0.757, blue: 0.242)
    static let red = Color(.displayP3, red: 0.894, green: 0.208, blue: 0.310)
    static let high = Color(.displayP3, red: 151 / 255, green: 90 / 255, blue: 232 / 255)
    static let insulin = Color(.displayP3, red: 0.175, green: 0.542, blue: 0.970)
    static let pump = Color(red: 0.443, green: 0.380, blue: 0.937)
    static let carbs = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1, green: 0.757, blue: 0.271, alpha: 1)
            : UIColor(red: 1, green: 0.613, blue: 0, alpha: 1)
    })
    static let device = Color(red: 142 / 255, green: 144 / 255, blue: 151 / 255)

    static func text(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white : Color(red: 22 / 255, green: 24 / 255, blue: 29 / 255)
    }

    static func muted(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 143 / 255, green: 148 / 255, blue: 156 / 255)
            : Color(red: 94 / 255, green: 96 / 255, blue: 104 / 255)
    }

    static func card(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.05) : Color.white.opacity(0.72)
    }

    static func cardBorder(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.08) : text(.light).opacity(0.06)
    }

    static func hairline(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.1) : text(.light).opacity(0.1)
    }

    /// Fill of small controls (the hours switch, tags).
    static func control(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.07) : text(.light).opacity(0.05)
    }

    /// Glucose status color for a value in mg/dL, against the user's own range.
    static func status(mgdl: Double, low: Double, high: Double) -> Color {
        if mgdl < low { return red }
        if mgdl > high { return self.high }
        return green
    }

    /// A status color readable as small text: on light backgrounds the accent is deepened.
    static func readable(_ color: Color, _ scheme: ColorScheme) -> Color {
        scheme == .dark ? color : deepened(color)
    }

    /// Shifts every channel toward white by `amount` (0…1).
    static func lightened(_ color: Color, by amount: CGFloat) -> Color {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        let lift: (CGFloat) -> CGFloat = { min(1, $0 + (1 - $0) * amount) }
        return Color(red: lift(r), green: lift(g), blue: lift(b), opacity: a)
    }

    /// Shifts every channel 18% toward black.
    static func deepened(_ color: Color) -> Color {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        let darken: (CGFloat) -> CGFloat = { max(0, min(1, $0 - 0.18)) }
        return Color(red: darken(r), green: darken(g), blue: darken(b), opacity: a)
    }
}

/// Screen background: a green glow on a pale ground by day, a night-blue tint on the top half
/// by night, with soft violet and blue glows lower down.
struct ElaraBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            if scheme == .dark {
                Color(red: 20 / 255, green: 25 / 255, blue: 35 / 255)
                LinearGradient(
                    stops: [
                        .init(color: Color(red: 16 / 255, green: 32 / 255, blue: 68 / 255), location: 0),
                        .init(color: Color(red: 18 / 255, green: 36 / 255, blue: 74 / 255).opacity(0.72), location: 0.26),
                        .init(color: .clear, location: 0.5)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                RadialGradient(
                    colors: [Color(red: 34 / 255, green: 62 / 255, blue: 122 / 255).opacity(0.5), .clear],
                    center: UnitPoint(x: 0.7, y: 0),
                    startRadius: 0,
                    endRadius: 420
                )
            } else {
                Color(red: 246 / 255, green: 251 / 255, blue: 241 / 255)
                RadialGradient(
                    colors: [ElaraPalette.green.opacity(0.18), .clear],
                    center: UnitPoint(x: 0.85, y: 0.06),
                    startRadius: 0,
                    endRadius: 360
                )
            }
            RadialGradient(
                colors: [ElaraPalette.high.opacity(0.10), .clear],
                center: UnitPoint(x: 0, y: 0.55),
                startRadius: 0,
                endRadius: 340
            )
            RadialGradient(
                colors: [ElaraPalette.insulin.opacity(0.12), .clear],
                center: UnitPoint(x: 1, y: 0.95),
                startRadius: 0,
                endRadius: 380
            )
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// The rounded, lightly translucent card every Elara block sits on.
    func elaraCard(_ scheme: ColorScheme, radius: CGFloat = 20) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(ElaraPalette.card(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(ElaraPalette.cardBorder(scheme), lineWidth: 1)
        )
    }

    /// Gives a screen the Elara look while the Elara skin is chosen; otherwise leaves it as it is.
    func elaraScreen() -> some View {
        modifier(ElaraScreenModifier())
    }
}

/// Applies Elara to the rest of the app: the screen background, the translucent rows of lists
/// and forms, and the green accent. Every screen of the router gets it, so they all follow
/// the skin without restyling each one by hand.
private struct ElaraScreenModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    // One view structure for both skins, so switching keeps the screens that are open
    func body(content: Content) -> some View {
        let active = ElaraTheme.shared.isActive
        content
            .scrollContentBackground(active ? .hidden : .automatic)
            .background { if active { ElaraBackground() } }
            .tint(active ? ElaraPalette.readable(ElaraPalette.green, scheme) : nil)
    }
}

/// Whether the Elara skin is on, for views that are not handed the settings.
@Observable final class ElaraTheme {
    static let shared = ElaraTheme()

    private(set) var isActive = false

    /// Row background of lists and forms: Elara's translucent card, or the system row while Elara is off.
    static var rowBackground: Color? {
        shared.isActive ? Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.05)
                : UIColor.white.withAlphaComponent(0.72)
        }) : nil
    }

    @MainActor func update(skin: Skin) {
        let active = skin == .elara
        guard active != isActive else { return }
        isActive = active
        // Segmented pickers: a soft, translucent green for the chosen segment
        UISegmentedControl.appearance().selectedSegmentTintColor = active
            ? UIColor(ElaraPalette.green).withAlphaComponent(0.55)
            : nil
        // Screen titles as in the design: a heavy large title, a semibold inline title
        let navigationBar = UINavigationBar.appearance()
        navigationBar.largeTitleTextAttributes = active ? [.font: UIFont.systemFont(ofSize: 34, weight: .heavy)] : nil
        navigationBar.titleTextAttributes = active ? [.font: UIFont.systemFont(ofSize: 17, weight: .semibold)] : nil
    }
}
