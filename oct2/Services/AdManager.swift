import UIKit
import GoogleMobileAds
import UserMessagingPlatform
import AppTrackingTransparency
import Observation

/// Ad unit configuration (production AdMob ids).
/// The app id lives in Footprints-Info.plist → GADApplicationIdentifier.
enum AdConfig {
    static let appOpenUnitID = "ca-app-pub-3633271666253179/4244216854"
    static let interstitialUnitID = "ca-app-pub-3633271666253179/7317314782"

    /// Minimum gap between any two full-screen ads.
    static let appOpenCooldown: TimeInterval = 4 * 60
    static let interstitialCooldown: TimeInterval = 90
    /// Show an interstitial on every Nth natural break (saving a walk / place).
    static let interstitialEveryNthBreak = 2
    /// Google: app open ads expire after 4 hours.
    static let appOpenExpiry: TimeInterval = 4 * 3600
    /// Don't greet brand-new users with an ad.
    static let minLaunchesBeforeAppOpen = 2
}

/// Owns consent (UMP + ATT), loading and showing of app open and interstitial ads.
@Observable
final class AdManager: NSObject, FullScreenContentDelegate {
    static let shared = AdManager()

    private(set) var canRequestAds = false
    private(set) var privacyOptionsRequired = false

    /// Hook for a future "Remove Ads" purchase.
    var adsRemoved: Bool {
        get { UserDefaults.standard.bool(forKey: "adsRemoved") }
        set { UserDefaults.standard.set(newValue, forKey: "adsRemoved") }
    }

    /// Set by the app: true while ads must not interrupt (recording a walk, onboarding…).
    @ObservationIgnored var isSuppressed: () -> Bool = { false }

    @ObservationIgnored private var started = false
    @ObservationIgnored private var appOpenAd: AppOpenAd?
    @ObservationIgnored private var appOpenLoadedAt: Date?
    @ObservationIgnored private var interstitial: InterstitialAd?
    @ObservationIgnored private var loadingAppOpen = false
    @ObservationIgnored private var loadingInterstitial = false
    @ObservationIgnored private var isShowing = false
    @ObservationIgnored private var lastFullScreenAt: Date?
    @ObservationIgnored private var breaks = 0
    @ObservationIgnored private var wasInBackground = false

    private var launchCount: Int { UserDefaults.standard.integer(forKey: "launchCount") }

    // MARK: Startup

    /// Gathers consent, then initializes the SDK and preloads ads. Safe to call more than once.
    func start() async {
        guard !started else { return }
        started = true
        UserDefaults.standard.set(launchCount + 1, forKey: "launchCount")

        // 1. GDPR / US-state consent via Google's User Messaging Platform.
        do {
            try await ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters())
            try await ConsentForm.loadAndPresentIfRequired(from: topViewController())
        } catch {
            // Fall through: canRequestAds reflects whatever consent we already have.
        }
        privacyOptionsRequired = ConsentInformation.shared.privacyOptionsRequirementStatus == .required

        // 2. Apple's App Tracking Transparency prompt (personalized ads).
        var askATT = ATTrackingManager.trackingAuthorizationStatus == .notDetermined
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "skipATT") { askATT = false }   // simulator automation
        #endif
        if askATT {
            _ = await ATTrackingManager.requestTrackingAuthorization()
        }

        guard ConsentInformation.shared.canRequestAds else { return }
        canRequestAds = true
        _ = await MobileAds.shared.start()

        await loadAppOpen()
        await loadInterstitial()
        showAppOpenIfAvailable()   // cold start

        #if DEBUG
        if UserDefaults.standard.bool(forKey: "forceInterstitial") {
            try? await Task.sleep(for: .seconds(1))
            lastFullScreenAt = nil
            showInterstitialIfAvailable()
        }
        #endif
    }

    /// Re-opens the consent form (required "Privacy choices" entry point in Settings).
    func presentPrivacyOptions() async {
        try? await ConsentForm.presentPrivacyOptionsForm(from: topViewController())
        canRequestAds = ConsentInformation.shared.canRequestAds
    }

    // MARK: Lifecycle

    func didEnterBackground() { wasInBackground = true }

    func didBecomeActive() {
        guard wasInBackground else { return }
        wasInBackground = false
        showAppOpenIfAvailable()
    }

    // MARK: App open

    private func loadAppOpen() async {
        guard canRequestAds, !adsRemoved, !loadingAppOpen, !appOpenIsFresh else { return }
        loadingAppOpen = true
        defer { loadingAppOpen = false }
        do {
            let ad = try await AppOpenAd.load(with: AdConfig.appOpenUnitID, request: Request())
            ad.fullScreenContentDelegate = self
            appOpenAd = ad
            appOpenLoadedAt = .now
        } catch {
            appOpenAd = nil
        }
    }

    private var appOpenIsFresh: Bool {
        guard appOpenAd != nil, let loaded = appOpenLoadedAt else { return false }
        return Date.now.timeIntervalSince(loaded) < AdConfig.appOpenExpiry
    }

    func showAppOpenIfAvailable() {
        guard canRequestAds, !adsRemoved, !isShowing, !isSuppressed(),
              launchCount >= AdConfig.minLaunchesBeforeAppOpen,
              cooledDown(AdConfig.appOpenCooldown) else { return }
        guard appOpenIsFresh, let ad = appOpenAd else {
            Task { await loadAppOpen() }
            return
        }
        appOpenAd = nil
        isShowing = true
        ad.present(from: topViewController())
    }

    // MARK: Interstitial

    private func loadInterstitial() async {
        guard canRequestAds, !adsRemoved, !loadingInterstitial, interstitial == nil else { return }
        loadingInterstitial = true
        defer { loadingInterstitial = false }
        do {
            let ad = try await InterstitialAd.load(with: AdConfig.interstitialUnitID, request: Request())
            ad.fullScreenContentDelegate = self
            interstitial = ad
        } catch {
            interstitial = nil
        }
    }

    /// Call at a natural pause (after saving a walk or a place). Shows an ad only sometimes.
    func naturalBreak() {
        guard canRequestAds, !adsRemoved else { return }
        breaks += 1
        guard breaks % AdConfig.interstitialEveryNthBreak == 0 else { return }
        // Let any sheet finish dismissing before presenting.
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            showInterstitialIfAvailable()
        }
    }

    private func showInterstitialIfAvailable() {
        guard !isShowing, !isSuppressed(), cooledDown(AdConfig.interstitialCooldown) else { return }
        guard let ad = interstitial else {
            Task { await loadInterstitial() }
            return
        }
        interstitial = nil
        isShowing = true
        ad.present(from: topViewController())
    }

    // MARK: FullScreenContentDelegate

    nonisolated func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {
        Task { @MainActor in self.lastFullScreenAt = .now }
    }

    nonisolated func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        Task { @MainActor in self.finishedShowing() }
    }

    nonisolated func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        Task { @MainActor in self.finishedShowing() }
    }

    private func finishedShowing() {
        isShowing = false
        lastFullScreenAt = .now
        Task {
            await loadAppOpen()
            await loadInterstitial()
        }
    }

    // MARK: Helpers

    private func cooledDown(_ interval: TimeInterval) -> Bool {
        guard let last = lastFullScreenAt else { return true }
        return Date.now.timeIntervalSince(last) >= interval
    }

    /// The top-most presented controller, so ads can show above open sheets.
    private func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ?? UIApplication.shared.connectedScenes.first as? UIWindowScene
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}
