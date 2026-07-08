import SwiftUI

@main
struct LexisApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Run persistence migrations FIRST, synchronously, before any manager
        // reads its UserDefaults-backed state.
        DataMigration.runIfNeeded()
        // Then reconcile progress with iCloud (also synchronous, pre-managers),
        // so a reinstall/new device restores XP, coins, high scores, streaks
        // and owned cosmetics before anything reads them.
        CloudSync.shared.startAndReconcile()

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
            // Rewarded ads: attach the network provider. nil → DEBUG stub so
            // the watch→reward flow is testable now; a real build with no
            // provider simply shows no ads. Wire an AdMob/AppLovin provider
            // here once the SDK + ad units exist.
            AdManager.shared.configure(nil)
        }
    }
    
    var body: some Scene {
        WindowGroup {
            GameView()
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, phase in
            // Back progress up to iCloud when the app goes to the background.
            if phase == .background { CloudSync.shared.pushToCloud() }
        }
    }
}
