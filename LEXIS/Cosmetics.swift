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
    // Scene backdrops — evocative, gently animated, matched to a theme's world.
    case oceanDeep, sunsetBeach

    var id: String { rawValue }
    var cosmeticID: String { "backdrop.\(rawValue)" }
    var isDefault: Bool { self == .none }
    /// Scenes are the fancier, animated tier.
    var isScene: Bool { self == .oceanDeep || self == .sunsetBeach }
    var displayName: String {
        switch self {
        case .none: return "None"
        case .dusk: return "Dusk"
        case .mint: return "Mint Glow"
        case .ember: return "Ember"
        case .grid: return "Neon Grid"
        case .oceanDeep: return "Ocean Deep"
        case .sunsetBeach: return "Sunset Beach"
        }
    }
    var coinPrice: Int {
        switch self {
        case .none: return 0
        case .dusk, .mint: return 150
        case .ember, .grid: return 200
        case .oceanDeep, .sunsetBeach: return 350   // scenes cost a bit more
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
