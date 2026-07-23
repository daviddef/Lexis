import SwiftUI

// MARK: - Design System
// One visual language for every screen. Before this, each screen hand-rolled
// its own buttons and cards at slightly different corner radii (6/8/9/10/12/
// 14/16), paddings, and font weights — which is exactly what read as
// "half-baked" and made the menu, Game Over, and result screens feel like
// they belonged to different apps. Everything routes through these tokens
// and styles now, so polishing one place polishes everywhere.

enum DS {
    // Spacing scale — use these instead of arbitrary numbers so vertical
    // rhythm is consistent between screens.
    enum Space {
        static let xs: CGFloat = 6
        static let sm: CGFloat = 10
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    // Corner radii. Continuous (squircle) corners everywhere for a softer,
    // more modern read than the default circular corner.
    enum Radius {
        static let chip: CGFloat = 12
        static let card: CGFloat = 16
        static let button: CGFloat = 16
        static let hero: CGFloat = 20
    }

    // The one spring used for tactile press/appear feedback, so every
    // interaction has the same "snap."
    static let pressSpring = Animation.spring(response: 0.28, dampingFraction: 0.62)
}

// MARK: - Button styles
// ButtonStyle (rather than a plain styled label) so every button gets the
// same press-scale + shadow-collapse feedback for free — the single biggest
// contributor to the UI feeling "alive" rather than static.

/// The primary call-to-action: big, filled, glowing. Play / Play Again.
struct LexisPrimaryButtonStyle: ButtonStyle {
    var tint: Color = .lexisAccent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 19, weight: .black, design: .rounded))
            .tracking(3)
            .foregroundColor(.lexisBg)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous)
                    .fill(tint)
                    .shadow(
                        color: tint.opacity(configuration.isPressed ? 0.25 : 0.45),
                        radius: configuration.isPressed ? 6 : 18,
                        y: configuration.isPressed ? 2 : 7
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(DS.pressSpring, value: configuration.isPressed)
    }
}

/// Secondary, tinted-outline actions: Top Scores, Share, Duel, etc. The tint
/// carries the semantic color (gold for scores, mint for share, …).
struct LexisSecondaryButtonStyle: ButtonStyle {
    var tint: Color = .lexisMid

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .black, design: .rounded))
            .tracking(1.5)
            .foregroundColor(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(tint.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                            .strokeBorder(tint.opacity(0.35), lineWidth: 1.5)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(DS.pressSpring, value: configuration.isPressed)
    }
}

/// Adds the standard press-scale to a button that draws its OWN background
/// (difficulty cards, the menu's Daily/Duel tiles) — keeps the custom label
/// intact while making it respond to touch like everything else.
struct LexisScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(DS.pressSpring, value: configuration.isPressed)
    }
}

/// Quiet, filled-slate actions where an outline would be too loud (Main Menu,
/// Cancel). Same press feedback as the others.
struct LexisGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .tracking(1)
            .foregroundColor(.lexisMid)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(Color.lexisBlock)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(DS.pressSpring, value: configuration.isPressed)
    }
}

// MARK: - Shared building blocks

/// The small uppercase, monospaced, letter-spaced label used above every
/// section ("SELECT DIFFICULTY", "WORDS YOU MADE", …).
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .black, design: .monospaced))
            .foregroundColor(.lexisMid)
            .tracking(2)
    }
}

/// A standard content card: slate fill, hairline border, continuous corners.
struct LexisCard<Content: View>: View {
    var padding: CGFloat = DS.Space.md
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(Color.lexisBlock.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                            .strokeBorder(Color.lexisBlockBorder.opacity(0.25), lineWidth: 1)
                    )
            )
    }
}

// MARK: - Press feedback for non-Button tappables
// Some tappable surfaces (difficulty cards, the wildcard picker) aren't
// Buttons. This modifier gives them the same tactile press-scale so the whole
// UI responds uniformly to touch.
struct PressableModifier: ViewModifier {
    @State private var pressed = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(pressed ? 0.97 : 1)
            .animation(DS.pressSpring, value: pressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in pressed = true }
                    .onEnded { _ in pressed = false }
            )
    }
}

extension View {
    func pressable() -> some View { modifier(PressableModifier()) }
}

// MARK: - iPad layout

// Phone-designed full-screen views (menu, game over, result screens) otherwise
// stretch edge-to-edge on iPad — buttons span the whole display and text reads
// tiny against all that width. This constrains the content to a centred column
// on the REGULAR width class (iPad, and iPhone landscape on big phones) while
// leaving COMPACT width (portrait iPhone) untouched. LEXIS must ship universal
// (2.0 shipped universal; Apple's QA1623 blocks dropping iPad), so every
// full-screen phone layout should wear this.
struct IPadColumn: ViewModifier {
    @Environment(\.horizontalSizeClass) private var hSize
    var maxWidth: CGFloat = 620
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: hSize == .regular ? maxWidth : .infinity)
            .frame(maxWidth: .infinity)   // centre the column in the full width
    }
}

extension View {
    /// Constrain phone-designed content to a centred column on iPad / regular
    /// width; no-op on compact (portrait iPhone).
    func iPadColumn(_ maxWidth: CGFloat = 620) -> some View {
        modifier(IPadColumn(maxWidth: maxWidth))
    }
}
