import Foundation
#if canImport(GoogleMobileAds)
import GoogleMobileAds
import UserMessagingPlatform
import AppTrackingTransparency
import UIKit

// MARK: - AdMob integration
//
// The concrete AdMob implementation of `RewardedAdProvider` (see AdManager),
// plus the consent/ATT bootstrap that must run before any ad loads.
//
// HOW THIS IS WIRED (deliberately, so 2.0 can ship ad-free and clean):
//
//   DEBUG    → Google's official TEST ad unit. The whole watch→reward flow is
//              live and testable in the simulator right now, no account needed.
//   RELEASE  → uses `realRewardedUnitID`. While that's EMPTY, `isConfigured` is
//              false, the SDK is never started, no ATT prompt is shown, and the
//              game simply shows no ads — exactly the current 2.0 behaviour.
//
// TO GO LIVE WITH ADS (all of it is these steps, nothing else):
//   1. AdMob console → create the LEXIS iOS app + a REWARDED ad unit.
//   2. Paste both IDs into `AdsConfig` below.
//   3. In project.yml, uncomment the two Release keys
//      (GADApplicationIdentifier = your real App ID, NSUserTrackingUsageDescription).
//   4. Update the App Store privacy nutrition label to declare Third-Party
//      Advertising + the device identifier, and re-run `xcodegen generate`.
//
// LEXIS uses ONLY rewarded, opt-in ads — never interstitials or banners.

enum AdsConfig {
    /// Your real AdMob IDs. Leave EMPTY to ship with no ads (release shows none).
    /// App ID looks like  ca-app-pub-4156851882993001~1234567890
    /// Unit ID looks like ca-app-pub-4156851882993001/1234567890
    static let realAppID = ""
    static let realRewardedUnitID = ""

    /// Google's official test IDs — safe to use forever in DEBUG, and the only
    /// way to exercise a real ad render without a configured account.
    static let testAppID = "ca-app-pub-3940256099942544~1458002511"
    static let testRewardedUnitID = "ca-app-pub-3940256099942544/1712485313"

    /// The unit to actually request, or nil when ads should be off entirely.
    static var rewardedUnitID: String? {
        #if DEBUG
        return realRewardedUnitID.isEmpty ? testRewardedUnitID : realRewardedUnitID
        #else
        return realRewardedUnitID.isEmpty ? nil : realRewardedUnitID
        #endif
    }

    /// False → never touch the SDK, never prompt for ATT, never show ads.
    static var isConfigured: Bool { rewardedUnitID != nil }
}

// MARK: - Bootstrap (consent → ATT → SDK start)

@MainActor
enum AdsBootstrap {
    /// Run once at launch. Safe to call when ads aren't configured — it returns
    /// immediately and the game stays exactly as it is today.
    static func start() async {
        // Not configured → exactly today's behaviour: DEBUG stub, release no ads.
        guard AdsConfig.isConfigured, let unitID = AdsConfig.rewardedUnitID else {
            AdManager.shared.configure(nil)
            return
        }

        // 1. UMP consent must be resolved BEFORE starting the SDK — the SDK may
        //    preload ads the moment it starts.
        await requestConsent()

        // 2. ATT, after the consent flow (Google's recommended order). Only
        //    reached when ads are configured, so no prompt in an ad-free build.
        if #available(iOS 14, *) {
            _ = await ATTrackingManager.requestTrackingAuthorization()
        }

        // 3. Respect the consent outcome — canRequestAds is false until the
        //    consent info update has run, and stays false if the user declined.
        guard ConsentInformation.shared.canRequestAds else {
            AdManager.shared.configure(nil)
            return
        }

        await MobileAds.shared.start()
        AdManager.shared.configure(GoogleRewardedAdProvider(adUnitID: unitID))
    }

    private static func requestConsent() async {
        let params = RequestParameters()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            ConsentInformation.shared.requestConsentInfoUpdate(with: params) { _ in
                cont.resume()
            }
        }
        // Presents the EU/UK consent form only where one is actually required.
        if let vc = topViewController() {
            try? await ConsentForm.loadAndPresentIfRequired(from: vc)
        }
    }
}

// MARK: - Provider

@MainActor
final class GoogleRewardedAdProvider: NSObject, RewardedAdProvider {
    private let adUnitID: String
    private var ad: RewardedAd?
    private var loading = false
    private var pendingFinish: (() -> Void)?

    var isReady: Bool { ad != nil }

    init(adUnitID: String) {
        self.adUnitID = adUnitID
        super.init()
    }

    func load() {
        guard ad == nil, !loading, ConsentInformation.shared.canRequestAds else { return }
        loading = true
        Task { @MainActor in
            defer {
                loading = false
                AdManager.shared.providerReadinessChanged()
            }
            do {
                let loaded = try await RewardedAd.load(with: adUnitID, request: Request())
                loaded.fullScreenContentDelegate = self
                ad = loaded
            } catch {
                // No ad fill / no network — stay unavailable; the UI hides every
                // "Watch" affordance and the game plays on. AdManager retries
                // after the next present.
                ad = nil
            }
        }
    }

    func present(onReward: @escaping () -> Void, onFinished: @escaping () -> Void) {
        guard let ad, let vc = topViewController() else {
            onFinished()
            return
        }
        pendingFinish = onFinished
        ad.present(from: vc) { onReward() }
    }

    private func finish() {
        ad = nil                     // a presented ad can never be reused
        let done = pendingFinish
        pendingFinish = nil
        done?()
    }
}

extension GoogleRewardedAdProvider: FullScreenContentDelegate {
    nonisolated func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        Task { @MainActor in self.finish() }
    }

    nonisolated func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        Task { @MainActor in self.finish() }
    }
}

// MARK: - Presentation host

@MainActor
private func topViewController() -> UIViewController? {
    guard let scene = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .first(where: { $0.activationState == .foregroundActive }) ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
          let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController ?? scene.windows.first?.rootViewController
    else { return nil }

    var top = root
    while let presented = top.presentedViewController { top = presented }
    return top
}

#else

// The SDK isn't linked in this build — keep the call site in LexisApp valid.
@MainActor
enum AdsBootstrap {
    static func start() async { AdManager.shared.configure(nil) }
}

#endif
