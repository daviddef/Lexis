import SwiftUI

// MARK: - Tile Themes
// Purely cosmetic — no effect on play. Once a player has seen every
// difficulty and word length, the game has nothing new to show them; a
// small collection layer unlocked by real milestones gives long-term
// players a reason to keep opening the app after they've "mastered" the
// scoring, without touching balance.
@MainActor
enum TileTheme: String, CaseIterable, Identifiable, Codable {
    case classic = "Classic"
    case sunset = "Sunset"
    case ocean = "Ocean"
    case violet = "Violet"
    case gold = "Gold"

    var id: String { rawValue }

    var topColor: Color {
        switch self {
        case .classic: return Color(red: 0.24, green: 0.28, blue: 0.4)
        case .sunset: return Color(red: 0.46, green: 0.26, blue: 0.18)
        case .ocean: return Color(red: 0.14, green: 0.32, blue: 0.42)
        case .violet: return Color(red: 0.33, green: 0.22, blue: 0.46)
        case .gold: return Color(red: 0.44, green: 0.37, blue: 0.14)
        }
    }

    var bottomColor: Color {
        switch self {
        case .classic: return Color(red: 0.09, green: 0.11, blue: 0.18)
        case .sunset: return Color(red: 0.18, green: 0.08, blue: 0.05)
        case .ocean: return Color(red: 0.04, green: 0.12, blue: 0.18)
        case .violet: return Color(red: 0.12, green: 0.06, blue: 0.19)
        case .gold: return Color(red: 0.16, green: 0.13, blue: 0.03)
        }
    }

    // Blended in as tiles age, same as the classic theme's existing
    // "older tiles redden" treatment — just each theme's own accent instead
    // of always red.
    var ageAccent: Color {
        switch self {
        case .classic: return .lexisDanger
        case .sunset: return Color(red: 1.0, green: 0.45, blue: 0.15)
        case .ocean: return Color(red: 0.3, green: 0.75, blue: 0.95)
        case .violet: return Color(red: 0.75, green: 0.4, blue: 0.95)
        case .gold: return Color(red: 1.0, green: 0.85, blue: 0.3)
        }
    }

    var unlockDescription: String {
        switch self {
        case .classic: return "Always available"
        case .sunset: return "Find 25 words total"
        case .ocean: return "Find 100 words total"
        case .violet: return "Reach a 3-day daily streak"
        case .gold: return "Score 10,000 in a single run"
        }
    }

    var isUnlocked: Bool {
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
        }
    }
}
