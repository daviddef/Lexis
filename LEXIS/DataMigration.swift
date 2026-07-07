import Foundation

// MARK: - Persistence versioning & migration (launch hardening)
//
// All save data lives in flat UserDefaults keys. That's fine until a future
// update needs to rename a key or change a value's shape — at which point,
// with no version stamp, old data is silently misread or lost. This adds the
// missing anchor: a schema version and an ordered migration runner.
//
// Run ONCE, synchronously, at the very start of launch — before any manager
// (GameSettings, DailyChallengeManager, PlayerProfile, …) reads its defaults —
// so migrations always see the old shape before anyone consumes it.
//
// There are no transformations yet: today's flat keys ARE schema v1. The
// value is the framework — future releases add a `case` here instead of
// risking players' streaks, coins, and high scores.
enum DataMigration {
    /// Bump this whenever a migration step is added below.
    static let currentVersion = 1
    private static let versionKey = "lexisSchemaVersion"

    static func runIfNeeded() {
        let defaults = UserDefaults.standard
        // 0 when never set — i.e. a pre-versioning install (or a fresh one).
        let stored = defaults.integer(forKey: versionKey)
        guard stored < currentVersion else { return }

        var version = stored
        while version < currentVersion {
            migrate(from: version)
            version += 1
        }
        defaults.set(currentVersion, forKey: versionKey)
    }

    /// Apply the single step that moves data from `version` to `version + 1`.
    private static func migrate(from version: Int) {
        switch version {
        case 0:
            // 0 → 1: adopt the existing flat keys as the v1 baseline. Existing
            // installs already hold valid v1 data, so there's nothing to
            // transform — we only need to stamp the version (done by caller).
            break
        default:
            break
        }
    }
}
