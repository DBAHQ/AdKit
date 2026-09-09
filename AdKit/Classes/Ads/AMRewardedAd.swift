//
//  AMRewardedAd.swift
//  AdKit
//

import YandexMobileAds
import GoogleMobileAds
import MintegralAdapter
import AppLovinSDK

class AMRewardedAd: NSObject, FullScreenContentDelegate, RewardedAdLoaderDelegate, RewardedAdDelegate, MARewardedAdDelegate, MAAdRevenueDelegate {

    // MARK: - Properties
    
    private var ad: AdPlacement
    private var yandexRewardedAd: YandexMobileAds.RewardedAd?
    private var googleRewardedAd: GoogleMobileAds.RewardedAd?
    private var appLovinRewardedAd: MARewardedAd?
    private var rewardedPresentAttempts = 0
    var rewardHasBeenEarned = false
    private lazy var yandexRewardedAdLoader: RewardedAdLoader = {
        let loader = RewardedAdLoader()
        loader.delegate = self
        return loader
    }()
    
    // MARK: - Handlers Properties
    
    private var didShowHandler: (() -> ())?
    private var didLoadHandler: (() -> ())?
    private var didCloseHandler: ((_ isRewardEarned: Bool) -> ())?
    private var didEarnRewardHandler: (() -> ())?
    private var didFailPresentHandler: ((Error?) -> ())?
    private var didClickHandler: (() -> ())?
    private var noAdsAvailableHandler: (() -> ())?
    
    private let failedRequests = ThreadSafeCounter(identifier: "rewarded")
    private var appLovinLoadStartDate: Date?

    // MARK: - Additional Properties
    
    private var retryAttempt = 0
    private var retryTimer: Timer?
    private var isRetrying = false
    private let maxRetryInterval: TimeInterval = 64
    
    // MARK: - Inits
    
    init(ad: AdPlacement) {
        self.ad = ad
        super.init()
    }
    
    // MARK: - Ad Loading
    
    private func loadAd() {
        let providers = AdManager.shared.getEligibleProviders(for: .rewarded)
        
        guard let provider = providers.first else {
            let error = NSError(domain: "AdLoader", code: -1, userInfo: [NSLocalizedDescriptionKey: "No ad providers available for Rewarded Ad."])
            noAdsAvailableHandler?()
            didFailPresentHandler?(error)
            return
        }
        
        switch provider {
        case .yandex:
            loadYandexAd()
        case .appLovin:
            loadAppLovinAd()
        case .admob:
            loadGoogleAd()
        }
    }
    
    private func loadYandexAd() {
        let configuration = AdRequestConfiguration(adUnitID: ad.yandexID)
        yandexRewardedAdLoader.loadAd(with: configuration)
        AdKit.analytics.trackFullAdDidRequest(
            in: self.ad.placement,
            type: "Rewarded",
            displayCount: AdKit.storage.rewardedDisplayCount,
            fullScreenDisplayCount: AdKit.storage.fullScreenDisplayCount,
            totalAdsDisplayCount: AdKit.storage.totalAdsDisplayCount
        )
    }
    
    private func loadGoogleAd() {
        AdKit.analytics.trackFullAdDidRequest(
            in: self.ad.placement,
            type: "Rewarded",
            displayCount: AdKit.storage.rewardedDisplayCount,
            fullScreenDisplayCount: AdKit.storage.fullScreenDisplayCount,
            totalAdsDisplayCount: AdKit.storage.totalAdsDisplayCount
        )
        let request = GoogleMobileAds.Request()
        addMintegralExtras(request)
        
        GoogleMobileAds.RewardedAd.load(with: self.ad.googleID, request: request, completionHandler: { [weak self] (ad, error) in
            guard let self = self else { return }
            if let error = error {
                failedRequests.increment()
                self.didFailPresentHandler?(error)
                AdKit.analytics.trackAdDidFailToLoad(in: self.ad.placement, type: "Rewarded", failedRequests: failedRequests.value, error: error.localizedDescription)
                return
            }
            
            failedRequests.reset()  // Сброс
            AdKit.analytics.trackFullAdDidLoad(
                in: self.ad.placement,
                type: "Rewarded",
                displayCount: AdKit.storage.rewardedDisplayCount,
                fullScreenDisplayCount: AdKit.storage.fullScreenDisplayCount,
                totalAdsDisplayCount: AdKit.storage.totalAdsDisplayCount
            )
            self.googleRewardedAd = ad
            self.googleRewardedAd?.fullScreenContentDelegate = self
            self.googleRewardedAd?.paidEventHandler = { [weak self] value in
                let winningNetwork = self?.googleRewardedAd?.responseInfo.loadedAdNetworkResponseInfo?.adSourceName ?? "AdMob"
                // Раньше при уничтоженном self подставлялся конкретный кейс приложения
                // (.bonusAdWatchingHome) — событие уходило с чужим плейсментом.
                // В пакете такого кейса нет: если объекта уже нет, событие не шлём.
                guard let self else { return }
                AdKit.analytics.trackAdRevenue(in: self.ad.placement, type: "Rewarded", value: value.value.decimalValue, currency: value.currencyCode, network: "AdMob", adNetwork: winningNetwork, unitId: self.ad.googleID)
            }
            self.didLoadHandler?()
        })
    }

    private func loadAppLovinAd() {
        AdKit.analytics.trackFullAdDidRequest(
            in: self.ad.placement,
            type: "Rewarded",
            displayCount: AdKit.storage.rewardedDisplayCount,
            fullScreenDisplayCount: AdKit.storage.fullScreenDisplayCount,
            totalAdsDisplayCount: AdKit.storage.totalAdsDisplayCount
        )
        appLovinRewardedAd = MARewardedAd.shared(withAdUnitIdentifier: self.ad.appLovinID)
        appLovinRewardedAd?.delegate = self
        appLovinRewardedAd?.revenueDelegate = self
        appLovinLoadStartDate = AdLoadTimeTracker.loadStarted()
        appLovinRewardedAd?.load()
    }

    private func addMintegralExtras(_ request: GoogleMobileAds.Request) {
        let extras = GADMAdapterMintegralExtras()
        request.register(extras)
    }
    
    // MARK: - Ad Presentation
    
    func present(in viewController: UIViewController) {
        // Rewarded ad fallback (remote-config controlled). When enabled, we do
        // NOT attempt to show a real ad. Instead the caller's loader stays on
        // screen for 3 seconds and then the reward is granted, mirroring the
        // normal "ad watched" flow (didShow → didEarnReward → didClose). This
        // prevents a user-facing error when ad networks return no fill
        // (e.g. in the App Review environment).
        if AdKit.remoteConfig.rewardedAdFallbackEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                guard let self = self else { return }
                self.didShowHandler?()
                self.rewardHasBeenEarned = true
                self.didEarnRewardHandler?()
                self.didCloseHandler?(true)
            }
            return
        }

        loadAd()

        // The presentation logic will attempt to show an ad from the highest priority provider.
        // It relies on the polling mechanism inside each present... method.
        let providers = AdManager.shared.getEligibleProviders(for: .rewarded)
        guard let provider = providers.first else {
            noAdsAvailableHandler?()
            return
        }
        
        switch provider {
        case .yandex:
            presentYandex(in: viewController)
        case .appLovin:
            presentAppLovin(in: viewController)
        case .admob:
            presentGoogle(in: viewController)
        }
    }
    
    private func presentYandex(in viewController: UIViewController) {
        if let ad = yandexRewardedAd {
            ad.show(from: viewController)
        } else {
            if rewardedPresentAttempts < 1500 {
                rewardedPresentAttempts += 1
                Timer.scheduledTimer(withTimeInterval: 0.01, repeats: false) { _ in
                    self.presentYandex(in: viewController)
                }
            } else {
                noAdsAvailableHandler?()
            }
        }
    }
    
    private func presentGoogle(in viewController: UIViewController) {
        if let ad = googleRewardedAd {
            ad.present(from: viewController, userDidEarnRewardHandler: { [weak self] in
                self?.rewardHasBeenEarned = true
                self?.didEarnRewardHandler?()
            })
        } else {
            if rewardedPresentAttempts < 1500 {
                rewardedPresentAttempts += 1
                Timer.scheduledTimer(withTimeInterval: 0.01, repeats: false) { _ in
                    self.presentGoogle(in: viewController)
                }
            } else {
                noAdsAvailableHandler?()
            }
        }
    }
    
    private func presentAppLovin(in viewController: UIViewController) {
        if let ad = appLovinRewardedAd, ad.isReady {
            ad.show(forPlacement: self.ad.appLovinID, customData: nil, viewController: viewController)
        } else {
            if rewardedPresentAttempts < 1500 {
                rewardedPresentAttempts += 1
                Timer.scheduledTimer(withTimeInterval: 0.01, repeats: false) { _ in
                    self.presentAppLovin(in: viewController)
                }
            } else {
                noAdsAvailableHandler?()
            }
        }
    }
    
    // MARK: - Setters
    
    func setDidShowHandler(_ handler: (() -> ())?) -> AMRewardedAd {
        self.didShowHandler = handler
        return self
    }

    func setDidLoadHandler(_ handler: (() -> ())?) -> AMRewardedAd {
        self.didLoadHandler = handler
        return self
    }

    func setDidCloseHandler(_ handler: ((Bool) -> ())?) -> AMRewardedAd {
        self.didCloseHandler = handler
        return self
    }

    func setDidEarnRewardHandler(_ handler: (() -> ())?) -> AMRewardedAd {
        self.didEarnRewardHandler = handler
        return self
    }

    func setDidFailPresentHandler(_ handler: ((Error?) -> ())?) -> AMRewardedAd {
        self.didFailPresentHandler = handler
        return self
    }

    func setDidClickHandler(_ handler: (() -> ())?) -> AMRewardedAd {
        self.didClickHandler = handler
        return self
    }

    func setNoAdsAvailableHandler(_ handler: (() -> ())?) -> AMRewardedAd {
        self.noAdsAvailableHandler = handler
        return self
    }
    
    // MARK: - GADRewardedAdDelegate
    
    func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {
        AdKit.storage.rewardedAdPresentedTime = Date().timeIntervalSince1970
        // После показа rewarded сбрасываем счётчик навигаций и interstitial-cooldown,
        // чтобы interstitial не выскочил сразу после rewarded на следующем экране.
        AdKit.storage.interstitialAdPresentedTime = Date().timeIntervalSince1970
        AdKit.storage.screenTransitionCount = 0
        // Устанавливаем флаг анимации для текущего view controller
        AdKit.host.setAdLoadingIndicator(visible: true)
        didShowHandler?()
    }
    
    func adDidRecordImpression(_ ad: FullScreenPresentingAd) {
        incrementRewardedDisplayCount()

    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        AdKit.analytics.trackAdDidFailToDisplay(in: self.ad.placement, type: "Rewarded")
        didFailPresentHandler?(error)
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        AdKit.analytics.trackAdDidHide(in: self.ad.placement, type: "Rewarded")
        // Сбрасываем флаг анимации для текущего view controller
        AdKit.host.setAdLoadingIndicator(visible: false)
        didCloseHandler?(rewardHasBeenEarned)
    }
    
    func adDidRecordClick(_ ad: FullScreenPresentingAd) {
        AdKit.analytics.trackAdDidClick(in: self.ad.placement, type: "Rewarded")
        didClickHandler?()
    }
    
    // MARK: - RewardedAdLoaderDelegate (Yandex)
    
    func rewardedAdLoader(_ adLoader: RewardedAdLoader, didLoad rewardedAd: YandexMobileAds.RewardedAd) {
        failedRequests.reset()
        AdKit.analytics.trackFullAdDidLoad(
            in: self.ad.placement,
            type: "Rewarded",
            displayCount: AdKit.storage.rewardedDisplayCount,
            fullScreenDisplayCount: AdKit.storage.fullScreenDisplayCount,
            totalAdsDisplayCount: AdKit.storage.totalAdsDisplayCount
        )
        self.yandexRewardedAd = rewardedAd
        self.yandexRewardedAd?.delegate = self
        self.didLoadHandler?()
    }
    
    func rewardedAdLoader(_ adLoader: YandexMobileAds.RewardedAdLoader, didFailToLoadWithError error: YandexMobileAds.AdRequestError) {
        failedRequests.increment()
        didFailPresentHandler?(error.error)
        AdKit.analytics.trackAdDidFailToLoad(in: ad.placement, type: "Rewarded", failedRequests: failedRequests.value, error: error.error.localizedDescription)
    }
    
    // MARK: - RewardedAdDelegate (Yandex)
    
    func rewardedAdDidShow(_ rewardedAd: YandexMobileAds.RewardedAd) {
        AdKit.storage.rewardedAdPresentedTime = Date().timeIntervalSince1970
        // После показа rewarded сбрасываем счётчик навигаций и interstitial-cooldown,
        // чтобы interstitial не выскочил сразу после rewarded на следующем экране.
        AdKit.storage.interstitialAdPresentedTime = Date().timeIntervalSince1970
        AdKit.storage.screenTransitionCount = 0
        // Устанавливаем флаг анимации для текущего view controller
        AdKit.host.setAdLoadingIndicator(visible: true)
        self.didShowHandler?()
    }
    
    func rewardedAd(_ rewardedAd: YandexMobileAds.RewardedAd, didTrackImpressionWith impressionData: (any ImpressionData)?) {
        incrementRewardedDisplayCount()
        if let data = impressionData?.rawData.data(using: .utf8) {
            do {
                guard let dict = try JSONSerialization.jsonObject(with: data, options: []) as? [String : Any], let revenue = (dict["revenueUSD"] as? String)?.decimal else {
                    return
                }
                
                AdKit.analytics.trackAdRevenue(in: ad.placement, type: "Rewarded", value: revenue, currency: "USD", network: "Yandex")
            } catch {
                print(error.localizedDescription)
            }
        }
    }

    func rewardedAdDidFail(toLoad rewardedAd: YandexMobileAds.RewardedAd, error: Error) {
        AdKit.analytics.trackAdDidFailToDisplay(in: self.ad.placement, type: "Rewarded")
        self.didFailPresentHandler?(error)
    }

    func rewardedAd(_ rewardedAd: YandexMobileAds.RewardedAd, didReward reward: Reward) {
        rewardHasBeenEarned = true
        didEarnRewardHandler?()
    }
    
    func rewardedAdDidClick(_ rewardedAd: YandexMobileAds.RewardedAd) {
        AdKit.analytics.trackAdDidClick(in: self.ad.placement, type: "Rewarded")
        didClickHandler?()
    }
    
    func rewardedAdDidDismiss(_ rewardedAd: YandexMobileAds.RewardedAd) {
        AdKit.analytics.trackAdDidHide(in: self.ad.placement, type: "Rewarded")
        // Сбрасываем флаг анимации для текущего view controller
        AdKit.host.setAdLoadingIndicator(visible: false)
        didCloseHandler?(rewardHasBeenEarned)
    }
    
    // MARK: - MARewardedAdDelegate (AppLovin)
    
    func didLoad(_ ad: MAAd) {
        retryAttempt = 0
        retryTimer?.invalidate()
        retryTimer = nil
        isRetrying = false
        failedRequests.reset()
        let loadingTime = AdLoadTimeTracker.loadingTime(since: appLovinLoadStartDate)
        appLovinLoadStartDate = nil
        AdKit.analytics.trackFullAdDidLoad(
            in: self.ad.placement,
            type: "Rewarded",
            displayCount: AdKit.storage.rewardedDisplayCount,
            fullScreenDisplayCount: AdKit.storage.fullScreenDisplayCount,
            totalAdsDisplayCount: AdKit.storage.totalAdsDisplayCount,
            loadingTime: loadingTime
        )
        didLoadHandler?()
    }

    func didFailToLoadAd(forAdUnitIdentifier adUnitIdentifier: String, withError error: MAError) {
        failedRequests.increment()
        didFailPresentHandler?(nil)
        AdKit.analytics.trackAdDidFailToLoad(in: self.ad.placement, type: "Rewarded", failedRequests: failedRequests.value, error: error.message)
        scheduleRetry()
    }
    
    func didDisplay(_ ad: MAAd) {
        AdKit.storage.rewardedAdPresentedTime = Date().timeIntervalSince1970
        // После показа rewarded сбрасываем счётчик навигаций и interstitial-cooldown,
        // чтобы interstitial не выскочил сразу после rewarded на следующем экране.
        AdKit.storage.interstitialAdPresentedTime = Date().timeIntervalSince1970
        AdKit.storage.screenTransitionCount = 0
        incrementRewardedDisplayCount()
        // Устанавливаем флаг анимации для текущего view controller
        AdKit.host.setAdLoadingIndicator(visible: true)
        didShowHandler?()
    }
    
    func didHide(_ ad: MAAd) {
        AdKit.analytics.trackAdDidHide(in: self.ad.placement, type: "Rewarded")
        // Сбрасываем флаг анимации для текущего view controller
        AdKit.host.setAdLoadingIndicator(visible: false)
        didCloseHandler?(rewardHasBeenEarned)
    }
    
    func didClick(_ ad: MAAd) {
        AdKit.analytics.trackAdDidClick(in: self.ad.placement, type: "Rewarded")
        didClickHandler?()
    }
    
    func didPayRevenue(for ad: MAAd) {
        AdKit.analytics.trackAdRevenue(in: self.ad.placement, type: "Rewarded", value: ad.revenue.decimalValue, currency: "USD", network: "AppLovin", adNetwork: ad.networkName, unitId: ad.adUnitIdentifier)
    }
    
    func didFail(toDisplay ad: MAAd, withError error: MAError) {
        AdKit.analytics.trackAdDidFailToDisplay(in: self.ad.placement, type: "Rewarded")
        didFailPresentHandler?(nil)
        scheduleRetry()
    }
    
    func didRewardUser(for ad: MAAd, with reward: MAReward) {
        rewardHasBeenEarned = true
        didEarnRewardHandler?()
    }
    
    // MARK: - Additional Methods
    
    private func scheduleRetry() {
        guard !isRetrying else { return }
        isRetrying = true
        
        retryTimer?.invalidate()
        
        let interval = min(pow(2.0, Double(retryAttempt)), maxRetryInterval)
        retryAttempt += 1
        
        
        retryTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            guard let self = self,
                  UIApplication.shared.applicationState == .active else {
                self?.isRetrying = false
                return
            }
            DispatchQueue.main.async {
                self.loadAppLovinAd()
            }
        }
    }
    
    deinit {
        retryTimer?.invalidate()
        retryTimer = nil
    }
    
    private func incrementRewardedDisplayCount() {
        let newRewardedCount = (AdKit.storage.rewardedDisplayCount) + 1
        let newFullScreenCount = (AdKit.storage.fullScreenDisplayCount) + 1
        let newAllCount = (AdKit.storage.totalAdsDisplayCount) + 1
        
        AdKit.storage.rewardedDisplayCount = newRewardedCount
        AdKit.storage.fullScreenDisplayCount = newFullScreenCount
        AdKit.storage.totalAdsDisplayCount = newAllCount
        
        AdKit.analytics.trackFullAdDidDisplay(
            in: ad.placement,
            type: "Rewarded",
            failedRequests: failedRequests.value,
            displayCount: newRewardedCount,
            fullScreenDisplayCount: newFullScreenCount,
            totalAdsDisplayCount: newAllCount
        )
    }
    
}
