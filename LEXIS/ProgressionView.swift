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
    @State private var showCollection = false

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

                    // Collection entry
                    Button { showCollection = true } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle().fill(Color.lexisAccent.opacity(0.15)).frame(width: 44, height: 44)
                                Image(systemName: "square.grid.2x2.fill")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(.lexisAccent)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("COLLECTION")
                                    .font(.system(size: 14, weight: .black, design: .rounded))
                                    .foregroundColor(.lexisText).tracking(1)
                                Text("Spend coins on new tile themes")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundColor(.lexisMid)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold)).foregroundColor(.lexisMid)
                        }
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.lexisBlock.opacity(0.6)))
                    }
                    .buttonStyle(LexisScaleButtonStyle())

                    Spacer(minLength: 8)
                }
                .padding(20)
            }
        }
        .sheet(isPresented: $showCollection) { CollectionView() }
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

// MARK: - Collection (R4)

/// A small static tile in a theme's colours, with the same bevel as the
/// in-game tiles, used as the preview swatch in the collection.
struct ThemeSwatch: View {
    let theme: TileTheme
    var size: CGFloat = 56
    var letter: String = "A"

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(LinearGradient(colors: [theme.topColor, theme.bottomColor],
                                     startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.35), lineWidth: 1.5)
                .offset(x: -0.5, y: -0.5)
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .strokeBorder(Color.black.opacity(0.3), lineWidth: 1.5)
                .offset(x: 0.5, y: 0.5)
            Text(letter)
                .font(.system(size: size * 0.5, weight: .black, design: .rounded))
                .foregroundColor(.lexisText)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.4), radius: 5, y: 2)
    }
}

/// The collection: browse every tile theme, unlock locked ones with coins
/// (earned from goals, level-ups, dailies, and rewarded ads), and equip
/// anything owned. LEXIS is ad-supported — there are no real-money purchases.
struct CollectionView: View {
    @ObservedObject private var settings = GameSettings.shared
    @ObservedObject private var profile = PlayerProfile.shared
    @ObservedObject private var store = CosmeticsStore.shared
    @ObservedObject private var ads = AdManager.shared
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        ZStack {
            Color.lexisBg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    HStack {
                        Text("Collection")
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundColor(.lexisText)
                        Spacer()
                        HStack(spacing: 5) {
                            Image(systemName: "circle.hexagongrid.fill")
                            Text("\(profile.coins)")
                        }
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundColor(.lexisGold)
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.lexisMid)
                                .frame(width: 36, height: 36)
                                .background(Color.lexisBlock.opacity(0.7))
                                .clipShape(Circle())
                        }
                    }

                    // Rewarded ad → coins. Shown only when an ad is ready.
                    if ads.isReady {
                        Button {
                            ads.showRewarded(placement: "coins") {
                                PlayerProfile.shared.addCoins(50)
                                Haptics.success()
                            }
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle().fill(Color.lexisAccent.opacity(0.16)).frame(width: 42, height: 42)
                                    Image(systemName: "play.rectangle.fill").font(.system(size: 17, weight: .bold)).foregroundColor(.lexisAccent)
                                }
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("WATCH FOR COINS").font(.system(size: 14, weight: .black, design: .rounded)).foregroundColor(.lexisText).tracking(1)
                                    Text("Earn 50 coins toward a new theme").font(.system(size: 12, weight: .medium, design: .rounded)).foregroundColor(.lexisMid)
                                }
                                Spacer()
                                HStack(spacing: 3) {
                                    Image(systemName: "circle.hexagongrid.fill").font(.system(size: 12, weight: .bold))
                                    Text("+50").font(.system(size: 15, weight: .black, design: .rounded))
                                }.foregroundColor(.lexisGold)
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color.lexisAccent.opacity(0.08))
                                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .strokeBorder(Color.lexisAccent.opacity(0.35), lineWidth: 1.5))
                            )
                        }
                        .buttonStyle(LexisScaleButtonStyle())
                    }

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(TileTheme.allCases) { theme in
                            ThemeCard(theme: theme)
                        }
                    }
                }
                .padding(20)
            }
        }
    }
}

struct ThemeCard: View {
    let theme: TileTheme
    @ObservedObject private var settings = GameSettings.shared
    @ObservedObject private var profile = PlayerProfile.shared
    @ObservedObject private var store = CosmeticsStore.shared

    private var unlocked: Bool { theme.isUnlocked }
    private var equipped: Bool { settings.tileTheme == theme }

    var body: some View {
        VStack(spacing: 10) {
            ThemeSwatch(theme: theme, size: 58, letter: String(theme.rawValue.prefix(1)))
                .padding(.top, 4)
            Text(theme.rawValue)
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundColor(.lexisText)
            action
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.lexisBlock.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(equipped ? Color.lexisAccent : Color.clear, lineWidth: 2)
                )
        )
    }

    @ViewBuilder private var action: some View {
        if equipped {
            label("EQUIPPED", color: .lexisAccent, filled: true)
        } else if unlocked {
            Button {
                settings.tileTheme = theme
                Haptics.light()
            } label: { label("EQUIP", color: .lexisAccent, filled: false) }
        } else if theme.isBuyOnly || theme.milestoneMet == false {
            // Locked: buyable with coins, or (for milestone themes) show the
            // milestone but still allow buying past it.
            Button {
                if store.buyWithCoins(theme) {
                    settings.tileTheme = theme  // equip immediately
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "circle.hexagongrid.fill").font(.system(size: 11, weight: .bold))
                    Text("\(theme.coinPrice)").font(.system(size: 13, weight: .black, design: .rounded))
                }
                .foregroundColor(profile.canAfford(theme.coinPrice) ? .lexisBg : .lexisMid)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Capsule().fill(profile.canAfford(theme.coinPrice) ? Color.lexisGold : Color.lexisBlockBorder.opacity(0.4)))
            }
            .disabled(!profile.canAfford(theme.coinPrice))
            if !theme.isBuyOnly {
                Text(theme.unlockDescription)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.lexisMid).multilineTextAlignment(.center)
            }
        }
    }

    private func label(_ text: String, color: Color, filled: Bool) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .black, design: .rounded))
            .foregroundColor(filled ? .lexisBg : color)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Capsule().fill(filled ? color : color.opacity(0.15)))
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
