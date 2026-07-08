import Foundation

// MARK: - iCloud progress sync (launch hardening)
//
// Backs up the player's PROGRESS to iCloud's key-value store so a reinstall or
// a new device recovers it — no account, no server. This is a backup+restore
// model (not live multi-device merge, which a single-player game doesn't need):
//
//   • At launch (synchronously, before any manager reads UserDefaults) we
//     reconcile local ↔ cloud. Monotonic "best" values take the max so they
//     never regress; owned-cosmetic sets take the union; everything else is
//     last-device-wins (restore from cloud only if we have nothing locally,
//     otherwise push local up as the backup).
//   • On backgrounding we push the current values to iCloud.
//   • An external change (cloud data arriving after a fresh install) is merged
//     into UserDefaults and takes effect on the next launch.
//
// Requires the iCloud key-value entitlement (see project.yml). Without it,
// NSUbiquitousKeyValueStore simply no-ops, so this stays harmless until the
// capability is enabled.

// Not @MainActor: it must run synchronously in LexisApp.init (before any
// manager reads UserDefaults), and it only touches UserDefaults and
// NSUbiquitousKeyValueStore, both of which are thread-safe.
final class CloudSync: @unchecked Sendable {
    static let shared = CloudSync()

    private let kv = NSUbiquitousKeyValueStore.default
    private let ud = UserDefaults.standard

    // Monotonically-increasing "best" numbers → take max (never regress).
    private let maxKeys = [
        "lexisTotalXP", "lexisAllTimeWordCount", "lexisDailyBestStreak",
        "lexisHighScore_Relaxed", "lexisHighScore_Classic",
        "lexisHighScore_Rapid", "lexisHighScore_Insane"
    ]
    // Owned-cosmetic sets → union (never lose an unlock).
    private let unionKeys = ["lexisPurchasedThemes", "lexisSeenUnlockedThemes"]
    // Mutable state → restore from cloud only if missing locally, else push
    // local up (last active device wins).
    private let lastWinsKeys = [
        "lexisCoins", "lexisTileTheme", "lexisEquippedBurst", "lexisEquippedBackdrop",
        "lexisAllTimeScores", "lexisScores_Relaxed", "lexisScores_Classic",
        "lexisScores_Rapid", "lexisScores_Insane",
        "lexisDailyCurrentStreak", "lexisDailyTotalDaysPlayed", "lexisDailyLastPlayedKey"
    ]

    private init() {}

    /// Reconcile once, synchronously. Call at the very start of launch.
    func startAndReconcile() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(cloudChangedExternally),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: kv)
        kv.synchronize()
        reconcile()
    }

    /// Push current local values to iCloud (call on backgrounding).
    func pushToCloud() {
        reconcile()
    }

    @objc private func cloudChangedExternally(_ note: Notification) {
        reconcile()
    }

    private func reconcile() {
        for k in maxKeys {
            let local = ud.object(forKey: k) != nil ? ud.integer(forKey: k) : Int.min
            let cloud = kv.object(forKey: k) != nil ? Int(kv.longLong(forKey: k)) : Int.min
            let best = max(local, cloud)
            guard best != Int.min else { continue }
            if best != ud.integer(forKey: k) { ud.set(best, forKey: k) }
            kv.set(Int64(best), forKey: k)
        }
        for k in unionKeys {
            let local = Set(ud.stringArray(forKey: k) ?? [])
            let cloud = Set((kv.array(forKey: k) as? [String]) ?? [])
            let union = local.union(cloud)
            if union != local { ud.set(Array(union), forKey: k) }
            if union != cloud { kv.set(Array(union), forKey: k) }
        }
        for k in lastWinsKeys {
            if ud.object(forKey: k) == nil {
                if let cloudVal = kv.object(forKey: k) { ud.set(cloudVal, forKey: k) }   // restore
            } else if let localVal = ud.object(forKey: k) {
                kv.set(localVal, forKey: k)                                              // back up
            }
        }
        kv.synchronize()
    }
}
