import GameKit
import SwiftUI

// MARK: - Game Center Manager
// Handles authentication, leaderboard submission (one per difficulty), and
// achievement unlocks. All calls are safe no-ops if the player declines
// Game Center sign-in, so the game is fully playable without it.
@MainActor
class GameCenterManager: NSObject, ObservableObject {
    static let shared = GameCenterManager()
    
    @Published var isAuthenticated = false
    @Published var localPlayer = GKLocalPlayer.local
    
    // Leaderboard IDs — configure these to match App Store Connect entries.
    // NOTE: `daily` must be created in App Store Connect (My Apps > Game
    // Center > Leaderboards) with this exact ID before scores will actually
    // appear — submitting to a leaderboard ID that doesn't exist there yet
    // is a silent no-op.
    enum LeaderboardID: String {
        case relaxed = "lexis_leaderboard_relaxed"
        case classic = "lexis_leaderboard_classic"
        case rapid = "lexis_leaderboard_rapid"
        case insane = "lexis_leaderboard_insane"
        case daily = "lexis_leaderboard_daily"

        static func from(_ difficulty: Difficulty) -> LeaderboardID {
            switch difficulty {
            case .relaxed: return .relaxed
            case .classic: return .classic
            case .rapid: return .rapid
            case .insane: return .insane
            }
        }
    }
    
    // Achievement IDs
    enum AchievementID: String {
        case firstWord = "lexis_achievement_first_word"
        case wordsmith50 = "lexis_achievement_50_words"
        case wordsmith200 = "lexis_achievement_200_words"
        case sevenLetterWord = "lexis_achievement_seven_letters"
        case comboMaster = "lexis_achievement_combo_5"
        case insaneSurvivor = "lexis_achievement_insane_survivor"
        case scoreTenK = "lexis_achievement_score_10k"
    }
    
    private override init() {
        super.init()
    }
    
    func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            Task { @MainActor in
                guard let self = self else { return }
                if let vc = viewController {
                    // Present this view controller from the root view controller
                    // when wiring into a real app target.
                    self.presentAuthViewController(vc)
                } else if GKLocalPlayer.local.isAuthenticated {
                    self.isAuthenticated = true
                } else {
                    self.isAuthenticated = false
                    if let error = error {
                        print("Game Center auth failed: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    private func presentAuthViewController(_ vc: UIViewController) {
        #if canImport(UIKit)
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else { return }
        rootVC.present(vc, animated: true)
        #endif
    }
    
    func submitScore(_ score: Int, difficulty: Difficulty) {
        submitScore(score, to: .from(difficulty))
    }

    // Daily Challenge has its own leaderboard rather than sharing one of the
    // four difficulty boards — it's a fixed, identical-for-everyone letter
    // sequence, so ranking it against endless-mode scores wouldn't be a fair
    // comparison.
    func submitDailyScore(_ score: Int) {
        submitScore(score, to: .daily)
    }

    private func submitScore(_ score: Int, to leaderboard: LeaderboardID) {
        guard isAuthenticated else { return }
        GKLeaderboard.submitScore(
            score,
            context: 0,
            player: GKLocalPlayer.local,
            leaderboardIDs: [leaderboard.rawValue]
        ) { error in
            if let error = error {
                print("Score submission failed: \(error.localizedDescription)")
            }
        }
    }
    
    func reportAchievement(_ id: AchievementID, percentComplete: Double = 100) {
        guard isAuthenticated else { return }
        let achievement = GKAchievement(identifier: id.rawValue)
        achievement.percentComplete = percentComplete
        achievement.showsCompletionBanner = true
        GKAchievement.report([achievement]) { error in
            if let error = error {
                print("Achievement report failed: \(error.localizedDescription)")
            }
        }
    }
    
    // friendsOnly matters more than it sounds like it should: a casual
    // player has essentially zero realistic shot at ranking on a global
    // word-game leaderboard, but beating a specific friend is achievable
    // and far more motivating. GKGameCenterViewController supports this
    // natively via playerScope — this was previously hardcoded to .global.
    func showLeaderboard(for difficulty: Difficulty, friendsOnly: Bool = false) {
        presentLeaderboard(id: .from(difficulty), timeScope: .allTime, friendsOnly: friendsOnly)
    }

    // Daily Challenge scores accumulate on one leaderboard forever, so we
    // scope the view to .today rather than .allTime — that's what actually
    // shows "how everyone did on today's puzzle" instead of an all-time
    // ranking dominated by whoever's played the longest.
    func showDailyLeaderboard(friendsOnly: Bool = false) {
        presentLeaderboard(id: .daily, timeScope: .today, friendsOnly: friendsOnly)
    }

    private func presentLeaderboard(id: LeaderboardID, timeScope: GKLeaderboard.TimeScope, friendsOnly: Bool = false) {
        #if canImport(UIKit)
        guard isAuthenticated,
              let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else { return }

        let gcVC = GKGameCenterViewController(
            leaderboardID: id.rawValue,
            playerScope: friendsOnly ? .friendsOnly : .global,
            timeScope: timeScope
        )
        gcVC.gameCenterDelegate = self
        rootVC.present(gcVC, animated: true)
        #endif
    }
}

extension GameCenterManager: GKGameCenterControllerDelegate {
    nonisolated func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
        // The delegate callback is nonisolated, but dismiss() is main-actor
        // isolated (it's UIKit), so hop to the main actor to call it —
        // otherwise this is a data-race warning today and an error in Swift 6.
        Task { @MainActor in
            gameCenterViewController.dismiss(animated: true)
        }
    }
}

// MARK: - Achievement Tracking Hooks
// Call these from GameModel at the relevant moments. Kept separate so the
// core game logic file doesn't need to import GameKit directly.
@MainActor
enum AchievementTracker {
    static func onWordFound(word: String, totalWordsThisSession: Int, allTimeWordCount: Int) {
        let gc = GameCenterManager.shared
        if allTimeWordCount == 1 {
            gc.reportAchievement(.firstWord)
        }
        if allTimeWordCount >= 50 {
            gc.reportAchievement(.wordsmith50)
        }
        if allTimeWordCount >= 200 {
            gc.reportAchievement(.wordsmith200)
        }
        if word.count >= 7 {
            gc.reportAchievement(.sevenLetterWord)
        }
    }
    
    static func onCombo(_ comboCount: Int) {
        if comboCount >= 5 {
            GameCenterManager.shared.reportAchievement(.comboMaster)
        }
    }
    
    static func onGameOver(score: Int, difficulty: Difficulty, blocksDropped: Int) {
        let gc = GameCenterManager.shared
        gc.submitScore(score, difficulty: difficulty)
        if score >= 10_000 {
            gc.reportAchievement(.scoreTenK)
        }
        if difficulty == .insane && blocksDropped >= 100 {
            gc.reportAchievement(.insaneSurvivor)
        }
    }
}
