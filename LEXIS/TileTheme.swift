import SwiftUI

// MARK: - Tile Themes
// Purely cosmetic — no effect on play. Once a player has seen every
// difficulty and word length, the game has nothing new to show them; a
// small collection layer unlocked by real milestones gives long-term
// players a reason to keep opening the app after they've "mastered" the
// scoring, without touching balance.
// Not @MainActor as a whole: the enum itself, its id, colors, and Codable/
// CaseIterable conformances are pure value logic that must stay nonisolated
// (marking the enum @MainActor makes its Identifiable conformance cross into
// main-actor code — a data-race warning, and a Swift 6 error). Only
// isUnlocked touches main-actor singletons, so only it is @MainActor below.
enum TileTheme: String, CaseIterable, Identifiable, Codable {
    case classic = "Classic"
    case sunset = "Sunset"
    case ocean = "Ocean"
    case violet = "Violet"
    case gold = "Gold"
    case forest = "Forest"
    case rose = "Rose"
    case mono = "Mono"

    var id: String { rawValue }

    var topColor: Color {
        switch self {
        case .classic: return Color(red: 0.24, green: 0.28, blue: 0.4)
        case .sunset: return Color(red: 0.46, green: 0.26, blue: 0.18)
        case .ocean: return Color(red: 0.14, green: 0.32, blue: 0.42)
        case .violet: return Color(red: 0.33, green: 0.22, blue: 0.46)
        case .gold: return Color(red: 0.44, green: 0.37, blue: 0.14)
        case .forest: return Color(red: 0.16, green: 0.34, blue: 0.22)
        case .rose: return Color(red: 0.44, green: 0.20, blue: 0.30)
        case .mono: return Color(red: 0.30, green: 0.32, blue: 0.36)
        }
    }

    var bottomColor: Color {
        switch self {
        case .classic: return Color(red: 0.09, green: 0.11, blue: 0.18)
        case .sunset: return Color(red: 0.18, green: 0.08, blue: 0.05)
        case .ocean: return Color(red: 0.04, green: 0.12, blue: 0.18)
        case .violet: return Color(red: 0.12, green: 0.06, blue: 0.19)
        case .gold: return Color(red: 0.16, green: 0.13, blue: 0.03)
        case .forest: return Color(red: 0.04, green: 0.13, blue: 0.08)
        case .rose: return Color(red: 0.18, green: 0.05, blue: 0.10)
        case .mono: return Color(red: 0.08, green: 0.09, blue: 0.11)
        }
    }

    // Blended in as tiles age, same as the classic theme's existing
    // "older tiles redden" treatment — just each theme's own accent instead
    // of always red. Every accent needs to stay visually distinct from the
    // board's "word is glowing, ready to clear" yellow (see TileView's
    // isGlowing fill/border) — the Gold theme's accent originally sat right
    // on top of that same bright yellow, so an old, ordinary tile could
    // look indistinguishable from an actually-glowing one at a glance.
    // Shifted toward a deeper bronze/copper to keep the "gold" identity
    // without the collision.
    var ageAccent: Color {
        switch self {
        case .classic: return .lexisDanger
        case .sunset: return Color(red: 1.0, green: 0.45, blue: 0.15)
        case .ocean: return Color(red: 0.3, green: 0.75, blue: 0.95)
        case .violet: return Color(red: 0.75, green: 0.4, blue: 0.95)
        case .gold: return Color(red: 0.72, green: 0.42, blue: 0.06)
        case .forest: return Color(red: 0.30, green: 0.85, blue: 0.45)
        case .rose: return Color(red: 1.0, green: 0.42, blue: 0.62)
        case .mono: return Color(red: 0.70, green: 0.75, blue: 0.85)
        }
    }

    // Coins to buy this theme outright from the collection, as an alternative
    // to reaching its milestone. The three newest themes are buy-only (no
    // milestone), so they exist purely as a coin sink for the economy.
    var coinPrice: Int {
        switch self {
        case .classic: return 0
        case .sunset: return 150
        case .violet: return 250
        case .ocean: return 300
        case .forest: return 250
        case .rose: return 250
        case .mono: return 400
        case .gold: return 500
        }
    }

    /// True when this theme has no milestone and can only be bought with coins.
    var isBuyOnly: Bool {
        switch self {
        case .forest, .rose, .mono: return true
        default: return false
        }
    }

    var unlockDescription: String {
        switch self {
        case .classic: return "Always available"
        case .sunset: return "Find 25 words total"
        case .ocean: return "Find 100 words total"
        case .violet: return "Reach a 3-day daily streak"
        case .gold: return "Score 10,000 in a single run"
        case .forest, .rose, .mono: return "Unlock in the Collection"
        }
    }

    /// Whether this theme's MILESTONE (not coin purchase) has been reached.
    /// Kept separate from `isUnlocked` so the collection can show "earned via
    /// milestone" vs "bought" and so buy-only themes never auto-unlock.
    @MainActor
    var milestoneMet: Bool {
        switch self {
        case .classic:
            return true
        case .sunset:
            return UserDefaults.standard.integer(forKey: "lexisAllTimeWordCount") >= 25
        case .ocean:
            return UserDefaults.standard.integer(forKey: "lexisAllTimeWordCount") >= 100
        case .violet:
            return DailyChallengeManager.shared.bestStreak >= 3
        case .gold:
            return (GameSettings.shared.allTimeScores().first?.score ?? 0) >= 10_000
        case .forest, .rose, .mono:
            return false
        }
    }

    // Reads main-actor singletons, so this member is main-actor isolated while
    // the rest of the enum stays nonisolated. Callers are all UI. A theme is
    // available if its milestone is met OR it's been bought with coins.
    @MainActor
    var isUnlocked: Bool {
        milestoneMet || CosmeticsStore.shared.isPurchased(self)
    }

    /// The scene backdrop that shares this theme's world, used by the
    /// "Match Theme" backdrop so equipping a theme dresses the whole board to
    /// match. Must never return `.matchTheme` (that would recurse in
    /// BoardBackdropView). Classic has no scene → `.none` (plain board).
    var matchingScene: BoardBackdrop {
        switch self {
        case .classic: return .none
        case .ocean:   return .oceanDeep
        case .sunset:  return .sunsetBeach
        case .forest:  return .forest
        case .violet:  return .starfield
        case .rose:    return .rosePetals
        case .gold:    return .goldRays
        case .mono:    return .monoRain
        }
    }
}
