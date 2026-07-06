import SwiftUI

// MARK: - Settings View
struct SettingsView: View {
    @ObservedObject var settings = GameSettings.shared
    @Environment(\.dismiss) private var dismiss
    var onDifficultyChanged: ((Difficulty) -> Void)? = nil
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.lexisBg.ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        
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
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color.lexisBlock.opacity(0.6))
                            )
                        }
                        
                        // About / reset
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "ABOUT")
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("LEXIS v1.1")
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
