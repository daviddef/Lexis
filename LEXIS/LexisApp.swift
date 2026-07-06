import SwiftUI

@main
struct LexisApp: App {
    init() {
        // Kick off Game Center auth early so leaderboards/achievements are
        // ready by the time the player finishes their first game.
        Task { @MainActor in
            GameCenterManager.shared.authenticate()
        }
    }
    
    var body: some Scene {
        WindowGroup {
            GameView()
                .preferredColorScheme(.dark)
        }
    }
}
