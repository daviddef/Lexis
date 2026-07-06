import Foundation
import SwiftUI

// MARK: - Seeded RNG
// A simple deterministic PRNG (splitmix64) so every player worldwide gets
// byte-for-byte the same letter sequence on a given calendar day. Swift's
// built-in RandomNumberGenerator is not guaranteed reproducible across
// versions/platforms, so we can't rely on seeding Int.random(in:using:)
// long-term — this hand-rolled generator is small, fast, and stable forever.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    
    init(seed: UInt64) {
        self.state = seed
    }
    
    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

// MARK: - Daily Challenge Result
struct DailyResult: Codable {
    let dateKey: String          // "yyyy-MM-dd", the puzzle this result belongs to
    let score: Int
    let wordsFound: [String]
    let longestWord: String
    let blocksPlaced: Int
    let completedAt: Date
    let survived: Bool           // false if the board filled before the letter sequence ran out
}

// MARK: - Daily Challenge Manager
@MainActor
class DailyChallengeManager: ObservableObject {
    static let shared = DailyChallengeManager()
    
    @Published var todayResult: DailyResult? = nil
    @Published var currentStreak: Int = 0
    @Published var bestStreak: Int = 0
    @Published var totalDaysPlayed: Int = 0
    
    // The daily puzzle is a fixed-length letter sequence (rather than
    // endless falling like normal mode) so every player faces an identical,
    // finite challenge — the mode is "how well can you use exactly these
    // 40 letters" rather than "how long can you survive."
    static let dailySequenceLength = 40
    
    private let calendar = Calendar(identifier: .gregorian)
    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone.current // local midnight reset, matching how players think about "today"
        return df
    }()
    
    private init() {
        loadState()
    }
    
    // MARK: - Date keying
    var todayKey: String {
        dateFormatter.string(from: Date())
    }
    
    private func seed(for dateKey: String) -> UInt64 {
        // Stable hash of the date string into a 64-bit seed. FNV-1a is
        // simple, deterministic, and has no platform-dependent behavior.
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in dateKey.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
    
    // MARK: - Puzzle generation
    // Returns today's deterministic letter sequence, generated the same way
    // real Scrabble-style bags are weighted so the puzzle feels fair rather
    // than randomly ASCII-uniform.
    func todaysLetterSequence() -> [Character] {
        sequence(for: todayKey)
    }
    
    func sequence(for dateKey: String) -> [Character] {
        var rng = SeededGenerator(seed: seed(for: dateKey))
        let freq: [(Character, Int)] = [
            ("E", 12), ("A", 9), ("I", 9), ("O", 8), ("N", 6), ("T", 6),
            ("R", 6), ("S", 6), ("L", 4), ("C", 4), ("D", 4), ("U", 4),
            ("M", 3), ("G", 3), ("H", 3), ("B", 2), ("F", 2), ("P", 2),
            ("W", 2), ("Y", 2), ("K", 2), ("V", 2), ("X", 1), ("Q", 1),
            ("J", 1), ("Z", 1)
        ]
        var pool: [Character] = []
        for (letter, count) in freq {
            pool.append(contentsOf: Array(repeating: letter, count: count))
        }
        pool.shuffle(using: &rng)
        
        var result: [Character] = []
        var poolIndex = 0
        while result.count < Self.dailySequenceLength {
            if poolIndex >= pool.count {
                pool.shuffle(using: &rng)
                poolIndex = 0
            }
            result.append(pool[poolIndex])
            poolIndex += 1
        }
        return result
    }
    
    // MARK: - Completion state
    var hasCompletedToday: Bool {
        todayResult?.dateKey == todayKey
    }
    
    func recordResult(score: Int, wordsFound: [String], blocksPlaced: Int, survived: Bool) {
        let longest = wordsFound.max(by: { $0.count < $1.count }) ?? ""
        let result = DailyResult(
            dateKey: todayKey,
            score: score,
            wordsFound: wordsFound,
            longestWord: longest,
            blocksPlaced: blocksPlaced,
            completedAt: Date(),
            survived: survived
        )
        todayResult = result
        updateStreak(for: result)
        saveState()
    }
    
    private func updateStreak(for result: DailyResult) {
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()) else { return }
        let yesterdayKey = dateFormatter.string(from: yesterday)
        let lastPlayedKey = UserDefaults.standard.string(forKey: "lexisDailyLastPlayedKey")
        
        if lastPlayedKey == yesterdayKey {
            currentStreak += 1
        } else if lastPlayedKey != result.dateKey {
            currentStreak = 1
        }
        
        bestStreak = max(bestStreak, currentStreak)
        totalDaysPlayed += 1
        UserDefaults.standard.set(result.dateKey, forKey: "lexisDailyLastPlayedKey")
    }
    
    // MARK: - Share card
    func shareText(for result: DailyResult) -> String {
        let scoreTier: String
        switch result.score {
        case 0..<500: scoreTier = "🟫"
        case 500..<1500: scoreTier = "🟨"
        case 1500..<3000: scoreTier = "🟩"
        default: scoreTier = "🟪"
        }
        
        let survivalEmoji = result.survived ? "✅" : "💥"
        let wordCountBlocks = String(repeating: "🟩", count: min(result.wordsFound.count, 10))
        
        return """
        LEXIS \(result.dateKey) \(survivalEmoji)
        Score: \(result.score) \(scoreTier)
        Words found: \(result.wordsFound.count)
        Longest: \(result.longestWord.uppercased())
        \(wordCountBlocks)
        
        Play LEXIS — one letter at a time.
        """
    }
    
    // MARK: - Persistence
    private func saveState() {
        if let result = todayResult, let encoded = try? JSONEncoder().encode(result) {
            UserDefaults.standard.set(encoded, forKey: "lexisDailyResult_\(result.dateKey)")
        }
        UserDefaults.standard.set(currentStreak, forKey: "lexisDailyCurrentStreak")
        UserDefaults.standard.set(bestStreak, forKey: "lexisDailyBestStreak")
        UserDefaults.standard.set(totalDaysPlayed, forKey: "lexisDailyTotalDaysPlayed")
    }
    
    private func loadState() {
        currentStreak = UserDefaults.standard.integer(forKey: "lexisDailyCurrentStreak")
        bestStreak = UserDefaults.standard.integer(forKey: "lexisDailyBestStreak")
        totalDaysPlayed = UserDefaults.standard.integer(forKey: "lexisDailyTotalDaysPlayed")
        
        if let data = UserDefaults.standard.data(forKey: "lexisDailyResult_\(todayKey)"),
           let decoded = try? JSONDecoder().decode(DailyResult.self, from: data) {
            todayResult = decoded
        }
        
        if let lastPlayedKey = UserDefaults.standard.string(forKey: "lexisDailyLastPlayedKey"),
           lastPlayedKey != todayKey {
            if let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()) {
                let yesterdayKey = dateFormatter.string(from: yesterday)
                if lastPlayedKey != yesterdayKey {
                    currentStreak = 0
                    saveState()
                }
            }
        }
    }
}
