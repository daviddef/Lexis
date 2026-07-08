import Foundation

// MARK: - Rewarded ads (network-agnostic)
//
// The same pattern as Analytics: the app only ever talks to
// `AdManager.shared`, and the actual ad network (AdMob / AppLovin) is attached
// via a `RewardedAdProvider`. Ships SAFE:
//   • DEBUG with no real provider → a stub that "watches" instantly, so the
//     whole watch → reward UX is testable in the simulator with no SDK.
//   • Release with no provider → ads are simply unavailable and every "Watch"
//     affordance hides. The game is fully playable with zero ads configured.
//
// LEXIS uses ONLY rewarded, opt-in ads — never interstitials or banners — so
// ad exposure can't depress retention (the research: >3 forced ads/session
// drops retention ~27%; rewarded opt-in doesn't).
//
// To go live: create an AdMob (or AppLovin) app + a *rewarded* ad unit, add
// the SDK as a Swift Package, implement `RewardedAdProvider` around it, add
// the App Tracking Transparency + consent prompt, and pass the provider to
// `configure(_:)` in LexisApp.

@MainActor
protocol RewardedAdProvider: AnyObject {
    var isReady: Bool { get }
    /// Begin loading (and reloading after each present) so an ad is ready when
    /// the player asks.
    func load()
    /// Present the rewarded ad. Call `onReward` exactly once IF the user earned
    /// the reward (watched enough), then `onFinished` when the ad is dismissed
    /// (whether or not it rewarded).
    func present(onReward: @escaping () -> Void, onFinished: @escaping () -> Void)
}

@MainActor
final class AdManager: ObservableObject {
    static let shared = AdManager()

    /// Drives whether "Watch" affordances show. Observed by the UI.
    @Published private(set) var isReady = false

    private var provider: RewardedAdProvider?
    private var presenting = false

    private init() {}

    /// Attach the ad network. Pass the real provider once you've integrated an
    /// SDK; pass nil to use the DEBUG stub (real builds with nil get no ads).
    func configure(_ provider: RewardedAdProvider?) {
        #if DEBUG
        self.provider = provider ?? StubRewardedProvider()
        #else
        self.provider = provider
        #endif
        self.provider?.load()
        refreshReady()
    }

    /// A real provider whose readiness changes asynchronously should call this
    /// so the UI updates.
    func providerReadinessChanged() { refreshReady() }

    private func refreshReady() { isReady = provider?.isReady ?? false }

    /// Show a rewarded ad for `placement`. `onReward` runs only if the user
    /// actually earned it. No-ops (and logs) if no ad is available.
    func showRewarded(placement: String, onReward: @escaping () -> Void) {
        guard !presenting, let provider, provider.isReady else {
            Analytics.shared.track(.init("ad_unavailable", ["placement": placement]))
            return
        }
        presenting = true
        Analytics.shared.track(.init("ad_shown", ["placement": placement]))
        var earned = false
        provider.present(onReward: {
            earned = true
        }, onFinished: { [weak self] in
            guard let self else { return }
            self.presenting = false
            if earned {
                Analytics.shared.track(.init("ad_rewarded", ["placement": placement]))
                onReward()
            }
            provider.load()          // preload the next one
            self.refreshReady()
        })
    }
}

#if DEBUG
/// Stand-in for a real rewarded ad so the reward flow is fully testable with
/// no SDK: always ready, and "watching" completes and rewards immediately (a
/// real ad would run ~15–30s and only reward on completion).
@MainActor
final class StubRewardedProvider: RewardedAdProvider {
    private(set) var isReady = true
    func load() { isReady = true }
    func present(onReward: @escaping () -> Void, onFinished: @escaping () -> Void) {
        onReward()
        onFinished()
    }
}
#endif
