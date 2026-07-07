import SwiftUI

// MARK: - Progression UI (R3)
// The player-facing surface for the XP/level track, coins, and today's goals.
// A compact level chip lives in the menu header; tapping it (or the goals
// badge) opens ProgressSheet.

/// Compact "LV n" chip with a thin XP progress ring — the always-visible
/// sense that playing is getting the player somewhere.
struct LevelChip: View {
    @ObservedObject private var profile = PlayerProfile.shared

    var body: some View {
        HStack(spacing: 7) {
            ZStack {
                Circle()
                    .stroke(Color.lexisBlockBorder.opacity(0.4), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: profile.levelProgress)
                    .stroke(Color.lexisAccent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(profile.level)")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(.lexisText)
            }
            .frame(width: 30, height: 30)

            HStack(spacing: 3) {
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.system(size: 10, weight: .bold))
                Text("\(profile.coins)")
                    .font(.system(size: 13, weight: .black, design: .rounded))
            }
            .foregroundColor(.lexisGold)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.lexisBlock.opacity(0.6)))
    }
}

/// The progression sheet: level + XP, coins, and today's three goals.
struct ProgressSheet: View {
    @ObservedObject private var profile = PlayerProfile.shared
    @ObservedObject private var goals = GoalsManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.lexisBg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 24) {
                    header

                    // Level + XP
                    VStack(spacing: 10) {
                        HStack {
                            Text("LEVEL \(profile.level)")
                                .font(.system(size: 22, weight: .black, design: .rounded))
                                .foregroundColor(.lexisText)
                            Spacer()
                            HStack(spacing: 5) {
                                Image(systemName: "circle.hexagongrid.fill")
                                    .font(.system(size: 14, weight: .bold))
                                Text("\(profile.coins)")
                                    .font(.system(size: 18, weight: .black, design: .rounded))
                            }
                            .foregroundColor(.lexisGold)
                        }
                        xpBar
                        Text("\(profile.xpIntoCurrentLevel) / \(profile.xpForCurrentLevelSpan) XP to level \(profile.level + 1)")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.lexisMid)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(18)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.lexisBlock.opacity(0.6)))

                    // Daily goals
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("DAILY GOALS")
                                .font(.system(size: 13, weight: .black, design: .rounded))
                                .foregroundColor(.lexisMid)
                                .tracking(1.5)
                            Spacer()
                            Text("\(goals.completedCount)/\(goals.dailyGoals.count)")
                                .font(.system(size: 13, weight: .black, design: .rounded))
                                .foregroundColor(goals.completedCount == goals.dailyGoals.count ? .lexisAccent : .lexisMid)
                        }
                        ForEach(goals.dailyGoals) { goal in
                            GoalRow(goal: goal)
                        }
                        Text("New goals every day. Progress carries across every mode.")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.lexisMid.opacity(0.7))
                            .padding(.top, 2)
                    }
                    .padding(18)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.lexisBlock.opacity(0.6)))

                    Spacer(minLength: 8)
                }
                .padding(20)
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Progress")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundColor(.lexisText)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.lexisMid)
                    .frame(width: 36, height: 36)
                    .background(Color.lexisBlock.opacity(0.7))
                    .clipShape(Circle())
            }
        }
    }

    private var xpBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.lexisBlockBorder.opacity(0.3))
                Capsule()
                    .fill(LinearGradient(colors: [Color.lexisAccent, Color.lexisAccent.opacity(0.7)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(6, geo.size.width * profile.levelProgress))
            }
        }
        .frame(height: 12)
    }
}

struct GoalRow: View {
    let goal: Goal

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(goal.isComplete ? Color.lexisAccent.opacity(0.18) : Color.lexisBlockBorder.opacity(0.2))
                    .frame(width: 34, height: 34)
                Image(systemName: goal.isComplete ? "checkmark" : icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(goal.isComplete ? .lexisAccent : .lexisMid)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(goal.title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(goal.isComplete ? .lexisMid : .lexisText)
                    .strikethrough(goal.isComplete, color: .lexisMid)
                if !goal.isComplete && goal.target > 1 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.lexisBlockBorder.opacity(0.25))
                            Capsule().fill(Color.lexisAccent.opacity(0.8))
                                .frame(width: max(4, geo.size.width * goal.fraction))
                        }
                    }
                    .frame(height: 6)
                }
            }

            Spacer()

            HStack(spacing: 3) {
                Text("+\(goal.xpReward)")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(.lexisAccent)
                Text("XP")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .foregroundColor(.lexisAccent.opacity(0.7))
            }
            .opacity(goal.isComplete ? 0.4 : 1)
        }
    }

    private var icon: String {
        switch goal.kind {
        case .wordLength: return "textformat.abc"
        case .combo: return "flame.fill"
        case .wordsInRun: return "square.grid.2x2.fill"
        case .diagonal: return "arrow.up.right"
        case .scoreInRun: return "star.fill"
        case .playDaily: return "calendar"
        }
    }
}

/// Payload for the transient celebration banner.
struct CelebrationItem: Equatable {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
}

/// A transient celebration banner for a level-up or a goal completion. Driven
/// from GameView, which watches PlayerProfile.pendingLevelUp and
/// GoalsManager.justCompleted.
struct CelebrationToast: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(tint.opacity(0.18)).frame(width: 42, height: 42)
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .black))
                    .foregroundColor(tint)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundColor(.lexisText)
                Text(subtitle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.lexisMid)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.lexisBlock)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(tint.opacity(0.5), lineWidth: 1.5))
                .shadow(color: tint.opacity(0.3), radius: 14, y: 4)
        )
        .padding(.horizontal, 20)
    }
}
