import SwiftUI

// MARK: - Cosmetics (sprint: expressive categories)
//
// Beyond tile themes, LEXIS now has cosmetics you SEE constantly: the
// clear-burst effect fired on every word clear, and (see BoardBackdrop) the
// backdrop behind the grid. They're earned with coins (or, for the exclusive
// one, by playing the weekly event) — the same earn-or-unlock economy as
// themes. Ownership lives in CosmeticsStore, keyed by each item's `cosmeticID`.

/// The particle shape a burst flings out.
enum BurstShape {
    case shard      // small rounded rectangle (the original look)
    case circle     // soft dot
    case spark      // thin bright line
    case petal      // tall rounded flake
}

/// The effect played where each tile of a cleared word was — the most-seen
/// cosmetic in the game.
enum BurstStyle: String, CaseIterable, Codable, Identifiable {
    case shards     // default — the original shard fling
    case embers     // glowing dots that rise and fade
    case sparks     // bright thin lines flung outward
    case petals     // soft flakes drifting out and down
    case bloom      // event-exclusive: a bright expanding ring of dots

    var id: String { rawValue }
    var cosmeticID: String { "burst.\(rawValue)" }

    var displayName: String {
        switch self {
        case .shards: return "Shards"
        case .embers: return "Embers"
        case .sparks: return "Sparks"
        case .petals: return "Petals"
        case .bloom:  return "Bloom"
        }
    }

    var isDefault: Bool { self == .shards }
    /// Earnable only by playing a weekly event — never coin-buyable.
    var isEventExclusive: Bool { self == .bloom }
    var coinPrice: Int {
        switch self {
        case .shards: return 0
        case .embers: return 150
        case .sparks: return 200
        case .petals: return 200
        case .bloom:  return 0   // event-only
        }
    }

    // MARK: rendering parameters
    var count: Int {
        switch self {
        case .shards: return 6
        case .embers: return 7
        case .sparks: return 8
        case .petals: return 6
        case .bloom:  return 12
        }
    }
    var shape: BurstShape {
        switch self {
        case .shards: return .shard
        case .embers: return .circle
        case .sparks: return .spark
        case .petals: return .petal
        case .bloom:  return .circle
        }
    }
    /// How far particles fly, as a multiple of tile size.
    var spread: CGFloat {
        switch self {
        case .shards: return 1.15
        case .embers: return 0.7
        case .sparks: return 1.5
        case .petals: return 1.0
        case .bloom:  return 1.3
        }
    }
    /// Extra vertical drift at the end (negative = rise). Multiple of tile size.
    var drift: CGFloat {
        switch self {
        case .embers: return -0.8   // rise
        case .petals: return 0.5    // settle down
        default:      return 0
        }
    }
    var spin: Double {
        switch self {
        case .shards: return 140
        case .petals: return 90
        default:      return 0
        }
    }
    /// When nil, the burst uses the cleared word's colour; otherwise this
    /// fixed palette (cycled per particle).
    var palette: [Color]? {
        switch self {
        case .embers: return [Color(red: 1.0, green: 0.55, blue: 0.2), Color(red: 1.0, green: 0.8, blue: 0.3)]
        case .petals: return [Color(red: 1.0, green: 0.5, blue: 0.7), Color(red: 0.7, green: 0.5, blue: 1.0)]
        default:      return nil
        }
    }
}
