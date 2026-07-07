import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Progression (R3 — the meta engine)
//
// Two systems that give every session a purpose beyond a one-off high score:
//
//   • PlayerProfile — a persistent XP / level track (distinct from the
//     in-run "level"), plus a soft currency (coins) that R4's collection &
//     shop spend. Levelling up is a real, celebrated moment.
//   • GoalsManager — three rotating daily goals, seeded by the date so
//     everyone's set is stable across the day and refreshes at midnight.
//     Completing one grants XP + coins — a thread the player leaves
//     half-pulled, which is what actually brings them back tomorrow.
//
// Both are plain ObservableObjects persisted to UserDefaults; no server.

// MARK: PlayerProfile

@MainActor
final class PlayerProfile: ObservableObject {
    static let shared = PlayerProfile()

    @Published private(set) var totalXP: Int
    @Published private(set) var coins: Int
    /// Set when a call to addXP crosses a level boundary; the UI reads it to
    /// play the level-up celebration, then clears it.
    @Published var pendingLevelUp: Int?

    private init() {
        totalXP = UserDefaults.standard.integer(forKey: "lexisTotalXP")
        coins = UserDefaults.standard.integer(forKey: "lexisCoins")
    }

    // Level curve: cost to advance FROM level L is 100 + (L-1)*50, so early
    // levels come fast and later ones stretch out.
    private func levelCost(_ level: Int) -> Int { 100 + (level - 1) * 50 }

    func xpToReach(_ level: Int) -> Int {
        guard level > 1 else { return 0 }
        return (1..<level).reduce(0) { $0 + levelCost($1) }
    }

    var level: Int {
        var l = 1
        while totalXP >= xpToReach(l + 1) { l += 1 }
        return l
    }

    var xpIntoCurrentLevel: Int { totalXP - xpToReach(level) }
    var xpForCurrentLevelSpan: Int { xpToReach(level + 1) - xpToReach(level) }
    var levelProgress: Double {
        let span = xpForCurrentLevelSpan
        return span > 0 ? min(1, Double(xpIntoCurrentLevel) / Double(span)) : 0
    }

    func addXP(_ amount: Int) {
        guard amount > 0 else { return }
        let before = level
        totalXP += amount
        UserDefaults.standard.set(totalXP, forKey: "lexisTotalXP")
        let after = level
        if after > before {
            pendingLevelUp = after
            // Each level banks coins toward the collection — the level-up
            // moment pays out, not just increments a number.
            addCoins(25 * (after - before))
            Analytics.shared.track(.init("level_up", ["level": "\(after)"]))
        }
    }

    func addCoins(_ amount: Int) {
        guard amount != 0 else { return }
        coins = max(0, coins + amount)
        UserDefaults.standard.set(coins, forKey: "lexisCoins")
    }

    /// True if the player could afford `cost`; used by the R4/R6 shop.
    func canAfford(_ cost: Int) -> Bool { coins >= cost }

    @discardableResult
    func spendCoins(_ cost: Int) -> Bool {
        guard coins >= cost else { return false }
        addCoins(-cost)
        return true
    }
}

// MARK: Goals

/// What a goal measures. Kept as a plain string tag (not an associated-value
/// enum) so `Goal` stays trivially Codable for persistence.
enum GoalKind: String, Codable {
    case wordLength   // find one word of length >= target
    case combo        // reach an N-chain combo in a run
    case wordsInRun   // clear N words in a single run
    case diagonal     // clear one diagonal word
    case scoreInRun   // score N points in a single run
    case playDaily    // play today's Daily Challenge
}

struct Goal: Codable, Identifiable, Equatable {
    let id: String            // template key, stable within a day
    let kind: GoalKind
    let target: Int
    var progress: Int
    let xpReward: Int
    let coinReward: Int
    let title: String

    var isComplete: Bool { progress >= target }
    var fraction: Double { target > 0 ? min(1, Double(progress) / Double(target)) : 0 }
}

@MainActor
final class GoalsManager: ObservableObject {
    static let shared = GoalsManager()

    @Published private(set) var dailyGoals: [Goal] = []
    /// Set when a goal is completed, for a one-shot UI toast.
    @Published var justCompleted: Goal?

    // Per-run counters, reset at the start of each game.
    private var runWordCount = 0

    private let templates: [Goal] = [
        Goal(id: "w5", kind: .wordLength, target: 5, progress: 0, xpReward: 40, coinReward: 10, title: "Find a 5-letter word"),
        Goal(id: "w6", kind: .wordLength, target: 6, progress: 0, xpReward: 60, coinReward: 15, title: "Find a 6-letter word"),
        Goal(id: "w7", kind: .wordLength, target: 7, progress: 0, xpReward: 90, coinReward: 22, title: "Find a 7-letter word"),
        Goal(id: "c3", kind: .combo, target: 3, progress: 0, xpReward: 50, coinReward: 12, title: "Reach a 3-chain combo"),
        Goal(id: "c4", kind: .combo, target: 4, progress: 0, xpReward: 80, coinReward: 20, title: "Reach a 4-chain combo"),
        Goal(id: "n15", kind: .wordsInRun, target: 15, progress: 0, xpReward: 50, coinReward: 12, title: "Clear 15 words in one run"),
        Goal(id: "n25", kind: .wordsInRun, target: 25, progress: 0, xpReward: 90, coinReward: 20, title: "Clear 25 words in one run"),
        Goal(id: "diag", kind: .diagonal, target: 1, progress: 0, xpReward: 60, coinReward: 15, title: "Clear a diagonal word"),
        Goal(id: "s800", kind: .scoreInRun, target: 800, progress: 0, xpReward: 50, coinReward: 12, title: "Score 800 in one run"),
        Goal(id: "s1500", kind: .scoreInRun, target: 1500, progress: 0, xpReward: 90, coinReward: 22, title: "Score 1,500 in one run"),
        Goal(id: "daily", kind: .playDaily, target: 1, progress: 0, xpReward: 40, coinReward: 10, title: "Play today's Daily Challenge"),
    ]

    private init() {
        loadOrGenerate()
    }

    private func todayKey() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    /// Restore today's goals (preserving progress) or generate a fresh trio.
    func loadOrGenerate() {
        let today = todayKey()
        let savedDate = UserDefaults.standard.string(forKey: "lexisDailyGoalsDate")
        if savedDate == today,
           let data = UserDefaults.standard.data(forKey: "lexisDailyGoals"),
           let saved = try? JSONDecoder().decode([Goal].self, from: data), !saved.isEmpty {
            dailyGoals = saved
            return
        }
        dailyGoals = pickGoals(seed: today)
        persist()
        UserDefaults.standard.set(today, forKey: "lexisDailyGoalsDate")
    }

    /// Deterministically pick 3 distinct goals from the catalogue, seeded by
    /// the date string so the set is stable all day and identical on relaunch.
    private func pickGoals(seed: String) -> [Goal] {
        var state = UInt64(bitPattern: Int64(seed.hashValue)) ^ 0x9E3779B97F4A7C15
        func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
        var pool = templates
        var chosen: [Goal] = []
        while chosen.count < 3 && !pool.isEmpty {
            let idx = Int(next() % UInt64(pool.count))
            chosen.append(pool.remove(at: idx))
        }
        return chosen
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(dailyGoals) {
            UserDefaults.standard.set(data, forKey: "lexisDailyGoals")
        }
    }

    // MARK: Event intake (called from GameModel)

    func onRunStarted() { runWordCount = 0 }

    func onWordCleared(length: Int, isDiagonal: Bool) {
        runWordCount += 1
        bump(.wordLength) { length >= $0.target ? $0.target : $0.progress }
        bump(.wordsInRun) { max($0.progress, runWordCount) }
        if isDiagonal { bump(.diagonal) { _ in 1 } }
    }

    func onComboReached(_ combo: Int) {
        bump(.combo) { max($0.progress, combo) }
    }

    func onRunEnded(score: Int) {
        bump(.scoreInRun) { max($0.progress, score) }
    }

    func onDailyPlayed() {
        bump(.playDaily) { _ in 1 }
    }

    /// Apply a progress update to every goal of `kind`, awarding rewards the
    /// moment one crosses into completion.
    private func bump(_ kind: GoalKind, _ newProgress: (Goal) -> Int) {
        var changed = false
        for i in dailyGoals.indices where dailyGoals[i].kind == kind && !dailyGoals[i].isComplete {
            let np = newProgress(dailyGoals[i])
            if np != dailyGoals[i].progress {
                dailyGoals[i].progress = np
                changed = true
                if dailyGoals[i].isComplete {
                    complete(dailyGoals[i])
                }
            }
        }
        if changed { persist() }
    }

    private func complete(_ goal: Goal) {
        PlayerProfile.shared.addXP(goal.xpReward)
        PlayerProfile.shared.addCoins(goal.coinReward)
        justCompleted = goal
        Haptics.success()
        SoundManager.powerUp()
        Analytics.shared.track(.init("goal_complete", ["id": goal.id, "xp": "\(goal.xpReward)"]))
    }

    var completedCount: Int { dailyGoals.filter { $0.isComplete }.count }
}
