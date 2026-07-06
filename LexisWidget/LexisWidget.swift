import WidgetKit
import SwiftUI

// This target is a separate process/module from the main LEXIS app, so it
// can't import DailyChallengeManager directly — it reads the same handful
// of keys from the shared App Group container instead. Keep this list in
// sync with DailyChallengeManager.swift's saveState()/loadState() if those
// keys ever change.
private enum SharedKeys {
    static let appGroupID = "group.com.daviddefranceski.lexis"
    static let currentStreak = "lexisDailyCurrentStreak"
    static let bestStreak = "lexisDailyBestStreak"
    static func dailyResult(for dateKey: String) -> String { "lexisDailyResult_\(dateKey)" }
}

private func todayDateKey() -> String {
    let df = DateFormatter()
    df.dateFormat = "yyyy-MM-dd"
    df.timeZone = TimeZone.current
    return df.string(from: Date())
}

struct LexisStreakEntry: TimelineEntry {
    let date: Date
    let currentStreak: Int
    let bestStreak: Int
    let completedToday: Bool
}

struct LexisStreakProvider: TimelineProvider {
    private func currentEntry() -> LexisStreakEntry {
        let defaults = UserDefaults(suiteName: SharedKeys.appGroupID) ?? .standard
        let completed = defaults.data(forKey: SharedKeys.dailyResult(for: todayDateKey())) != nil
        return LexisStreakEntry(
            date: Date(),
            currentStreak: defaults.integer(forKey: SharedKeys.currentStreak),
            bestStreak: defaults.integer(forKey: SharedKeys.bestStreak),
            completedToday: completed
        )
    }

    func placeholder(in context: Context) -> LexisStreakEntry {
        LexisStreakEntry(date: Date(), currentStreak: 3, bestStreak: 7, completedToday: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (LexisStreakEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LexisStreakEntry>) -> Void) {
        let entry = currentEntry()
        // "Today" flips at local midnight — that's the only moment this
        // entry can go stale on its own, so that's when to refresh next.
        // (The app also force-refreshes via WidgetCenter right after a
        // Daily run completes, so a same-day result shows up immediately
        // rather than waiting for this scheduled refresh.)
        let nextMidnight = Calendar.current.nextDate(
            after: Date(),
            matching: DateComponents(hour: 0, minute: 0),
            matchingPolicy: .nextTime
        ) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(nextMidnight)))
    }
}

struct LexisWidgetView: View {
    // Mirrors LEXIS's own palette (GameView.swift's Color extension) — this
    // target can't import that extension, so the values are copied rather
    // than shared, to keep the widget feeling like the same app rather than
    // a generic system widget.
    private static let bg = Color(red: 0.06, green: 0.06, blue: 0.12)
    private static let bgRaised = Color(red: 0.11, green: 0.12, blue: 0.2)
    private static let accent = Color(red: 0.4, green: 0.9, blue: 0.7)
    private static let gold = Color(red: 1.0, green: 0.82, blue: 0.2)
    private static let combo = Color(red: 1.0, green: 0.5, blue: 0.1)
    private static let mid = Color(red: 0.5, green: 0.6, blue: 0.8)

    var entry: LexisStreakProvider.Entry

    var body: some View {
        ZStack {
            LinearGradient(colors: [Self.bg, Self.bgRaised], startPoint: .top, endPoint: .bottom)

            VStack(spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "flame.fill")
                        .foregroundColor(Self.combo)
                    Text("\(entry.currentStreak)")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                }
                Text("DAY STREAK")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Self.mid)
                    .tracking(1.5)

                Spacer(minLength: 6)

                HStack(spacing: 5) {
                    Image(systemName: entry.completedToday ? "checkmark.circle.fill" : "calendar")
                        .font(.system(size: 11, weight: .bold))
                    Text(entry.completedToday ? "TODAY DONE" : "PLAY TODAY")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .tracking(0.5)
                }
                .foregroundColor(entry.completedToday ? Self.accent : Self.gold)
            }
            .padding(12)
        }
    }
}

struct LexisWidget: Widget {
    let kind: String = "LexisWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LexisStreakProvider()) { entry in
            LexisWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("LEXIS Streak")
        .description("See your daily streak and whether you've played today's challenge.")
        .supportedFamilies([.systemSmall])
    }
}

#Preview(as: .systemSmall) {
    LexisWidget()
} timeline: {
    LexisStreakEntry(date: .now, currentStreak: 5, bestStreak: 12, completedToday: true)
    LexisStreakEntry(date: .now, currentStreak: 5, bestStreak: 12, completedToday: false)
}
