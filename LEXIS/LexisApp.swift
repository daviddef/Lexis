import SwiftUI

@main
struct LexisApp: App {
    init() {
        // Run persistence migrations FIRST, synchronously, before any manager
        // reads its UserDefaults-backed state.
        DataMigration.runIfNeeded()

        // Kick off Game Center auth early so leaderboards/achievements are
        // ready by the time the player finishes their first game. Same task
        // wires up telemetry: attach analytics sinks, log the app-open, and
        // start MetricKit crash/perf reporting.
        Task { @MainActor in
            GameCenterManager.shared.authenticate()
            Analytics.shared.attachDefaultSinks()
            Analytics.shared.appOpen()
            MetricKitReporter.shared.start()
            // Notifications: register the tap handler and re-lay the schedule
            // from current streak/settings state (self-heals on every launch).
            NotificationManager.shared.configure()
            NotificationManager.shared.refresh()
            // Refresh today's goals (regenerates if the date rolled over).
            GoalsManager.shared.loadOrGenerate()
            // Roll the weekly event forward if the week/weekend flavour changed.
            WeeklyEventManager.shared.refresh()
            // StoreKit: begin the transaction listener + load products (no-op
            // until App Store Connect products exist).
            StoreManager.shared.start()
        }
    }
    
    var body: some Scene {
        WindowGroup {
            GameView()
                .preferredColorScheme(.dark)
        }
    }
}
