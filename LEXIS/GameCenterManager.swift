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
    
    // Leaderboard IDs — configure these to match App Store Connect entries
    enum LeaderboardID: String {
        case relaxed = "lexis_leaderboard_relaxed"
        case classic = "lexis_leaderboard_classic"
        case rapid = "lexis_leaderboard_rapid"
        case insane = "lexis_leaderboard_insane"
        
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
        guard isAuthenticated else { return }
        let leaderboardID = LeaderboardID.from(difficulty).rawValue
        GKLeaderboard.submitScore(
            score,
            context: 0,
            player: GKLocalPlayer.local,
            leaderboardIDs: [leaderboardID]
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
    
    func showLeaderboard(for difficulty: Difficulty) {
        #if canImport(UIKit)
        guard isAuthenticated,
              let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else { return }
        
        let gcVC = GKGameCenterViewController(
            leaderboardID: LeaderboardID.from(difficulty).rawValue,
            playerScope: .global,
            timeScope: .allTime
        )
        gcVC.gameCenterDelegate = self
        rootVC.present(gcVC, animated: true)
        #endif
    }
}

extension GameCenterManager: GKGameCenterControllerDelegate {
    nonisolated func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
        gameCenterViewController.dismiss(animated: true)
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
