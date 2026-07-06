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

                switch model.phase {
                case .menu:
                    MenuView(model: model, showSettings: $showSettings, showDifficultySelect: $showDifficultySelect)
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
                case .gameOver:
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
                        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                            dangerVignettePulse = true
                        }
                    }
                    .onDisappear { dangerVignettePulse = false }
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

    // Tile size was previously derived from screen WIDTH alone, which on a
    // 14-row board silently overflowed the screen HEIGHT on every device —
    // pushing the header off the top and the controls panel off the bottom
    // (never caught before because this project had no buildable Xcode
    // target to actually run it in). Constraining by both dimensions keeps
    // the whole PlayingView layout on-screen everywhere.
    private func tileSize(for size: CGSize) -> CGFloat {
        let widthBased = (size.width - 2 * boardHorizontalPadding) / CGFloat(GameConstants.cols) - 2
        // Reduced from 340 after removing the redundant DROP button and then
        // again after moving the NEXT-letter preview into the header and the
        // gesture hint into Settings — the controls panel is now usually
        // empty during normal play. If you change GameConstants.rows/cols or
        // add substantial new permanent UI chrome, revisit this constant.
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
    @State private var dragAccumulator: CGFloat = 0
    @FocusState private var boardFocused: Bool

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
            // things: that dragging steers the piece, and that a glowing
            // tile needs a double-tap. It disappears for good the moment
            // that first word is cleared.
            if model.isTutorialActive {
                VStack {
                    HStack(spacing: 10) {
                        Image(systemName: model.tutorialStep == 0 ? "hand.draw.fill" : "hand.tap.fill")
                            .font(.system(size: 16, weight: .bold))
                        Text(model.tutorialStep == 0 ?
                             "DRAG LEFT OR RIGHT TO STEER — OR JUST LET IT FALL" :
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
                        Text("×\(model.comboCount) COMBO!")
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .foregroundColor(.lexisCombo)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                
                Spacer()
                
                HStack(spacing: 8) {
                    // NEXT letter preview + high score, relocated here from
                    // the controls panel so the bottom of the screen isn't
                    // permanently spending space on it — the panel now only
                    // appears when there's an actual power-up to show. This
                    // shows the UPCOMING piece (a real lookahead), not the
                    // one currently falling — that's already visible on the
                    // board, so showing it twice told the player nothing new.
                    VStack(spacing: 2) {
                        FallingLetterPreview(
                            letter: model.upcomingLetter,
                            isWildcard: model.upcomingIsWildcard,
                            isBomb: model.upcomingIsBomb,
                            isDynamite: model.upcomingIsDynamite,
                            size: 36
                        )
                        Text("HI \(model.highScore)")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.lexisGold)
                    }

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
                // Primary touch control for moving the falling piece: drag
                // left/right anywhere on the board to shift columns, or
                // drag downward to soft-drop (accelerate the fall without
                // instantly slamming to the bottom — that's still the
                // double-tap hard drop). Whichever axis dominates a given
                // drag gesture wins, so a slightly-diagonal swipe doesn't
                // fight itself.
                .contentShape(Rectangle())
                .simultaneousGesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { value in
                            let horizontalDominant = abs(value.translation.width) > abs(value.translation.height)
                            
                            if horizontalDominant {
                                if model.isSoftDropping { model.endSoftDrop() }
                                let columnWidth = tileSize + 2
                                let threshold = columnWidth * 0.7
                                let delta = value.translation.width - dragAccumulator
                                if delta > threshold {
                                    dragAccumulator += threshold
                                    model.moveRight()
                                } else if delta < -threshold {
                                    dragAccumulator -= threshold
                                    model.moveLeft()
                                }
                            } else if value.translation.height > 16 {
                                // A clear, sustained downward drag engages
                                // soft-drop. Small vertical jitter during a
                                // horizontal swipe is ignored via the
                                // horizontalDominant check above. The fall
                                // speed then tracks the drag's own velocity
                                // continuously, rather than snapping straight
                                // to one fixed fast rate.
                                if !model.isSoftDropping { model.beginSoftDrop() }
                                model.updateSoftDropSpeed(velocity: value.velocity.height)
                            }
                        }
                        .onEnded { _ in
                            dragAccumulator = 0
                            model.endSoftDrop()
                        }
                )

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

                // Word flash overlay
                if wordFlashOpacity > 0 {
                    Text(wordFlashText)
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundColor(wordFlashColor)
                        .shadow(color: wordFlashColor.opacity(0.8), radius: 12)
                        .opacity(wordFlashOpacity)
                        .scaleEffect(wordFlash: wordBurst)
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
            .padding(.bottom, 20)
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
        let tile = TileView(
            tile: model.grid[row][col],
            isFallingPos: row == model.fallingRow && col == model.fallingCol,
            fallingLetter: model.fallingLetter,
            isWildcard: model.isWildcard,
            isBomb: model.isBomb,
            isDynamite: model.isDynamite,
            isStuckPos: model.isStuck && row == model.fallingRow && col == model.fallingCol,
            isGhostPos: model.settings.showGhostPiece && col == model.fallingCol && row == ghostRow(),
            isDangerRow: row < GameConstants.dangerRow,
            isTippable: model.tipsAvailable > 0 && isTopOfColumn(row: row, col: col),
            isHintSource: model.hintTargetCol == col && isTopOfColumn(row: row, col: col),
            colorBlindMode: model.settings.colorBlindMode,
            largeText: model.settings.largeText,
            tileSize: tileSize
        )
        // Double-tap on a glowing tile confirms a word clear, otherwise it
        // hard-drops.
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

    func triggerWordFlash(_ result: WordResult) {
        wordFlashText = result.word.uppercased()
        wordFlashColor = result.isChain ? .lexisCombo : (result.word.count >= 6 ? .lexisGold : .lexisAccent)
        wordBurst = true
        
        withAnimation(.spring(response: 0.15)) {
            wordFlashOpacity = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.easeOut(duration: 0.4)) {
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

    @State private var appear = false
    @State private var glowPulse = false
    @State private var hintPulse = false
    
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
                        lineWidth: isFallingPos ? 2 : (isGlowing ? (glowPulse ? 2.6 : 1.8) : (isGhostPos ? 1.2 : 1)),
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
                        (isGlowing ? .yellow : (tile?.isWildcard == true ? .lexisGold : .lexisText)))
                    .shadow(color: .black.opacity(0.4), radius: 0.5, y: 1) // tiny drop shadow on the letter itself, for print-like crispness
                    .shadow(color: glowColor?.opacity(isGlowing ? 0.9 : 0.6) ?? .clear, radius: isGlowing ? 10 : 6)
                    .scaleEffect(appear ? (isGlowing && glowPulse ? 1.08 : 1) : 0.3)
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
        }
        .frame(width: tileSize, height: tileSize)
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
    @State private var logoScale: CGFloat = 0.8
    @State private var logoGlow = false
    @State private var showDailyResults = false
    @State private var showLeaderboardScopeDialog = false
    @State private var showDuelSetup = false
    // Spells the game's own name, not an arbitrary word — each tile falls
    // in its own column (xOffset) so together they read "LEXIS" left to
    // right, matching how a real falling piece would land into a word.
    @State private var demoTiles: [(letter: String, xOffset: CGFloat, delay: Double)] = [
        ("L", -84, 0), ("E", -42, 0.15), ("X", 0, 0.3), ("I", 42, 0.45), ("S", 84, 0.6)
    ]
    
    var body: some View {
        ZStack {
            // Falling-letter rain spelling LEXIS, as a background layer
            // behind the menu content rather than a boxed-in inline element.
            // Previously it sat inline between the logo and the how-to-play
            // card and visibly overlapped the subtitle text; starting it
            // below that text and letting it fall toward the bottom of the
            // screen keeps it feeling like ambient background motion rather
            // than something colliding with the UI on top of it.
            GeometryReader { geo in
                ZStack {
                    ForEach(0..<demoTiles.count, id: \.self) { i in
                        DemoTile(
                            letter: demoTiles[i].letter,
                            xOffset: demoTiles[i].xOffset,
                            delay: demoTiles[i].delay,
                            startY: 0,
                            endY: geo.size.height - menuHeaderClearance
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.top, menuHeaderClearance)
            }
            .allowsHitTesting(false)

            menuContent
        }
    }

    // Clears the top icon row + logo + subtitle before the falling tiles
    // start, so they never overlap that text. Empirically sized rather than
    // measured exactly — revisit if the logo block's height changes.
    private let menuHeaderClearance: CGFloat = 260

    private var menuContent: some View {
        VStack(spacing: 0) {
            // Leaderboard + settings, top-right
            HStack {
                Spacer()
                
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
                
                Text("ONE LETTER · ONE WORD · ONE LIFE")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.lexisMid)
                    .tracking(2)
            }
            .onAppear {
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
                HowToRow(icon: "arrow.left.arrow.right", text: "Steer each falling letter left & right")
                HowToRow(icon: "hand.tap", text: "Tap a tile to clear words — any direction")
                HowToRow(icon: "star.fill", color: .lexisGold, text: "Golden blocks = wildcards. Pick any letter!")
                HowToRow(icon: "arrow.up.right.and.arrow.down.left", text: "Chain words for massive combo scores")
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
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.lexisGold.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(Color.lexisGold.opacity(0.35), lineWidth: 1.5)
                        )
                )
            }
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
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.lexisAccent.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(Color.lexisAccent.opacity(0.3), lineWidth: 1.5)
                        )
                )
            }
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
            // returning player wants to see.
            if let topEntry = settings.allTimeScores().first {
                VStack(spacing: 2) {
                    Text("ALL-TIME BEST")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundColor(.lexisMid)
                        .tracking(3)
                    HStack(spacing: 8) {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.lexisGold)
                        Text("\(topEntry.score)")
                            .font(.system(size: 34, weight: .black, design: .monospaced))
                            .foregroundColor(.lexisGold)
                    }
                    Text(topEntry.difficulty.rawValue.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.lexisMid)
                }
                .padding(.bottom, 16)
                .transition(.opacity)
            }
            
            // All difficulty levels visible at a glance — tap any card to
            // select it directly, rather than hiding the other three
            // behind a single chip that only shows the current pick.
            VStack(alignment: .leading, spacing: 8) {
                Text("SELECT DIFFICULTY")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundColor(.lexisMid)
                    .tracking(2)
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
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(isSelected ? Color.lexisAccent : Color.lexisBlock.opacity(0.7))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14)
                                                .strokeBorder(isSelected ? Color.clear : Color.lexisBlockBorder.opacity(0.3), lineWidth: 1)
                                        )
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }
            .padding(.bottom, 20)
            
            // Start button — unlimited endless mode
            Button {
                withAnimation(.spring()) {
                    model.startGame()
                }
            } label: {
                Text("PLAY ENDLESS")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundColor(Color.lexisBg)
                    .tracking(4)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.lexisAccent)
                            .shadow(color: Color.lexisAccent.opacity(0.4), radius: 16, y: 6)
                    )
            }
            .padding(.horizontal, 32)
            
            Spacer()
        }
        .sheet(isPresented: $showDailyResults) {
            if let result = dailyManager.todayResult {
                DailyResultView(result: result, streak: dailyManager.currentStreak)
            }
        }
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

    var body: some View {
        Text(letter)
            .font(.system(size: tileSize * 0.6, weight: .black, design: .rounded))
            .foregroundColor(color)
            .frame(width: tileSize, height: tileSize)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(color.opacity(0.4), lineWidth: 1))
            )
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

    // Same falling-tile mechanic as the menu's LEXIS demo, spelling "GAME
    // OVER" instead — aligns the two bookend screens visually rather than
    // this one just being a plain static text dump.
    private let demoTiles: [(letter: String, xOffset: CGFloat, delay: Double)] = [
        ("G", -133, 0), ("A", -95, 0.1), ("M", -57, 0.2), ("E", -19, 0.3),
        ("O", 19, 0.4), ("V", 57, 0.5), ("E", 95, 0.6), ("R", 133, 0.7)
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
        ZStack {
            Color.lexisBg.opacity(0.92).ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Game over text — same glowing-pulse treatment as the
                // menu's LEXIS logo (just red instead of mint), plus the
                // falling-tile demo re-spelling "GAME OVER" beneath it.
                VStack(spacing: 4) {
                    Text("GAME OVER")
                        .font(.system(size: 42, weight: .black, design: .rounded))
                        .foregroundColor(.lexisDanger)
                        .tracking(4)
                        .shadow(color: Color.lexisDanger.opacity(titleGlow ? 0.8 : 0.3), radius: titleGlow ? 24 : 8)

                    Text("your words ran out")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.lexisMid)

                    ZStack {
                        ForEach(0..<demoTiles.count, id: \.self) { i in
                            DemoTile(
                                letter: demoTiles[i].letter,
                                xOffset: demoTiles[i].xOffset,
                                delay: demoTiles[i].delay,
                                tileSize: 30,
                                color: .lexisDanger
                            )
                        }
                    }
                    .frame(height: 60)
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
                
                // Score cards
                HStack(spacing: 16) {
                    ScoreCard(label: "SCORE", value: "\(model.score)", color: .lexisAccent)
                    ScoreCard(label: "BEST", value: "\(model.highScore)", color: .lexisGold)
                    ScoreCard(label: "LEVEL", value: "\(model.level)", color: .lexisMid)
                }
                
                // Words found
                if !model.foundWords.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("WORDS YOU MADE")
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundColor(.lexisMid)
                            .tracking(2)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(model.foundWords.prefix(15)) { word in
                                    WordChip(result: word)
                                }
                            }
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.lexisBlock.opacity(0.6)))
                }
                
                // Buttons
                VStack(spacing: 12) {
                    Button {
                        withAnimation(.spring()) { model.startGame() }
                    } label: {
                        Text("PLAY AGAIN")
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .foregroundColor(Color.lexisBg)
                            .tracking(3)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color.lexisAccent))
                    }
                    
                    Button {
                        showLeaderboard = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 14, weight: .bold))
                            Text("TOP SCORES")
                                .font(.system(size: 15, weight: .black, design: .rounded))
                                .tracking(2)
                        }
                        .foregroundColor(.lexisGold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.lexisGold.opacity(0.1))
                                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.lexisGold.opacity(0.35), lineWidth: 1.5))
                        )
                    }

                    // Every mode's best moments should be exportable, not
                    // just Daily Challenge — that used to be the only mode
                    // with any share affordance at all.
                    Button {
                        showShareSheet = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 14, weight: .bold))
                            Text("SHARE RESULT")
                                .font(.system(size: 15, weight: .black, design: .rounded))
                                .tracking(2)
                        }
                        .foregroundColor(.lexisAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.lexisAccent.opacity(0.1))
                                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.lexisAccent.opacity(0.35), lineWidth: 1.5))
                        )
                    }

                    HStack(spacing: 12) {
                        Button {
                            model.phase = .menu
                            showDifficultySelect = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.system(size: 13, weight: .bold))
                                Text("DIFFICULTY")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .tracking(1)
                            }
                            .foregroundColor(.lexisMid)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color.lexisBlock))
                        }
                        
                        Button {
                            withAnimation(.spring()) { model.phase = .menu }
                        } label: {
                            Text("MAIN MENU")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .tracking(1)
                                .foregroundColor(.lexisMid)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(RoundedRectangle(cornerRadius: 14).fill(Color.lexisBlock))
                        }
                    }
                }
            }
            .padding(24)
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
                                .tracking(1)
                        }
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundColor(Color.lexisBg)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.lexisAccent))
                    }
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
                            .font(.system(size: 15, weight: .black, design: .rounded))
                            .tracking(1)
                    }
                    .foregroundColor(Color.lexisBg)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.lexisGold))
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)

                Button {
                    phase = .menu
                } label: {
                    Text("MAIN MENU")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.lexisMid)
                }
                .padding(.top, 8)

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
                                    .font(.system(size: 15, weight: .black, design: .rounded))
                                    .tracking(2)
                            }
                            .foregroundColor(Color.lexisBg)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color.lexisGold))
                        }
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
                                        .font(.system(size: 13, weight: .black, design: .rounded))
                                        .tracking(1)
                                }
                                .foregroundColor(.lexisAccent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(Color.lexisAccent.opacity(0.1))
                                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.lexisAccent.opacity(0.35), lineWidth: 1.5))
                                )
                            }
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
