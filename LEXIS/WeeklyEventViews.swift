import SwiftUI

// MARK: - Weekly event result (R5)
// The game-over screen for a Weekly Challenge / Weekend Sprint run. Shows the
// score against the player's event best, a "new best" flourish, the coin
// reward, and a jump to the shared leaderboard.
struct WeeklyResultView: View {
    let score: Int
    let survived: Bool
    @Binding var phase: GamePhase

    @ObservedObject private var weekly = WeeklyEventManager.shared
    @ObservedObject private var gameCenter = GameCenterManager.shared
    @State private var showShareSheet = false

    private var isNewBest: Bool { score >= weekly.bestScore && score > 0 }

    var body: some View {
        ZStack {
            Color.lexisBg.ignoresSafeArea()

            VStack(spacing: 16) {
                Spacer()

                Image(systemName: weekly.event.isWeekend ? "bolt.fill" : "trophy.fill")
                    .font(.system(size: 34, weight: .black))
                    .foregroundColor(.lexisGold)

                Text(weekly.event.title.uppercased())
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundColor(.lexisAccent)
                    .tracking(1)

                Text(survived ? "Sequence complete" : "Board filled")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.lexisMid)

                VStack(spacing: 2) {
                    Text("\(score)")
                        .font(.system(size: 48, weight: .black, design: .monospaced))
                        .foregroundColor(.lexisText)
                    Text(isNewBest ? "NEW BEST" : "SCORE · BEST \(weekly.bestScore)")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundColor(isNewBest ? .lexisGold : .lexisMid)
                        .tracking(2)
                }
                .padding(.vertical, 8)

                if gameCenter.isAuthenticated {
                    Button {
                        gameCenter.showWeeklyLeaderboard()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "list.number").font(.system(size: 15, weight: .bold))
                            Text("LEADERBOARD")
                        }
                    }
                    .buttonStyle(LexisPrimaryButtonStyle(tint: .lexisGold))
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                }

                Button {
                    showShareSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 15, weight: .bold))
                        Text("SHARE")
                    }
                }
                .buttonStyle(LexisSecondaryButtonStyle(tint: .lexisAccent))
                .padding(.horizontal, 24)
                .padding(.top, gameCenter.isAuthenticated ? 4 : 12)

                Button {
                    phase = .menu
                } label: {
                    Text("MAIN MENU")
                }
                .buttonStyle(LexisGhostButtonStyle())
                .padding(.horizontal, 24)
                .padding(.top, 4)

                Spacer()
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: ["I scored \(score) in this week's LEXIS \(weekly.event.title). Can you beat it?"])
        }
    }
}
