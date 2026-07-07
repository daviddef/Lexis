import SwiftUI

// MARK: - Settings View
struct SettingsView: View {
    @ObservedObject var settings = GameSettings.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showGuide = false
    var onDifficultyChanged: ((Difficulty) -> Void)? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color.lexisBg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {

                        // Help section — the on-board "drag to move /
                        // double-tap to drop" hint used to sit permanently
                        // under the board; it now lives here instead, plus
                        // the rest of the mechanics (tips, bombs, wildcards)
                        // that never had an in-game explainer at all.
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "HELP")

                            Button {
                                showGuide = true
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: "questionmark.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(.lexisAccent)
                                        .frame(width: 24)
                                    Text("How to Play")
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                        .foregroundColor(.lexisText)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.lexisMid)
                                }
                                .padding(16)
                                .background(RoundedRectangle(cornerRadius: 14).fill(Color.lexisBlock.opacity(0.6)))
                            }
                        }

                        // Difficulty section
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "DIFFICULTY")
                            
                            VStack(spacing: 10) {
                                ForEach(Difficulty.allCases) { diff in
                                    DifficultyRow(
                                        difficulty: diff,
                                        isSelected: settings.difficulty == diff,
                                        highScore: settings.highScore(for: diff)
                                    ) {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            settings.difficulty = diff
                                        }
                                        onDifficultyChanged?(diff)
                                        Haptics.light()
                                    }
                                }
                            }
                        }
                        
                        // Tile theme — purely cosmetic, unlocked by real
                        // milestones so long-time players have something to
                        // work toward beyond the scoreboard.
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "TILE THEME")

                            VStack(spacing: 10) {
                                ForEach(TileTheme.allCases) { theme in
                                    ThemeRow(
                                        theme: theme,
                                        isSelected: settings.tileTheme == theme
                                    ) {
                                        guard theme.isUnlocked else {
                                            Haptics.light()
                                            return
                                        }
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            settings.tileTheme = theme
                                        }
                                        Haptics.light()
                                    }
                                }
                            }
                        }

                        // Gameplay toggles
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "GAMEPLAY")
                            
                            VStack(spacing: 2) {
                                ToggleRow(
                                    icon: "hand.tap.fill",
                                    title: "Haptic Feedback",
                                    subtitle: "Vibration on moves, words & danger",
                                    isOn: $settings.hapticsEnabled
                                )
                                Divider().background(Color.lexisBlockBorder.opacity(0.2))
                                ToggleRow(
                                    icon: "speaker.wave.2.fill",
                                    title: "Sound Effects",
                                    subtitle: "Drop, clear & combo sounds",
                                    isOn: $settings.soundEnabled
                                )
                                Divider().background(Color.lexisBlockBorder.opacity(0.2))
                                ToggleRow(
                                    icon: "arrow.down.to.line.compact",
                                    title: "Ghost Piece",
                                    subtitle: "Preview where your letter will land",
                                    isOn: $settings.showGhostPiece
                                )
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color.lexisBlock.opacity(0.6))
                            )
                        }
                        
                        // Accessibility
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "ACCESSIBILITY")
                            
                            VStack(spacing: 2) {
                                ToggleRow(
                                    icon: "eye.fill",
                                    title: "Color-Blind Friendly Mode",
                                    subtitle: "Adds shape markers to distinguish tile types",
                                    isOn: $settings.colorBlindMode
                                )
                                Divider().background(Color.lexisBlockBorder.opacity(0.2))
                                ToggleRow(
                                    icon: "textformat.size",
                                    title: "Large Text",
                                    subtitle: "Bigger letters on every tile",
                                    isOn: $settings.largeText
                                )
                                Divider().background(Color.lexisBlockBorder.opacity(0.2))
                                ToggleRow(
                                    icon: "wind",
                                    title: "Reduce Motion",
                                    subtitle: "Calms drifting, gliding & burst effects",
                                    isOn: $settings.reduceMotion
                                )
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color.lexisBlock.opacity(0.6))
                            )
                        }
                        
                        // Notifications (R2 — the daily habit)
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "NOTIFICATIONS")

                            VStack(spacing: 2) {
                                ToggleRow(
                                    icon: "bell.badge.fill",
                                    title: "Daily Reminder",
                                    subtitle: "A nudge when today's puzzle is ready",
                                    isOn: $settings.dailyReminderEnabled
                                )
                                if settings.dailyReminderEnabled {
                                    Divider().background(Color.lexisBlockBorder.opacity(0.2))
                                    HStack {
                                        Image(systemName: "clock.fill")
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(.lexisAccent)
                                            .frame(width: 26)
                                        Text("Reminder Time")
                                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                                            .foregroundColor(.lexisText)
                                        Spacer()
                                        Picker("", selection: $settings.dailyReminderHour) {
                                            ForEach(0..<24, id: \.self) { h in
                                                Text(hourLabel(h)).tag(h)
                                            }
                                        }
                                        .tint(.lexisAccent)
                                    }
                                    .padding(.vertical, 8)
                                }
                                Divider().background(Color.lexisBlockBorder.opacity(0.2))
                                ToggleRow(
                                    icon: "flame.fill",
                                    title: "Streak Reminder",
                                    subtitle: "Warn me before a streak expires at midnight",
                                    isOn: $settings.streakReminderEnabled
                                )
                                Divider().background(Color.lexisBlockBorder.opacity(0.2))
                                ToggleRow(
                                    icon: "hand.wave.fill",
                                    title: "Comeback Nudge",
                                    subtitle: "A reminder if I've been away a few days",
                                    isOn: $settings.winbackEnabled
                                )
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color.lexisBlock.opacity(0.6))
                            )
                            .onChange(of: settings.dailyReminderEnabled) { NotificationManager.shared.settingsChanged() }
                            .onChange(of: settings.dailyReminderHour) { NotificationManager.shared.settingsChanged() }
                            .onChange(of: settings.streakReminderEnabled) { NotificationManager.shared.settingsChanged() }
                            .onChange(of: settings.winbackEnabled) { NotificationManager.shared.settingsChanged() }
                        }

                        // About / reset
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "ABOUT")
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("LEXIS \(appVersionString)")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundColor(.lexisText)
                                Text("One letter. One word. One life.")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundColor(.lexisMid)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color.lexisBlock.opacity(0.6)))
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.lexisBg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.lexisAccent)
                        .fontWeight(.bold)
                }
            }
        }
        .sheet(isPresented: $showGuide) {
            GuideView()
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - How to Play Guide
struct GuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.lexisBg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "MOVING & DROPPING")
                            VStack(alignment: .leading, spacing: 16) {
                                HowToRow(icon: "hand.tap.fill", text: "Tap the left or right side of the board to move one column that way — or slide across to fling it fast")
                                HowToRow(icon: "arrow.down.to.line", text: "Drag down to speed up the fall, or double-tap to drop instantly")
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color.lexisBlock.opacity(0.6)))
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "CLEARING WORDS")
                            VStack(alignment: .leading, spacing: 16) {
                                HowToRow(icon: "hand.tap", text: "Words can read in any of 8 directions. A glowing, pulsing tile means a word is ready")
                                HowToRow(icon: "hand.tap.fill", text: "Double-tap a glowing tile to confirm the clear")
                                HowToRow(icon: "star.fill", color: .lexisGold, text: "Golden blocks are wildcards — tap the popup to pick any letter you need")
                                HowToRow(icon: "arrow.up.right.and.arrow.down.left", text: "Clear words back-to-back without a miss to chain a combo multiplier")
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color.lexisBlock.opacity(0.6)))
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "POWER-UPS")
                            VStack(alignment: .leading, spacing: 16) {
                                HowToRow(icon: "burst.fill", color: .lexisDanger, text: "Spelling a 5+ letter word banks a Clear Path bomb — wipes your current column on demand")
                                HowToRow(icon: "arrow.left.arrow.right", color: .purple, text: "Chaining combos banks a Tip — swipe a glowing top tile sideways to knock it onto a neighbor and reveal what's underneath")
                                HowToRow(icon: "flame.fill", color: .lexisDanger, text: "A 🧨 dynamite tile falling into a stack destroys the one tile it lands on — a precise strike, not the whole column")
                                HowToRow(icon: "bolt.badge.clock.fill", color: .lexisAccent, text: "Leveling up banks a Charge — spend it on Freeze (pause the timer), Reroll (swap your letter), or Peek (see what's coming)")
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color.lexisBlock.opacity(0.6)))
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("How to Play")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.lexisBg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.lexisAccent)
                        .fontWeight(.bold)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .black, design: .monospaced))
            .foregroundColor(.lexisMid)
            .tracking(2)
    }
}

struct ThemeRow: View {
    let theme: TileTheme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: [theme.topColor, theme.bottomColor], startPoint: .top, endPoint: .bottom))
                    .frame(width: 40, height: 40)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(isSelected ? Color.lexisAccent : Color.white.opacity(0.15), lineWidth: isSelected ? 2 : 1)
                    )
                    .opacity(theme.isUnlocked ? 1 : 0.4)

                VStack(alignment: .leading, spacing: 3) {
                    Text(theme.rawValue)
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundColor(theme.isUnlocked ? .lexisText : .lexisMid)
                    Text(theme.isUnlocked ? "Unlocked" : theme.unlockDescription)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.lexisMid)
                }

                Spacer()

                if !theme.isUnlocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.lexisMid)
                } else if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.lexisAccent)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? Color.lexisAccent.opacity(0.08) : Color.lexisBlock.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(isSelected ? Color.lexisAccent.opacity(0.5) : Color.clear, lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct DifficultyRow: View {
    let difficulty: Difficulty
    let isSelected: Bool
    let highScore: Int
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.lexisAccent.opacity(0.2) : Color.lexisBlockBorder.opacity(0.1))
                        .frame(width: 44, height: 44)
                    Image(systemName: difficulty.icon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(isSelected ? .lexisAccent : .lexisMid)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(difficulty.rawValue)
                            .font(.system(size: 16, weight: .black, design: .rounded))
                            .foregroundColor(isSelected ? .lexisAccent : .lexisText)
                        if highScore > 0 {
                            Text("BEST \(highScore)")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.lexisGold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.lexisGold.opacity(0.15)))
                        }
                    }
                    Text(difficulty.subtitle)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.lexisMid)
                        .lineLimit(2)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.lexisAccent)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? Color.lexisAccent.opacity(0.08) : Color.lexisBlock.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(isSelected ? Color.lexisAccent.opacity(0.5) : Color.clear, lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

/// The app's marketing version + build, read from the bundle so it never goes
/// stale as versions bump (this used to be hardcoded and drifted out of date).
var appVersionString: String {
    let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    return "v\(v) (\(b))"
}

/// "7:00 PM" style label for an hour 0…23, used by the daily-reminder time
/// picker. Kept simple and locale-agnostic (12-hour clock with AM/PM).
func hourLabel(_ h: Int) -> String {
    let ampm = h < 12 ? "AM" : "PM"
    let twelve = h % 12 == 0 ? 12 : h % 12
    return "\(twelve):00 \(ampm)"
}

struct ToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.lexisAccent)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.lexisText)
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.lexisMid)
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(.lexisAccent)
        }
        .padding(.vertical, 10)
    }
}

// MARK: - Difficulty Select (pre-game)
struct DifficultySelectSheet: View {
    @ObservedObject var settings = GameSettings.shared
    @Environment(\.dismiss) private var dismiss
    let onStart: (Difficulty) -> Void
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.lexisBg.ignoresSafeArea()
                
                VStack(spacing: 20) {
                    VStack(spacing: 4) {
                        Text("CHOOSE YOUR PACE")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundColor(.lexisText)
                        Text("You can change this anytime in Settings")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.lexisMid)
                    }
                    .padding(.top, 16)
                    
                    VStack(spacing: 12) {
                        ForEach(Difficulty.allCases) { diff in
                            DifficultyRow(
                                difficulty: diff,
                                isSelected: settings.difficulty == diff,
                                highScore: settings.highScore(for: diff)
                            ) {
                                settings.difficulty = diff
                                Haptics.light()
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    Spacer()
                    
                    Button {
                        onStart(settings.difficulty)
                        dismiss()
                    } label: {
                        Text("START GAME")
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .foregroundColor(Color.lexisBg)
                            .tracking(3)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color.lexisAccent))
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.lexisMid)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
