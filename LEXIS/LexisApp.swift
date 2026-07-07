import SwiftUI

@main
struct LexisApp: App {
    init() {
        // Kick off Game Center auth early so leaderboards/achievements are
        // ready by the time the player finishes their first game. Same task
        // wires up telemetry: attach analytics sinks, log the app-open, and
        // start MetricKit crash/perf reporting.
        Task { @MainActor in
            GameCenterManager.shared.authenticate()
            Analytics.shared.attachDefaultSinks()
            Analytics.shared.appOpen()
            MetricKitReporter.shared.start()
        }
    }
    
    var body: some Scene {
        WindowGroup {
            GameView()
                .preferredColorScheme(.dark)
        }
    }
}
