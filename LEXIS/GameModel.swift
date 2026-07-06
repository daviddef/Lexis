import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Letter Tile
struct LetterTile: Identifiable, Equatable {
    let id = UUID()
    var letter: Character
    var row: Int
    var col: Int
    var isWildcard: Bool = false
    var isHighlighted: Bool = false
    var isPartOfWord: Bool = false
    var color: TileColor = .standard
    var age: Int = 0 // how many drops old this tile is (older = more urgent)
    var glowingWordID: UUID? = nil // non-nil once part of a detected-but-not-yet-cleared word
    
    enum TileColor {
        case standard, wildcard, danger, selected, clearing
    }
}

// MARK: - Word Result
struct WordResult: Identifiable {
    let id = UUID()
    let word: String
    let tiles: [LetterTile]
    let score: Int
    let isChain: Bool
}

// MARK: - Game State
enum GamePhase {
    case menu, playing, paused, gameOver
}

// MARK: - Difficulty
enum Difficulty: String, CaseIterable, Identifiable, Codable {
    case relaxed = "Relaxed"
    case classic = "Classic"
    case rapid = "Rapid"
    case insane = "Insane"

    var id: String { rawValue }

    var baseDropInterval: Double {
        switch self {
        case .relaxed: return 2.2
        case .classic: return 1.4
        case .rapid: return 0.95
        case .insane: return 0.65
        }
    }

    var speedIncreasePerLevel: Double {
        switch self {
        case .relaxed: return 0.02
        case .classic: return 0.04
        case .rapid: return 0.05
        case .insane: return 0.07
        }
    }

    var minDropInterval: Double {
        switch self {
        case .relaxed: return 0.55
        case .classic: return 0.32
        case .rapid: return 0.22
        case .insane: return 0.16
        }
    }

    var wildcardInterval: Int {
        switch self {
        case .relaxed: return 7
        case .classic: return 10
        case .rapid: return 12
        case .insane: return 16
        }
    }

    var scoreMultiplier: Double {
        switch self {
        case .relaxed: return 0.75
        case .classic: return 1.0
        case .rapid: return 1.35
        case .insane: return 1.75
        }
    }

    var icon: String {
        switch self {
        case .relaxed: return "leaf.fill"
        case .classic: return "gamecontroller.fill"
        case .rapid: return "bolt.fill"
        case .insane: return "flame.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .relaxed: return "Slow drop, more wildcards, great for learning"
        case .classic: return "The original balanced LEXIS experience"
        case .rapid: return "Faster drops, higher scores, sharper reflexes"
        case .insane: return "Blistering speed, rare wildcards, pure chaos"
        }
    }
}

// MARK: - Game Constants
struct GameConstants {
    static let cols = 7
    static let rows = 14
    static let minWordLength = 3
    static let dangerRow = 2
    static let bombInterval = 25
}

// MARK: - Settings
@MainActor
class GameSettings: ObservableObject {
    static let shared = GameSettings()

    @Published var difficulty: Difficulty {
        didSet { UserDefaults.standard.set(difficulty.rawValue, forKey: "lexisDifficulty") }
    }
    @Published var hapticsEnabled: Bool {
        didSet { UserDefaults.standard.set(hapticsEnabled, forKey: "lexisHaptics") }
    }
    @Published var soundEnabled: Bool {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: "lexisSound") }
    }
    @Published var colorBlindMode: Bool {
        didSet { UserDefaults.standard.set(colorBlindMode, forKey: "lexisColorBlind") }
    }
    @Published var showGhostPiece: Bool {
        didSet { UserDefaults.standard.set(showGhostPiece, forKey: "lexisGhost") }
    }
    @Published var largeText: Bool {
        didSet { UserDefaults.standard.set(largeText, forKey: "lexisLargeText") }
    }

    private init() {
        let savedDiff = UserDefaults.standard.string(forKey: "lexisDifficulty") ?? Difficulty.classic.rawValue
        self.difficulty = Difficulty(rawValue: savedDiff) ?? .classic
        self.hapticsEnabled = UserDefaults.standard.object(forKey: "lexisHaptics") as? Bool ?? true
        self.soundEnabled = UserDefaults.standard.object(forKey: "lexisSound") as? Bool ?? true
        self.colorBlindMode = UserDefaults.standard.object(forKey: "lexisColorBlind") as? Bool ?? false
        self.showGhostPiece = UserDefaults.standard.object(forKey: "lexisGhost") as? Bool ?? true
        self.largeText = UserDefaults.standard.object(forKey: "lexisLargeText") as? Bool ?? false
    }

    func highScore(for difficulty: Difficulty) -> Int {
        UserDefaults.standard.integer(forKey: "lexisHighScore_" + difficulty.rawValue)
    }

    func setHighScore(_ value: Int, for difficulty: Difficulty) {
        UserDefaults.standard.set(value, forKey: "lexisHighScore_" + difficulty.rawValue)
    }
    
    // MARK: - Top scores ever achieved
    // A persisted top-10 list, both per-difficulty and combined across all
    // of them, so players can see "best I've ever done" at a glance rather
    // than only the single running high score for whatever difficulty
    // they're currently on.
    private let maxLeaderboardEntries = 10
    
    func recordScore(_ score: Int, difficulty: Difficulty, wordsFound: Int, date: Date = Date()) {
        guard score > 0 else { return }
        let entry = ScoreEntry(score: score, difficulty: difficulty, wordsFound: wordsFound, date: date)
        
        var all = allTimeScores()
        all.append(entry)
        all.sort { $0.score > $1.score }
        if all.count > maxLeaderboardEntries { all = Array(all.prefix(maxLeaderboardEntries)) }
        save(all, key: "lexisAllTimeScores")
        
        var perDiff = scores(for: difficulty)
        perDiff.append(entry)
        perDiff.sort { $0.score > $1.score }
        if perDiff.count > maxLeaderboardEntries { perDiff = Array(perDiff.prefix(maxLeaderboardEntries)) }
        save(perDiff, key: "lexisScores_" + difficulty.rawValue)
    }
    
    func allTimeScores() -> [ScoreEntry] {
        load(key: "lexisAllTimeScores")
    }
    
    func scores(for difficulty: Difficulty) -> [ScoreEntry] {
        load(key: "lexisScores_" + difficulty.rawValue)
    }
    
    private func save(_ entries: [ScoreEntry], key: String) {
        if let encoded = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }
    
    private func load(key: String) -> [ScoreEntry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([ScoreEntry].self, from: data) else {
            return []
        }
        return decoded
    }
}

// MARK: - Score Entry
struct ScoreEntry: Codable, Identifiable {
    var id = UUID()
    let score: Int
    let difficulty: Difficulty
    let wordsFound: Int
    let date: Date
}

// MARK: - Valid Word Checker
// Backed by a bundled dictionary file (lexis_dictionary.txt, derived from
// ENABLE1 — a well-established free/open general-English word list used in
// word games) rather than a small hand-typed word set. The earlier inline
// list only covered ~1,900 words and had real gaps (e.g. "rave" was
// missing despite being common), which broke the core "yellow = valid word"
// promise the whole game is built on. This loads ~105K words (3–9 letters,
// matching the board's realistic word lengths) at launch.
class WordValidator {
    static let shared = WordValidator()
    private var wordSet: Set<String> = []
    
    init() {
        loadWords()
    }
    
    private func loadWords() {
        guard let url = Bundle.main.url(forResource: "lexis_dictionary", withExtension: "txt"),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            // Fallback so the game never ships with zero valid words if the
            // resource somehow fails to bundle correctly — small but covers
            // the most common short words so play isn't completely broken.
            assertionFailure("lexis_dictionary.txt failed to load from the app bundle — check it's included in the target's Copy Bundle Resources build phase.")
            wordSet = ["the","and","for","are","one","cat","dog","run","word","play","game","rave","cave","gave"]
            return
        }
        
        let words = contents.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        wordSet = Set(words.filter { !$0.isEmpty }.map { $0.lowercased() })
    }
    
    func isValid(_ word: String) -> Bool {
        let lower = word.lowercased()
        return lower.count >= GameConstants.minWordLength && wordSet.contains(lower)
    }
}

// MARK: - Haptics
@MainActor
enum Haptics {
    static func light() {
        guard GameSettings.shared.hapticsEnabled else { return }
        #if canImport(UIKit)
        let gen = UIImpactFeedbackGenerator(style: .light)
        gen.impactOccurred()
        #endif
    }
    static func medium() {
        guard GameSettings.shared.hapticsEnabled else { return }
        #if canImport(UIKit)
        let gen = UIImpactFeedbackGenerator(style: .medium)
        gen.impactOccurred()
        #endif
    }
    static func success() {
        guard GameSettings.shared.hapticsEnabled else { return }
        #if canImport(UIKit)
        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(.success)
        #endif
    }
    static func warning() {
        guard GameSettings.shared.hapticsEnabled else { return }
        #if canImport(UIKit)
        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(.warning)
        #endif
    }
    static func error() {
        guard GameSettings.shared.hapticsEnabled else { return }
        #if canImport(UIKit)
        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(.error)
        #endif
    }
    static func rigid() {
        guard GameSettings.shared.hapticsEnabled else { return }
        #if canImport(UIKit)
        let gen = UIImpactFeedbackGenerator(style: .rigid)
        gen.impactOccurred()
        #endif
    }
    
    // A very soft tick used every time a piece naturally settles — meant to
    // be felt as rhythm during fast play rather than as an "event," so it
    // uses the lightest possible intensity rather than reusing .light()
    // (which is also used for movement feedback and would otherwise blur
    // together with it).
    static func tileLand() {
        guard GameSettings.shared.hapticsEnabled else { return }
        #if canImport(UIKit)
        let gen = UIImpactFeedbackGenerator(style: .soft)
        gen.impactOccurred(intensity: 0.5)
        #endif
    }
    
    // Scales in perceived intensity with combo depth, so a 5-chain feels
    // more emphatic than a 2-chain without needing a different call site
    // per combo tier.
    static func comboEscalation(_ comboCount: Int) {
        guard GameSettings.shared.hapticsEnabled else { return }
        #if canImport(UIKit)
        let gen = UIImpactFeedbackGenerator(style: comboCount >= 5 ? .heavy : .medium)
        let intensity = min(1.0, 0.5 + Double(comboCount) * 0.12)
        gen.impactOccurred(intensity: intensity)
        #endif
    }
}

// MARK: - Game Model
@MainActor
class GameModel: ObservableObject {
    @Published var grid: [[LetterTile?]] = Array(repeating: Array(repeating: nil, count: GameConstants.cols), count: GameConstants.rows)
    @Published var fallingLetter: Character = "A"
    @Published var fallingCol: Int = 3
    @Published var fallingRow: Int = 0
    @Published var isWildcard: Bool = false
    @Published var isBomb: Bool = false
    @Published var score: Int = 0
    @Published var level: Int = 1
    @Published var phase: GamePhase = .menu
    @Published var lastWordResult: WordResult? = nil
    @Published var comboCount: Int = 0
    @Published var highScore: Int = 0
    @Published var blocksDropped: Int = 0
    @Published var foundWords: [WordResult] = []
    @Published var shakeBoard: Bool = false
    @Published var dangerZoneActive: Bool = false
    @Published var bombsAvailable: Int = 0   // banked "clear path" charges the player can trigger manually
    @Published var justUsedBomb: Bool = false
    @Published var tipsAvailable: Int = 0    // banked "tip" charges: knock the top tile of a column sideways into a neighbor
    @Published var justUsedTip: Bool = false
    @Published var tipTargetCol: Int? = nil  // when non-nil, the player has selected a source column and is choosing a direction
    @Published var isStuck: Bool = false   // true when the falling letter has caught on a neighboring tile mid-air
    @Published var pendingWords: [WordResult] = [] // detected words glowing yellow, awaiting a double-tap to clear
    @Published var isDailyMode: Bool = false
    @Published var dailyLettersRemaining: Int = 0

    let settings = GameSettings.shared
    let dailyManager = DailyChallengeManager.shared
    private var dailySequence: [Character] = []
    private var dailySequenceIndex: Int = 0
    private var dailyWordsFoundList: [String] = []
    private var allTimeWordCount: Int {
        get { UserDefaults.standard.integer(forKey: "lexisAllTimeWordCount") }
        set { UserDefaults.standard.set(newValue, forKey: "lexisAllTimeWordCount") }
    }
    private var dropTimer: Timer?
    private let validator = WordValidator.shared
    private var letterBag: [Character] = []
    
    // Letter frequency (Scrabble-inspired distribution)
    private let letterPool: [Character] = {
        var pool: [Character] = []
        let freq: [(Character, Int)] = [
            ("E", 12), ("A", 9), ("I", 9), ("O", 8), ("N", 6), ("T", 6),
            ("R", 6), ("S", 6), ("L", 4), ("C", 4), ("D", 4), ("U", 4),
            ("M", 3), ("G", 3), ("H", 3), ("B", 2), ("F", 2), ("P", 2),
            ("W", 2), ("Y", 2), ("K", 2), ("V", 2), ("X", 1), ("Q", 1),
            ("J", 1), ("Z", 1)
        ]
        for (letter, count) in freq {
            pool.append(contentsOf: Array(repeating: letter, count: count))
        }
        return pool
    }()
    
    init() {
        highScore = settings.highScore(for: settings.difficulty)
        refillBag()
    }
    
    func startGame() {
        grid = Array(repeating: Array(repeating: nil, count: GameConstants.cols), count: GameConstants.rows)
        score = 0
        level = 1
        comboCount = 0
        blocksDropped = 0
        bombsAvailable = 0
        tipsAvailable = 0
        tipTargetCol = nil
        foundWords = []
        lastWordResult = nil
        isDailyMode = false
        highScore = settings.highScore(for: settings.difficulty)
        refillBag()
        spawnNewLetter()
        phase = .playing
        startDropTimer()
    }
    
    // MARK: - Daily Challenge
    // A fixed 40-letter sequence, identical for every player on a given
    // calendar day (seeded from the date). No wildcards or bombs — the
    // challenge is purely "how well can you use exactly these letters,"
    // so results are directly comparable between players, like Wordle.
    // The run ends either when the sequence is exhausted (success) or the
    // board fills before that happens (the daily "loss" state).
    func startDailyChallenge() {
        grid = Array(repeating: Array(repeating: nil, count: GameConstants.cols), count: GameConstants.rows)
        score = 0
        level = 1
        comboCount = 0
        blocksDropped = 0
        bombsAvailable = 0
        tipsAvailable = 0 // no power-ups in daily mode — every player faces the identical challenge
        tipTargetCol = nil
        foundWords = []
        lastWordResult = nil
        isDailyMode = true
        dailySequence = dailyManager.todaysLetterSequence()
        dailySequenceIndex = 0
        dailyWordsFoundList = []
        dailyLettersRemaining = dailySequence.count
        spawnNewLetter()
        phase = .playing
        startDropTimer()
    }
    
    func pauseGame() {
        phase = .paused
        dropTimer?.invalidate()
    }
    
    func resumeGame() {
        phase = .playing
        startDropTimer()
    }
    
    private func refillBag() {
        letterBag = letterPool.shuffled()
    }
    
    private func nextLetter() -> Character {
        if letterBag.isEmpty { refillBag() }
        return letterBag.removeLast()
    }
    
    private func spawnNewLetter() {
        blocksDropped += 1
        
        if isDailyMode {
            // Sequence exhausted with room still on the board — the player
            // has successfully completed today's challenge.
            if dailySequenceIndex >= dailySequence.count {
                completeDailyChallenge(survived: true)
                return
            }
            isWildcard = false
            isBomb = false
            fallingLetter = dailySequence[dailySequenceIndex]
            dailySequenceIndex += 1
            dailyLettersRemaining = dailySequence.count - dailySequenceIndex
        } else {
            let diff = settings.difficulty
            isWildcard = (blocksDropped % diff.wildcardInterval == 0)
            isBomb = !isWildcard && (blocksDropped % GameConstants.bombInterval == 0) && blocksDropped > 0
            if isBomb {
                fallingLetter = "✸"
            } else {
                fallingLetter = isWildcard ? "★" : nextLetter()
            }
        }
        
        fallingCol = GameConstants.cols / 2
        fallingRow = 0
        isStuck = false
        stuckTicksElapsed = 0
        
        // Check if spawn position is occupied -> game over
        if grid[0][fallingCol] != nil {
            if isDailyMode {
                completeDailyChallenge(survived: false)
            } else {
                triggerGameOver()
            }
            return
        }
        
        checkDangerZone()
    }
    
    private func completeDailyChallenge(survived: Bool) {
        dropTimer?.invalidate()
        dailyManager.recordResult(
            score: score,
            wordsFound: dailyWordsFoundList,
            blocksPlaced: blocksDropped,
            survived: survived
        )
        phase = .gameOver
        if survived {
            Haptics.success()
        } else {
            Haptics.error()
        }
    }
    
    private func checkDangerZone() {
        var danger = false
        for col in 0..<GameConstants.cols {
            for row in 0...GameConstants.dangerRow {
                if grid[row][col] != nil {
                    danger = true
                    break
                }
            }
        }
        if danger && !dangerZoneActive {
            Haptics.warning()
        }
        dangerZoneActive = danger
    }
    
    private func startDropTimer() {
        restartDropTimerForCurrentSpeed()
    }
    
    // Single source of truth for "what should the drop interval be right
    // now" — called both when starting a fresh drop and when soft-drop
    // engages/disengages, so the timer never has two competing owners.
    private func restartDropTimerForCurrentSpeed() {
        dropTimer?.invalidate()
        let interval: Double
        if isSoftDropping {
            interval = softDropInterval
        } else if isDailyMode {
            // Fixed, unhurried pace — the daily challenge tests word-finding
            // skill against a shared fixed letter set, not reflexes against
            // an escalating speed curve. Everyone should face the same
            // pressure level.
            interval = 1.6
        } else {
            let diff = settings.difficulty
            interval = max(diff.minDropInterval, diff.baseDropInterval - Double(level - 1) * diff.speedIncreasePerLevel)
        }
        dropTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.dropOneTick()
            }
        }
    }
    
    // MARK: - Movement (fixed: always re-validates against live grid state,
    // clamps to bounds, and gives haptic + rejection feedback so input never
    // feels unresponsive)
    
    // MARK: - Lateral adhesion ("sticking")
    // A falling letter sticks mid-air the moment it's dragged into direct
    // horizontal contact with an existing tile at the same row — as if it
    // snagged against the side of a tower. This is the mechanic that lets
    // players build words at height rather than only reading whatever lines
    // up after pure vertical stacking.
    private func checkForStick() {
        let leftNeighbor = fallingCol > 0 ? grid[fallingRow][fallingCol - 1] : nil
        let rightNeighbor = fallingCol < GameConstants.cols - 1 ? grid[fallingRow][fallingCol + 1] : nil
        let hasSupportBelow = (fallingRow + 1 >= GameConstants.rows) || (grid[fallingRow + 1][fallingCol] != nil)
        
        // Only stick if there's a lateral neighbor AND the cell below is still
        // open — if it's already resting on something, that's normal landing,
        // not sticking, so we don't want a redundant haptic/visual cue.
        let newStuck = (leftNeighbor != nil || rightNeighbor != nil) && !hasSupportBelow
        if newStuck && !isStuck {
            Haptics.rigid()
        }
        isStuck = newStuck
    }
    
    @discardableResult
    func moveLeft() -> Bool {
        guard phase == .playing else { return false }
        let newCol = fallingCol - 1
        guard newCol >= 0 else {
            Haptics.rigid() // bump feedback at the wall
            return false
        }
        guard grid[fallingRow][newCol] == nil else {
            Haptics.rigid()
            return false
        }
        fallingCol = newCol
        Haptics.light()
        checkForStick()
        return true
    }
    
    @discardableResult
    func moveRight() -> Bool {
        guard phase == .playing else { return false }
        let newCol = fallingCol + 1
        guard newCol < GameConstants.cols else {
            Haptics.rigid()
            return false
        }
        guard grid[fallingRow][newCol] == nil else {
            Haptics.rigid()
            return false
        }
        fallingCol = newCol
        Haptics.light()
        checkForStick()
        return true
    }
    
    func dropFast() {
        guard phase == .playing else { return }
        // If currently stuck to a neighbor, dropFast releases the stick and
        // lets the piece fall the rest of the way rather than instantly
        // placing at the stuck row — gives players an intentional "let go"
        // action rather than trapping them once they've grabbed on.
        if isStuck {
            isStuck = false
        }
        var targetRow = fallingRow
        while targetRow + 1 < GameConstants.rows && grid[targetRow + 1][fallingCol] == nil {
            targetRow += 1
        }
        fallingRow = targetRow
        Haptics.medium()
        placeLetter()
    }
    
    // MARK: - Soft drop
    // Dragging downward accelerates the fall rather than instantly slamming
    // to the bottom (that's dropFast/double-tap). This gives players a
    // middle gear: speed up when they're confident about the landing spot,
    // without committing to a full hard drop. Releasing the drag restores
    // normal timer-driven falling immediately.
    @Published var isSoftDropping: Bool = false
    private let softDropInterval: Double = 0.06 // fast, but not instant — still a readable fall
    
    func beginSoftDrop() {
        guard phase == .playing, !isSoftDropping else { return }
        isSoftDropping = true
        Haptics.light()
        restartDropTimerForCurrentSpeed()
    }
    
    func endSoftDrop() {
        guard isSoftDropping else { return }
        isSoftDropping = false
        restartDropTimerForCurrentSpeed()
    }
    
    // Manually trigger a banked "clear path" bomb: wipes the bottom N rows
    // of the current falling column, instantly creating breathing room.
    func triggerBankedBomb() {
        guard bombsAvailable > 0, phase == .playing else { return }
        bombsAvailable -= 1
        clearColumn(fallingCol)
        justUsedBomb = true
        Haptics.success()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            self.justUsedBomb = false
        }
    }
    
    private func clearColumn(_ col: Int) {
        for row in 0..<GameConstants.rows {
            grid[row][col] = nil
        }
        checkDangerZone()
    }
    
    // MARK: - Tip mechanic
    // A banked, limited-use action: relocate the topmost tile of a column
    // sideways onto the top of a neighboring column, purely to reveal
    // whatever word might now be readable underneath it. Unlike the bomb,
    // this doesn't destroy a tile — it's conserved and re-enters play, so
    // it's a tactical trade (reshuffle for a shot at a word) rather than a
    // free "get out of danger" card. Only the very top tile of a column is
    // eligible, and the destination must have room (its own top tile can't
    // already be at the topmost row).
    
    // Step 1: player selects which column's top tile they want to move.
    // Call this when they tap/long-press a top tile — it arms the tip and
    // waits for a direction choice.
    func selectTipSource(col: Int) {
        guard tipsAvailable > 0, phase == .playing else { return }
        guard topmostTileRow(in: col) != nil else { return } // nothing to tip in an empty column
        tipTargetCol = col
        Haptics.light()
    }
    
    func cancelTip() {
        tipTargetCol = nil
    }
    
    // Step 2: player chooses left or right. Moves the source column's top
    // tile onto the top of the destination column, if there's room.
    func confirmTip(direction: TipDirection) {
        guard tipsAvailable > 0, let sourceCol = tipTargetCol, phase == .playing else { return }
        let destCol = direction == .left ? sourceCol - 1 : sourceCol + 1
        guard destCol >= 0, destCol < GameConstants.cols else {
            Haptics.rigid()
            return
        }
        guard let sourceRow = topmostTileRow(in: sourceCol), var tile = grid[sourceRow][sourceCol] else {
            tipTargetCol = nil
            return
        }
        
        // Destination needs an open landing row — its current top tile
        // (or the floor) determines where the tipped tile settles.
        let destLandingRow = topmostTileRow(in: destCol).map { $0 - 1 } ?? (GameConstants.rows - 1)
        guard destLandingRow >= 0 else {
            Haptics.rigid() // destination column is already full to the ceiling
            return
        }
        
        tipsAvailable -= 1
        grid[sourceRow][sourceCol] = nil
        tile.row = destLandingRow
        tile.col = destCol
        grid[destLandingRow][destCol] = tile
        tipTargetCol = nil
        justUsedTip = true
        Haptics.success()
        
        // Tipping can reveal or complete a word both in the column the
        // tile left (now shorter) and the column it landed in — check both.
        markGlowingWords()
        checkDangerZone()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            self.justUsedTip = false
        }
    }
    
    private func topmostTileRow(in col: Int) -> Int? {
        for row in 0..<GameConstants.rows {
            if grid[row][col] != nil { return row }
        }
        return nil
    }
    
    // The letter currently armed for tipping, for UI display in the
    // direction-picker prompt.
    var tipSourceLetter: Character? {
        guard let col = tipTargetCol, let row = topmostTileRow(in: col) else { return nil }
        return grid[row][col]?.letter
    }
    
    private var stuckTicksElapsed: Int = 0
    private let stuckGracePeriodTicks = 2 // how many drop-ticks a stuck piece clings before locking permanently
    
    private func dropOneTick() {
        guard phase == .playing else { return }
        
        if isStuck {
            // A stuck piece doesn't fall — it clings for a short grace window,
            // giving the player a beat to nudge it further along the tower or
            // deliberately drop-release it, before it locks in place for good.
            stuckTicksElapsed += 1
            if stuckTicksElapsed >= stuckGracePeriodTicks {
                stuckTicksElapsed = 0
                isStuck = false
                placeLetter()
            }
            return
        }
        
        stuckTicksElapsed = 0
        let nextRow = fallingRow + 1
        if nextRow >= GameConstants.rows || grid[nextRow][fallingCol] != nil {
            placeLetter()
        } else {
            fallingRow = nextRow
            checkForStick()
        }
    }
    
    private func placeLetter() {
        isStuck = false
        stuckTicksElapsed = 0
        
        // Bomb tiles clear their landing column instead of becoming a permanent tile
        if isBomb {
            clearColumn(fallingCol)
            Haptics.success()
            level = max(1, blocksDropped / 15 + 1)
            checkDangerZone()
            spawnNewLetter()
            startDropTimer()
            return
        }
        
        // Place tile on grid
        let tile = LetterTile(
            letter: fallingLetter,
            row: fallingRow,
            col: fallingCol,
            isWildcard: isWildcard,
            age: blocksDropped
        )
        grid[fallingRow][fallingCol] = tile
        Haptics.tileLand() // a subtle tick every time a piece settles, for rhythm
        
        // Update level
        level = max(1, blocksDropped / 15 + 1)
        
        // Detect words: they now glow yellow rather than auto-clearing, so
        // the player gets to see and choose which ones to bank via a
        // double-tap — turns word-finding into a deliberate, satisfying
        // action instead of something that just happens to you.
        markGlowingWords()
        
        checkDangerZone()
        spawnNewLetter()
        startDropTimer()
    }
    
    // Scans the board, marks every tile that's part of a detected word with
    // a glowingWordID, and refreshes `pendingWords` for the UI to render the
    // yellow glow + await a double-tap.
    private func markGlowingWords() {
        let words = findAllWords()
        
        // Clear old glow markers first
        for row in 0..<GameConstants.rows {
            for col in 0..<GameConstants.cols {
                grid[row][col]?.glowingWordID = nil
            }
        }
        
        pendingWords = words
        for word in words {
            for tile in word.tiles {
                grid[tile.row][tile.col]?.glowingWordID = word.id
            }
        }
        
        if !words.isEmpty {
            Haptics.light() // a soft confirm pulse when a word lights up, distinct from the success chime on actual clear
        }
    }
    
    // MARK: - Word Detection
    // Direction rules (deliberately asymmetric, not "any direction" —
    // this makes the board more readable and predictable to learn):
    //   • Horizontal: left-to-right ONLY. Reading right-to-left does not
    //     count, so players can't accidentally spell backwards nonsense
    //     and have it register.
    //   • Vertical: BOTH directions count — top-to-bottom and bottom-to-
    //     top — since a column a player builds upward should still let
    //     them read the word top-down, and one they build reading up
    //     should also work.
    //   • Diagonals: forward-only (top-left→bottom-right and
    //     top-right→bottom-left), matching the horizontal "no backwards"
    //     rule for consistency.
    func findAllWords() -> [WordResult] {
        var results: [WordResult] = []
        var usedPositions = Set<String>()
        
        // Horizontal runs: left-to-right only
        for row in 0..<GameConstants.rows {
            var col = 0
            while col < GameConstants.cols {
                guard grid[row][col] != nil else { col += 1; continue }
                var tiles: [LetterTile] = []
                var c = col
                while c < GameConstants.cols, let tile = grid[row][c] {
                    tiles.append(tile)
                    c += 1
                }
                checkSubstrings(of: tiles, results: &results, usedPositions: &usedPositions)
                col = c
            }
        }
        
        // Vertical runs: both top-to-bottom and bottom-to-top count
        for col in 0..<GameConstants.cols {
            var row = 0
            while row < GameConstants.rows {
                guard grid[row][col] != nil else { row += 1; continue }
                var tiles: [LetterTile] = []
                var r = row
                while r < GameConstants.rows, let tile = grid[r][col] {
                    tiles.append(tile)
                    r += 1
                }
                checkSubstrings(of: tiles, results: &results, usedPositions: &usedPositions)
                checkSubstrings(of: tiles.reversed(), results: &results, usedPositions: &usedPositions)
                row = r
            }
        }
        
        // Diagonal runs, top-left to bottom-right (forward-only)
        for startRow in 0..<GameConstants.rows {
            for startCol in 0..<GameConstants.cols {
                var tiles: [LetterTile] = []
                var r = startRow, c = startCol
                while r < GameConstants.rows && c < GameConstants.cols, let tile = grid[r][c] {
                    tiles.append(tile)
                    r += 1; c += 1
                }
                if tiles.count >= GameConstants.minWordLength {
                    checkSubstrings(of: tiles, results: &results, usedPositions: &usedPositions)
                }
            }
        }
        
        // Diagonal runs, top-right to bottom-left (forward-only)
        for startRow in 0..<GameConstants.rows {
            for startCol in 0..<GameConstants.cols {
                var tiles: [LetterTile] = []
                var r = startRow, c = startCol
                while r < GameConstants.rows && c >= 0, let tile = grid[r][c] {
                    tiles.append(tile)
                    r += 1; c -= 1
                }
                if tiles.count >= GameConstants.minWordLength {
                    checkSubstrings(of: tiles, results: &results, usedPositions: &usedPositions)
                }
            }
        }
        
        return results
    }
    
    // Scans every contiguous substring of a tile run (in the order given)
    // for dictionary matches, appending any new hits to results.
    // Scans every contiguous substring of a tile run for dictionary
    // matches. When a shorter valid word is fully contained within a
    // longer valid word found in the same run (e.g. "END" inside
    // "REVEREND"), only the longer word is kept — the shorter one is
    // suppressed entirely rather than also being offered as a separate,
    // smaller clear. This matches the rule that players get maximum value
    // from a run rather than being tempted to grab a small win early.
    private func checkSubstrings(of tiles: [LetterTile], results: inout [WordResult], usedPositions: inout Set<String>) {
        guard tiles.count >= GameConstants.minWordLength else { return }
        
        // First pass: collect every valid (word, tileRange) match in this
        // run, without filtering yet.
        struct Candidate {
            let word: String
            let range: Range<Int> // index range within `tiles`
        }
        var candidates: [Candidate] = []
        
        for start in 0..<tiles.count {
            var word = ""
            for i in start..<tiles.count {
                word.append(tiles[i].letter)
                if word.count >= GameConstants.minWordLength && validator.isValid(word) {
                    candidates.append(Candidate(word: word, range: start..<(i + 1)))
                }
            }
        }
        
        guard !candidates.isEmpty else { return }
        
        // Second pass: drop any candidate whose tile range is fully
        // contained within a strictly longer candidate's range. A range is
        // "contained" if it starts at-or-after and ends at-or-before the
        // longer one — this covers both same-start extensions (EN -> END)
        // and shifted containment (END inside REVEREND).
        let survivors = candidates.filter { candidate in
            !candidates.contains { other in
                other.range.count > candidate.range.count &&
                other.range.lowerBound <= candidate.range.lowerBound &&
                other.range.upperBound >= candidate.range.upperBound
            }
        }
        
        for candidate in survivors {
            let run = Array(tiles[candidate.range])
            let key = run.map { "\($0.row),\($0.col)" }.sorted().joined()
            if !usedPositions.contains(key) {
                results.append(WordResult(word: candidate.word, tiles: run, score: calculateScore(candidate.word), isChain: false))
                usedPositions.insert(key)
            }
        }
    }
    
    // MARK: - Manual word tap detection
    func checkTapWord(at positions: [(row: Int, col: Int)]) -> WordResult? {
        var word = ""
        var tiles: [LetterTile] = []
        for pos in positions {
            guard let tile = grid[pos.row][pos.col] else { return nil }
            word.append(tile.letter)
            tiles.append(tile)
        }
        if validator.isValid(word) {
            return WordResult(word: word, tiles: tiles, score: calculateScore(word), isChain: false)
        }
        return nil
    }
    
    private func calculateScore(_ word: String) -> Int {
        let baseScore = word.count * word.count * 10 // quadratic: longer = much better
        let comboMultiplier = max(1, comboCount)
        let levelMultiplier = level
        let difficultyMultiplier = settings.difficulty.scoreMultiplier
        return Int(Double(baseScore * comboMultiplier * levelMultiplier) * difficultyMultiplier)
    }
    
    private func processWords(_ words: [WordResult]) {
        comboCount += 1
        
        var totalScore = 0
        for word in words {
            totalScore += word.score
            // Animate clearing
            for tile in word.tiles {
                grid[tile.row][tile.col] = nil
            }
            foundWords.insert(word, at: 0)
            if foundWords.count > 10 { foundWords.removeLast() }
            if isDailyMode {
                dailyWordsFoundList.append(word.word)
            }
        }
        
        score += totalScore
        if !isDailyMode, score > highScore {
            highScore = score
            settings.setHighScore(highScore, for: settings.difficulty)
        }
        
        lastWordResult = words.first
        Haptics.success()
        
        // Longer words (5+) bank a "clear path" bomb charge as a reward,
        // giving players an escape hatch when things get tight later.
        if let longest = words.map({ $0.word.count }).max(), longest >= 5 {
            bombsAvailable = min(3, bombsAvailable + 1)
        }
        
        // Chained combos (3+ in a row) bank a Tip charge instead — this
        // rewards tempo and reading the board ahead, distinct from the
        // vocabulary-driven bomb reward above.
        if comboCount >= 3 && comboCount % 3 == 0 {
            tipsAvailable = min(3, tipsAvailable + 1)
        }
        
        // Track lifetime words for Game Center achievements
        for word in words {
            allTimeWordCount += 1
            AchievementTracker.onWordFound(word: word.word, totalWordsThisSession: foundWords.count, allTimeWordCount: allTimeWordCount)
        }
        AchievementTracker.onCombo(comboCount)
        
        // Remove the words we just cleared from the pending/glowing set
        let clearedIDs = Set(words.map { $0.id })
        pendingWords.removeAll { clearedIDs.contains($0.id) }
        
        // Apply gravity after clearing
        applyGravity()
        checkDangerZone()
        
        // Chain reactions: gravity can reveal new words automatically. These
        // also glow rather than auto-clearing, so a big cascade still gives
        // the player a beat to see and confirm each wave rather than the
        // board exploding on its own.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.markGlowingWords()
        }
        
        // Shake board for big combos
        if comboCount >= 3 {
            shakeBoard = true
            Haptics.comboEscalation(comboCount)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.shakeBoard = false
            }
        }
    }
    
    private func applyGravity() {
        for col in 0..<GameConstants.cols {
            var tiles: [LetterTile] = []
            for row in 0..<GameConstants.rows {
                if let tile = grid[row][col] {
                    tiles.append(tile)
                }
            }
            // Clear column
            for row in 0..<GameConstants.rows {
                grid[row][col] = nil
            }
            // Restack from bottom
            for (i, var tile) in tiles.reversed().enumerated() {
                let newRow = GameConstants.rows - 1 - i
                tile.row = newRow
                grid[newRow][col] = tile
            }
        }
    }
    
    private func triggerGameOver() {
        phase = .gameOver
        dropTimer?.invalidate()
        Haptics.error()
        settings.recordScore(score, difficulty: settings.difficulty, wordsFound: foundWords.count)
        AchievementTracker.onGameOver(score: score, difficulty: settings.difficulty, blocksDropped: blocksDropped)
    }
    
    // MARK: - Wildcard selection
    func selectWildcardLetter(_ letter: Character) {
        if isWildcard {
            fallingLetter = letter
            isWildcard = false
        }
    }
    
    // Picks 5 candidate letters for the wildcard picker: prioritizes common,
    // useful letters that are either completely absent from the board or
    // have the lowest current count on it. This makes the wildcard actually
    // useful for unblocking a stuck board (giving you a letter you're
    // missing) rather than just repeating whatever's already plentiful.
    func wildcardCandidates() -> [Character] {
        // A pool of generally useful letters to draw from, roughly ordered
        // by how often they show up in real words — biases the "smart"
        // selection toward letters that are actually likely to complete a
        // word, not obscure ones just because they're rare on the board.
        let usefulPool: [Character] = ["E","A","R","I","O","T","N","S","L","C",
                                        "U","D","G","B","H","M","P","Y","F","W"]
        
        var boardCounts: [Character: Int] = [:]
        for row in grid {
            for tile in row {
                guard let tile = tile else { continue }
                boardCounts[tile.letter, default: 0] += 1
            }
        }
        
        // Sort by (count on board ascending, then pool order) so absent
        // letters (count 0) come first, and among equally-absent letters
        // the more generally useful ones win.
        let sorted = usefulPool.enumerated().sorted { lhs, rhs in
            let lhsCount = boardCounts[lhs.element] ?? 0
            let rhsCount = boardCounts[rhs.element] ?? 0
            if lhsCount != rhsCount { return lhsCount < rhsCount }
            return lhs.offset < rhs.offset
        }
        
        return Array(sorted.prefix(5).map { $0.element })
    }
    
    // MARK: - Double-tap to clear a glowing word
    // Called when the player double-taps a tile. Only tiles currently
    // glowing (part of a detected, not-yet-banked word) respond — tapping
    // a non-glowing tile does nothing, since there's nothing to confirm.
    func doubleTapClear(row: Int, col: Int) {
        guard let wordID = grid[row][col]?.glowingWordID else { return }
        guard let word = pendingWords.first(where: { $0.id == wordID }) else { return }
        processWords([word])
    }
    
    // Check if any valid words exist on board (for hint system)
    func hasAnyWords() -> Bool {
        return !findAllWords().isEmpty
    }
}

enum WordDirection {
    case horizontal, vertical
}

enum TipDirection {
    case left, right
}
