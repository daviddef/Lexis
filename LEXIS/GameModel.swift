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

// A board coordinate. Small Equatable value so the view can observe "which
// cell just took an impact" via onChange.
struct GridPos: Equatable {
    let row: Int
    let col: Int
}

// MARK: - Word Result
struct WordResult: Identifiable, Equatable {
    let id = UUID()
    let word: String
    let tiles: [LetterTile]
    let score: Int
    let isChain: Bool
}

// MARK: - Bomb blast
// A one-shot marker that a bomb just detonated in `col`. The unique id lets
// the view restart its explosion animation even when two bombs go off in
// the same column back to back.
struct BombBlast: Equatable {
    let id = UUID()
    let col: Int
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
    static let cols = 9
    // 14 rows (not 16): with the control chrome (header + word strip) inside
    // the safe area, a 16-row board is taller than the screen can show at
    // full tile width, so it gets shrunk to fit height — leaving side gaps
    // and "wasted" horizontal space. 14 rows lets the board fill edge to
    // edge at full tile width instead.
    static let rows = 14
    // 3-letter minimum in every direction. 2-letter words were tried but
    // felt like noise — too many trivial clears lighting up, and they cheapen
    // the "find a real word" payoff. Diagonals were already 3+ (a 2-letter
    // diagonal reads as an unrelated tile glowing); now the whole board is.
    static let minWordLength = 3
    static let minDiagonalWordLength = 3
    static let dangerRow = 2
    static let bombInterval = 25
    static let dynamiteInterval = 18
    static let diagonalScoreMultiplier = 1.25
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
    // User-facing "Reduce Motion" toggle. The effective state (see
    // `motionReduced`) is this OR the system-wide accessibility setting, so a
    // player who's turned it on system-wide gets the calm experience without
    // touching our toggle, while anyone can also opt in just for LEXIS.
    @Published var reduceMotion: Bool {
        didSet { UserDefaults.standard.set(reduceMotion, forKey: "lexisReduceMotion") }
    }
    @Published var tileTheme: TileTheme {
        didSet { UserDefaults.standard.set(tileTheme.rawValue, forKey: "lexisTileTheme") }
    }
    @Published var hasSeenTutorial: Bool {
        didSet { UserDefaults.standard.set(hasSeenTutorial, forKey: "lexisHasSeenTutorial") }
    }

    private init() {
        let savedDiff = UserDefaults.standard.string(forKey: "lexisDifficulty") ?? Difficulty.classic.rawValue
        self.difficulty = Difficulty(rawValue: savedDiff) ?? .classic
        self.hapticsEnabled = UserDefaults.standard.object(forKey: "lexisHaptics") as? Bool ?? true
        self.soundEnabled = UserDefaults.standard.object(forKey: "lexisSound") as? Bool ?? true
        self.colorBlindMode = UserDefaults.standard.object(forKey: "lexisColorBlind") as? Bool ?? false
        self.showGhostPiece = UserDefaults.standard.object(forKey: "lexisGhost") as? Bool ?? true
        self.largeText = UserDefaults.standard.object(forKey: "lexisLargeText") as? Bool ?? false
        self.reduceMotion = UserDefaults.standard.object(forKey: "lexisReduceMotion") as? Bool ?? false
        let savedTheme = UserDefaults.standard.string(forKey: "lexisTileTheme") ?? TileTheme.classic.rawValue
        self.tileTheme = TileTheme(rawValue: savedTheme) ?? .classic
        self.hasSeenTutorial = UserDefaults.standard.object(forKey: "lexisHasSeenTutorial") as? Bool ?? false

        // Republish when the SYSTEM reduce-motion setting flips mid-session so
        // views recompute `motionReduced` live. Our own toggle already drives
        // @Published updates.
        #if canImport(UIKit)
        NotificationCenter.default.addObserver(
            forName: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.objectWillChange.send() }
        }
        #endif
    }

    /// Effective "reduce motion" state: the player's in-app toggle OR the
    /// system-wide accessibility setting. All decorative/ambient animation
    /// added in the UI-uplift roadmap checks this and either freezes on a
    /// static frame or drops to an instant, non-animated state change.
    var motionReduced: Bool {
        #if canImport(UIKit)
        return reduceMotion || UIAccessibility.isReduceMotionEnabled
        #else
        return reduceMotion
        #endif
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
    // A heavy thud for big, physical events (bomb detonation). Full-intensity
    // impact — meatier than medium/rigid.
    static func heavy() {
        guard GameSettings.shared.hapticsEnabled else { return }
        #if canImport(UIKit)
        let gen = UIImpactFeedbackGenerator(style: .heavy)
        gen.impactOccurred(intensity: 1.0)
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
    // Identity of the current falling piece + the interval it's descending
    // at — the view uses these to glide the piece down at fall speed (a new
    // id on spawn stops the glide from animating up from the last landing).
    @Published var fallingPieceID = UUID()
    @Published var currentDropInterval: Double = 1.0
    @Published var isWildcard: Bool = false
    @Published var isBomb: Bool = false
    @Published var isDynamite: Bool = false   // explodes on landing, removing just the one tile it hits (not the whole column)
    // A genuine lookahead at what's coming after the current piece — drawn
    // from the bag (or the daily sequence) without consuming it. The header
    // preview used to just redundantly show the CURRENT falling letter,
    // which is already visible on the board; this is what actually lets a
    // player plan a word around what's coming next, the way a "next piece"
    // preview does in any falling-block game.
    @Published var upcomingLetter: Character = "A"
    @Published var upcomingIsWildcard: Bool = false
    @Published var upcomingIsBomb: Bool = false
    @Published var upcomingIsDynamite: Bool = false
    @Published var score: Int = 0
    @Published var level: Int = 1
    @Published var phase: GamePhase = .menu
    @Published var lastWordResult: WordResult? = nil
    @Published var perfectClear: Bool = false   // toggled briefly when a clear happens to empty the whole board
    @Published var perfectClearBonus: Int = 0
    @Published var comboCount: Int = 0
    // blocksDropped at the last combo-counted clear. Used to decide whether
    // the NEXT clear continues the streak or starts a fresh one — see
    // comboDecayBlockWindow below.
    private var lastComboBlockCount: Int = 0
    // If more pieces than this drop between one clear and the next, the
    // combo resets instead of continuing — this is what makes "×N COMBO!"
    // an actual hot streak the player has to protect by keeping up tempo,
    // rather than a number that only ever climbs for the rest of the run.
    private let comboDecayBlockWindow = 3
    @Published var highScore: Int = 0
    @Published var blocksDropped: Int = 0
    @Published var foundWords: [WordResult] = []
    @Published var shakeBoard: Bool = false
    // The cell a player-dropped piece just locked into — the view squashes
    // that one tile on impact. Only set for real landings (not gravity
    // settles), so the "thunk" reads as the piece you just placed.
    @Published var lastLandedCell: GridPos? = nil
    // Non-nil for ~0.8s right after a bomb detonates, so the view can play a
    // one-shot explosion burst at the detonation column. Carries a fresh id
    // each time so back-to-back bombs each re-trigger the animation.
    @Published var bombBlast: BombBlast? = nil
    @Published var dangerZoneActive: Bool = false
    @Published var bombsAvailable: Int = 0   // banked "clear path" charges the player can trigger manually
    @Published var justUsedBomb: Bool = false
    @Published var tipsAvailable: Int = 0    // banked "tip" charges: knock the top tile of a column sideways into a neighbor
    @Published var justUsedTip: Bool = false
    @Published var isStuck: Bool = false   // true when the falling letter has caught on a neighboring tile mid-air
    @Published var pendingWords: [WordResult] = [] // detected words glowing yellow, awaiting a double-tap to clear
    @Published var isDailyMode: Bool = false
    @Published var dailyLettersRemaining: Int = 0
    // Duel mode reuses the exact same fixed-sequence machinery as Daily
    // Challenge (dailySequence/dailySequenceIndex below) — the only real
    // difference is the seed key is a shareable code instead of today's
    // date, and completion doesn't touch the real daily streak/leaderboard.
    @Published var isDuelMode: Bool = false
    @Published var duelCode: String = ""
    @Published var duelResult: (code: String, score: Int, wordsFound: [String])? = nil
    // True for either fixed-sequence mode — used wherever the gating is
    // "no power-ups / fixed pace because everyone must face identical
    // letters," which applies the same way to both Daily and Duel.
    private var isSequenceMode: Bool { isDailyMode || isDuelMode }

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

    // MARK: - First-run tutorial
    // The menu's "how to play" bullets and the Settings guide are good
    // reference material, but a brand-new player still has to translate
    // words into the actual drag/double-tap motions themselves — that gap
    // is where most casual-game first sessions are lost. Rather than more
    // text, the very first run scripts the opening few letters to
    // guarantee an easy word lands in whatever column the player leaves
    // the piece in (i.e. even if they never touch the screen), so the
    // "aha, it glowed" moment happens on its own, with a couple of small
    // tooltips guiding the two motions that matter.
    @Published var isTutorialActive: Bool = false
    @Published var tutorialStep: Int = 0 // 0: "drag to steer" / 1: "double-tap to clear"
    private var tutorialLetterQueue: [Character] = []
    
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
        lastComboBlockCount = 0
        blocksDropped = 0
        bombsAvailable = 0
        tipsAvailable = 0
        utilityCharges = 0
        isFrozen = false
        peekLetters = []
        foundWords = []
        pendingWords = []
        lastWordResult = nil
        isDailyMode = false
        isDuelMode = false
        highScore = settings.highScore(for: settings.difficulty)
        refillBag()

        // First-run tutorial: force an easy, guaranteed-to-glow word into
        // whatever column the player leaves the piece in, so the "aha, it
        // glowed" moment happens even if they never touch the screen.
        if !settings.hasSeenTutorial {
            isTutorialActive = true
            tutorialStep = 0
            tutorialLetterQueue = ["C", "A", "T"]
        } else {
            isTutorialActive = false
            tutorialLetterQueue = []
        }

        spawnNewLetter()
        phase = .playing
        startDropTimer()
        gameStartDate = Date()
        Analytics.shared.gameStart(mode: "endless", difficulty: settings.difficulty.rawValue)
    }

    // Wall-clock start of the current run, for the game_over duration metric.
    private var gameStartDate = Date()

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
        lastComboBlockCount = 0
        blocksDropped = 0
        bombsAvailable = 0
        tipsAvailable = 0 // no power-ups in daily mode — every player faces the identical challenge
        utilityCharges = 0
        isFrozen = false
        peekLetters = []
        foundWords = []
        pendingWords = []
        lastWordResult = nil
        isDailyMode = true
        isDuelMode = false
        isTutorialActive = false
        tutorialLetterQueue = []
        dailySequence = dailyManager.todaysLetterSequence()
        dailySequenceIndex = 0
        dailyWordsFoundList = []
        dailyLettersRemaining = dailySequence.count
        spawnNewLetter()
        phase = .playing
        startDropTimer()
        gameStartDate = Date()
        Analytics.shared.gameStart(mode: "daily", difficulty: settings.difficulty.rawValue)
    }

    // MARK: - Duel
    // Async head-to-head: two players play the identical letter sequence
    // (keyed by a shareable code instead of a date) and compare scores
    // afterward — no server needed, since DailyChallengeManager's seeded
    // generator is already fully deterministic from any string key.
    func startDuel(code: String) {
        grid = Array(repeating: Array(repeating: nil, count: GameConstants.cols), count: GameConstants.rows)
        score = 0
        level = 1
        comboCount = 0
        lastComboBlockCount = 0
        blocksDropped = 0
        bombsAvailable = 0
        tipsAvailable = 0 // no power-ups — both players must face identical letters
        utilityCharges = 0
        isFrozen = false
        peekLetters = []
        foundWords = []
        pendingWords = []
        lastWordResult = nil
        isDailyMode = false
        isDuelMode = true
        isTutorialActive = false
        tutorialLetterQueue = []
        duelCode = code
        duelResult = nil
        dailySequence = dailyManager.sequence(for: code)
        dailySequenceIndex = 0
        dailyWordsFoundList = []
        dailyLettersRemaining = dailySequence.count
        spawnNewLetter()
        phase = .playing
        startDropTimer()
        gameStartDate = Date()
        Analytics.shared.gameStart(mode: "duel", difficulty: settings.difficulty.rawValue)
    }

    private func completeDuel(survived: Bool) {
        dropTimer?.invalidate()
        duelResult = (code: duelCode, score: score, wordsFound: dailyWordsFoundList)
        phase = .gameOver
        Analytics.shared.gameOver(mode: "duel", difficulty: settings.difficulty.rawValue,
                                  score: score, level: level, words: dailyWordsFoundList.count,
                                  durationSec: Int(Date().timeIntervalSince(gameStartDate)), survived: survived)
        if survived {
            Haptics.success()
        } else {
            Haptics.error()
            SoundManager.gameOver()
        }
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
        if !tutorialLetterQueue.isEmpty {
            return tutorialLetterQueue.removeFirst()
        }
        if letterBag.isEmpty { refillBag() }
        return letterBag.removeLast()
    }
    
    private func spawnNewLetter() {
        blocksDropped += 1

        if isSequenceMode {
            // Sequence exhausted with room still on the board — the player
            // has successfully completed the challenge (today's Daily
            // puzzle, or the other player's Duel sequence).
            if dailySequenceIndex >= dailySequence.count {
                if isDuelMode {
                    completeDuel(survived: true)
                } else {
                    completeDailyChallenge(survived: true)
                }
                return
            }
            isWildcard = false
            isBomb = false
            isDynamite = false
            fallingLetter = dailySequence[dailySequenceIndex]
            dailySequenceIndex += 1
            dailyLettersRemaining = dailySequence.count - dailySequenceIndex
        } else {
            let diff = settings.difficulty
            isWildcard = (blocksDropped % diff.wildcardInterval == 0)
            isBomb = !isWildcard && (blocksDropped % GameConstants.bombInterval == 0) && blocksDropped > 0
            isDynamite = !isWildcard && !isBomb && (blocksDropped % GameConstants.dynamiteInterval == 0) && blocksDropped > 0
            if isBomb {
                fallingLetter = "✸"
            } else if isDynamite {
                fallingLetter = "🧨"
            } else {
                fallingLetter = isWildcard ? "★" : nextLetter()
            }
        }
        
        fallingCol = GameConstants.cols / 2
        fallingRow = 0
        isStuck = false
        stuckTicksElapsed = 0
        fallingPieceID = UUID() // fresh identity so the glide overlay appears
                                // at the top rather than sliding up from the
                                // previous piece's landing spot.

        // Check if spawn position is occupied -> game over
        if grid[0][fallingCol] != nil {
            if isDuelMode {
                completeDuel(survived: false)
            } else if isDailyMode {
                completeDailyChallenge(survived: false)
            } else {
                triggerGameOver()
            }
            return
        }

        checkDangerZone()
        updateUpcomingPreview()
    }

    // Computes what the NEXT spawn (after this one) will be, without
    // actually consuming it from the bag/sequence. Mirrors the same
    // isWildcard/isBomb/isDynamite priority order as spawnNewLetter() so the
    // preview never shows a state that couldn't actually occur.
    private func updateUpcomingPreview() {
        if isSequenceMode {
            if dailySequenceIndex < dailySequence.count {
                upcomingLetter = dailySequence[dailySequenceIndex]
            }
            upcomingIsWildcard = false
            upcomingIsBomb = false
            upcomingIsDynamite = false
            return
        }
        let nextBlockCount = blocksDropped + 1
        let diff = settings.difficulty
        upcomingIsWildcard = (nextBlockCount % diff.wildcardInterval == 0)
        upcomingIsBomb = !upcomingIsWildcard && (nextBlockCount % GameConstants.bombInterval == 0) && nextBlockCount > 0
        upcomingIsDynamite = !upcomingIsWildcard && !upcomingIsBomb && (nextBlockCount % GameConstants.dynamiteInterval == 0) && nextBlockCount > 0
        if upcomingIsBomb {
            upcomingLetter = "✸"
        } else if upcomingIsDynamite {
            upcomingLetter = "🧨"
        } else if upcomingIsWildcard {
            upcomingLetter = "★"
        } else {
            if letterBag.isEmpty { refillBag() }
            upcomingLetter = letterBag.last ?? "A"
        }
    }
    
    private func completeDailyChallenge(survived: Bool) {
        dropTimer?.invalidate()
        dailyManager.recordResult(
            score: score,
            wordsFound: dailyWordsFoundList,
            blocksPlaced: blocksDropped,
            survived: survived
        )
        GameCenterManager.shared.submitDailyScore(score)
        phase = .gameOver
        Analytics.shared.gameOver(mode: "daily", difficulty: settings.difficulty.rawValue,
                                  score: score, level: level, words: dailyWordsFoundList.count,
                                  durationSec: Int(Date().timeIntervalSince(gameStartDate)), survived: survived)
        Analytics.shared.dailyComplete(survived: survived, score: score, streak: dailyManager.currentStreak)
        if survived {
            Haptics.success()
        } else {
            Haptics.error()
            SoundManager.gameOver()
        }
    }

    // How much of the danger zone is actually filled, 0...1 — drives an
    // escalating vignette in the view layer rather than the single static
    // "you're in danger, full stop" banner this used to be. A board with
    // one column brushing the danger zone should feel very different from
    // one with every column crowding it.
    @Published var dangerSeverity: Double = 0

    // Escalation tiers for the danger zone: 0 safe, 1 entered, 2 mounting
    // (half the danger row crowded), 3 critical. Crossing UP a tier re-fires
    // the warning cue, so the dread deepens as the board fills rather than
    // firing once and going quiet.
    private var lastDangerTier = 0

    private func checkDangerZone() {
        var occupiedCols = 0
        for col in 0..<GameConstants.cols {
            for row in 0...GameConstants.dangerRow {
                if grid[row][col] != nil {
                    occupiedCols += 1
                    break
                }
            }
        }
        let danger = occupiedCols > 0
        let severity = Double(occupiedCols) / Double(GameConstants.cols)
        let tier = occupiedCols == 0 ? 0 : (severity >= 0.75 ? 3 : (severity >= 0.5 ? 2 : 1))
        if tier > lastDangerTier {
            Haptics.warning()
            SoundManager.dangerPulse(tier: tier) // lower + louder as it climbs
        }
        lastDangerTier = tier
        dangerZoneActive = danger
        dangerSeverity = severity
    }
    
    private func startDropTimer() {
        restartDropTimerForCurrentSpeed()
    }
    
    // Single source of truth for "what should the drop interval be right
    // now" — called both when starting a fresh drop and when soft-drop
    // engages/disengages, so the timer never has two competing owners.
    private func restartDropTimerForCurrentSpeed() {
        dropTimer?.invalidate()
        // A Freeze charge in effect always wins — anything else that tries
        // to restart the timer mid-freeze (soft-drop engaging, a new drag)
        // just leaves it stopped. Only the freeze-expiry callback in
        // useFreeze(), which clears isFrozen first, actually restarts it.
        guard !isFrozen else { return }
        let interval: Double
        if isSoftDropping {
            interval = softDropInterval
        } else if isSequenceMode {
            // Fixed, unhurried pace — a fixed-sequence mode tests word-
            // finding skill against a shared fixed letter set, not reflexes
            // against an escalating speed curve. Everyone comparing results
            // should face the same pressure level.
            interval = 1.6
        } else {
            let diff = settings.difficulty
            interval = max(diff.minDropInterval, diff.baseDropInterval - Double(level - 1) * diff.speedIncreasePerLevel)
        }
        currentDropInterval = interval // drives the visual glide speed
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
    // Not a fixed constant — updateSoftDropSpeed(velocity:) rewrites this
    // continuously while the drag is active, so the fall speed tracks how
    // fast the player is actually dragging rather than snapping to one
    // fixed fast speed the instant a downward drag is detected.
    private static let softDropIntervalRange = (lowerBound: 0.02, upperBound: 0.16)
    private var softDropInterval: Double = GameModel.softDropIntervalRange.upperBound
    // The drag velocity (points/sec) at which soft drop reaches its fastest
    // interval. Tuned empirically against tileSize-scale drag distances.
    private static let softDropReferenceVelocity: Double = 900

    func beginSoftDrop() {
        guard phase == .playing, !isSoftDropping else { return }
        isSoftDropping = true
        softDropInterval = Self.softDropIntervalRange.upperBound
        Haptics.light()
        restartDropTimerForCurrentSpeed()
    }

    func endSoftDrop() {
        guard isSoftDropping else { return }
        isSoftDropping = false
        restartDropTimerForCurrentSpeed()
    }

    // Called continuously while the player's drag stays vertical-dominant,
    // so the drop tick interval tracks their current swipe speed instead of
    // jumping straight to one fixed "fast" rate the moment soft-drop
    // engages.
    func updateSoftDropSpeed(velocity: Double) {
        guard isSoftDropping else { return }
        let clamped = min(1, max(0, abs(velocity) / Self.softDropReferenceVelocity))
        let range = Self.softDropIntervalRange
        let newInterval = range.upperBound - (range.upperBound - range.lowerBound) * clamped
        guard abs(newInterval - softDropInterval) > 0.004 else { return } // avoid restarting the timer every pixel
        softDropInterval = newInterval
        restartDropTimerForCurrentSpeed()
    }
    
    // Manually trigger a banked "clear path" bomb: wipes the bottom N rows
    // of the current falling column, instantly creating breathing room.
    func triggerBankedBomb() {
        guard bombsAvailable > 0, phase == .playing else { return }
        bombsAvailable -= 1
        Analytics.shared.powerUpUsed("bomb")
        triggerBombBlast(col: fallingCol)
        clearColumn(fallingCol)
        justUsedBomb = true
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

    // Fires the explosion juice for a bomb detonation in `col`: a one-shot
    // burst marker the view animates, a heavy board shake, a chunky haptic,
    // and the power-up chime. Kept separate from clearColumn so the banked
    // bomb and the falling-bomb-tile path share identical feedback.
    private func triggerBombBlast(col: Int) {
        let blast = BombBlast(col: col)
        bombBlast = blast
        shakeBoard = true
        Haptics.heavy()
        SoundManager.explosion()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            self.shakeBoard = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
            if self.bombBlast?.id == blast.id { self.bombBlast = nil }
        }
    }

    // Centralized so every placeLetter() branch (bomb, dynamite, normal
    // tile) awards a utility charge the same way on level-up, instead of
    // each branch recomputing `level` independently with no shared payoff.
    private func updateLevel() {
        let newLevel = max(1, blocksDropped / 15 + 1)
        if newLevel > level && !isSequenceMode { // no power-ups in fixed-sequence modes — see startDailyChallenge()/startDuel()
            utilityCharges = min(3, utilityCharges + 1)
        }
        level = newLevel
    }

    // MARK: - Utility power-ups (Freeze / Reroll / Peek)
    // Bomb rewards vocabulary (5+ letter words) and Tip rewards tempo
    // (chained combos) — utilityCharges is a third currency, earned simply
    // by leveling up, spendable on whichever of three different problems is
    // actually bothering the player right now rather than forcing three
    // separate meters for three fairly small conveniences.
    @Published var utilityCharges: Int = 0
    @Published var isFrozen: Bool = false
    @Published var peekLetters: [Character] = []

    // Freeze: pause the drop timer for a few seconds — a breather to think,
    // not an escape from a bad board (the board itself doesn't change).
    func useFreeze() {
        guard utilityCharges > 0, phase == .playing, !isFrozen else { return }
        utilityCharges -= 1
        isFrozen = true
        dropTimer?.invalidate()
        Haptics.success()
        SoundManager.powerUp()
        Analytics.shared.powerUpUsed("freeze")
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            guard self.phase == .playing else { return }
            self.isFrozen = false
            self.restartDropTimerForCurrentSpeed()
        }
    }

    // Reroll: swap the current falling letter for a fresh draw — the letter
    // itself is the problem here (dead weight for the board you've built),
    // not the board state, so this doesn't touch the grid at all.
    func useReroll() {
        guard utilityCharges > 0, phase == .playing, !isWildcard, !isBomb, !isDynamite else { return }
        utilityCharges -= 1
        fallingLetter = nextLetter()
        Haptics.success()
        SoundManager.powerUp()
        Analytics.shared.powerUpUsed("reroll")
    }

    // Peek: briefly reveal the 2 letters after the very next one (which is
    // already always visible via upcomingLetter) — for a player weighing
    // whether to finish a word now or wait for something better.
    func usePeek() {
        guard utilityCharges > 0, phase == .playing, peekLetters.isEmpty else { return }
        utilityCharges -= 1
        // Peeking this deep can require refilling the bag early to have
        // enough letters to show — safe, since refillBag() is just a
        // reshuffle and doesn't change what's already queued to be drawn.
        // nextLetter() draws from the END of the bag, so the letter drawn
        // 2nd-from-now sits at count-2 and 3rd-from-now at count-3 —
        // dropLast() removes the already-visible upcomingLetter (count-1),
        // and reversed() puts what's left back into draw order.
        while letterBag.count < 3 { refillBag() }
        peekLetters = Array(letterBag.suffix(3).dropLast().reversed())
        Haptics.success()
        SoundManager.powerUp()
        Analytics.shared.powerUpUsed("peek")
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            self.peekLetters = []
        }
    }


    // MARK: - Tip mechanic ("knock")
    // A banked, limited-use action: relocate the topmost tile of a column
    // sideways onto the top of a neighboring column, purely to reveal
    // whatever word might now be readable underneath it. Unlike the bomb,
    // this doesn't destroy a tile — it's conserved and re-enters play, so
    // it's a tactical trade (reshuffle for a shot at a word) rather than a
    // free "get out of danger" card. Only the very top tile of a column is
    // eligible, and the destination must have room (its own top tile can't
    // already be at the topmost row).
    //
    // This used to be a two-step tap-to-arm-then-choose-a-side flow with an
    // intermediate confirmation panel. Players expected a single direct
    // motion — swipe the tile off the stack and it falls down that side —
    // so it's now one atomic call triggered by a swipe gesture on the tile
    // itself (see the per-tile gesture in GameView.swift).
    func knockTile(col: Int, direction: TipDirection) {
        guard phase == .playing else { return }
        guard tipsAvailable > 0 else {
            Haptics.rigid() // this tile IS knockable, just no charge banked to spend
            SoundManager.reject()
            return
        }
        let destCol = direction == .left ? col - 1 : col + 1
        guard destCol >= 0, destCol < GameConstants.cols else {
            Haptics.rigid()
            SoundManager.reject()
            return
        }
        guard let sourceRow = topmostTileRow(in: col), var tile = grid[sourceRow][col] else {
            return
        }

        // Destination needs an open landing row — its current top tile
        // (or the floor) determines where the knocked tile settles.
        let destLandingRow = topmostTileRow(in: destCol).map { $0 - 1 } ?? (GameConstants.rows - 1)
        guard destLandingRow >= 0 else {
            Haptics.rigid() // destination column is already full to the ceiling
            SoundManager.reject()
            return
        }

        tipsAvailable -= 1
        grid[sourceRow][col] = nil
        tile.row = destLandingRow
        tile.col = destCol
        grid[destLandingRow][destCol] = tile
        justUsedTip = true
        Haptics.success()
        SoundManager.powerUp()
        Analytics.shared.powerUpUsed("tip")

        // Knocking can reveal or complete a word both in the column the
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
            // Deliberately NOT calling checkForStick() here. Sticking should
            // only ever be triggered by the player actively steering into a
            // neighbor (moveLeft/moveRight already call it) — not merely by
            // natural vertical fall carrying the piece past a tile that
            // happens to be at the same row in an adjacent column.
            fallingRow = nextRow
        }
    }
    
    private func placeLetter() {
        isStuck = false
        stuckTicksElapsed = 0
        
        // Bomb tiles clear their landing column instead of becoming a permanent tile
        if isBomb {
            triggerBombBlast(col: fallingCol)
            clearColumn(fallingCol)
            updateLevel()
            checkDangerZone()
            spawnNewLetter()
            startDropTimer()
            return
        }

        // Dynamite detonates on the single tile it lands on, removing just
        // that one tile (not the whole column, unlike the bomb) — surgical
        // rather than sweeping. It's consumed either way, even if it reaches
        // the floor without hitting anything.
        if isDynamite {
            let hitRow = fallingRow + 1
            if hitRow < GameConstants.rows, grid[hitRow][fallingCol] != nil {
                grid[hitRow][fallingCol] = nil
                Haptics.success()
                SoundManager.powerUp()
                applyGravity() // let whatever was stacked above the removed tile settle down
                markGlowingWords() // the shifted stack can reveal or complete a word
            } else {
                Haptics.rigid() // fizzled — nothing below to detonate
            }
            updateLevel()
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
        lastLandedCell = GridPos(row: fallingRow, col: fallingCol) // squash this tile on impact
        Haptics.tileLand() // a subtle tick every time a piece settles, for rhythm
        SoundManager.tileLand()

        updateLevel()

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

        if isTutorialActive && tutorialStep == 0 && !words.isEmpty {
            tutorialStep = 1 // "it's glowing — double-tap it to clear"
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
    // Accepts an optional grid so callers can check a hypothetical board
    // state (e.g. "what if this tile got knocked over there?") without
    // mutating the real grid — see suggestedKnock() below. `grid` shadows
    // the instance property of the same name for the rest of this function,
    // so the body needs no other changes to search whichever grid was passed.
    func findAllWords(in grid: [[LetterTile?]]? = nil) -> [WordResult] {
        let grid = grid ?? self.grid
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
                if tiles.count >= GameConstants.minDiagonalWordLength {
                    checkSubstrings(of: tiles, results: &results, usedPositions: &usedPositions, scoreMultiplier: GameConstants.diagonalScoreMultiplier, minLength: GameConstants.minDiagonalWordLength)
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
                if tiles.count >= GameConstants.minDiagonalWordLength {
                    checkSubstrings(of: tiles, results: &results, usedPositions: &usedPositions, scoreMultiplier: GameConstants.diagonalScoreMultiplier, minLength: GameConstants.minDiagonalWordLength)
                }
            }
        }

        // Final cross-run suppression pass. checkSubstrings() only suppresses
        // a short word in favor of a longer one WITHIN the same run — but a
        // vertical run is scanned twice, once forward and once reversed, as
        // two independent calls. That let a short reversed-direction word
        // (e.g. "EH") survive even when a longer forward word ("HERE") on
        // those exact tiles should have taken priority, since each call's
        // containment check never saw the other call's candidates. Drop any
        // word whose tile set is fully covered by a strictly longer word's
        // tile set, regardless of which run or direction produced either one.
        let survivors = results.filter { candidate in
            let candidateKeys = Set(candidate.tiles.map { "\($0.row),\($0.col)" })
            return !results.contains { other in
                guard other.id != candidate.id else { return false }
                let otherKeys = Set(other.tiles.map { "\($0.row),\($0.col)" })
                return otherKeys.count > candidateKeys.count && candidateKeys.isSubset(of: otherKeys)
            }
        }

        return survivors
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
    // scoreMultiplier rewards directions that are harder to spot — diagonals
    // pass this at 1.25 (see findAllWords) since there's otherwise no
    // mechanical reason to hunt for a diagonal over an easier horizontal or
    // vertical read.
    private func checkSubstrings(of tiles: [LetterTile], results: inout [WordResult], usedPositions: inout Set<String>, scoreMultiplier: Double = 1.0, minLength: Int = GameConstants.minWordLength) {
        guard tiles.count >= minLength else { return }

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
                if word.count >= minLength && validator.isValid(word) {
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
                let score = Int(Double(calculateScore(candidate.word)) * scoreMultiplier)
                results.append(WordResult(word: candidate.word, tiles: run, score: score, isChain: false))
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
        // Quadratic in length — longer words are worth much more than a
        // string of short ones. (Words are 3+ letters now; the old
        // flat-rate discount for 2-letter words is gone with them.)
        let baseScore = word.count * word.count * 10
        let comboMultiplier = max(1, comboCount)
        let levelMultiplier = level
        let difficultyMultiplier = settings.difficulty.scoreMultiplier
        return Int(Double(baseScore * comboMultiplier * levelMultiplier) * difficultyMultiplier)
    }
    
    private func processWords(_ words: [WordResult]) {
        if isTutorialActive {
            // The player just cleared their first word — the loop has been
            // demonstrated, so the tutorial is done and never runs again.
            isTutorialActive = false
            settings.hasSeenTutorial = true
            Analytics.shared.tutorialComplete()
        }

        if blocksDropped - lastComboBlockCount <= comboDecayBlockWindow {
            comboCount += 1
        } else {
            comboCount = 1
        }
        lastComboBlockCount = blocksDropped

        var totalScore = 0
        for word in words {
            totalScore += word.score
            // Animate clearing
            for tile in word.tiles {
                grid[tile.row][tile.col] = nil
            }
            foundWords.insert(word, at: 0)
            if foundWords.count > 10 { foundWords.removeLast() }
            if isSequenceMode {
                dailyWordsFoundList.append(word.word)
            }
        }

        score += totalScore
        if !isSequenceMode, score > highScore {
            highScore = score
            settings.setHighScore(highScore, for: settings.difficulty)
        }
        
        lastWordResult = words.first
        Haptics.success()
        SoundManager.wordClear(length: words.map { $0.word.count }.max() ?? 3)
        Analytics.shared.wordCleared(maxLen: words.map { $0.word.count }.max() ?? 3,
                                     isChain: words.contains { $0.isChain }, comboCount: comboCount)


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

        // Invalidate glow state immediately rather than waiting for the
        // cascade-reveal rescan below. Without this, grid markers and
        // pendingWords keep referencing pre-gravity tile positions for the
        // full 0.3s gap — a double-tap landing in that window could resolve
        // to a stale WordResult and delete whatever tile gravity happened
        // to shift into those old coordinates, not the tiles the player
        // actually tapped.
        for row in 0..<GameConstants.rows {
            for col in 0..<GameConstants.cols {
                grid[row][col]?.glowingWordID = nil
            }
        }
        pendingWords = []

        checkDangerZone()

        // Perfect Clear: the clear we just processed happened to empty the
        // entire board. Rare, skill-adjacent (usually only happens when a
        // player has been deliberately shaping the board), and worth a
        // distinct, unmistakable celebration rather than blending into a
        // normal word-clear — borrowed from Tetris's "All Clear" and Puyo
        // Puyo, which reward emptying the board as its own achievement.
        if grid.allSatisfy({ row in row.allSatisfy { $0 == nil } }) {
            let bonus = 500 * level
            score += bonus
            if !isSequenceMode, score > highScore {
                highScore = score
                settings.setHighScore(highScore, for: settings.difficulty)
            }
            perfectClearBonus = bonus
            perfectClear = true
            Haptics.success()
            SoundManager.fanfare()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                self.perfectClear = false
            }
        }


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
            SoundManager.comboEscalation(comboCount)
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
            // Restack from bottom. Dropping any leftover glowingWordID here
            // matters: a tile carrying a stale glow marker to its new
            // position would let a double-tap resolve to a WordResult whose
            // tile coordinates gravity has since reassigned to different
            // letters — the exact bug where a clear removed/left the wrong
            // tiles. Whatever glow state applies post-shift gets
            // recomputed by the next markGlowingWords() call.
            for (i, var tile) in tiles.reversed().enumerated() {
                let newRow = GameConstants.rows - 1 - i
                tile.row = newRow
                tile.glowingWordID = nil
                grid[newRow][col] = tile
            }
        }
    }
    
    private func triggerGameOver() {
        phase = .gameOver
        dropTimer?.invalidate()
        Haptics.error()
        SoundManager.gameOver()
        settings.recordScore(score, difficulty: settings.difficulty, wordsFound: foundWords.count)
        AchievementTracker.onGameOver(score: score, difficulty: settings.difficulty, blocksDropped: blocksDropped)
        Analytics.shared.gameOver(mode: "endless", difficulty: settings.difficulty.rawValue,
                                  score: score, level: level, words: foundWords.count,
                                  durationSec: Int(Date().timeIntervalSince(gameStartDate)))
    }

    // A Wordle-style recap for an Endless run — DailyChallengeManager
    // already builds one of these for Daily Challenge, but that was the
    // ONLY mode with any way to share a result at all. A great Insane-mode
    // run deserved the same, not just one of five modes.
    func endlessShareText() -> String {
        let longest = foundWords.map { $0.word }.max(by: { $0.count < $1.count }) ?? ""
        var lines = [
            "LEXIS — \(settings.difficulty.rawValue.uppercased())",
            "Score: \(score)",
            "Words: \(foundWords.count)" + (longest.isEmpty ? "" : " (longest: \(longest.uppercased()))"),
            "Level \(level)"
        ]
        lines.append("")
        lines.append("Play LEXIS — one letter at a time.")
        return lines.joined(separator: "\n")
    }
    
    // MARK: - Wildcard selection
    func selectWildcardLetter(_ letter: Character) {
        if isWildcard {
            fallingLetter = letter
            isWildcard = false
            SoundManager.powerUp()
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
    
    // Every pending word whose tiles include this cell. A tile can be part
    // of more than one pending word at once (e.g. an intersecting
    // horizontal and vertical word sharing a letter), but
    // markGlowingWords() only stamps ONE glowingWordID per tile — whichever
    // word was marked last wins that stamp. Resolving a tap through that
    // single ID meant it only ever found one of the words touching a
    // shared tile. Shared by doubleTapClear (clears all matches) and the
    // single-tap word-info preview (shows all matches).
    func pendingWords(at row: Int, col: Int) -> [WordResult] {
        pendingWords.filter { word in
            word.tiles.contains { $0.row == row && $0.col == col }
        }
    }

    // MARK: - Double-tap to clear a glowing word
    // Called when the player double-taps a tile. Only tiles currently
    // glowing (part of a detected, not-yet-banked word) respond — tapping
    // a non-glowing tile does nothing, since there's nothing to confirm.
    func doubleTapClear(row: Int, col: Int) {
        let matches = pendingWords(at: row, col: col)
        guard !matches.isEmpty else { return }
        processWords(matches)
    }
    
    // MARK: - Hint
    // Every findable word already glows automatically the instant it
    // appears (see markGlowingWords()), so a hint that just re-scanned the
    // current board would tell the player nothing they can't already see.
    // The genuinely useful hint is the opposite case: the board LOOKS dead
    // (nothing glowing), but knocking some top tile sideways would reveal a
    // word. This simulates every possible knock against a copy of the grid
    // and, if one would work, flags that tile for a few seconds.
    @Published var hintTargetCol: Int? = nil
    @Published var hintDirection: TipDirection? = nil

    func requestHint() {
        guard phase == .playing else { return }
        guard pendingWords.isEmpty else {
            // Something's already glowing — nothing new to suggest, just
            // acknowledge the tap so it doesn't feel ignored.
            Haptics.light()
            return
        }
        guard let suggestion = suggestedKnock() else {
            Haptics.rigid() // no knock would reveal anything right now
            SoundManager.reject()
            return
        }
        hintTargetCol = suggestion.col
        hintDirection = suggestion.direction
        Haptics.success()
        SoundManager.powerUp()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            self.hintTargetCol = nil
            self.hintDirection = nil
        }
    }

    private func suggestedKnock() -> (col: Int, direction: TipDirection)? {
        guard tipsAvailable > 0 else { return nil } // the suggestion wouldn't be actionable anyway
        for col in 0..<GameConstants.cols {
            guard topmostTileRow(in: col) != nil else { continue }
            for direction in [TipDirection.left, .right] {
                if wouldKnockRevealWord(col: col, direction: direction) {
                    return (col, direction)
                }
            }
        }
        return nil
    }

    private func wouldKnockRevealWord(col: Int, direction: TipDirection) -> Bool {
        let destCol = direction == .left ? col - 1 : col + 1
        guard destCol >= 0, destCol < GameConstants.cols else { return false }
        guard let sourceRow = topmostTileRow(in: col), let tile = grid[sourceRow][col] else { return false }
        let destLandingRow = topmostTileRow(in: destCol).map { $0 - 1 } ?? (GameConstants.rows - 1)
        guard destLandingRow >= 0 else { return false }

        var simulatedGrid = grid
        simulatedGrid[sourceRow][col] = nil
        var movedTile = tile
        movedTile.row = destLandingRow
        movedTile.col = destCol
        simulatedGrid[destLandingRow][destCol] = movedTile

        return !findAllWords(in: simulatedGrid).isEmpty
    }
}

enum WordDirection {
    case horizontal, vertical
}

enum TipDirection {
    case left, right
}
