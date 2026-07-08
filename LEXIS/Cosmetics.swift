import SwiftUI

// MARK: - Cosmetics (sprint: expressive categories)
//
// Beyond tile themes, LEXIS now has cosmetics you SEE constantly: the
// clear-burst effect fired on every word clear, and (see BoardBackdrop) the
// backdrop behind the grid. They're earned with coins (or, for the exclusive
// one, by playing the weekly event) — the same earn-or-unlock economy as
// themes. Ownership lives in CosmeticsStore, keyed by each item's `cosmeticID`.

/// The particle shape a burst flings out.
enum BurstShape {
    case shard      // small rounded rectangle (the original look)
    case circle     // soft dot
    case spark      // thin bright line
    case petal      // tall rounded flake
}

/// The effect played where each tile of a cleared word was — the most-seen
/// cosmetic in the game.
enum BurstStyle: String, CaseIterable, Codable, Identifiable {
    case shards     // default — the original shard fling
    case embers     // glowing dots that rise and fade
    case sparks     // bright thin lines flung outward
    case petals     // soft flakes drifting out and down
    case bloom      // event-exclusive: a bright expanding ring of dots

    var id: String { rawValue }
    var cosmeticID: String { "burst.\(rawValue)" }

    var displayName: String {
        switch self {
        case .shards: return "Shards"
        case .embers: return "Embers"
        case .sparks: return "Sparks"
        case .petals: return "Petals"
        case .bloom:  return "Bloom"
        }
    }

    var isDefault: Bool { self == .shards }
    /// Earnable only by playing a weekly event — never coin-buyable.
    var isEventExclusive: Bool { self == .bloom }
    var coinPrice: Int {
        switch self {
        case .shards: return 0
        case .embers: return 150
        case .sparks: return 200
        case .petals: return 200
        case .bloom:  return 0   // event-only
        }
    }

    // MARK: rendering parameters
    var count: Int {
        switch self {
        case .shards: return 6
        case .embers: return 7
        case .sparks: return 8
        case .petals: return 6
        case .bloom:  return 12
        }
    }
    var shape: BurstShape {
        switch self {
        case .shards: return .shard
        case .embers: return .circle
        case .sparks: return .spark
        case .petals: return .petal
        case .bloom:  return .circle
        }
    }
    /// How far particles fly, as a multiple of tile size.
    var spread: CGFloat {
        switch self {
        case .shards: return 1.15
        case .embers: return 0.7
        case .sparks: return 1.5
        case .petals: return 1.0
        case .bloom:  return 1.3
        }
    }
    /// Extra vertical drift at the end (negative = rise). Multiple of tile size.
    var drift: CGFloat {
        switch self {
        case .embers: return -0.8   // rise
        case .petals: return 0.5    // settle down
        default:      return 0
        }
    }
    var spin: Double {
        switch self {
        case .shards: return 140
        case .petals: return 90
        default:      return 0
        }
    }
    /// When nil, the burst uses the cleared word's colour; otherwise this
    /// fixed palette (cycled per particle).
    var palette: [Color]? {
        switch self {
        case .embers: return [Color(red: 1.0, green: 0.55, blue: 0.2), Color(red: 1.0, green: 0.8, blue: 0.3)]
        case .petals: return [Color(red: 1.0, green: 0.5, blue: 0.7), Color(red: 0.7, green: 0.5, blue: 1.0)]
        default:      return nil
        }
    }
}

// MARK: - Board backdrop

/// A subtle, always-on-screen layer behind the board. Static (no animation),
/// so it stays performant and reduce-motion-safe. `none` is the default plain
/// look; the rest are coin-buyable cosmetics.
enum BoardBackdrop: String, CaseIterable, Codable, Identifiable {
    case none, dusk, mint, ember, grid
    // "Match Theme": renders whichever scene fits the equipped tile theme —
    // the elegant "your theme is a whole world" option. Always free.
    case matchTheme
    // Scene backdrops — evocative, gently animated, one per theme's world.
    case oceanDeep, sunsetBeach, forest, starfield, rosePetals, goldRays, monoRain

    var id: String { rawValue }
    var cosmeticID: String { "backdrop.\(rawValue)" }
    var isDefault: Bool { self == .none }
    /// Available without buying (the plain default + the theme-matcher).
    var alwaysAvailable: Bool { self == .none || self == .matchTheme }
    /// Scenes are the fancier, animated tier.
    var isScene: Bool {
        switch self {
        case .oceanDeep, .sunsetBeach, .forest, .starfield, .rosePetals, .goldRays, .monoRain: return true
        default: return false
        }
    }
    var displayName: String {
        switch self {
        case .none: return "None"
        case .matchTheme: return "Match Theme"
        case .dusk: return "Dusk"
        case .mint: return "Mint Glow"
        case .ember: return "Ember"
        case .grid: return "Neon Grid"
        case .oceanDeep: return "Ocean Deep"
        case .sunsetBeach: return "Sunset Beach"
        case .forest: return "Forest"
        case .starfield: return "Starfield"
        case .rosePetals: return "Rose Petals"
        case .goldRays: return "Gold Rays"
        case .monoRain: return "Mono Rain"
        }
    }
    var coinPrice: Int {
        switch self {
        case .none, .matchTheme: return 0
        case .dusk, .mint: return 150
        case .ember, .grid: return 200
        default: return 350   // scenes cost a bit more
        }
    }
}

/// Renders a BoardBackdrop full-screen behind the game content.
struct BoardBackdropView: View {
    let style: BoardBackdrop

    var body: some View {
        switch style {
        case .none:
            Color.clear
        case .dusk:
            LinearGradient(colors: [Color(red: 0.16, green: 0.10, blue: 0.28), .clear],
                           startPoint: .top, endPoint: .center).ignoresSafeArea()
        case .mint:
            RadialGradient(colors: [Color.lexisAccent.opacity(0.14), .clear],
                           center: .center, startRadius: 8, endRadius: 420).ignoresSafeArea()
        case .ember:
            LinearGradient(colors: [.clear, Color(red: 0.5, green: 0.18, blue: 0.06).opacity(0.5)],
                           startPoint: .center, endPoint: .bottom).ignoresSafeArea()
        case .grid:
            GeometryReader { geo in
                Path { p in
                    let step: CGFloat = 40
                    var x: CGFloat = 0
                    while x < geo.size.width { p.move(to: .init(x: x, y: 0)); p.addLine(to: .init(x: x, y: geo.size.height)); x += step }
                    var y: CGFloat = 0
                    while y < geo.size.height { p.move(to: .init(x: 0, y: y)); p.addLine(to: .init(x: geo.size.width, y: y)); y += step }
                }
                .stroke(Color.lexisAccent.opacity(0.10), lineWidth: 1)
            }
            .ignoresSafeArea()
        case .oceanDeep:
            OceanBackdrop()
        case .sunsetBeach:
            SunsetBackdrop()
        case .forest:
            ForestBackdrop()
        case .starfield:
            StarfieldBackdrop()
        case .rosePetals:
            RosePetalsBackdrop()
        case .goldRays:
            GoldRaysBackdrop()
        case .monoRain:
            MonoRainBackdrop()
        case .matchTheme:
            // Resolve to whichever scene fits the equipped tile theme. The
            // theme's `matchingScene` never returns `.matchTheme`, so no
            // recursion. If a theme has no scene it returns `.none` (Color.clear).
            BoardBackdropView(style: GameSettings.shared.tileTheme.matchingScene)
        }
    }
}

// A simple right-pointing triangle, used for fish tails / dune shapes.
private struct SceneTriangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Ocean Deep scene
// A deep-water gradient with faint fish silhouettes drifting across at
// different depths, and a few bubbles rising. Deliberately dark and low-
// contrast so it never competes with the bright tiles on top.
struct OceanBackdrop: View {
    @ObservedObject private var settings = GameSettings.shared

    // yFrac, scale, seconds to cross, direction, phase 0…1, opacity
    private let fish: [(y: CGFloat, scale: CGFloat, dur: Double, dir: CGFloat, phase: Double, opacity: Double)] = [
        (0.18, 1.0, 28, 1, 0.00, 0.16),
        (0.34, 0.7, 22, -1, 0.45, 0.12),
        (0.52, 1.3, 34, 1, 0.72, 0.14),
        (0.68, 0.6, 19, -1, 0.20, 0.10),
        (0.83, 0.9, 25, 1, 0.55, 0.13),
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: [
                    Color(red: 0.05, green: 0.20, blue: 0.30),
                    Color(red: 0.02, green: 0.06, blue: 0.12)
                ], startPoint: .top, endPoint: .bottom)

                ForEach(0..<fish.count, id: \.self) { i in
                    let f = fish[i]
                    FishView(width: geo.size.width, scale: f.scale, dur: f.dur, dir: f.dir,
                             phase: f.phase, opacity: f.opacity, animate: !settings.motionReduced)
                        .position(x: 0, y: geo.size.height * f.y)   // x driven inside
                }

                // A couple of slow rising bubbles.
                ForEach(0..<3, id: \.self) { i in
                    BubbleView(x: geo.size.width * [0.25, 0.6, 0.85][i], height: geo.size.height,
                               dur: [16.0, 21.0, 18.0][i], phase: [0.3, 0.7, 0.1][i],
                               animate: !settings.motionReduced)
                }
            }
        }
        .ignoresSafeArea()
    }
}

private struct FishView: View {
    let width: CGFloat
    let scale: CGFloat
    let dur: Double
    let dir: CGFloat
    let phase: Double
    let opacity: Double
    let animate: Bool
    @State private var t: CGFloat

    init(width: CGFloat, scale: CGFloat, dur: Double, dir: CGFloat, phase: Double, opacity: Double, animate: Bool) {
        self.width = width; self.scale = scale; self.dur = dur; self.dir = dir
        self.phase = phase; self.opacity = opacity; self.animate = animate
        _t = State(initialValue: CGFloat(phase))
    }

    var body: some View {
        let frac = t - t.rounded(.down)
        // Travel from one side (off-screen) to the other; wrap seam is off-screen.
        let travel = width + 120
        let x = dir > 0 ? (-60 + travel * frac) : (width + 60 - travel * frac)
        fish
            .frame(width: 34 * scale, height: 16 * scale)
            .scaleEffect(x: dir, y: 1)          // face swim direction
            .position(x: x, y: 0)
            .offset(y: 0)
            .onAppear {
                guard animate else { return }
                withAnimation(.linear(duration: dur).repeatForever(autoreverses: false)) { t = CGFloat(phase) + 1 }
            }
    }

    private var fish: some View {
        let c = Color(red: 0.55, green: 0.85, blue: 0.95).opacity(opacity)
        return ZStack(alignment: .leading) {
            Ellipse().fill(c).frame(width: 30 * scale, height: 14 * scale).offset(x: 6 * scale)
            SceneTriangle().fill(c)
                .frame(width: 12 * scale, height: 16 * scale)
                .rotationEffect(.degrees(180))    // tail behind
        }
    }
}

private struct BubbleView: View {
    let x: CGFloat
    let height: CGFloat
    let dur: Double
    let phase: Double
    let animate: Bool
    @State private var t: CGFloat

    init(x: CGFloat, height: CGFloat, dur: Double, phase: Double, animate: Bool) {
        self.x = x; self.height = height; self.dur = dur; self.phase = phase; self.animate = animate
        _t = State(initialValue: CGFloat(phase))
    }

    var body: some View {
        let frac = t - t.rounded(.down)
        let y = height + 20 - (height + 40) * frac   // rise from bottom to top
        Circle().fill(Color.white.opacity(0.10))
            .frame(width: 6, height: 6)
            .position(x: x, y: y)
            .onAppear {
                guard animate else { return }
                withAnimation(.linear(duration: dur).repeatForever(autoreverses: false)) { t = CGFloat(phase) + 1 }
            }
    }
}

// MARK: - Sunset Beach scene
// A warm gradient sky, a low sun with a soft glow, a horizon line, and a
// gently-rolling dune silhouette along the bottom. Mostly static (only the
// sun's glow breathes), so it's calm and reduce-motion-friendly.
struct SunsetBackdrop: View {
    @ObservedObject private var settings = GameSettings.shared
    @State private var glow = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                LinearGradient(colors: [
                    Color(red: 0.30, green: 0.14, blue: 0.22),
                    Color(red: 0.55, green: 0.26, blue: 0.18),
                    Color(red: 0.14, green: 0.08, blue: 0.14)
                ], startPoint: .top, endPoint: .bottom)

                // Sun, low over the horizon, with a soft breathing glow.
                Circle()
                    .fill(RadialGradient(colors: [Color(red: 1.0, green: 0.7, blue: 0.4).opacity(0.5), .clear],
                                         center: .center, startRadius: 2, endRadius: 130 * (glow ? 1.08 : 1.0)))
                    .frame(width: 260, height: 260)
                    .position(x: w * 0.5, y: h * 0.62)
                Circle()
                    .fill(Color(red: 1.0, green: 0.62, blue: 0.35).opacity(0.35))
                    .frame(width: 96, height: 96)
                    .position(x: w * 0.5, y: h * 0.62)

                // Dune silhouette along the bottom.
                Path { p in
                    p.move(to: .init(x: 0, y: h))
                    p.addLine(to: .init(x: 0, y: h * 0.82))
                    p.addCurve(to: .init(x: w, y: h * 0.86),
                               control1: .init(x: w * 0.35, y: h * 0.74),
                               control2: .init(x: w * 0.7, y: h * 0.92))
                    p.addLine(to: .init(x: w, y: h))
                    p.closeSubpath()
                }
                .fill(Color(red: 0.06, green: 0.03, blue: 0.06).opacity(0.9))
            }
            .onAppear {
                guard !settings.motionReduced else { return }
                withAnimation(.easeInOut(duration: 3.5).repeatForever(autoreverses: true)) { glow = true }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Reusable drift particle
// A single element that travels a linear path across the board and wraps.
// `axis: .vertical` falls top→bottom (or rises, if `rising`); `.horizontal`
// crosses left→right. The wrap seam is pushed off-screen by the ±margin so
// it's never visible, and `frac` is modulo-wrapped for a seamless loop.
private enum DriftAxis { case vertical, horizontal }

private struct Drifter<Content: View>: View {
    let axis: DriftAxis
    let rising: Bool
    let cross: CGFloat          // fixed position on the perpendicular axis (points)
    let extent: CGFloat         // length of the travel axis (points)
    let sway: CGFloat           // lateral wobble amplitude (points)
    let dur: Double
    let phase: Double
    let animate: Bool
    let content: () -> Content
    @State private var t: CGFloat

    init(axis: DriftAxis, rising: Bool = false, cross: CGFloat, extent: CGFloat,
         sway: CGFloat = 0, dur: Double, phase: Double, animate: Bool,
         @ViewBuilder content: @escaping () -> Content) {
        self.axis = axis; self.rising = rising; self.cross = cross; self.extent = extent
        self.sway = sway; self.dur = dur; self.phase = phase; self.animate = animate
        self.content = content
        _t = State(initialValue: CGFloat(phase))
    }

    var body: some View {
        let frac = t - t.rounded(.down)
        let travel = extent + 120
        // progress along the travel axis, 0…1, offset so the seam is off-screen
        let p = -60 + travel * (rising ? (1 - frac) : frac)
        // gentle sinusoidal sway on the perpendicular axis
        let swayOffset = sway == 0 ? 0 : sin((Double(frac) + phase) * .pi * 2) * Double(sway)
        content()
            .position(
                x: axis == .vertical ? cross + CGFloat(swayOffset) : p,
                y: axis == .vertical ? p : cross + CGFloat(swayOffset)
            )
            .onAppear {
                guard animate else { return }
                withAnimation(.linear(duration: dur).repeatForever(autoreverses: false)) {
                    t = CGFloat(phase) + 1
                }
            }
    }
}

// A soft-edged particle body used by several scenes.
private struct Mote: View {
    var color: Color
    var size: CGFloat
    var body: some View {
        Circle().fill(color).frame(width: size, height: size).blur(radius: size * 0.25)
    }
}

// MARK: - Forest scene
// A deep-green canopy gradient with leaves drifting down and a few fireflies
// pulsing. Calm and dim so tiles stay legible.
struct ForestBackdrop: View {
    @ObservedObject private var settings = GameSettings.shared

    // xFrac, size, dur, phase, sway, hue(0 green…1 amber), opacity
    private let leaves: [(x: CGFloat, size: CGFloat, dur: Double, phase: Double, sway: CGFloat, hue: CGFloat, opacity: Double)] = [
        (0.12, 12, 20, 0.00, 14, 0.1, 0.16),
        (0.30, 9, 26, 0.55, 20, 0.5, 0.13),
        (0.48, 14, 17, 0.30, 10, 0.0, 0.18),
        (0.66, 8, 30, 0.80, 24, 0.7, 0.12),
        (0.82, 11, 23, 0.15, 16, 0.3, 0.15),
        (0.92, 7, 28, 0.62, 12, 0.9, 0.11),
    ]
    // xFrac, yFrac, dur, phase
    private let flies: [(x: CGFloat, y: CGFloat, dur: Double, phase: Double)] = [
        (0.22, 0.40, 3.0, 0.0), (0.58, 0.28, 3.8, 0.4),
        (0.74, 0.55, 3.3, 0.7), (0.40, 0.66, 4.1, 0.2),
    ]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                LinearGradient(colors: [
                    Color(red: 0.04, green: 0.14, blue: 0.08),
                    Color(red: 0.02, green: 0.07, blue: 0.05)
                ], startPoint: .top, endPoint: .bottom)

                ForEach(0..<leaves.count, id: \.self) { i in
                    let l = leaves[i]
                    Drifter(axis: .vertical, cross: w * l.x, extent: h, sway: l.sway,
                            dur: l.dur, phase: l.phase, animate: !settings.motionReduced) {
                        LeafShape()
                            .fill(Color(red: 0.4 + Double(l.hue) * 0.5,
                                        green: 0.6 - Double(l.hue) * 0.2,
                                        blue: 0.25).opacity(l.opacity))
                            .frame(width: l.size, height: l.size)
                            .rotationEffect(.degrees(Double(l.phase) * 360))
                    }
                }

                ForEach(0..<flies.count, id: \.self) { i in
                    let f = flies[i]
                    FireflyView(x: w * f.x, y: h * f.y, dur: f.dur, phase: f.phase,
                                animate: !settings.motionReduced)
                }
            }
        }
        .ignoresSafeArea()
    }
}

private struct LeafShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.maxY), control: CGPoint(x: r.maxX, y: r.midY))
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.minY), control: CGPoint(x: r.minX, y: r.midY))
        p.closeSubpath()
        return p
    }
}

private struct FireflyView: View {
    let x: CGFloat; let y: CGFloat; let dur: Double; let phase: Double; let animate: Bool
    @State private var on = false
    var body: some View {
        Mote(color: Color(red: 0.85, green: 0.95, blue: 0.5).opacity(on ? 0.5 : 0.08), size: 6)
            .position(x: x, y: y)
            .onAppear {
                guard animate else { return }
                withAnimation(.easeInOut(duration: dur).repeatForever(autoreverses: true).delay(phase * dur)) {
                    on = true
                }
            }
    }
}

// MARK: - Starfield scene
// A dark violet nebula glow with static, softly twinkling stars. No motion
// across the screen (just opacity breathing), so it's the calmest scene.
struct StarfieldBackdrop: View {
    @ObservedObject private var settings = GameSettings.shared

    // xFrac, yFrac, size, dur, phase, baseOpacity
    private let stars: [(x: CGFloat, y: CGFloat, size: CGFloat, dur: Double, phase: Double, op: Double)] = [
        (0.10, 0.12, 2.5, 3.2, 0.0, 0.5), (0.24, 0.30, 1.8, 4.0, 0.3, 0.35),
        (0.38, 0.08, 3.0, 3.6, 0.6, 0.6), (0.52, 0.22, 2.0, 4.4, 0.1, 0.4),
        (0.66, 0.14, 1.6, 3.0, 0.8, 0.3), (0.80, 0.34, 2.8, 3.8, 0.5, 0.55),
        (0.90, 0.18, 2.0, 4.2, 0.2, 0.4), (0.16, 0.48, 1.7, 3.4, 0.7, 0.32),
        (0.44, 0.44, 2.4, 4.1, 0.4, 0.45), (0.72, 0.52, 1.9, 3.7, 0.9, 0.36),
        (0.30, 0.62, 2.2, 3.9, 0.15, 0.42), (0.86, 0.66, 1.6, 4.3, 0.55, 0.3),
    ]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                LinearGradient(colors: [
                    Color(red: 0.06, green: 0.04, blue: 0.16),
                    Color(red: 0.02, green: 0.02, blue: 0.06)
                ], startPoint: .top, endPoint: .bottom)

                // Nebula glow.
                RadialGradient(colors: [Color(red: 0.4, green: 0.2, blue: 0.6).opacity(0.28), .clear],
                               center: .init(x: 0.7, y: 0.3), startRadius: 10, endRadius: 320)
                RadialGradient(colors: [Color(red: 0.2, green: 0.3, blue: 0.6).opacity(0.20), .clear],
                               center: .init(x: 0.25, y: 0.6), startRadius: 10, endRadius: 260)

                ForEach(0..<stars.count, id: \.self) { i in
                    let s = stars[i]
                    StarView(x: w * s.x, y: h * s.y, size: s.size, dur: s.dur,
                             phase: s.phase, baseOpacity: s.op, animate: !settings.motionReduced)
                }
            }
        }
        .ignoresSafeArea()
    }
}

private struct StarView: View {
    let x: CGFloat; let y: CGFloat; let size: CGFloat
    let dur: Double; let phase: Double; let baseOpacity: Double; let animate: Bool
    @State private var bright = false
    var body: some View {
        Circle().fill(Color.white.opacity(bright ? baseOpacity : baseOpacity * 0.3))
            .frame(width: size, height: size)
            .position(x: x, y: y)
            .onAppear {
                guard animate else { return }
                withAnimation(.easeInOut(duration: dur).repeatForever(autoreverses: true).delay(phase * dur)) {
                    bright = true
                }
            }
    }
}

// MARK: - Rose Petals scene
// A warm rosé gradient with soft petals drifting down and swaying. Romantic,
// low-contrast pinks that read behind the rose tile theme.
struct RosePetalsBackdrop: View {
    @ObservedObject private var settings = GameSettings.shared

    private let petals: [(x: CGFloat, size: CGFloat, dur: Double, phase: Double, sway: CGFloat, opacity: Double)] = [
        (0.10, 13, 22, 0.00, 22, 0.16), (0.28, 10, 27, 0.50, 28, 0.13),
        (0.46, 15, 18, 0.25, 16, 0.18), (0.64, 9, 31, 0.75, 30, 0.12),
        (0.80, 12, 24, 0.10, 20, 0.15), (0.90, 8, 29, 0.60, 24, 0.11),
    ]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                LinearGradient(colors: [
                    Color(red: 0.26, green: 0.10, blue: 0.16),
                    Color(red: 0.12, green: 0.05, blue: 0.09)
                ], startPoint: .top, endPoint: .bottom)

                ForEach(0..<petals.count, id: \.self) { i in
                    let pt = petals[i]
                    Drifter(axis: .vertical, cross: w * pt.x, extent: h, sway: pt.sway,
                            dur: pt.dur, phase: pt.phase, animate: !settings.motionReduced) {
                        PetalShape()
                            .fill(Color(red: 0.95, green: 0.55, blue: 0.65).opacity(pt.opacity))
                            .frame(width: pt.size, height: pt.size * 1.3)
                            .rotationEffect(.degrees(Double(pt.phase) * 300 + 20))
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}

private struct PetalShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.maxY), control: CGPoint(x: r.maxX * 1.05, y: r.midY))
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.minY), control: CGPoint(x: r.minX - r.width * 0.05, y: r.midY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Gold Rays scene
// A warm amber gradient with slow godrays and gold sparkles rising, evoking
// treasure/light. Pairs with the gold tile theme.
struct GoldRaysBackdrop: View {
    @ObservedObject private var settings = GameSettings.shared

    private let sparks: [(x: CGFloat, size: CGFloat, dur: Double, phase: Double, sway: CGFloat, opacity: Double)] = [
        (0.15, 5, 14, 0.00, 12, 0.5), (0.30, 3, 18, 0.45, 16, 0.35),
        (0.45, 6, 12, 0.70, 10, 0.55), (0.60, 4, 20, 0.20, 18, 0.4),
        (0.75, 3, 16, 0.55, 14, 0.32), (0.88, 5, 15, 0.30, 12, 0.45),
    ]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                LinearGradient(colors: [
                    Color(red: 0.20, green: 0.14, blue: 0.03),
                    Color(red: 0.09, green: 0.06, blue: 0.02)
                ], startPoint: .top, endPoint: .bottom)

                // A few soft godrays fanning from the top.
                ForEach(0..<4, id: \.self) { i in
                    let cx = [0.2, 0.4, 0.6, 0.8][i]
                    Rectangle()
                        .fill(LinearGradient(colors: [Color(red: 1.0, green: 0.85, blue: 0.5).opacity(0.10), .clear],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: 40, height: h * 0.9)
                        .rotationEffect(.degrees([-8, -3, 3, 8][i]), anchor: .top)
                        .position(x: w * cx, y: h * 0.45)
                        .blur(radius: 12)
                }

                ForEach(0..<sparks.count, id: \.self) { i in
                    let s = sparks[i]
                    Drifter(axis: .vertical, rising: true, cross: w * s.x, extent: h, sway: s.sway,
                            dur: s.dur, phase: s.phase, animate: !settings.motionReduced) {
                        Mote(color: Color(red: 1.0, green: 0.85, blue: 0.45).opacity(s.opacity), size: s.size)
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Mono Rain scene
// A cool charcoal gradient with thin falling code-rain streaks. Minimal and
// monochrome to pair with the mono tile theme.
struct MonoRainBackdrop: View {
    @ObservedObject private var settings = GameSettings.shared

    private let streaks: [(x: CGFloat, len: CGFloat, dur: Double, phase: Double, opacity: Double)] = [
        (0.08, 60, 6.0, 0.00, 0.14), (0.18, 40, 8.0, 0.45, 0.10),
        (0.30, 80, 5.0, 0.20, 0.16), (0.42, 50, 7.0, 0.70, 0.12),
        (0.54, 70, 5.5, 0.10, 0.15), (0.66, 45, 8.5, 0.55, 0.10),
        (0.78, 65, 6.5, 0.30, 0.13), (0.90, 55, 7.5, 0.80, 0.11),
    ]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                LinearGradient(colors: [
                    Color(red: 0.08, green: 0.09, blue: 0.10),
                    Color(red: 0.03, green: 0.03, blue: 0.04)
                ], startPoint: .top, endPoint: .bottom)

                ForEach(0..<streaks.count, id: \.self) { i in
                    let s = streaks[i]
                    Drifter(axis: .vertical, cross: w * s.x, extent: h, sway: 0,
                            dur: s.dur, phase: s.phase, animate: !settings.motionReduced) {
                        Capsule()
                            .fill(LinearGradient(colors: [.clear, Color(red: 0.6, green: 0.9, blue: 0.75).opacity(s.opacity)],
                                                 startPoint: .top, endPoint: .bottom))
                            .frame(width: 2, height: s.len)
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}
