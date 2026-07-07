import Foundation

// MARK: - Analytics
//
// A deliberately tiny, vendor-agnostic telemetry layer. The rest of the app
// only ever talks to `Analytics.shared` through the typed helpers below;
// whether an event goes to the console, a product-analytics vendor, or
// nowhere at all is decided here by which sinks are attached.
//
// Ships SAFE by default: with no vendor attached it's a no-op in release and
// a console print in DEBUG. Attaching a real vendor later is a one-liner in
// `attachDefaultSinks()` — recommended TelemetryDeck (Swift-native,
// privacy-first, no PII).
//
// No PII is ever collected — only anonymous gameplay events and coarse
// counters — so it stays clean against App Store privacy nutrition labels.

/// One analytics event: a name plus a small bag of string parameters.
struct AnalyticsEvent {
    let name: String
    let params: [String: String]
    init(_ name: String, _ params: [String: String] = [:]) {
        self.name = name
        self.params = params
    }
}

/// A destination for events. Implement one per vendor. MainActor-isolated so
/// vendor SDKs (many of which touch UIKit/UserDefaults) never get called off
/// the main thread, and so the whole pipe stays free of Sendable friction.
@MainActor
protocol AnalyticsSink: AnyObject {
    func log(_ event: AnalyticsEvent)
}

@MainActor
final class Analytics {
    static let shared = Analytics()
    private var sinks: [AnalyticsSink] = []
    private init() {}

    func attach(_ sink: AnalyticsSink) { sinks.append(sink) }

    func track(_ event: AnalyticsEvent) {
        for sink in sinks { sink.log(event) }
    }

    // MARK: Typed events
    // The ONLY events the app emits, gathered here so the funnel is legible in
    // one place and param keys can never drift between call sites.

    func appOpen() { track(.init("app_open")) }

    func gameStart(mode: String, difficulty: String) {
        track(.init("game_start", ["mode": mode, "difficulty": difficulty]))
    }

    func gameOver(mode: String, difficulty: String, score: Int, level: Int,
                  words: Int, durationSec: Int, survived: Bool? = nil) {
        var p: [String: String] = [
            "mode": mode, "difficulty": difficulty,
            "score": "\(score)", "level": "\(level)",
            "words": "\(words)", "duration_s": "\(durationSec)"
        ]
        if let survived { p["survived"] = survived ? "1" : "0" }
        track(.init("game_over", p))
    }

    func wordCleared(maxLen: Int, isChain: Bool, comboCount: Int) {
        track(.init("word_cleared", [
            "max_len": "\(maxLen)", "chain": isChain ? "1" : "0", "combo": "\(comboCount)"
        ]))
    }

    func powerUpUsed(_ kind: String) { track(.init("powerup_used", ["kind": kind])) }

    func tutorialComplete() { track(.init("tutorial_complete")) }

    func dailyComplete(survived: Bool, score: Int, streak: Int) {
        track(.init("daily_complete", [
            "survived": survived ? "1" : "0", "score": "\(score)", "streak": "\(streak)"
        ]))
    }

    func themeUnlocked(_ id: String) { track(.init("theme_unlocked", ["id": id])) }

    func notificationPermission(granted: Bool) {
        track(.init("notif_permission", ["granted": granted ? "1" : "0"]))
    }

    func purchase(_ productID: String) { track(.init("purchase", ["product": productID])) }

    // MARK: Setup

    /// Attach the default sinks. Console-only in DEBUG today. To turn on real
    /// product analytics, add ONE line here once a vendor is chosen, e.g.:
    ///   attach(TelemetryDeckSink(appID: "YOUR-APP-ID"))
    func attachDefaultSinks() {
        #if DEBUG
        attach(ConsoleAnalyticsSink())
        #endif
    }
}

#if DEBUG
/// Prints every event to the Xcode console so the funnel is visible during
/// development even before a vendor is wired.
@MainActor
final class ConsoleAnalyticsSink: AnalyticsSink {
    func log(_ event: AnalyticsEvent) {
        let kv = event.params.map { "\($0)=\($1)" }.sorted().joined(separator: " ")
        print("📊 \(event.name)\(kv.isEmpty ? "" : " · \(kv)")")
    }
}
#endif
