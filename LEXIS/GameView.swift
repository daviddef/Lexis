import SwiftUI
import UIKit
extension Color {
    static let lexisBg = Color(red: 0.06, green: 0.06, blue: 0.12)
    static let lexisAccent = Color(red: 0.4, green: 0.9, blue: 0.7)      // Mint green
    static let lexisGold = Color(red: 1.0, green: 0.82, blue: 0.2)       // Gold
    static let lexisDanger = Color(red: 1.0, green: 0.25, blue: 0.35)    // Hot red
    static let lexisBlock = Color(red: 0.15, green: 0.18, blue: 0.28)    // Dark slate
    static let lexisBlockBorder = Color(red: 0.3, green: 0.4, blue: 0.6) // Blue-grey
    static let lexisText = Color(red: 0.95, green: 0.95, blue: 1.0)      // Near white
    static let lexisMid = Color(red: 0.5, green: 0.6, blue: 0.8)         // Soft blue
    static let lexisCombo = Color(red: 1.0, green: 0.5, blue: 0.1)       // Orange
}

// Board sits nearly flush with the screen edges — tileSize(for:) and the
// board's own horizontal padding must agree on this value, or the board
// either overflows the screen or leaves unused space at the sides.
let boardHorizontalPadding: CGFloat = 4

// MARK: - Main Game View
struct GameView: View {
    @StateObject private var model = GameModel()
    @ObservedObject private var settings = GameSettings.shared
    @ObservedObject private var notifications = NotificationManager.shared
    @ObservedObject private var profile = PlayerProfile.shared
    @ObservedObject private var goals = GoalsManager.shared
    @State private var celebration: CelebrationItem?
    @State private var showWildcardPicker = false
    @State private var selectedTiles: [(row: Int, col: Int)] = []
    @State private var wordFlashText: String = ""
    @State private var wordFlashOpacity: Double = 0
    @State private var wordFlashColor: Color = .lexisAccent
    @State private var particleEffects: [ParticleEffect] = []
    @State private var showSettings = false
    @State private var showDifficultySelect = false
    @State private var dangerVignettePulse = false

    var body: some View {
        GeometryReader { geo in
            let tileSize = tileSize(for: geo.size)
            ZStack {
                // Background
                Color.lexisBg.ignoresSafeArea()

                // Ambient grid lines
                Path { path in
                    for col in 0...GameConstants.cols {
                        let x = CGFloat(col) * (tileSize + 2) + boardHorizontalPadding
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: geo.size.height))
                    }
                }
                .stroke(Color.lexisBlockBorder.opacity(0.12), lineWidth: 0.5)
                .allowsHitTesting(false)

                // Phase content, cross-faded with a subtle scale so moving
                // between menu / play / game-over feels like one continuous
                // space rather than an abrupt screen swap. The
                // .animation(value:) drives the child insert/remove
                // transitions off the phase change wherever it's set.
                Group {
                    switch model.phase {
                    case .menu:
                        MenuView(model: model, showSettings: $showSettings, showDifficultySelect: $showDifficultySelect)
                            .transition(.opacity.combined(with: .scale(scale: 1.03)))
                    case .playing, .paused:
                        PlayingView(
                            model: model,
                            tileSize: tileSize,
                            showWildcardPicker: $showWildcardPicker,
                            selectedTiles: $selectedTiles,
                            wordFlashText: $wordFlashText,
                            wordFlashOpacity: $wordFlashOpacity,
                            wordFlashColor: $wordFlashColor,
                            showSettings: $showSettings
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    case .gameOver:
                        Group {
                            if model.isDuelMode, let duel = model.duelResult {
                                DuelResultView(code: duel.code, score: duel.score, phase: $model.phase)
                            } else if model.isDailyMode, let result = model.dailyManager.todayResult {
                                DailyResultView(result: result, streak: model.dailyManager.currentStreak)
                                    .onDisappear {
                                        model.phase = .menu
                                    }
                            } else {
                                GameOverView(model: model, showDifficultySelect: $showDifficultySelect)
                            }
                        }
                        .transition(.opacity.combined(with: .scale(scale: 1.03)))
                    }
                }
                .animation(.easeInOut(duration: 0.4), value: model.phase)
                // Deep-link from a tapped notification. Only auto-starts the
                // daily from the menu (a tap mid-game shouldn't abandon a run),
                // and only if today's puzzle isn't already done.
                .onChange(of: notifications.pendingRoute) { _, route in
                    guard route != nil else { return }
                    if model.phase == .menu, !model.dailyManager.hasCompletedToday {
                        model.startDailyChallenge()
                    }
                    notifications.pendingRoute = nil
                }
                // Progression celebrations (R3): a level-up or goal completion
                // raises a transient banner. Goal-completion fires first so a
                // goal whose XP triggers a level-up shows both in sequence.
                .onChange(of: goals.justCompleted) { _, g in
                    guard let g else { return }
                    showCelebration(CelebrationItem(icon: "checkmark.seal.fill", tint: .lexisGold,
                        title: "Goal complete!", subtitle: "\(g.title)  ·  +\(g.xpReward) XP"))
                    goals.justCompleted = nil
                }
                .onChange(of: profile.pendingLevelUp) { _, lvl in
                    guard let lvl else { return }
                    showCelebration(CelebrationItem(icon: "arrow.up.circle.fill", tint: .lexisAccent,
                        title: "Level \(lvl)!", subtitle: "You leveled up"))
                    profile.pendingLevelUp = nil
                }

                // Celebration banner overlay
                if let c = celebration {
                    VStack {
                        CelebrationToast(icon: c.icon, tint: c.tint, title: c.title, subtitle: c.subtitle)
                            .padding(.top, 8)
                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .allowsHitTesting(false)
                    .zIndex(10)
                }

                // Danger-zone vignette — escalates with dangerSeverity
                // (fraction of columns crowding the danger zone) rather than
                // the single static "you're in danger" banner this used to
                // be alone. One column brushing the top should barely
                // register; every column crowding it should feel urgent.
                if (model.phase == .playing || model.phase == .paused) && model.dangerZoneActive {
                    RadialGradient(
                        colors: [Color.clear, Color.lexisDanger.opacity(0.05 + 0.25 * model.dangerSeverity * (dangerVignettePulse ? 1 : 0.5))],
                        center: .center,
                        startRadius: geo.size.width * 0.35,
                        endRadius: geo.size.width * 0.9
                    )
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
                    .onAppear {
                        // Reduce Motion: hold a steady danger tint (still
                        // clearly readable as danger) instead of pulsing.
                        guard !settings.motionReduced else { return }
                        withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                            dangerVignettePulse = true
                        }
                    }
                    .onDisappear { dangerVignettePulse = false }
                }

                // High-combo edge glow — from a x4 chain up, the screen edges
                // ring in the combo color (gold, then hot red past x5),
                // deepening with the count, so a big chain is felt at the
                // periphery, not just read in the header.
                if (model.phase == .playing || model.phase == .paused) && model.comboCount >= 4 {
                    let hot = model.comboCount >= 5
                    RadialGradient(
                        colors: [Color.clear, (hot ? Color.lexisDanger : Color.lexisGold)
                            .opacity(min(0.34, 0.12 + Double(model.comboCount - 4) * 0.05))],
                        center: .center,
                        startRadius: geo.size.width * 0.45,
                        endRadius: geo.size.width * 0.95
                    )
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .animation(.easeOut(duration: 0.25), value: model.comboCount)
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView { _ in
                    // If mid-game, the new speed/rules apply from next spawn onward
                }
            }
            .sheet(isPresented: $showDifficultySelect) {
                DifficultySelectSheet { _ in
                    model.startGame()
                }
            }
        }
    }

    // Raises the celebration banner and auto-dismisses it. A fresh item
    // replaces any showing one, so back-to-back completions don't stack.
    private func showCelebration(_ item: CelebrationItem) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            celebration = item
        }
        let shown = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            if celebration == shown {
                withAnimation(.easeOut(duration: 0.3)) { celebration = nil }
            }
        }
    }

    // Tile size was previously derived from screen WIDTH alone, which on a
    // 14-row board silently overflowed the screen HEIGHT on every device —
    // pushing the header off the top and the controls panel off the bottom
    // (never caught before because this project had no buildable Xcode
    // target to actually run it in). Constraining by both dimensions keeps
    // the whole PlayingView layout on-screen everywhere.
    private func tileSize(for size: CGSize) -> CGFloat {
        let widthBased = (size.width - 2 * boardHorizontalPadding) / CGFloat(GameConstants.cols) - 2
        // Budget for the non-board chrome: header, recent-words strip, and
        // the (usually empty) power-up panel. Tuned so a 14-row board fills
        // the width edge to edge (tile size limited by width, not height)
        // on a typical phone. If you change GameConstants.rows/cols or add
        // substantial new permanent UI chrome, revisit this constant.
        let reservedChromeHeight: CGFloat = 170
        let heightBased = (size.height - reservedChromeHeight) / CGFloat(GameConstants.rows) - 2
        return min(widthBased, heightBased)
    }
}

// MARK: - Playing View
struct PlayingView: View {
    @ObservedObject var model: GameModel
    let tileSize: CGFloat
    @Binding var showWildcardPicker: Bool
    @Binding var selectedTiles: [(row: Int, col: Int)]
    @Binding var wordFlashText: String
    @Binding var wordFlashOpacity: Double
    @Binding var wordFlashColor: Color
    @Binding var showSettings: Bool
    
    @State private var boardOffset: CGFloat = 0
    @State private var wordBurst: Bool = false
    // The "+N" that floats up with the word flash on a clear, and whether it's
    // mid-rise, so the whole word+score group drifts upward as it fades.
    @State private var wordFlashScore: Int = 0
    @State private var wordFlashRise: Bool = false
    @State private var previewedWords: [WordResult] = []
    @State private var previewDismissTask: DispatchWorkItem?
    // How much horizontal drag has already been "spent" moving the piece
    // this gesture — lets a continuous slide across the board step the piece
    // column by column as the finger travels, then resets on release.
    @State private var boardDragAccum: CGFloat = 0
    // Short-lived shard bursts, one per tile of a just-cleared word, so a
    // clear reads as the tiles bursting apart rather than blinking out.
    @State private var shardBursts: [ClearShardBurst] = []
    @FocusState private var boardFocused: Bool

    // Combo crescendo: the chain gets louder as it climbs — warmer color and
    // a larger label — so higher combos feel meaningfully hotter, not just a
    // bigger number.
    private var comboColor: Color {
        switch model.comboCount {
        case ..<3: return .lexisCombo   // orange
        case 3..<5: return .lexisGold   // gold
        default: return .lexisDanger    // hot red at 5+
        }
    }
    private var comboFontSize: CGFloat {
        min(20, 11 + CGFloat(max(0, model.comboCount - 1)) * 1.5)
    }

    // Every board position covered by the currently-previewed word(s), for
    // the bright-orange tile highlight. A Set of "row,col" strings rather
    // than tuples since tuples aren't Hashable.
    private var previewedPositions: Set<String> {
        Set(previewedWords.flatMap { $0.tiles.map { "\($0.row),\($0.col)" } })
    }

    // Single-tapping a glowing tile shows what word(s) it's part of and
    // what tapping double would score, without pausing or otherwise
    // interrupting play. Re-tapping (or any change to the board's pending
    // words) resets the auto-dismiss clock / clears a now-stale preview.
    private func showWordPreview(row: Int, col: Int) {
        let matches = model.pendingWords(at: row, col: col)
        guard !matches.isEmpty else { return }
        presentPreview(matches)
    }

    // Tapping the "N FOUND" pill previews every currently-pending word at
    // once — handy specifically for the overlap case (two words sharing a
    // tile), where a single tile tap only ever shows the word(s) touching
    // that one cell.
    private func showAllPendingPreview() {
        guard !model.pendingWords.isEmpty else { return }
        presentPreview(model.pendingWords)
    }

    private func presentPreview(_ words: [WordResult]) {
        previewDismissTask?.cancel()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            previewedWords = words
        }
        let task = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.25)) { previewedWords = [] }
        }
        previewDismissTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: task)
    }

    var body: some View {
        ZStack {
        VStack(spacing: 0) {
            headerBar
            statusBanner
            boardArea
            // The flexible gap lives here, not above the board — it packs
            // the header/board together at the top and pushes the recent-
            // words strip + controls panel down to the bottom edge, instead
            // of leaving them stranded with dead space underneath.
            Spacer(minLength: 4)
            recentWordsStrip
            controlsPanel
        }
        // Hardware-keyboard support (Simulator's Connect Hardware Keyboard,
        // or a real iPad with a keyboard case) — mirrors the touch controls
        // exactly rather than adding new capability: left/right match the
        // drag-to-move columns, down matches the drag-down soft drop (held
        // vs released via key phase, same as the drag gesture's onEnded),
        // and up matches double-tap's hard drop.
        .focusable()
        .focused($boardFocused)
        .onAppear { boardFocused = true }
        .onKeyPress(phases: .down) { press in
            switch press.key {
            case .leftArrow:
                model.moveLeft()
                return .handled
            case .rightArrow:
                model.moveRight()
                return .handled
            case .upArrow:
                model.dropFast()
                return .handled
            case .downArrow:
                model.beginSoftDrop()
                return .handled
            default:
                return .ignored
            }
        }
        .onKeyPress(phases: .up) { press in
            guard press.key == .downArrow else { return .ignored }
            model.endSoftDrop()
            return .handled
        }
        .onChange(of: model.lastWordResult) { _, result in
            if let result = result {
                triggerWordFlash(result)
                spawnShatter(for: result)
            }
        }
        .onChange(of: model.pendingWords) { _, newWords in
            // markGlowingWords() rescans and reassigns fresh WordResult IDs
            // on every single tile placement, even when the word being
            // previewed is still sitting there completely untouched — so
            // comparing pendingWords by identity/equality would dismiss the
            // preview within about a second of showing it, almost every
            // time, since a new tile locks in that often during normal
            // play. Match by tile position instead: if the exact same
            // tiles are still glowing, keep showing it (refreshed to the
            // current WordResult) and let the original auto-dismiss timer
            // run its course; only clear immediately if those tiles
            // genuinely aren't part of any pending word anymore.
            guard !previewedWords.isEmpty else { return }
            let previewedKeys = Set(previewedWords.map { word in
                word.tiles.map { "\($0.row),\($0.col)" }.sorted().joined()
            })
            let stillPending = newWords.filter { word in
                previewedKeys.contains(word.tiles.map { "\($0.row),\($0.col)" }.sorted().joined())
            }
            if stillPending.isEmpty {
                previewDismissTask?.cancel()
                previewedWords = []
            } else {
                previewedWords = stillPending
            }
        }
        .onChange(of: model.isWildcard) { _, wild in
            if wild {
                // Fresh wildcard spawn — start collapsed so
                // FloatingWildcardBadge's onAppear auto-expand plays again.
                showWildcardPicker = false
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: model.comboCount)
        .animation(.easeInOut(duration: 0.2), value: model.dangerZoneActive)
        .animation(.easeInOut(duration: 0.2), value: model.pendingWords.count)
        .animation(.easeInOut(duration: 0.2), value: model.tipsAvailable)
        .animation(.easeInOut(duration: 0.2), value: model.utilityCharges)
        .animation(.easeInOut(duration: 0.2), value: model.isFrozen)
        .animation(.easeInOut(duration: 0.2), value: model.peekLetters)

            // Previously, pausing just froze the board mid-animation and
            // swapped the pause icon for a play icon — nothing told the
            // player the app had actually registered the pause. A dimmed
            // overlay with an explicit choice reads as intentional instead
            // of the game just stopping.
            if model.phase == .paused {
                Color.black.opacity(0.75)
                    .ignoresSafeArea()
                    .transition(.opacity)

                VStack(spacing: 20) {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.lexisAccent)
                    Text("PAUSED")
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundColor(.lexisText)
                        .tracking(3)

                    VStack(spacing: 12) {
                        Button {
                            model.resumeGame()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "play.fill")
                                Text("RESUME")
                                    .tracking(2)
                            }
                            .font(.system(size: 16, weight: .black, design: .rounded))
                            .foregroundColor(Color.lexisBg)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color.lexisAccent))
                        }

                        Button {
                            withAnimation(.spring()) { model.phase = .menu }
                        } label: {
                            Text("MAIN MENU")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(.lexisMid)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(RoundedRectangle(cornerRadius: 14).fill(Color.lexisBlock))
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 8)
                }
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }

            // First-run tutorial tooltip. The opening letters are scripted
            // (see GameModel.startGame()) to guarantee an easy word glows
            // almost immediately, so this only ever has to explain two
            // things: that tapping steers the piece, and that a glowing
            // tile needs a double-tap. It disappears for good the moment
            // that first word is cleared.
            if model.isTutorialActive {
                VStack {
                    HStack(spacing: 10) {
                        Image(systemName: "hand.tap.fill")
                            .font(.system(size: 16, weight: .bold))
                        Text(model.tutorialStep == 0 ?
                             "TAP LEFT OR RIGHT TO STEER — OR JUST LET IT FALL" :
                             "IT'S GLOWING! DOUBLE-TAP IT TO CLEAR")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundColor(.lexisBg)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.lexisAccent))
                    .shadow(color: Color.lexisAccent.opacity(0.4), radius: 12)
                    .padding(.horizontal, 20)
                    .padding(.top, 64)
                    .allowsHitTesting(false)

                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: model.phase)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: model.tutorialStep)
        .animation(.easeOut(duration: 0.3), value: model.isTutorialActive)
    }

    @ViewBuilder
    private var headerBar: some View {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("LEXIS")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundColor(.lexisAccent)
                            .tracking(6)
                        Image(systemName: model.isDuelMode ? "person.2.fill" : (model.isDailyMode ? "calendar" : model.settings.difficulty.icon))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor((model.isDailyMode || model.isDuelMode) ? .lexisGold : .lexisMid)
                    }
                    if model.isDuelMode {
                        Text("DUEL \(model.duelCode) · \(model.dailyLettersRemaining) LEFT")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.lexisGold)
                    } else if model.isDailyMode {
                        Text("\(model.dailyLettersRemaining) LETTERS LEFT")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.lexisGold)
                    } else {
                        Text("LVL \(model.level) · \(model.settings.difficulty.rawValue.uppercased())")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.lexisMid)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .center, spacing: 2) {
                    Text("\(model.score)")
                        .font(.system(size: 28, weight: .black, design: .monospaced))
                        .foregroundColor(.lexisText)
                        .contentTransition(.numericText())

                    if model.comboCount > 1 {
                        // Escalates with the chain: bigger, and shifting
                        // orange → gold → hot red as it climbs, with a fresh
                        // scale-pop on every increment (via .id) so a ×6
                        // reads unmistakably hotter than a ×2.
                        Text("×\(model.comboCount) COMBO!")
                            .font(.system(size: comboFontSize, weight: .black, design: .rounded))
                            .foregroundColor(comboColor)
                            .shadow(color: comboColor.opacity(0.8), radius: model.comboCount >= 4 ? 10 : 0)
                            .id(model.comboCount)
                            .transition(.scale(scale: 1.4).combined(with: .opacity))
                    }

                    Text("HI \(model.highScore)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.lexisGold)
                }

                Spacer()

                HStack(spacing: 8) {
                    // NEXT letter preview, relocated here from the controls
                    // panel so the bottom of the screen isn't permanently
                    // spending space on it — the panel now only appears when
                    // there's an actual power-up to show. This shows the
                    // UPCOMING piece (a real lookahead), not the one
                    // currently falling — that's already visible on the
                    // board, so showing it twice told the player nothing new.
                    FallingLetterPreview(
                        letter: model.upcomingLetter,
                        isWildcard: model.upcomingIsWildcard,
                        isBomb: model.upcomingIsBomb,
                        isDynamite: model.upcomingIsDynamite,
                        size: 36
                    )

                    // A used Peek charge temporarily reveals the 2 letters
                    // after upcomingLetter — small and dimmer, since they're
                    // further off and less certain to matter than what's
                    // falling right now.
                    if !model.peekLetters.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(Array(model.peekLetters.enumerated()), id: \.offset) { _, letter in
                                Text(String(letter))
                                    .font(.system(size: 14, weight: .black, design: .rounded))
                                    .foregroundColor(.lexisAccent.opacity(0.7))
                                    .frame(width: 22, height: 22)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color.lexisAccent.opacity(0.12))
                                    )
                            }
                        }
                        .transition(.scale.combined(with: .opacity))
                    }

                    Button {
                        model.pauseGame()
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.lexisText)
                            .frame(width: 40, height: 40)
                            .background(Color.lexisBlock.opacity(0.8))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    
                    Button {
                        if model.phase == .playing {
                            model.pauseGame()
                        } else {
                            model.resumeGame()
                        }
                    } label: {
                        Image(systemName: model.phase == .paused ? "play.fill" : "pause.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.lexisText)
                            .frame(width: 40, height: 40)
                            .background(Color.lexisBlock.opacity(0.8))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
    }

    @ViewBuilder
    private var statusBanner: some View {
            // Danger indicator. The "N words found" pill used to live here
            // too, but that's board-status info that belongs with the rest
            // of the word bookkeeping at the bottom — see recentWordsStrip.
            if model.dangerZoneActive {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.lexisDanger)
                    Text("DANGER ZONE")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundColor(.lexisDanger)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.lexisDanger)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 12)
                .background(Color.lexisDanger.opacity(0.15))
                .clipShape(Capsule())
                .padding(.top, 4)
                .transition(.opacity.combined(with: .scale))
            }

            if model.isFrozen {
                HStack {
                    Image(systemName: "snowflake")
                    Text("FROZEN — TAKE YOUR TIME")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                    Image(systemName: "snowflake")
                }
                .foregroundColor(.lexisAccent)
                .padding(.vertical, 4)
                .padding(.horizontal, 12)
                .background(Color.lexisAccent.opacity(0.15))
                .clipShape(Capsule())
                .padding(.top, 4)
                .transition(.opacity.combined(with: .scale))
            }
    }

    private var boardArea: some View {
            // Game Board
            ZStack {
                // Falling letter indicator column — brightens and gains a
                // motion-streak look while soft-dropping, as a clear "you're
                // going fast now" cue.
                HStack(spacing: 2) {
                    ForEach(0..<GameConstants.cols, id: \.self) { col in
                        Rectangle()
                            .fill(col == model.fallingCol ?
                                  Color.lexisAccent.opacity(model.isSoftDropping ? 0.22 : 0.08) :
                                  Color.clear)
                            .frame(width: tileSize)
                    }
                }
                .frame(height: CGFloat(GameConstants.rows) * (tileSize + 2))
                .allowsHitTesting(false)
                .animation(.easeOut(duration: 0.15), value: model.isSoftDropping)
                
                // Grid tiles
                VStack(spacing: 2) {
                    ForEach(0..<GameConstants.rows, id: \.self) { row in
                        HStack(spacing: 2) {
                            ForEach(0..<GameConstants.cols, id: \.self) { col in
                                tileCell(row: row, col: col)
                            }
                        }
                    }
                }
                .offset(x: boardOffset)
                .onChange(of: model.shakeBoard) { _, shaking in
                    if shaking {
                        withAnimation(.default.repeatCount(3, autoreverses: true)) {
                            boardOffset = 8
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            boardOffset = 0
                        }
                    }
                }
                // Slide steering + soft-drop, layered on top of the tap
                // controls. A horizontal drag flings the piece across
                // columns fast (tracking the finger, ~0.6 tile per column);
                // a downward drag soft-drops at a speed that follows the
                // drag velocity. minimumDistance 16 is high enough that the
                // small jitter between a double-tap's two taps never trips
                // the drag, so tap-to-move and double-tap stay reliable.
                .contentShape(Rectangle())
                .simultaneousGesture(
                    DragGesture(minimumDistance: 16)
                        .onChanged { value in
                            if abs(value.translation.width) > abs(value.translation.height) {
                                if model.isSoftDropping { model.endSoftDrop() }
                                let step = (tileSize + 2) * 0.6
                                let delta = value.translation.width - boardDragAccum
                                if delta >= step {
                                    boardDragAccum += step
                                    model.moveRight()
                                } else if delta <= -step {
                                    boardDragAccum -= step
                                    model.moveLeft()
                                }
                            } else if value.translation.height > 16 {
                                if !model.isSoftDropping { model.beginSoftDrop() }
                                model.updateSoftDropSpeed(velocity: value.velocity.height)
                            }
                        }
                        .onEnded { _ in
                            boardDragAccum = 0
                            model.endSoftDrop()
                        }
                )

                // The falling piece, as a free-floating overlay that GLIDES
                // between cells instead of hard-stepping. It descends over
                // currentDropInterval (so it moves continuously at fall
                // speed; soft-drop shortens the interval → it speeds up), and
                // .id(fallingPieceID) gives each new piece a fresh identity
                // so a spawn appears at the top rather than sliding up from
                // the previous piece's landing spot. Same cell-center math as
                // the shard/indicator overlays, so it lines up with the grid.
                if model.phase == .playing || model.phase == .paused {
                    let step = tileSize + 2
                    ZStack(alignment: .topLeading) {
                        TileView(
                            tile: nil,
                            isFallingPos: true,
                            fallingLetter: model.fallingLetter,
                            isWildcard: model.isWildcard,
                            isBomb: model.isBomb,
                            isDynamite: model.isDynamite,
                            isStuckPos: model.isStuck,
                            isGhostPos: false,
                            isDangerRow: model.fallingRow < GameConstants.dangerRow,
                            colorBlindMode: model.settings.colorBlindMode,
                            largeText: model.settings.largeText,
                            tileSize: tileSize
                        )
                        .position(
                            x: CGFloat(model.fallingCol) * step + tileSize / 2,
                            y: CGFloat(model.fallingRow) * step + tileSize / 2
                        )
                        // Reduce Motion: no glide — the piece snaps cleanly
                        // from cell to cell (the pre-glide behavior) rather
                        // than continuously sliding.
                        .animation(model.settings.motionReduced ? nil : .linear(duration: max(0.05, model.currentDropInterval)), value: model.fallingRow)
                        .animation(model.settings.motionReduced ? nil : .easeOut(duration: 0.08), value: model.fallingCol)
                        .id(model.fallingPieceID)
                    }
                    .frame(
                        width: CGFloat(GameConstants.cols) * tileSize + CGFloat(GameConstants.cols - 1) * 2,
                        height: CGFloat(GameConstants.rows) * (tileSize + 2),
                        alignment: .topLeading
                    )
                    .allowsHitTesting(false)
                }

                // Bomb explosion burst — pinned to the detonation column via
                // the same HStack-of-columns layout as the falling-column
                // indicator, so it lines up exactly with the grid. Keyed by
                // the blast id so it replays for every detonation.
                if let blast = model.bombBlast {
                    HStack(spacing: 2) {
                        ForEach(0..<GameConstants.cols, id: \.self) { col in
                            ZStack {
                                if col == blast.col {
                                    BombExplosionView(tileSize: tileSize)
                                }
                            }
                            .frame(width: tileSize)
                        }
                    }
                    .frame(height: CGFloat(GameConstants.rows) * (tileSize + 2))
                    .allowsHitTesting(false)
                    .id(blast.id)
                }

                // Tile-shatter bursts — one per cleared tile, positioned at
                // that tile's cell center (same step as the grid) so the
                // shards fly out of exactly where the letters were.
                if !shardBursts.isEmpty {
                    ZStack(alignment: .topLeading) {
                        ForEach(shardBursts) { burst in
                            ClearShardView(tileSize: tileSize, color: burst.color)
                                .position(
                                    x: CGFloat(burst.col) * (tileSize + 2) + tileSize / 2,
                                    y: CGFloat(burst.row) * (tileSize + 2) + tileSize / 2
                                )
                        }
                    }
                    .frame(
                        width: CGFloat(GameConstants.cols) * tileSize + CGFloat(GameConstants.cols - 1) * 2,
                        height: CGFloat(GameConstants.rows) * (tileSize + 2),
                        alignment: .topLeading
                    )
                    .allowsHitTesting(false)
                }

                // Floating wildcard picker — a vertical panel pinned to the
                // board's trailing edge rather than a corner badge, so its
                // candidates have more room to be tapped accurately. This
                // must be layered AFTER the grid tiles VStack above: it used
                // to be layered before them, which put the tile grid's own
                // tap/drag gesture on top in z-order and silently ate taps
                // meant for the wildcard candidates.
                if model.isWildcard {
                    HStack {
                        Spacer()
                        FloatingWildcardBadge(
                            candidates: model.wildcardCandidates(),
                            isExpanded: $showWildcardPicker
                        ) { letter in
                            model.selectWildcardLetter(letter)
                            showWildcardPicker = false
                        }
                    }
                    .padding(.trailing, 8)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }

                // Word-info preview — a single tap on a glowing tile shows
                // what it's about to score without touching game state at
                // all: no pause, no sheet, allowsHitTesting(false) so it
                // never steals a touch from the board underneath. Purely a
                // "here's what double-tapping this would do" readout.
                if !previewedWords.isEmpty {
                    HStack {
                        Spacer()
                        WordPreviewPanel(words: previewedWords)
                    }
                    .padding(.trailing, 8)
                    .allowsHitTesting(false)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }

                // Word flash overlay — the cleared word pops in at board
                // center with its "+score" beneath, then the whole group
                // drifts upward as it fades, so every clear reads as points
                // lifting off the board rather than a static label blinking.
                if wordFlashOpacity > 0 {
                    VStack(spacing: 2) {
                        Text(wordFlashText)
                            .font(.system(size: 34, weight: .black, design: .rounded))
                            .foregroundColor(wordFlashColor)
                            .shadow(color: wordFlashColor.opacity(0.85), radius: 14)
                        Text("+\(wordFlashScore)")
                            .font(.system(size: 21, weight: .black, design: .monospaced))
                            .foregroundColor(.lexisGold)
                            .shadow(color: Color.lexisGold.opacity(0.7), radius: 8)
                    }
                    .opacity(wordFlashOpacity)
                    .scaleEffect(wordBurst ? 1.12 : 1.0)
                    .offset(y: wordFlashRise ? -72 : 0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.5), value: wordBurst)
                    .allowsHitTesting(false)
                }

                // Perfect Clear celebration — a clear that happened to empty
                // the entire board is rare and worth a distinct, bigger
                // flourish than a normal word flash, not the same treatment
                // as every other clear.
                if model.perfectClear {
                    VStack(spacing: 6) {
                        Text("PERFECT CLEAR!")
                            .font(.system(size: 30, weight: .black, design: .rounded))
                            .tracking(1)
                        Text("+\(model.perfectClearBonus)")
                            .font(.system(size: 20, weight: .black, design: .monospaced))
                    }
                    .foregroundColor(.lexisGold)
                    .shadow(color: Color.lexisGold.opacity(0.9), radius: 18)
                    .allowsHitTesting(false)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, boardHorizontalPadding)
            .animation(.spring(response: 0.35, dampingFraction: 0.6), value: model.perfectClear)
    }

    private var recentWordsStrip: some View {
            // Recent words strip — leads with the "N found, awaiting a
            // double-tap" pill (moved down from the top status banner) so
            // all the word bookkeeping lives in one place: what's currently
            // glowing, followed by what's already been banked.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if !model.pendingWords.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .foregroundColor(.yellow)
                            Text(model.pendingWords.count == 1 ? model.pendingWords[0].word.uppercased() : "\(model.pendingWords.count) FOUND")
                                .font(.system(size: 12, weight: .black, design: .rounded))
                                .foregroundColor(.yellow)
                                .lineLimit(1)
                        }
                        .padding(.vertical, 5)
                        .padding(.horizontal, 10)
                        .background(Color.yellow.opacity(0.15))
                        .clipShape(Capsule())
                        .transition(.scale.combined(with: .opacity))
                        // Tapping the pill previews every pending word at
                        // once (word, letters, score) — same non-blocking
                        // overlay a tile tap shows, but covering the whole
                        // set rather than just whatever one tile touches.
                        .onTapGesture {
                            showAllPendingPreview()
                        }
                    }
                    ForEach(model.foundWords.prefix(8)) { word in
                        WordChip(result: word)
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(height: 36)
            .padding(.vertical, 6)
    }

    @ViewBuilder
    private var controlsPanel: some View {
            // Controls — the NEXT-letter preview and the drag/double-tap
            // gesture hint used to live here permanently; the preview moved
            // to the header and the hint moved to Settings > How to Play,
            // so this panel now only occupies space when a power-up is
            // actually available.
            VStack(spacing: 10) {
                // Banked "clear path" bombs — earned by spelling 5+ letter words.
                // Lets a struggling player wipe their current column on demand.
                if model.bombsAvailable > 0 {
                    Button {
                        model.triggerBankedBomb()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "burst.fill")
                                .font(.system(size: 14, weight: .bold))
                            Text("CLEAR PATH ×\(model.bombsAvailable)")
                                .font(.system(size: 13, weight: .black, design: .rounded))
                                .tracking(1)
                        }
                        .foregroundColor(.lexisDanger)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.lexisDanger.opacity(0.12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(Color.lexisDanger.opacity(0.4), lineWidth: 1.5)
                                )
                        )
                    }
                    .padding(.horizontal, 16)
                    .scaleEffect(model.justUsedBomb ? 1.05 : 1)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                // Banked Tip charges — earned from chained combos. Using a
                // Tip is a single swipe directly on a violet-ringed top tile
                // (see knockGesture in PlayingView), so this is just an
                // informational reminder that the charge exists, not a
                // trigger itself.
                if model.tipsAvailable > 0 {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 13, weight: .bold))
                        Text("TIP ×\(model.tipsAvailable) — SWIPE A GLOWING TOP TILE SIDEWAYS")
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .tracking(0.5)
                    }
                    .foregroundColor(.purple)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.purple.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(Color.purple.opacity(0.35), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 16)
                    .transition(.opacity)
                }

                // Hint — only offered when the board looks dead (nothing
                // currently glowing) and there's a Tip charge to spend on
                // acting on the suggestion; see requestHint() for why a
                // hint that just re-showed an already-glowing word would be
                // pointless.
                if model.pendingWords.isEmpty && model.tipsAvailable > 0 && model.hintTargetCol == nil {
                    Button {
                        model.requestHint()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "lightbulb.fill")
                                .font(.system(size: 13, weight: .bold))
                            Text("HINT")
                                .font(.system(size: 12, weight: .black, design: .rounded))
                                .tracking(1)
                        }
                        .foregroundColor(.cyan)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.cyan.opacity(0.1))
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.cyan.opacity(0.35), lineWidth: 1))
                        )
                    }
                    .padding(.horizontal, 16)
                    .transition(.opacity)
                }

                if let direction = model.hintDirection {
                    HStack(spacing: 6) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text("SWIPE THE HIGHLIGHTED TILE \(direction == .left ? "LEFT" : "RIGHT")")
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .tracking(0.5)
                    }
                    .foregroundColor(.cyan)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.cyan.opacity(0.1))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.cyan.opacity(0.35), lineWidth: 1))
                    )
                    .padding(.horizontal, 16)
                    .transition(.opacity)
                }

                // Utility charges — a third currency (alongside bomb's
                // vocabulary reward and Tip's tempo reward) earned simply by
                // leveling up, spendable on whichever of three small
                // conveniences actually matters right now rather than three
                // separate meters.
                if model.utilityCharges > 0 {
                    Text("×\(model.utilityCharges) CHARGE\(model.utilityCharges == 1 ? "" : "S") — SPEND ON ANY ONE BELOW")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.lexisMid)
                        .padding(.horizontal, 16)
                    HStack(spacing: 10) {
                        Button {
                            model.useFreeze()
                        } label: {
                            utilityButtonLabel(icon: "snowflake", text: "FREEZE")
                        }
                        .disabled(model.isFrozen)
                        .opacity(model.isFrozen ? 0.4 : 1)

                        Button {
                            model.useReroll()
                        } label: {
                            utilityButtonLabel(icon: "arrow.triangle.2.circlepath", text: "REROLL")
                        }
                        .disabled(model.isWildcard || model.isBomb || model.isDynamite)
                        .opacity((model.isWildcard || model.isBomb || model.isDynamite) ? 0.4 : 1)

                        Button {
                            model.usePeek()
                        } label: {
                            utilityButtonLabel(icon: "eye.fill", text: "PEEK")
                        }
                        .disabled(!model.peekLetters.isEmpty)
                        .opacity(model.peekLetters.isEmpty ? 1 : 0.4)
                    }
                    .padding(.horizontal, 16)
                    .transition(.opacity)
                }

                // Wildcard picker now floats over the board (see below)
                // rather than living inline here, so it never displaces the
                // Tip picker or control buttons.
            }
            .padding(.bottom, 8)
    }

    @ViewBuilder
    private func utilityButtonLabel(icon: String, text: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
            Text(text)
                .font(.system(size: 9, weight: .black, design: .rounded))
                .tracking(0.5)
        }
        .foregroundColor(.lexisAccent)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.lexisAccent.opacity(0.1))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.lexisAccent.opacity(0.35), lineWidth: 1))
        )
    }

    // Computes where the falling letter would land if dropped now, for the
    // ghost-piece outline.
    func ghostRow() -> Int {
        var target = model.fallingRow
        while target + 1 < GameConstants.rows && model.grid[target + 1][model.fallingCol] == nil {
            target += 1
        }
        return target
    }
    
    // The letter count of whichever pending word STARTS at this cell, for
    // a small Scrabble-style badge — lets a player see at a glance how many
    // tiles a double-tap here will actually clear. A tile can be the start
    // of more than one glowing word at once (e.g. two words sharing their
    // first letter); showing the longest is more useful than showing both.
    func wordStartLength(row: Int, col: Int) -> Int? {
        let matches = model.pendingWords.filter { $0.tiles.first?.row == row && $0.tiles.first?.col == col }
        return matches.map { $0.tiles.count }.max()
    }

    // True if this cell holds the topmost (highest, lowest row index) tile
    // in its column — the only tile eligible to be tipped sideways.
    func isTopOfColumn(row: Int, col: Int) -> Bool {
        guard model.grid[row][col] != nil else { return false }
        for r in 0..<row {
            if model.grid[r][col] != nil { return false }
        }
        return true
    }

    // One tile cell, including its gestures. The knock swipe is only
    // attached AT ALL on genuinely eligible (top-of-column) tiles — earlier
    // this attached an always-present but "inert" high-priority drag
    // gesture to every tile so it wouldn't steal touches from the board's
    // move gesture, but merely attaching a highPriorityGesture (even one
    // that never resolves) still participates in touch disambiguation and
    // was intermittently delaying/eating the double-tap-to-drop recognition
    // on ordinary tiles. Structurally omitting it on ineligible tiles avoids
    // that interference entirely.
    @ViewBuilder
    private func tileCell(row: Int, col: Int) -> some View {
        // The falling piece is NOT drawn here anymore — it's a separate
        // gliding overlay (see fallingPieceOverlay) so it can move smoothly
        // between cells. Grid cells render only settled tiles + the ghost.
        let tile = TileView(
            tile: model.grid[row][col],
            isFallingPos: false,
            fallingLetter: model.fallingLetter,
            isWildcard: model.isWildcard,
            isBomb: model.isBomb,
            isDynamite: model.isDynamite,
            isStuckPos: false,
            isGhostPos: model.settings.showGhostPiece && col == model.fallingCol && row == ghostRow(),
            isDangerRow: row < GameConstants.dangerRow,
            isTippable: model.tipsAvailable > 0 && isTopOfColumn(row: row, col: col),
            isHintSource: model.hintTargetCol == col && isTopOfColumn(row: row, col: col),
            colorBlindMode: model.settings.colorBlindMode,
            largeText: model.settings.largeText,
            tileSize: tileSize,
            wordStartLength: wordStartLength(row: row, col: col),
            isPreviewHighlighted: previewedPositions.contains("\(row),\(col)"),
            justLanded: model.lastLandedCell == GridPos(row: row, col: col)
        )
        // Tap controls, arrow-key style: a single tap on the left half of
        // the board nudges the piece one column left, the right half nudges
        // it right — mirroring the keyboard's left/right arrows. Tapping a
        // glowing tile instead previews its word; double-tapping a glowing
        // tile clears it, and a double-tap anywhere else hard-drops (like the
        // up arrow). One combined gesture rather than separate
        // .onTapGesture(count:) modifiers — independent tap-count gestures
        // race each other unreliably; .exclusively(before:) tries the
        // double-tap first and falls back to single-tap.
        .gesture(
            TapGesture(count: 2)
                .onEnded {
                    let isFalling = (row == model.fallingRow && col == model.fallingCol)
                    if !isFalling, model.grid[row][col]?.glowingWordID != nil {
                        model.doubleTapClear(row: row, col: col)
                    } else {
                        model.dropFast()
                    }
                }
                .exclusively(before: TapGesture(count: 1)
                    .onEnded {
                        if model.grid[row][col]?.glowingWordID != nil {
                            showWordPreview(row: row, col: col)
                        } else if col < GameConstants.cols / 2 {
                            model.moveLeft()
                        } else {
                            model.moveRight()
                        }
                    }
                )
        )

        if isTopOfColumn(row: row, col: col) {
            // Knock: swipe this tile sideways and it falls off the stack
            // that way — a single direct motion, not a tap that arms a menu.
            tile.highPriorityGesture(
                DragGesture(minimumDistance: 18)
                    .onEnded { value in
                        let dx = value.translation.width
                        guard abs(dx) > tileSize * 0.4, abs(value.translation.height) < tileSize * 0.7 else { return }
                        model.knockTile(col: col, direction: dx > 0 ? .right : .left)
                    }
            )
        } else {
            tile
        }
    }

    // Spawns one shard burst per tile of the cleared word, at that tile's
    // board position, and clears them after the animation. Additive only —
    // the model still removes the tiles on its own schedule; this just plays
    // over the top so the clear feels physical.
    func spawnShatter(for result: WordResult) {
        // Reduce Motion: skip the flung-shard burst entirely — the tiles
        // simply clear. The score readout still appears (statically) so the
        // player never loses the "what did I score" feedback.
        guard !model.settings.motionReduced else { return }
        let color: Color = result.isChain ? .lexisCombo : (result.word.count >= 6 ? .lexisGold : .yellow)
        let bursts = result.tiles.map { ClearShardBurst(row: $0.row, col: $0.col, color: color) }
        shardBursts.append(contentsOf: bursts)
        let ids = Set(bursts.map { $0.id })
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            shardBursts.removeAll { ids.contains($0.id) }
        }
    }

    func triggerWordFlash(_ result: WordResult) {
        wordFlashText = result.word.uppercased()
        wordFlashScore = result.score
        wordFlashColor = result.isChain ? .lexisCombo : (result.word.count >= 6 ? .lexisGold : .lexisAccent)
        // Snap back to the resting position instantly (no animation) before
        // this clear's drift begins, so a rapid combo doesn't visibly yank
        // the previous flash back down.
        wordFlashRise = false

        // Reduce Motion: still show the word + score (it's real feedback), but
        // as a plain fade — no pop-scale, no upward drift.
        if model.settings.motionReduced {
            wordBurst = false
            withAnimation(.easeInOut(duration: 0.2)) { wordFlashOpacity = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                withAnimation(.easeOut(duration: 0.3)) { wordFlashOpacity = 0 }
            }
            return
        }

        wordBurst = true
        withAnimation(.spring(response: 0.18, dampingFraction: 0.6)) {
            wordFlashOpacity = 1
        }
        withAnimation(.easeOut(duration: 1.0)) {
            wordFlashRise = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            withAnimation(.easeOut(duration: 0.45)) {
                wordFlashOpacity = 0
                wordBurst = false
            }
        }
    }
}

// MARK: - Tile View
struct TileView: View {
    let tile: LetterTile?
    let isFallingPos: Bool
    let fallingLetter: Character
    let isWildcard: Bool
    var isBomb: Bool = false
    var isDynamite: Bool = false
    var isStuckPos: Bool = false
    var isGhostPos: Bool = false
    let isDangerRow: Bool
    var isTippable: Bool = false
    var isHintSource: Bool = false
    var colorBlindMode: Bool = false
    var largeText: Bool = false
    let tileSize: CGFloat
    var wordStartLength: Int? = nil
    var isPreviewHighlighted: Bool = false
    var justLanded: Bool = false

    @State private var appear = false
    @State private var glowPulse = false
    @State private var hintPulse = false
    @State private var landSquash = false
    
    private var isGlowing: Bool {
        !isFallingPos && tile?.glowingWordID != nil
    }
    
    var displayLetter: String {
        if isFallingPos {
            return String(fallingLetter)
        }
        if let tile = tile {
            return String(tile.letter)
        }
        return ""
    }
    
    // MARK: - Depth & bevel styling
    // A believable "physical button" look comes from three layers working
    // together: (1) a top-to-bottom gradient fill simulating a light source
    // from above, (2) a bright highlight stroke on the top/left edge and a
    // darker shadow stroke on the bottom/right (the classic bevel trick),
    // and (3) a drop shadow beneath the whole tile. Doing this as gradients
    // and layered strokes rather than flat fills is what makes tiles read
    // as chunky, tactile game pieces instead of flat UI chips.
    
    private var baseFillTop: Color {
        if isFallingPos {
            if isBomb || isDynamite { return Color.lexisDanger.opacity(0.5) }
            return isWildcard ? Color.lexisGold.opacity(0.55) : Color.lexisAccent.opacity(0.42)
        }
        if isPreviewHighlighted { return Color.orange.opacity(glowPulse ? 0.9 : 0.65) }
        if isGlowing { return Color.yellow.opacity(glowPulse ? 0.85 : 0.55) }
        if let tile = tile {
            if tile.isWildcard { return Color.lexisGold.opacity(0.5) }
            let ageRatio = min(1.0, Double(tile.age) / 50.0)
            let theme = GameSettings.shared.tileTheme
            return theme.topColor.mix(with: theme.ageAccent.opacity(0.4), ratio: ageRatio)
        }
        if isGhostPos { return Color.lexisMid.opacity(0.08) }
        return isDangerRow ? Color.lexisDanger.opacity(0.05) : Color.clear
    }

    private var baseFillBottom: Color {
        if isFallingPos {
            if isBomb || isDynamite { return Color.lexisDanger.opacity(0.18) }
            return isWildcard ? Color.lexisGold.opacity(0.12) : Color.lexisAccent.opacity(0.08)
        }
        if isPreviewHighlighted { return Color.orange.opacity(glowPulse ? 0.4 : 0.25) }
        if isGlowing { return Color.yellow.opacity(glowPulse ? 0.35 : 0.2) }
        if let tile = tile {
            if tile.isWildcard { return Color.lexisGold.opacity(0.15) }
            let ageRatio = min(1.0, Double(tile.age) / 50.0)
            let theme = GameSettings.shared.tileTheme
            return theme.bottomColor.mix(with: theme.ageAccent.opacity(0.25), ratio: ageRatio)
        }
        if isGhostPos { return Color.lexisMid.opacity(0.02) }
        return isDangerRow ? Color.lexisDanger.opacity(0.01) : Color.clear
    }
    
    // Bright edge simulating a light catching the top-left of a raised tile
    private var highlightStrokeColor: Color {
        if isPreviewHighlighted { return Color.white.opacity(0.85) }
        if isGlowing { return Color.white.opacity(0.7) }
        if isFallingPos { return Color.white.opacity(0.5) }
        if tile != nil { return Color.white.opacity(0.22) }
        return Color.clear
    }
    
    // Dark edge simulating shadow cast on the bottom-right of a raised tile
    private var shadowStrokeColor: Color {
        if tile != nil || isFallingPos { return Color.black.opacity(0.35) }
        return Color.clear
    }
    
    var tileColor: Color { baseFillTop } // retained for any external references expecting a single fill color
    
    var borderColor: Color {
        if isFallingPos {
            if isStuckPos { return .lexisCombo } // orange ring signals "caught on the tower"
            if isBomb || isDynamite { return .lexisDanger }
            return isWildcard ? Color.lexisGold : Color.lexisAccent
        }
        if isPreviewHighlighted { return Color.orange }
        if isGlowing { return Color.yellow }
        if isHintSource { return Color.cyan.opacity(hintPulse ? 0.95 : 0.6) } // "swipe THIS one — it'll reveal a word"
        if isTippable { return Color.purple.opacity(0.6) } // ring: "swipe this sideways to knock it"
        if let tile = tile {
            return tile.isWildcard ? Color.lexisGold.opacity(0.8) : Color.lexisBlockBorder.opacity(0.5)
        }
        if isGhostPos { return Color.lexisMid.opacity(0.35) }
        return isDangerRow ? Color.lexisDanger.opacity(0.2) : Color.lexisBlockBorder.opacity(0.08)
    }

    var glowColor: Color? {
        if isPreviewHighlighted { return .orange }
        if isGlowing { return .yellow }
        if isHintSource { return .cyan }
        if isFallingPos && (isBomb || isDynamite) { return .lexisDanger }
        if isFallingPos && isWildcard { return .lexisGold }
        if isFallingPos { return .lexisAccent }
        return nil
    }
    
    var body: some View {
        ZStack {
            // Outer drop shadow — cast beneath the tile, giving it lift off
            // the board background. Settled tiles get a soft ambient
            // shadow; the falling/glowing piece gets a colored glow-shadow
            // instead, since it's already emitting light thematically.
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(tile != nil || isFallingPos ? 0.35 : 0))
                .offset(y: 2)
                .blur(radius: 3)
            
            // Base fill: a top-to-bottom gradient rather than a flat color,
            // simulating a light source above each tile.
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [baseFillTop, baseFillBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            
            // Bevel: a bright stroke biased toward the top-left (highlight,
            // as if catching light) layered under a darker stroke biased
            // toward the bottom-right (shadow, as if the far edge recedes).
            // Two offset strokes rather than one flat border is what sells
            // the "raised chunky button" read.
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(shadowStrokeColor, lineWidth: 1.5)
                .offset(x: 0.5, y: 0.5)
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(highlightStrokeColor, lineWidth: 1.5)
                .offset(x: -0.5, y: -0.5)
            
            // The primary state-color border (glow/tip/wildcard/danger etc.)
            // sits on top of the bevel strokes so state communication stays
            // crisp even with the added depth layers underneath.
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    borderColor,
                    style: StrokeStyle(
                        lineWidth: isFallingPos ? 2 : ((isGlowing || isPreviewHighlighted) ? (glowPulse ? 2.6 : 1.8) : (isGhostPos ? 1.2 : 1)),
                        dash: isGhostPos ? [4, 3] : []
                    )
                )
            
            // Subtle top inner highlight band — a small glossy sheen across
            // the upper third, reinforcing the "physical, lit from above"
            // feel without being a distracting glare.
            if tile != nil || isFallingPos {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.12), Color.white.opacity(0)],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
                    .padding(2)
            }
            
            if isFallingPos && isBomb {
                Image(systemName: "burst.fill")
                    .font(.system(size: tileSize * 0.4, weight: .black))
                    .foregroundColor(.lexisDanger)
                    .shadow(color: .lexisDanger.opacity(0.7), radius: 6)
            } else if !displayLetter.isEmpty {
                Text(displayLetter)
                    .font(.system(size: tileSize * (largeText ? 0.6 : 0.52), weight: .black, design: .rounded))
                    .foregroundColor(isFallingPos ?
                        (isWildcard ? .lexisGold : .lexisAccent) :
                        (isPreviewHighlighted ? .white : (isGlowing ? .yellow : (tile?.isWildcard == true ? .lexisGold : .lexisText))))
                    .shadow(color: .black.opacity(0.4), radius: 0.5, y: 1) // tiny drop shadow on the letter itself, for print-like crispness
                    .shadow(color: glowColor?.opacity((isGlowing || isPreviewHighlighted) ? 0.9 : 0.6) ?? .clear, radius: (isGlowing || isPreviewHighlighted) ? 10 : 6)
                    .scaleEffect(appear ? ((isGlowing || isPreviewHighlighted) && glowPulse ? 1.08 : 1) : 0.3)
                    .opacity(appear ? 1 : 0)
                    .minimumScaleFactor(0.6)
            }
            
            // Color-blind mode: overlay a shape marker so wildcard/bomb/standard
            // tiles are distinguishable without relying on color alone.
            if colorBlindMode, let tile = tile, !isFallingPos {
                VStack {
                    HStack {
                        Spacer()
                        if tile.isWildcard {
                            Image(systemName: "star.fill")
                                .font(.system(size: tileSize * 0.18))
                                .foregroundColor(.lexisGold)
                                .padding(3)
                        }
                    }
                    Spacer()
                }
            }

            // Scrabble-style letter-count badge on the tile where a glowing
            // word starts — a quick "double-tapping here clears N tiles"
            // read. Top-left, opposite the color-blind marker's top-right
            // corner so the two never collide.
            if isGlowing, let count = wordStartLength {
                VStack {
                    HStack {
                        Text("\(count)")
                            .font(.system(size: tileSize * 0.24, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.6), radius: 1, y: 0.5)
                            .padding(5)
                        Spacer()
                    }
                    Spacer()
                }
            }
        }
        .frame(width: tileSize, height: tileSize)
        // Impact squash — the freshly-dropped tile compresses on landing and
        // springs back to full height, so a placement lands with weight
        // instead of just appearing. Anchored to the bottom so it squashes
        // "onto" the surface below it.
        .scaleEffect(x: landSquash ? 1.12 : 1.0, y: landSquash ? 0.78 : 1.0, anchor: .bottom)
        .onAppear {
            if tile != nil {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                    appear = true
                }
            } else {
                appear = true
            }
            if isGlowing { startGlowPulse() }
            if isHintSource { startHintPulse() }
        }
        .onChange(of: justLanded) { _, landed in
            guard landed else { return }
            // Reduce Motion: skip the squash-and-settle bounce; the tile just
            // appears in place.
            guard !GameSettings.shared.motionReduced else { return }
            landSquash = true
            withAnimation(.spring(response: 0.34, dampingFraction: 0.45)) {
                landSquash = false
            }
        }
        .onChange(of: isGlowing) { _, glowing in
            if glowing {
                startGlowPulse()
            } else {
                glowPulse = false
            }
        }
        .onChange(of: isHintSource) { _, hinting in
            if hinting {
                startHintPulse()
            } else {
                hintPulse = false
            }
        }
    }

    private func startGlowPulse() {
        withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
            glowPulse = true
        }
    }

    private func startHintPulse() {
        withAnimation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true)) {
            hintPulse = true
        }
    }
}

// MARK: - Falling Letter Preview
struct FallingLetterPreview: View {
    let letter: Character
    let isWildcard: Bool
    var isBomb: Bool = false
    var isDynamite: Bool = false
    var size: CGFloat = 52

    @State private var pulse = false

    private var accentColor: Color {
        if isBomb || isDynamite { return .lexisDanger }
        return isWildcard ? .lexisGold : .lexisAccent
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.19)
                .fill(accentColor.opacity((isBomb || isDynamite) ? 0.22 : (isWildcard ? 0.2 : 0.15)))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.19)
                        .strokeBorder(accentColor, lineWidth: 2)
                )
                .frame(width: size, height: size)
                .scaleEffect(pulse ? 1.05 : 1)

            if isBomb {
                Image(systemName: "burst.fill")
                    .font(.system(size: size * 0.46, weight: .black))
                    .foregroundColor(.lexisDanger)
                    .shadow(color: Color.lexisDanger.opacity(0.6), radius: 8)
            } else {
                Text(String(letter))
                    .font(.system(size: size * 0.54, weight: .black, design: .rounded))
                    .foregroundColor(accentColor)
                    .shadow(color: accentColor.opacity(0.5), radius: 8)
            }
        }
        .onAppear { updatePulse() }
        .onChange(of: isWildcard) { _, _ in updatePulse() }
        .onChange(of: isBomb) { _, _ in updatePulse() }
        .onChange(of: isDynamite) { _, _ in updatePulse() }
    }

    private func updatePulse() {
        if isWildcard || isBomb || isDynamite {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                pulse = true
            }
        } else {
            pulse = false
        }
    }
}

// MARK: - Control Button
struct ControlButton: View {
    let icon: String
    let color: Color
    let action: () -> Void
    
    @State private var pressed = false
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.1)) { pressed = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation { pressed = false }
            }
            action()
        }) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(color)
                .frame(width: 64, height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(color.opacity(pressed ? 0.25 : 0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(color.opacity(0.4), lineWidth: 1.5)
                        )
                )
                .scaleEffect(pressed ? 0.93 : 1)
        }
    }
}

// MARK: - Word Chip
struct WordChip: View {
    let result: WordResult
    
    var body: some View {
        HStack(spacing: 4) {
            Text(result.word.uppercased())
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundColor(result.word.count >= 6 ? .lexisGold : .lexisAccent)
            Text("+\(result.score)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.lexisMid)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color.lexisBlock)
                .overlay(Capsule().strokeBorder(Color.lexisBlockBorder.opacity(0.5), lineWidth: 1))
        )
        .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity),
                                removal: .opacity))
    }
}

// MARK: - Wildcard Picker
// MARK: - Word Preview Panel
// Shown after a single tap on a glowing tile — a non-blocking readout of
// exactly which word(s) that tile belongs to and what double-tapping it
// would score. Purely informational: no game state changes, and the
// board keeps running underneath (the falling piece doesn't pause).
struct WordPreviewPanel: View {
    let words: [WordResult]

    private var totalScore: Int { words.reduce(0) { $0 + $1.score } }

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(words) { word in
                VStack(alignment: .trailing, spacing: 1) {
                    Text(word.word.uppercased())
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundColor(.lexisText)
                    HStack(spacing: 5) {
                        Text("\(word.tiles.count) LETTERS")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundColor(.lexisMid)
                        Text("+\(word.score)")
                            .font(.system(size: 13, weight: .black, design: .monospaced))
                            .foregroundColor(.orange)
                    }
                }
            }
            if words.count > 1 {
                Divider().background(Color.white.opacity(0.25))
                HStack(spacing: 5) {
                    Text("TOTAL")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.lexisMid)
                        .tracking(1)
                    Text("+\(totalScore)")
                        .font(.system(size: 15, weight: .black, design: .monospaced))
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.lexisBg.opacity(0.94))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.orange.opacity(0.6), lineWidth: 1.5))
        )
        .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
    }
}

struct FloatingWildcardBadge: View {
    let candidates: [Character]
    @Binding var isExpanded: Bool
    let onSelect: (Character) -> Void
    
    @State private var pulse = false
    
    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if isExpanded {
                // Vertical column, not a horizontal row — this floats as a
                // side panel along the board's trailing edge, so a column
                // gives each candidate a full-width tap target instead of
                // cramming 5 buttons into a corner-sized row.
                VStack(spacing: 6) {
                    ForEach(candidates, id: \.self) { letter in
                        Button {
                            onSelect(letter)
                        } label: {
                            Text(String(letter))
                                .font(.system(size: 17, weight: .black, design: .rounded))
                                .foregroundColor(.lexisGold)
                                .frame(width: 38, height: 38)
                                .background(
                                    RoundedRectangle(cornerRadius: 9)
                                        .fill(Color.lexisGold.opacity(0.18))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 9)
                                                .strokeBorder(Color.lexisGold.opacity(0.55), lineWidth: 1.3)
                                        )
                                )
                        }
                    }
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.lexisBg.opacity(0.97))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.lexisGold.opacity(0.45), lineWidth: 1.5))
                )
                .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            } else {
                // Collapsed badge — a small glowing star, tappable to
                // expand. Auto-expands once on appear (below) since picking
                // a letter isn't optional, just re-collapsible if the
                // player wants the board visible while deciding.
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isExpanded = true
                    }
                } label: {
                    Image(systemName: "star.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.lexisGold)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(Color.lexisGold.opacity(0.2))
                                .overlay(Circle().strokeBorder(Color.lexisGold.opacity(0.6), lineWidth: 1.5))
                        )
                        .scaleEffect(pulse ? 1.12 : 1)
                        .shadow(color: .lexisGold.opacity(0.5), radius: pulse ? 8 : 4)
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                pulse = true
            }
            // Auto-expand immediately — a wildcard needs a choice made
            // before it lands, so surfacing the picker right away (rather
            // than waiting for a tap on the collapsed badge) keeps the
            // player from missing it entirely during fast play.
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.15)) {
                isExpanded = true
            }
        }
    }
}

// MARK: - Menu View
struct MenuView: View {
    @ObservedObject var model: GameModel
    @Binding var showSettings: Bool
    @Binding var showDifficultySelect: Bool
    @ObservedObject private var settings = GameSettings.shared
    @ObservedObject private var gameCenter = GameCenterManager.shared
    @ObservedObject private var dailyManager = DailyChallengeManager.shared
    @ObservedObject private var goalsManager = GoalsManager.shared
    @State private var logoScale: CGFloat = 0.8
    @State private var logoGlow = false
    @State private var showDailyResults = false
    @State private var showLeaderboardScopeDialog = false
    @State private var showDuelSetup = false
    @State private var showProgress = false
    // Measured frame of the "LEXIS" wordmark (in the "menu" coordinate
    // space) — the falling-tile rain starts from here so each letter looks
    // like it drops straight out of the title.
    @State private var logoFrame: CGRect = .zero
    // Spells the game's own name — the letters read "LEXIS" left to right.
    // Each tile's column is placed under its matching wordmark letter (see
    // the rain layer), so together they pour out of the logo in order.
    @State private var demoTiles: [(letter: String, delay: Double)] = [
        ("L", 0), ("E", 0.15), ("X", 0.3), ("I", 0.45), ("S", 0.6)
    ]

    var body: some View {
        ZStack {
            // Ambient parallax field of faint drifting letters — the backmost
            // decorative layer, giving the menu depth and life beneath the
            // sharper logo rain and content.
            AmbientDriftLayer(animate: !settings.motionReduced)

            // Falling-letter rain spelling LEXIS, as a background layer
            // behind the menu content. It begins at the measured "LEXIS"
            // wordmark and each tile falls down the column beneath its own
            // letter in the title, so the effect reads as the logo shedding
            // its letters rather than an unrelated rain starting in blank
            // space below it.
            GeometryReader { geo in
                // Reduce Motion hides the falling-letter rain entirely — it's
                // decorative and unavoidably motion.
                if logoFrame != .zero && !settings.motionReduced {
                    ZStack {
                        ForEach(0..<demoTiles.count, id: \.self) { i in
                            // Center of this letter within the wordmark:
                            // evenly spaced across the measured logo width.
                            let frac = (CGFloat(i) + 0.5) / CGFloat(demoTiles.count)
                            let letterX = logoFrame.minX + logoFrame.width * frac
                            DemoTile(
                                letter: demoTiles[i].letter,
                                xOffset: letterX - geo.size.width / 2,
                                delay: demoTiles[i].delay,
                                startY: logoFrame.maxY - 8,
                                endY: geo.size.height + 40
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    // Rebuild the tiles if the logo ever re-measures (e.g.
                    // rotation) so their startY tracks the new position.
                    .id(logoFrame.maxY)
                }
            }
            .allowsHitTesting(false)

            menuContent
        }
        .coordinateSpace(name: "menu")
        .onPreferenceChange(TitleFramePreferenceKey.self) { logoFrame = $0 }
    }

    private var menuContent: some View {
        VStack(spacing: 0) {
            // Level chip (leading) + goals/leaderboard/settings (trailing)
            HStack {
                Button { showProgress = true } label: { LevelChip() }
                    .buttonStyle(LexisScaleButtonStyle())

                Spacer()

                Button { showProgress = true } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "checklist")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.lexisMid)
                            .frame(width: 40, height: 40)
                            .background(Color.lexisBlock.opacity(0.6))
                            .clipShape(Circle())
                        // Gold dot while any of today's goals are still open.
                        if goalsManager.completedCount < goalsManager.dailyGoals.count {
                            Circle().fill(Color.lexisGold).frame(width: 9, height: 9)
                                .overlay(Circle().stroke(Color.lexisBg, lineWidth: 1.5))
                                .offset(x: 1, y: -1)
                        }
                    }
                }

                if gameCenter.isAuthenticated {
                    Button {
                        showLeaderboardScopeDialog = true
                    } label: {
                        Image(systemName: "list.number")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.lexisMid)
                            .frame(width: 40, height: 40)
                            .background(Color.lexisBlock.opacity(0.6))
                            .clipShape(Circle())
                    }
                    // A casual player has ~no shot at a global word-game
                    // leaderboard; beating a specific friend is achievable
                    // and far more motivating — this used to only offer the
                    // global (hardcoded) scope at all.
                    .confirmationDialog("Leaderboard", isPresented: $showLeaderboardScopeDialog) {
                        Button("Global") {
                            gameCenter.showLeaderboard(for: settings.difficulty)
                        }
                        Button("Friends Only") {
                            gameCenter.showLeaderboard(for: settings.difficulty, friendsOnly: true)
                        }
                    }
                }
                
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.lexisMid)
                        .frame(width: 40, height: 40)
                        .background(Color.lexisBlock.opacity(0.6))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            
            Spacer()
            
            // Logo
            VStack(spacing: 4) {
                Text("LEXIS")
                    .font(.system(size: 72, weight: .black, design: .rounded))
                    .foregroundColor(.lexisAccent)
                    .tracking(12)
                    .shadow(color: Color.lexisAccent.opacity(logoGlow ? 0.8 : 0.3), radius: logoGlow ? 24 : 8)
                    .scaleEffect(logoScale)
                    // Report the wordmark's on-screen frame so the falling
                    // rain can start exactly here. Measured at scaleEffect 1
                    // (natural size) via the unscaled background layer.
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: TitleFramePreferenceKey.self,
                                value: proxy.frame(in: .named("menu"))
                            )
                        }
                    )
                
                Text("ONE LETTER · ONE WORD · ONE LIFE")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.lexisMid)
                    .tracking(2)
            }
            .onAppear {
                // Reduce Motion: no spring-in, no breathing glow — the logo
                // just sits at full size and a steady glow.
                guard !settings.motionReduced else {
                    logoScale = 1
                    logoGlow = true
                    return
                }
                withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) {
                    logoScale = 1
                }
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                    logoGlow = true
                }
            }
            
            Spacer()

            // How to play
            VStack(alignment: .leading, spacing: 12) {
                // The game's core twist, taught with motion: a bright word
                // sweeps a 3×3 patch across, down, and along both diagonals,
                // so a new player sees the 8-way reading before hitting the
                // confusing "wait, why is that a word?" moment in-game.
                HStack(spacing: 14) {
                    DirectionReadingCue(animate: !settings.motionReduced)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("WORDS READ 8 WAYS")
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .foregroundColor(.lexisGold)
                            .tracking(1)
                        Text("Across, down & along both diagonals")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.lexisText.opacity(0.85))
                    }
                }
                HowToRow(icon: "arrow.left.arrow.right", text: "Tap the left or right of the board to steer — or slide to fling")
                HowToRow(icon: "hand.tap", text: "Double-tap a glowing tile to clear its word — any direction")
                HowToRow(icon: "star.fill", color: .lexisGold, text: "Golden blocks = wildcards. Pick any letter!")
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.lexisBlock.opacity(0.8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color.lexisBlockBorder.opacity(0.4), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 24)
            
            Spacer()
            
            // Daily Challenge — the featured mode. Same letter sequence for
            // every player each day, one attempt, streak tracking.
            Button {
                if !dailyManager.hasCompletedToday {
                    model.startDailyChallenge()
                } else {
                    showDailyResults = true
                }
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.lexisGold.opacity(0.15))
                            .frame(width: 44, height: 44)
                        Image(systemName: dailyManager.hasCompletedToday ? "checkmark" : "calendar")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.lexisGold)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DAILY CHALLENGE")
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .foregroundColor(.lexisText)
                            .tracking(1)
                        Text(dailyManager.hasCompletedToday ?
                             "Completed — tap to view results" :
                             "40 letters · same for everyone today")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.lexisMid)
                    }
                    
                    Spacer()
                    
                    if dailyManager.currentStreak > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 11))
                            Text("\(dailyManager.currentStreak)")
                                .font(.system(size: 13, weight: .black, design: .rounded))
                        }
                        .foregroundColor(.lexisCombo)
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                        .fill(Color.lexisGold.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                                .strokeBorder(Color.lexisGold.opacity(0.35), lineWidth: 1.5)
                        )
                )
            }
            .buttonStyle(LexisScaleButtonStyle())
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            // Duel — async head-to-head using the same seeded-sequence
            // machinery as Daily Challenge, just keyed by a shareable code
            // instead of today's date.
            Button {
                showDuelSetup = true
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.lexisAccent.opacity(0.15))
                            .frame(width: 44, height: 44)
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.lexisAccent)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("DUEL A FRIEND")
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .foregroundColor(.lexisText)
                            .tracking(1)
                        Text("Same letters, compare scores")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.lexisMid)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.lexisMid)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                        .fill(Color.lexisAccent.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                                .strokeBorder(Color.lexisAccent.opacity(0.3), lineWidth: 1.5)
                        )
                )
            }
            .buttonStyle(LexisScaleButtonStyle())
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
            .sheet(isPresented: $showDuelSetup) {
                DuelSetupSheet { code in
                    model.startDuel(code: code)
                }
            }

            // High score hero — the best score achieved across ANY
            // difficulty, shown prominently rather than buried as small
            // text, since "what's my best ever" is the first thing a
            // returning player wants to see. Shared with GameOverView so
            // "your best" reads identically on both screens.
            if let topEntry = settings.allTimeScores().first {
                AllTimeBestHero(score: topEntry.score, difficulty: topEntry.difficulty)
                    .padding(.bottom, 16)
                    .transition(.opacity)
            }
            
            // All difficulty levels visible at a glance — tap any card to
            // select it directly. Shared with the Game Over screen.
            DifficultyCardsRow()
                .padding(.bottom, 20)

            // Start button — unlimited endless mode
            Button {
                withAnimation(.spring()) {
                    model.startGame()
                }
            } label: {
                Text("PLAY ENDLESS")
            }
            .buttonStyle(LexisPrimaryButtonStyle())
            .padding(.horizontal, 32)

            Spacer()
        }
        .sheet(isPresented: $showDailyResults) {
            if let result = dailyManager.todayResult {
                DailyResultView(result: result, streak: dailyManager.currentStreak)
            }
        }
        .sheet(isPresented: $showProgress) {
            ProgressSheet()
        }
    }
}

// Carries the measured frame of a title wordmark (the menu's "LEXIS" logo,
// or Game Over's "GAME OVER") up to the view that draws the falling-tile
// rain, so the rain can begin exactly at the wordmark rather than at a
// hardcoded clearance below it — the letters appear to pour out of the
// title itself.
struct TitleFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

struct DemoTile: View {
    let letter: String
    let xOffset: CGFloat
    let delay: Double
    var tileSize: CGFloat = 40
    var color: Color = .lexisAccent
    // How far the tile falls per loop, start-to-end. Kept as a ratio to
    // duration below so a tile spanning the whole menu background falls at
    // the same visual speed as the short one in GameOverView, not slower.
    var startY: CGFloat = -40
    var endY: CGFloat = 60
    @State private var yPos: CGFloat

    init(letter: String, xOffset: CGFloat, delay: Double, tileSize: CGFloat = 40, color: Color = .lexisAccent, startY: CGFloat = -40, endY: CGFloat = 60) {
        self.letter = letter
        self.xOffset = xOffset
        self.delay = delay
        self.tileSize = tileSize
        self.color = color
        self.startY = startY
        self.endY = endY
        self._yPos = State(initialValue: startY)
    }

    // Mirrors TileView's "falling piece" bevel treatment (gradient fill,
    // bright top-left / dark bottom-right bevel strokes, drop shadow, inner
    // sheen) so the menu's and Game Over's decorative letter rain reads as
    // the same chunky, tactile tile a player sees during actual play,
    // rather than a flatter one-off look.
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.35))
                .offset(y: 2)
                .blur(radius: 3)

            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.5), color.opacity(0.1)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.black.opacity(0.35), lineWidth: 1.5)
                .offset(x: 0.5, y: 0.5)
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.white.opacity(0.45), lineWidth: 1.5)
                .offset(x: -0.5, y: -0.5)

            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(color, lineWidth: 1.5)

            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.14), Color.white.opacity(0)],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
                .padding(2)

            Text(letter)
                .font(.system(size: tileSize * 0.55, weight: .black, design: .rounded))
                .foregroundColor(color)
                .shadow(color: .black.opacity(0.4), radius: 0.5, y: 1)
                .shadow(color: color.opacity(0.6), radius: 6)
        }
        .frame(width: tileSize, height: tileSize)
        .offset(x: xOffset, y: yPos)
        .onAppear {
            let travel = Double(endY - startY)
            let duration = max(0.4, 1.2 * travel / 100)
            withAnimation(
                Animation.easeIn(duration: duration)
                    .delay(delay)
                    .repeatForever(autoreverses: false)
            ) {
                yPos = endY
            }
        }
    }
}

struct HowToRow: View {
    let icon: String
    var color: Color = .lexisAccent
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(color)
                .frame(width: 20)
            Text(text)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.lexisText.opacity(0.85))
        }
    }
}

// MARK: - Living-menu ambient layers

// A slow, parallax field of faint letter tiles drifting up behind the menu,
// giving the screen ambient depth and a sense of life without ever
// competing with the menu content. Purely decorative (no hit testing) and
// deliberately low-contrast. Tiles at different "depths" drift at different
// rates and blurs, which reads as parallax. The field is hand-tuned and
// deterministic — it looks the same every launch rather than randomly
// clustering — and every mote starts pre-distributed along its path (via
// its phase) so the menu is alive the instant it appears, not gradually
// populating. Gated by `animate` so a reduce-motion pass can freeze it.
struct AmbientDriftLayer: View {
    var animate: Bool = true
    // letter, x fraction across width, depth 0 (far) … 1 (near), phase 0…1
    private let motes: [(letter: String, xFrac: CGFloat, depth: CGFloat, phase: Double)] = [
        ("L", 0.12, 0.25, 0.00),
        ("E", 0.82, 0.55, 0.35),
        ("X", 0.30, 0.85, 0.60),
        ("I", 0.66, 0.40, 0.15),
        ("S", 0.50, 0.70, 0.80),
        ("A", 0.90, 0.30, 0.50),
        ("O", 0.06, 0.60, 0.25),
        ("T", 0.42, 0.50, 0.90),
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<motes.count, id: \.self) { i in
                    let m = motes[i]
                    AmbientMote(
                        letter: m.letter,
                        depth: m.depth,
                        phase: m.phase,
                        xFrac: m.xFrac,
                        size: geo.size,
                        animate: animate
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct AmbientMote: View {
    let letter: String
    let depth: CGFloat      // 0 far … 1 near
    let phase: Double
    let xFrac: CGFloat
    let size: CGSize
    let animate: Bool
    @State private var t: CGFloat

    init(letter: String, depth: CGFloat, phase: Double, xFrac: CGFloat, size: CGSize, animate: Bool) {
        self.letter = letter
        self.depth = depth
        self.phase = phase
        self.xFrac = xFrac
        self.size = size
        self.animate = animate
        _t = State(initialValue: CGFloat(phase))
    }

    var body: some View {
        let tileSize = 26 + depth * 40          // near tiles are larger
        let opacity = 0.035 + depth * 0.05      // all faint; near a touch stronger
        let blur = (1 - depth) * 4 + 1          // far tiles blurrier
        let duration = 26 - depth * 10          // near tiles drift faster
        let startY = size.height + tileSize     // just below the screen
        let endY = -tileSize                    // just above it
        // The wrap seam (frac 1 → 0) maps endY → startY, both off-screen, so
        // the loop never visibly teleports.
        let frac = t - t.rounded(.down)
        let y = startY + (endY - startY) * frac

        Text(letter)
            .font(.system(size: tileSize, weight: .black, design: .rounded))
            .foregroundColor(Color.lexisAccent.opacity(opacity))
            .blur(radius: blur)
            .position(x: size.width * xFrac, y: y)
            .onAppear {
                guard animate else { return }
                withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                    t = CGFloat(phase) + 1
                }
            }
    }
}

// A compact, self-animating cue that teaches the game's core twist — words
// read in several directions — right on the menu. A 3×3 patch of faint
// tiles has a bright "word" sweep through it horizontally, then vertically,
// then diagonally, on a loop, so a new player sees the 8-way reading before
// they ever hit the confusing "why is that a word?" moment. `animate` lets a
// reduce-motion pass hold it on the horizontal frame.
struct DirectionReadingCue: View {
    var animate: Bool = true
    private let cell: CGFloat = 13
    private let gap: CGFloat = 2
    private let step: TimeInterval = 0.9
    // Each frame lights a straight line of 3 cells in one direction.
    private let frames: [[(Int, Int)]] = [
        [(1, 0), (1, 1), (1, 2)],   // →  horizontal
        [(0, 1), (1, 1), (2, 1)],   // ↓  vertical
        [(0, 0), (1, 1), (2, 2)],   // ↘  diagonal
        [(2, 0), (1, 1), (0, 2)],   // ↗  anti-diagonal
    ]

    var body: some View {
        // Drive the sweep off a TimelineView clock rather than a Timer +
        // @State (which would reintroduce a Swift 6 Sendable-closure warning).
        TimelineView(.periodic(from: .now, by: step)) { context in
            let idx = animate
                ? Int(context.date.timeIntervalSinceReferenceDate / step) % frames.count
                : 0
            grid(for: idx)
                .animation(.easeInOut(duration: 0.35), value: idx)
        }
    }

    private func grid(for idx: Int) -> some View {
        let lit = Set(frames[idx].map { "\($0.0),\($0.1)" })
        return VStack(spacing: gap) {
            ForEach(0..<3, id: \.self) { r in
                HStack(spacing: gap) {
                    ForEach(0..<3, id: \.self) { c in
                        let on = lit.contains("\(r),\(c)")
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(on ? Color.lexisGold.opacity(0.9) : Color.lexisAccent.opacity(0.14))
                            .frame(width: cell, height: cell)
                            .shadow(color: on ? Color.lexisGold.opacity(0.7) : .clear, radius: on ? 4 : 0)
                    }
                }
            }
        }
    }
}

// MARK: - Game Over View
struct GameOverView: View {
    @ObservedObject var model: GameModel
    @Binding var showDifficultySelect: Bool
    @ObservedObject private var settings = GameSettings.shared
    @State private var scale: CGFloat = 0.7
    @State private var opacity: Double = 0
    @State private var showLeaderboard = false
    @State private var showShareSheet = false
    @State private var titleGlow = false
    // Measured frame of the "GAME OVER" title — the falling tiles start
    // from here, so the letters look like they spill out of the headline.
    @State private var titleFrame: CGRect = .zero

    // Same falling-tile mechanic as the menu's LEXIS demo, spelling "GAME
    // OVER" — aligns the two bookend screens visually. Each tile's column
    // is placed under its matching letter in the title (see the rain
    // layer), so they pour out of the headline in order.
    private let demoTiles: [(letter: String, delay: Double)] = [
        ("G", 0), ("A", 0.1), ("M", 0.2), ("E", 0.3),
        ("O", 0.4), ("V", 0.5), ("E", 0.6), ("R", 0.7)
    ]

    // True if this run's score placed in the persisted all-time top 10 —
    // used to show a small celebratory banner distinct from just "high
    // score for this difficulty."
    private var madeTopScores: Bool {
        let all = settings.allTimeScores()
        guard !all.isEmpty else { return model.score > 0 }
        return model.score >= (all.map { $0.score }.min() ?? 0) || all.count < 10
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.lexisBg.opacity(0.92).ignoresSafeArea()

                // Falling-tile rain spelling "GAME OVER," as an ambient
                // background layer behind all the score/button content. It
                // begins at the measured "GAME OVER" title and each tile
                // falls the full screen height beneath its own letter, so
                // the headline appears to shed its letters.
                if titleFrame != .zero {
                    ZStack {
                        ForEach(0..<demoTiles.count, id: \.self) { i in
                            let frac = (CGFloat(i) + 0.5) / CGFloat(demoTiles.count)
                            let letterX = titleFrame.minX + titleFrame.width * frac
                            DemoTile(
                                letter: demoTiles[i].letter,
                                xOffset: letterX - geo.size.width / 2,
                                delay: demoTiles[i].delay,
                                tileSize: 30,
                                color: .lexisDanger,
                                startY: titleFrame.maxY - 6,
                                endY: geo.size.height + 40
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .id(titleFrame.maxY)
                    .allowsHitTesting(false)
                }

                ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 18) {
                // Game over text — same glowing-pulse treatment as the
                // menu's LEXIS logo (just red instead of mint).
                VStack(spacing: 4) {
                    Text("GAME OVER")
                        .font(.system(size: 42, weight: .black, design: .rounded))
                        .foregroundColor(.lexisDanger)
                        .tracking(4)
                        .shadow(color: Color.lexisDanger.opacity(titleGlow ? 0.8 : 0.3), radius: titleGlow ? 24 : 8)
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: TitleFramePreferenceKey.self,
                                    value: proxy.frame(in: .named("gameover"))
                                )
                            }
                        )

                    Text("your words ran out")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.lexisMid)
                        .padding(.top, 8)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                                titleGlow = true
                            }
                        }

                    if madeTopScores && model.score > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "trophy.fill")
                            Text("NEW TOP SCORE!")
                        }
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundColor(.lexisGold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.lexisGold.opacity(0.15)))
                        .padding(.top, 4)
                        .transition(.scale.combined(with: .opacity))
                    }
                }

                // Score cards — this run's SCORE plus BEST/LEVEL context.
                // (The all-time-best hero that briefly lived here was
                // redundant: BEST already shows it, and the difficulty
                // cards below show each pace's best.)
                HStack(spacing: 16) {
                    ScoreCard(label: "SCORE", value: "\(model.score)", color: .lexisAccent)
                    ScoreCard(label: "BEST", value: "\(model.highScore)", color: .lexisGold)
                    ScoreCard(label: "LEVEL", value: "\(model.level)", color: .lexisMid)
                }
                
                // Words found
                if !model.foundWords.isEmpty {
                    LexisCard {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel("WORDS YOU MADE")
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(model.foundWords.prefix(15)) { word in
                                        WordChip(result: word)
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Difficulty picker — the exact same cards as the main menu,
                // so a player can switch pace before replaying without
                // bouncing back to the menu. Negative horizontal padding
                // lets the scroll row bleed to the screen edge like the menu
                // does, despite this content's 24pt inset.
                DifficultyCardsRow()
                    .padding(.horizontal, -24)

                // Buttons
                VStack(spacing: 12) {
                    // PLAY AGAIN gets the same prominent treatment as the
                    // menu's PLAY ENDLESS — big, glowing, unmistakably the
                    // primary action — and launches straight into whatever
                    // difficulty the cards above have selected.
                    Button {
                        withAnimation(.spring()) { model.startGame() }
                    } label: {
                        Text("PLAY AGAIN")
                    }
                    .buttonStyle(LexisPrimaryButtonStyle())

                    HStack(spacing: 12) {
                        Button {
                            showLeaderboard = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "trophy.fill")
                                    .font(.system(size: 13, weight: .bold))
                                Text("TOP SCORES")
                            }
                        }
                        .buttonStyle(LexisSecondaryButtonStyle(tint: .lexisGold))

                        // Every mode's best moments should be exportable,
                        // not just Daily Challenge.
                        Button {
                            showShareSheet = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 13, weight: .bold))
                                Text("SHARE")
                            }
                        }
                        .buttonStyle(LexisSecondaryButtonStyle(tint: .lexisAccent))
                    }

                    Button {
                        withAnimation(.spring()) { model.phase = .menu }
                    } label: {
                        Text("MAIN MENU")
                    }
                    .buttonStyle(LexisGhostButtonStyle())
                }
                .padding(24)
                }
            }
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    scale = 1
                    opacity = 1
                }
            }
        }
        .sheet(isPresented: $showLeaderboard) {
            TopScoresView()
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [model.endlessShareText()])
        }
        .coordinateSpace(name: "gameover")
        .onPreferenceChange(TitleFramePreferenceKey.self) { titleFrame = $0 }
        }
    }
}

// MARK: - Difficulty Cards Row
// The horizontally-scrolling difficulty picker — shared between MenuView
// and GameOverView so choosing a pace looks and behaves identically on
// both screens (tap a card to select it; its per-difficulty best shows
// underneath).
struct DifficultyCardsRow: View {
    @ObservedObject private var settings = GameSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("SELECT DIFFICULTY")
                .padding(.horizontal, 24)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Difficulty.allCases) { diff in
                        let isSelected = settings.difficulty == diff
                        let best = settings.highScore(for: diff)

                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                settings.difficulty = diff
                            }
                            Haptics.light()
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: diff.icon)
                                    .font(.system(size: 16, weight: .bold))
                                Text(diff.rawValue.uppercased())
                                    .font(.system(size: 11, weight: .black, design: .rounded))
                                    .tracking(0.5)
                                Text(best > 0 ? "\(best)" : "—")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .opacity(0.7)
                            }
                            .foregroundColor(isSelected ? Color.lexisBg : .lexisMid)
                            .frame(width: 76, height: 76)
                            .background(
                                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                                    .fill(isSelected ? Color.lexisAccent : Color.lexisBlock.opacity(0.7))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                                            .strokeBorder(isSelected ? Color.clear : Color.lexisBlockBorder.opacity(0.3), lineWidth: 1)
                                    )
                                    .shadow(color: isSelected ? Color.lexisAccent.opacity(0.4) : .clear, radius: 10, y: 3)
                            )
                        }
                        .buttonStyle(LexisScaleButtonStyle())
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }
}

// MARK: - All-Time Best Hero
// The "what's my best ever" display — shared between MenuView and
// GameOverView so a player's all-time high score reads identically no
// matter which screen they're looking at it from.
struct AllTimeBestHero: View {
    let score: Int
    let difficulty: Difficulty

    var body: some View {
        VStack(spacing: 2) {
            Text("ALL-TIME BEST")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundColor(.lexisMid)
                .tracking(3)
            HStack(spacing: 8) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.lexisGold)
                Text("\(score)")
                    .font(.system(size: 34, weight: .black, design: .monospaced))
                    .foregroundColor(.lexisGold)
            }
            Text(difficulty.rawValue.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.lexisMid)
        }
    }
}

struct ScoreCard: View {
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 28, weight: .black, design: .monospaced))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.lexisMid)
                .tracking(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.lexisBlock)
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(color.opacity(0.3), lineWidth: 1.5))
        )
    }
}

// MARK: - View Extension
extension View {
    func scaleEffect(wordFlash: Bool) -> some View {
        self.scaleEffect(wordFlash ? 1.2 : 1.0)
    }
}

// MARK: - Color mixing helper
extension Color {
    func mix(with other: Color, ratio: Double) -> Color {
        // Simplified blend - returns self with opacity adjusted
        return self.opacity(1 - ratio * 0.3)
    }
}

// MARK: - Particle Effect
struct ParticleEffect: Identifiable {
    let id = UUID()
    var position: CGPoint
    var color: Color
    var opacity: Double = 1
}

// MARK: - Bomb Explosion
// A one-shot burst played when a bomb detonates: a white-hot core flash, an
// expanding shockwave ring, and a ring of shrapnel flung radially outward.
// Draws beyond its column frame on purpose (no clipping) so the blast reads
// as bigger than a single tile. Self-animating on appear; the model clears
// the blast marker ~0.85s later, removing this view.
// One tile's-worth of shatter: a marker the view spawns at a cleared tile.
struct ClearShardBurst: Identifiable {
    let id = UUID()
    let row: Int
    let col: Int
    let color: Color
}

// A quick shard burst played where a tile was cleared: a bright flash plus a
// handful of shards flung outward and fading. Smaller and faster than the
// bomb blast — this fires many at once (one per cleared tile), so it stays
// light. Draws beyond its cell bounds on purpose (no clip).
struct ClearShardView: View {
    let tileSize: CGFloat
    let color: Color
    @State private var go = false

    private let shards = 6

    var body: some View {
        ZStack {
            // Core flash
            Circle()
                .fill(color)
                .frame(width: tileSize * 0.9, height: tileSize * 0.9)
                .scaleEffect(go ? 1.3 : 0.4)
                .opacity(go ? 0 : 0.9)

            // Shards
            ForEach(0..<shards, id: \.self) { i in
                let angle = (Double(i) / Double(shards)) * 2 * .pi + 0.4
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(color)
                    .frame(width: tileSize * 0.2, height: tileSize * 0.2)
                    .offset(
                        x: go ? CGFloat(cos(angle)) * tileSize * 1.15 : 0,
                        y: go ? CGFloat(sin(angle)) * tileSize * 1.15 : 0
                    )
                    .rotationEffect(.degrees(go ? 140 : 0))
                    .opacity(go ? 0 : 1)
                    .scaleEffect(go ? 0.4 : 1)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.55)) { go = true }
        }
    }
}

struct BombExplosionView: View {
    let tileSize: CGFloat
    @State private var animate = false

    private let shardCount = 12

    var body: some View {
        ZStack {
            // Shockwave ring
            Circle()
                .stroke(Color.lexisDanger, lineWidth: animate ? 1 : 5)
                .frame(width: tileSize * 1.3, height: tileSize * 1.3)
                .scaleEffect(animate ? 3.4 : 0.3)
                .opacity(animate ? 0 : 0.9)

            // White-hot core flash fading through gold to red
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white, .lexisGold, Color.lexisDanger.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: tileSize
                    )
                )
                .frame(width: tileSize * 2.2, height: tileSize * 2.2)
                .scaleEffect(animate ? 1.7 : 0.2)
                .opacity(animate ? 0 : 1)

            // Shrapnel flung outward
            ForEach(0..<shardCount, id: \.self) { i in
                let angle = (Double(i) / Double(shardCount)) * 2 * .pi
                Circle()
                    .fill(i.isMultiple(of: 2) ? Color.lexisGold : Color.lexisDanger)
                    .frame(width: tileSize * 0.26, height: tileSize * 0.26)
                    .offset(
                        x: animate ? CGFloat(cos(angle)) * tileSize * 2.6 : 0,
                        y: animate ? CGFloat(sin(angle)) * tileSize * 2.6 : 0
                    )
                    .opacity(animate ? 0 : 1)
                    .scaleEffect(animate ? 0.4 : 1)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                animate = true
            }
        }
    }
}

// MARK: - Daily Result View
// MARK: - Duel Setup
// Entry point for async head-to-head play: reuses the Daily Challenge's
// deterministic seeded-sequence generator, just keyed by a shareable code
// instead of a date, so two players can independently play the identical
// letters and compare scores without any server.
struct DuelSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var enteredCode: String = ""
    let onStart: (String) -> Void

    static func randomCode() -> String {
        let chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" // no ambiguous O/0, I/1
        return String((0..<6).compactMap { _ in chars.randomElement() })
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.lexisBg.ignoresSafeArea()

                VStack(spacing: 24) {
                    VStack(spacing: 6) {
                        Text("DUEL A FRIEND")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundColor(.lexisText)
                        Text("Play the exact same letters and compare scores")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.lexisMid)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)
                    .padding(.horizontal, 24)

                    Button {
                        onStart(Self.randomCode())
                        dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                            Text("START A NEW DUEL")
                        }
                    }
                    .buttonStyle(LexisPrimaryButtonStyle())
                    .padding(.horizontal, 20)

                    VStack(spacing: 10) {
                        Text("OR ENTER A FRIEND'S CODE")
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundColor(.lexisMid)
                            .tracking(1)
                        TextField("CODE", text: $enteredCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .font(.system(size: 18, weight: .black, design: .monospaced))
                            .multilineTextAlignment(.center)
                            .foregroundColor(.lexisText)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.lexisBlock.opacity(0.6)))
                        Button {
                            let code = enteredCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                            guard !code.isEmpty else { return }
                            onStart(code)
                            dismiss()
                        } label: {
                            Text("JOIN DUEL")
                                .font(.system(size: 15, weight: .black, design: .rounded))
                                .tracking(2)
                                .foregroundColor(.lexisGold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.lexisGold.opacity(0.1))
                                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.lexisGold.opacity(0.35), lineWidth: 1.5))
                                )
                        }
                        .disabled(enteredCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.horizontal, 20)

                    Spacer()
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

struct DuelResultView: View {
    let code: String
    let score: Int
    @Binding var phase: GamePhase
    @State private var showShareSheet = false

    var body: some View {
        ZStack {
            Color.lexisBg.ignoresSafeArea()

            VStack(spacing: 16) {
                Spacer()
                Text("DUEL COMPLETE")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundColor(.lexisAccent)
                Text("CODE: \(code)")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.lexisMid)
                    .tracking(1)

                VStack(spacing: 2) {
                    Text("\(score)")
                        .font(.system(size: 48, weight: .black, design: .monospaced))
                        .foregroundColor(.lexisText)
                    Text("SCORE")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundColor(.lexisMid)
                        .tracking(2)
                }
                .padding(.vertical, 8)

                Button {
                    showShareSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .bold))
                        Text("SHARE CHALLENGE")
                    }
                }
                .buttonStyle(LexisPrimaryButtonStyle(tint: .lexisGold))
                .padding(.horizontal, 24)
                .padding(.top, 12)

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
            ShareSheet(items: ["I scored \(score) in a LEXIS duel — enter code \(code) to play the exact same letters and beat me. Play LEXIS."])
        }
    }
}

struct DailyResultView: View {
    let result: DailyResult
    let streak: Int
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var dailyManager = DailyChallengeManager.shared
    @ObservedObject private var gameCenter = GameCenterManager.shared
    @State private var showShareSheet = false
    @State private var showLeaderboardScopeDialog = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.lexisBg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 6) {
                            Image(systemName: result.survived ? "checkmark.seal.fill" : "xmark.seal.fill")
                                .font(.system(size: 44))
                                .foregroundColor(result.survived ? .lexisAccent : .lexisDanger)
                            
                            Text(result.survived ? "CHALLENGE COMPLETE" : "BOARD FILLED")
                                .font(.system(size: 20, weight: .black, design: .rounded))
                                .foregroundColor(.lexisText)
                            
                            Text(result.dateKey)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(.lexisMid)
                        }
                        .padding(.top, 20)
                        
                        HStack(spacing: 12) {
                            ScoreCard(label: "SCORE", value: "\(result.score)", color: .lexisAccent)
                            ScoreCard(label: "WORDS", value: "\(result.wordsFound.count)", color: .lexisGold)
                            ScoreCard(label: "STREAK", value: "\(streak)", color: .lexisCombo)
                        }
                        .padding(.horizontal, 20)
                        
                        if !result.longestWord.isEmpty {
                            VStack(spacing: 4) {
                                Text("LONGEST WORD")
                                    .font(.system(size: 10, weight: .black, design: .monospaced))
                                    .foregroundColor(.lexisMid)
                                    .tracking(2)
                                Text(result.longestWord.uppercased())
                                    .font(.system(size: 28, weight: .black, design: .rounded))
                                    .foregroundColor(.yellow)
                            }
                        }
                        
                        if !result.wordsFound.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("ALL WORDS FOUND")
                                    .font(.system(size: 11, weight: .black, design: .monospaced))
                                    .foregroundColor(.lexisMid)
                                    .tracking(2)
                                
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 70))], spacing: 8) {
                                    ForEach(result.wordsFound, id: \.self) { word in
                                        Text(word.uppercased())
                                            .font(.system(size: 12, weight: .black, design: .rounded))
                                            .foregroundColor(.lexisAccent)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(Capsule().fill(Color.lexisBlock))
                                    }
                                }
                            }
                            .padding(16)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color.lexisBlock.opacity(0.5)))
                            .padding(.horizontal, 20)
                        }
                        
                        Button {
                            showShareSheet = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 15, weight: .bold))
                                Text("SHARE RESULT")
                            }
                        }
                        .buttonStyle(LexisPrimaryButtonStyle(tint: .lexisGold))
                        .padding(.horizontal, 20)

                        // Today's Daily Challenge is the same 40 letters for
                        // everyone, so — unlike endless mode's difficulty
                        // leaderboards — comparing against other players here
                        // is an apples-to-apples comparison. Scoped to .today
                        // in GameCenterManager, not all-time.
                        if gameCenter.isAuthenticated {
                            Button {
                                showLeaderboardScopeDialog = true
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "person.2.fill")
                                        .font(.system(size: 14, weight: .bold))
                                    Text("SEE HOW OTHERS DID TODAY")
                                }
                            }
                            .buttonStyle(LexisSecondaryButtonStyle(tint: .lexisAccent))
                            .padding(.horizontal, 20)
                            .confirmationDialog("Today's Leaderboard", isPresented: $showLeaderboardScopeDialog) {
                                Button("Everyone") {
                                    gameCenter.showDailyLeaderboard()
                                }
                                Button("Friends Only") {
                                    gameCenter.showDailyLeaderboard(friendsOnly: true)
                                }
                            }
                        }

                        Text("Come back tomorrow for a new challenge")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.lexisMid)
                            .padding(.bottom, 20)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.lexisAccent)
                        .fontWeight(.bold)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [dailyManager.shareText(for: result)])
        }
    }
}

// MARK: - Share Sheet (UIActivityViewController wrapper)
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Top Scores (all-time leaderboard)
struct TopScoresView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = GameSettings.shared
    @State private var selectedFilter: ScoreFilter = .allTime
    
    enum ScoreFilter: Hashable {
        case allTime
        case difficulty(Difficulty)
        
        var label: String {
            switch self {
            case .allTime: return "ALL-TIME"
            case .difficulty(let d): return d.rawValue.uppercased()
            }
        }
    }
    
    private var entries: [ScoreEntry] {
        switch selectedFilter {
        case .allTime: return settings.allTimeScores()
        case .difficulty(let d): return settings.scores(for: d)
        }
    }
    
    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        return df
    }()
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.lexisBg.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Filter chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            filterChip(.allTime)
                            ForEach(Difficulty.allCases) { diff in
                                filterChip(.difficulty(diff))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    
                    if entries.isEmpty {
                        Spacer()
                        VStack(spacing: 10) {
                            Image(systemName: "trophy")
                                .font(.system(size: 40))
                                .foregroundColor(.lexisMid.opacity(0.4))
                            Text("No scores yet — go make some words")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundColor(.lexisMid)
                        }
                        Spacer()
                    } else {
                        ScrollView {
                            VStack(spacing: 8) {
                                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                                    TopScoreRow(rank: index + 1, entry: entry, dateFormatter: Self.dateFormatter)
                                }
                            }
                            .padding(16)
                        }
                    }
                }
            }
            .navigationTitle("Top Scores")
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
    
    private func filterChip(_ filter: ScoreFilter) -> some View {
        let isSelected = selectedFilter == filter
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { selectedFilter = filter }
        } label: {
            Text(filter.label)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundColor(isSelected ? Color.lexisBg : .lexisMid)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(isSelected ? Color.lexisAccent : Color.lexisBlock)
                )
        }
    }
}

struct TopScoreRow: View {
    let rank: Int
    let entry: ScoreEntry
    let dateFormatter: DateFormatter
    
    private var rankColor: Color {
        switch rank {
        case 1: return .lexisGold
        case 2: return Color(white: 0.75)
        case 3: return Color(red: 0.8, green: 0.5, blue: 0.3)
        default: return .lexisMid
        }
    }
    
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(rankColor.opacity(rank <= 3 ? 0.2 : 0.08))
                    .frame(width: 36, height: 36)
                if rank <= 3 {
                    Image(systemName: "medal.fill")
                        .font(.system(size: 14))
                        .foregroundColor(rankColor)
                } else {
                    Text("\(rank)")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundColor(rankColor)
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("\(entry.score)")
                    .font(.system(size: 18, weight: .black, design: .monospaced))
                    .foregroundColor(.lexisText)
                HStack(spacing: 6) {
                    Image(systemName: entry.difficulty.icon)
                        .font(.system(size: 9))
                    Text(entry.difficulty.rawValue)
                    Text("·")
                    Text("\(entry.wordsFound) words")
                }
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.lexisMid)
            }
            
            Spacer()
            
            Text(dateFormatter.string(from: entry.date))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.lexisMid.opacity(0.7))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(rank == 1 ? Color.lexisGold.opacity(0.08) : Color.lexisBlock.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(rank == 1 ? Color.lexisGold.opacity(0.3) : Color.clear, lineWidth: 1)
                )
        )
    }
}

#Preview {
    GameView()
}
