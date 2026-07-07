import Foundation

// MARK: - Cosmetics store (R4 — collection & rewards)
//
// Owns the "which cosmetics does the player have" state and the two ways to
// get them: reach a milestone, or buy with coins earned from goals/levels.
// This is deliberately the same catalogue R6's real-money shop will sell —
// StoreKit purchases will simply call `grant(_:)` here — so the collection,
// the coin economy, and (later) IAP all share one source of truth.
//
// Also detects when a theme crosses its milestone during play so the UI can
// finally CELEBRATE an unlock (the audit flagged that unlocks were silent and
// invisible), and seeds "already seen" on first run so long-time players
// aren't spammed for milestones they passed long ago.

@MainActor
final class CosmeticsStore: ObservableObject {
    static let shared = CosmeticsStore()

    @Published private(set) var purchased: Set<String>
    /// Set when a theme becomes newly available (bought or milestone crossed),
    /// for a one-shot celebration in the UI.
    @Published var justUnlocked: TileTheme?

    private var seen: Set<String>

    private init() {
        purchased = Set(UserDefaults.standard.stringArray(forKey: "lexisPurchasedThemes") ?? [])
        if let seenSaved = UserDefaults.standard.stringArray(forKey: "lexisSeenUnlockedThemes") {
            seen = Set(seenSaved)
        } else {
            // First run under R4: treat every theme already earned/owned as
            // "seen", so we don't retroactively celebrate old milestones.
            seen = Set(TileTheme.allCases.filter { $0.milestoneMet }.map { $0.rawValue })
            seen.formUnion(purchased)
            UserDefaults.standard.set(Array(seen), forKey: "lexisSeenUnlockedThemes")
        }
    }

    func isPurchased(_ theme: TileTheme) -> Bool { purchased.contains(theme.rawValue) }

    /// Buy a theme with coins. Returns false if already owned or unaffordable.
    @discardableResult
    func buyWithCoins(_ theme: TileTheme) -> Bool {
        guard !theme.isUnlocked else { return false }
        guard theme.coinPrice > 0, PlayerProfile.shared.spendCoins(theme.coinPrice) else { return false }
        grant(theme, celebrate: true)
        Analytics.shared.track(.init("theme_bought", ["id": theme.rawValue, "coins": "\(theme.coinPrice)"]))
        return true
    }

    /// Mark a theme owned (from a coin buy, or later a StoreKit purchase).
    func grant(_ theme: TileTheme, celebrate: Bool) {
        purchased.insert(theme.rawValue)
        UserDefaults.standard.set(Array(purchased), forKey: "lexisPurchasedThemes")
        markSeen(theme)
        if celebrate {
            justUnlocked = theme
            Analytics.shared.themeUnlocked(theme.rawValue)
        }
    }

    /// Call after events that can cross a milestone (game over). Celebrates any
    /// theme whose milestone is now met but hasn't been announced yet.
    func checkMilestoneUnlocks() {
        for theme in TileTheme.allCases where theme.milestoneMet && !seen.contains(theme.rawValue) {
            markSeen(theme)
            justUnlocked = theme
            Analytics.shared.themeUnlocked(theme.rawValue)
        }
    }

    private func markSeen(_ theme: TileTheme) {
        seen.insert(theme.rawValue)
        UserDefaults.standard.set(Array(seen), forKey: "lexisSeenUnlockedThemes")
    }
}
