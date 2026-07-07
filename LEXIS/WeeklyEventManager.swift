import Foundation

// MARK: - Weekly event (R5 — live-ops lite)
//
// A recurring competitive event built entirely on the deterministic
// seeded-sequence engine already behind Daily and Duel — so it needs almost
// no new game tech and no server. Everyone playing in the same week gets the
// same letters; scores post to a shared weekly Game Center board.
//
// One event slot, two flavours: a normal Weekly Challenge (Mon–Thu) and a
// higher-reward Weekend Sprint (Fri–Sun). There's always exactly one active
// event, so the UI only ever shows one card.

struct WeeklyEvent: Equatable {
    let id: String          // e.g. "2026-W28" or "2026-W28-WKND"
    let title: String
    let subtitle: String
    let seed: String        // fed to DailyChallengeManager.sequence(for:)
    let isWeekend: Bool
    let coinReward: Int
}

@MainActor
final class WeeklyEventManager: ObservableObject {
    static let shared = WeeklyEventManager()

    @Published private(set) var event: WeeklyEvent
    @Published private(set) var bestScore: Int
    @Published private(set) var hasPlayed: Bool

    private init() {
        let e = Self.computeEvent()
        event = e
        bestScore = UserDefaults.standard.integer(forKey: Self.bestKey(e.id))
        hasPlayed = UserDefaults.standard.bool(forKey: Self.playedKey(e.id))
    }

    /// Recompute the active event (call on launch / becoming active) in case
    /// the week — or the weekday-driven weekend flavour — has rolled over.
    func refresh() {
        let e = Self.computeEvent()
        if e.id != event.id {
            event = e
            bestScore = UserDefaults.standard.integer(forKey: Self.bestKey(e.id))
            hasPlayed = UserDefaults.standard.bool(forKey: Self.playedKey(e.id))
        }
    }

    /// Record a finished run: update this event's personal best, mark played,
    /// grant the coin reward once, and submit to the weekly leaderboard.
    func recordResult(score: Int) {
        if !hasPlayed {
            hasPlayed = true
            UserDefaults.standard.set(true, forKey: Self.playedKey(event.id))
            // One-time coin reward per event for participating.
            PlayerProfile.shared.addCoins(event.coinReward)
        }
        if score > bestScore {
            bestScore = score
            UserDefaults.standard.set(score, forKey: Self.bestKey(event.id))
        }
        GameCenterManager.shared.submitWeeklyScore(score)
    }

    // MARK: Event computation

    private static func computeEvent() -> WeeklyEvent {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = .current
        let now = Date()
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear, .weekday], from: now)
        let year = comps.yearForWeekOfYear ?? 2026
        let week = comps.weekOfYear ?? 1
        // ISO weekday: 1 = Monday … 7 = Sunday. Weekend sprint runs Fri–Sun.
        let weekday = comps.weekday ?? 2
        let isoWeekday = (weekday + 5) % 7 + 1   // convert Gregorian (1=Sun) → ISO (1=Mon)
        let isWeekend = isoWeekday >= 5          // Fri(5) Sat(6) Sun(7)

        let base = String(format: "%04d-W%02d", year, week)
        if isWeekend {
            return WeeklyEvent(
                id: base + "-WKND",
                title: "Weekend Sprint",
                subtitle: "Bonus event · same letters for all",
                seed: "lexis-weekend-" + base,
                isWeekend: true,
                coinReward: 120)
        } else {
            return WeeklyEvent(
                id: base,
                title: "Weekly Challenge",
                subtitle: "One board, everyone, this week",
                seed: "lexis-weekly-" + base,
                isWeekend: false,
                coinReward: 60)
        }
    }

    private static func bestKey(_ id: String) -> String { "lexisWeeklyBest_\(id)" }
    private static func playedKey(_ id: String) -> String { "lexisWeeklyPlayed_\(id)" }
}
