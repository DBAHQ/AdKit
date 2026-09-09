//
//  AMAppOpenAd.swift
//  AdKit
//

import GoogleMobileAds
import YandexMobileAds
import AppLovinSDK

class AMAppOpenAd: NSObject, FullScreenContentDelegate, AppOpenAdLoaderDelegate, MAAdDelegate, MAAdRevenueDelegate, AppOpenAdDelegate {

    // MARK: - Properties
    
    private var ad: AdPlacement
    private var yandexAppOpen: YandexMobileAds.AppOpenAd?
    private var googleAppOpen: GoogleMobileAds.AppOpenAd?
    private var appLovinAppOpen: MAAppOpenAd?
    private var AppOpenPresentAttempts = 0
    private var yandexAppOpenAdLoader: YandexMobileAds.AppOpenAdLoader!
    private let failedRequests = ThreadSafeCounter(identifier: "appopen")
    private var appLovinLoadStartDate: Date?

    // MARK: - Handlers Properties
    
    private var didShowHandler: (() -> ())?
    private var didLoadHandler: (() -> ())?
    private var didCloseHandler: (() -> ())?
    private var didFailPresentHandler: ((Error?) -> ())?
    private var didClickHandler: (() -> ())?
    private var noAdsAvailableHandler: (() -> ())?
    
    // MARK: - Inits
    
    init(ad: AdPlacement) {
        self.ad = ad
        super.init()
        self.yandexAppOpenAdLoader = YandexMobileAds.AppOpenAdLoader()
        self.yandexAppOpenAdLoader.delegate = self
        self.yandexAppOpen = nil
    }
    
    // MARK: - Ad Loading
    
    func loadAd() {
        guard UIApplication.shared.applicationState != .background else { return }
        
        let providers = AdManager.shared.getEligibleProviders(for: .appOpen)
        
        guard let provider = providers.first else {
            let error = NSError(domain: "AdLoader", code: -1, userInfo: [NSLocalizedDescriptionKey: "No ad providers available for AppOpen."])
            didFailPresentHandler?(error)
            noAdsAvailableHandler?()
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
        AdKit.analytics.trackFullAdDidRequest(
            in: self.ad.placement,
            type: "AppOpen",
            displayCount: AdKit.storage.appOpenDisplayCount,
            fullScreenDisplayCount: AdKit.storage.fullScreenDisplayCount,
            totalAdsDisplayCount: AdKit.storage.totalAdsDisplayCount
        )
        let configuration = AdRequestConfiguration(adUnitID: self.ad.yandexID)
        self.yandexAppOpenAdLoader.loadAd(with: configuration)
    }
    
    private func loadGoogleAd() {
        AdKit.analytics.trackFullAdDidRequest(
            in: self.ad.placement,
            type: "AppOpen",
            displayCount: AdKit.storage.appOpenDisplayCount,
            fullScreenDisplayCount: AdKit.storage.fullScreenDisplayCount,
            totalAdsDisplayCount: AdKit.storage.totalAdsDisplayCount
        )
        
        let request = GoogleMobileAds.Request()
        GoogleMobileAds.AppOpenAd.load(with: self.ad.googleID, request: request) { [weak self] (ad, error) in
            guard let self = self else { return }
            
            if let error = error {
                failedRequests.increment()
                self.didFailPresentHandler?(error)
                AdKit.analytics.trackAdDidFailToLoad(in: self.ad.placement,
                     type: "AppOpen",
                     failedRequests: failedRequests.value,
                     error: error.localizedDescription)
                return
            }
            
            failedRequests.reset()
            AdKit.analytics.trackFullAdDidLoad(
                in: self.ad.placement,
                type: "AppOpen",
                displayCount: AdKit.storage.appOpenDisplayCount,
                fullScreenDisplayCount: AdKit.storage.fullScreenDisplayCount,
                totalAdsDisplayCount: AdKit.storage.totalAdsDisplayCount
            )
            
            self.googleAppOpen = ad
            self.googleAppOpen?.fullScreenContentDelegate = self
            
            self.googleAppOpen?.paidEventHandler = { value in
                let winningNetwork = self.googleAppOpen?.responseInfo.loadedAdNetworkResponseInfo?.adSourceName ?? "AdMob"
                AdKit.analytics.trackAdRevenue(in: self.ad.placement, type: "AppOpen", value: value.value.decimalValue, currency: value.currencyCode, network: "AdMob", adNetwork: winningNetwork, unitId: self.ad.googleID)
            }
            self.didLoadHandler?()
        }
    }

    private func presentGoogle(in viewController: UIViewController) {
        if let ad = googleAppOpen {
            ad.present(from: viewController)
        } else {
            noAdsAvailableHandler?()
            loadAd()
        }
    }
    
    private func loadAppLovinAd() {
        AdKit.analytics.trackFullAdDidRequest(
            in: self.ad.placement,
            type: "AppOpen",
            displayCount: AdKit.storage.appOpenDisplayCount,
            fullScreenDisplayCount: AdKit.storage.fullScreenDisplayCount,
            totalAdsDisplayCount: AdKit.storage.totalAdsDisplayCount
        )
        appLovinAppOpen = MAAppOpenAd(adUnitIdentifier: self.ad.appLovinID)
        appLovinAppOpen?.delegate = self
        appLovinAppOpen?.revenueDelegate = self
        appLovinLoadStartDate = AdLoadTimeTracker.loadStarted()
        appLovinAppOpen?.load()
    }

    private func presentAppLovin(in viewController: UIViewController) {
        if let ad = appLovinAppOpen, ad.isReady {
            ad.show()
        } else {
            if AppOpenPresentAttempts < 100 {
                AppOpenPresentAttempts += 1
                Timer.scheduledTimer(withTimeInterval: 0.01, repeats: false) { _ in
                    self.presentAppLovin(in: viewController)
                }
            } else {
                AppOpenPresentAttempts = 0
                noAdsAvailableHandler?()
            }
        }
    }
    
    // MARK: - Ad Presentation
    
    func present(in viewController: UIViewController) {
        if yandexAppOpen != nil {
            presentYandex(in: viewController)
        } else if appLovinAppOpen != nil {
            presentAppLovin(in: viewController)
        } else if googleAppOpen != nil {
            presentGoogle(in: viewController)
        } else {
            noAdsAvailableHandler?()
        }
    }

    private func presentYandex(in viewController: UIViewController) {
        if let ad = yandexAppOpen {
            ad.delegate = self
            do {
                ad.show(from: viewController)
            }
        } else {
            if AppOpenPresentAttempts < 3 {
                AppOpenPresentAttempts += 1
                Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
                    self.present(in: viewController)
                }
            } else {
                AppOpenPresentAttempts = 0
                noAdsAvailableHandler?()
                loadAd()
            }
        }
    }
    
    // MARK: - Setters
    
    func setDidShowHandler(_ handler: (() -> ())?) -> AMAppOpenAd {
        self.didShowHandler = handler
        return self
    }

    func setDidLoadHandler(_ handler: (() -> ())?) -> AMAppOpenAd {
        self.didLoadHandler = handler
        return self
    }

    func setDidCloseHandler(_ handler: (() -> ())?) -> AMAppOpenAd {
        self.didCloseHandler = handler
        return self
    }

    func setDidFailPresentHandler(_ handler: ((Error?) -> ())?) -> AMAppOpenAd {
        self.didFailPresentHandler = handler
        return self
    }

    func setDidClickHandler(_ handler: (() -> ())?) -> AMAppOpenAd {
        self.didClickHandler = handler
        return self
    }

    func setNoAdsAvailableHandler(_ handler: (() -> ())?) -> AMAppOpenAd {
        self.noAdsAvailableHandler = handler
        return self
    }
    
    // MARK: - GADFullScreenContentDelegate
    
    func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {
        AdKit.storage.interstitialAdPresentedTime = Date().timeIntervalSince1970
        incrementAppOpenDisplayCount()
        didShowHandler?()
    }
    
    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        AdKit.analytics.trackAdDidFailToDisplay(in: self.ad.placement, type: "AppOpen")
        didFailPresentHandler?(error)
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        AdKit.analytics.trackAdDidHide(in: self.ad.placement, type: "AppOpen")
        didCloseHandler?()
    }

    func adDidRecordClick(_ ad: FullScreenPresentingAd) {
        AdKit.analytics.trackAdDidClick(in: self.ad.placement, type: "AppOpen")
        didClickHandler?()
    }
    
    // MARK: - AppOpenAdLoaderDelegate (Yandex)
  
    func appOpenAdLoader(_ adLoader: YandexMobileAds.AppOpenAdLoader, didLoad appOpenAd: YandexMobileAds.AppOpenAd) {
        self.failedRequests.reset()
        self.yandexAppOpen = appOpenAd
        self.yandexAppOpen?.delegate = self
        AdKit.analytics.trackFullAdDidLoad(
            in: self.ad.placement,
            type: "AppOpen",
            displayCount: AdKit.storage.appOpenDisplayCount,
            fullScreenDisplayCount: AdKit.storage.fullScreenDisplayCount,
            totalAdsDisplayCount: AdKit.storage.totalAdsDisplayCount
        )
        didLoadHandler?()
    }
    
    func appOpenAdLoader(_ adLoader: YandexMobileAds.AppOpenAdLoader, didFailToLoadWithError error: YandexMobileAds.AdRequestError) {
        failedRequests.increment()
        didFailPresentHandler?(error.error)
        AdKit.analytics.trackAdDidFailToLoad(in: ad.placement, type: "AppOpen", failedRequests: failedRequests.value, error: error.error.localizedDescription)
    }
    
    // MARK: - AppOpenAdDelegate (Yandex)
    
    func appOpenAdDidShow(_ appOpenAd: YandexMobileAds.AppOpenAd) {
        didShowHandler?()
    }
    
    func appOpenAd(_ appOpeAd: YandexMobileAds.AppOpenAd, didTrackImpressionWith impressionData: (any ImpressionData)?) {
        incrementAppOpenDisplayCount()
        if let data = impressionData?.rawData.data(using: .utf8) {
            do {
                guard let dict = try JSONSerialization.jsonObject(with: data, options: []) as? [String : Any], let revenue = (dict["revenueUSD"] as? String)?.decimal else {
                    return
                }
                
                AdKit.analytics.trackAdRevenue(in: ad.placement, type: "AppOpen", value: revenue, currency: "USD", network: "Yandex")
            } catch {
                print(error.localizedDescription)
            }
        }
    }
    
    func appOpenAd(_ appOpenAd: YandexMobileAds.AppOpenAd, didFailToShowWithError error: any Error) {
        AdKit.analytics.trackAdDidFailToDisplay(in: self.ad.placement, type: "AppOpen")
        didFailPresentHandler?(error)
    }
    
    func appOpenAdDidDismiss(_ appOpenAd: YandexMobileAds.AppOpenAd) {
        AdKit.analytics.trackAdDidHide(in: self.ad.placement, type: "AppOpen")
        didCloseHandler?()
    }
    
    func appOpenAdDidClick(_ appOpenAd: YandexMobileAds.AppOpenAd) {
        AdKit.analytics.trackAdDidClick(in: self.ad.placement, type: "AppOpen")
        didClickHandler?()
    }
    
    // MARK: - MAAppOpenAdDelegate (AppLovin)
    
    func didLoad(_ ad: MAAd) {
        failedRequests.reset()
        let loadingTime = AdLoadTimeTracker.loadingTime(since: appLovinLoadStartDate)
        appLovinLoadStartDate = nil
        AdKit.analytics.trackFullAdDidLoad(
            in: self.ad.placement,
            type: "AppOpen",
            displayCount: AdKit.storage.appOpenDisplayCount,
            fullScreenDisplayCount: AdKit.storage.fullScreenDisplayCount,
            totalAdsDisplayCount: AdKit.storage.totalAdsDisplayCount,
            loadingTime: loadingTime
        )
        didLoadHandler?()
    }
    
    func didFailToLoadAd(forAdUnitIdentifier adUnitIdentifier: String, withError error: MAError) {
        failedRequests.increment()
        AdKit.analytics.trackAdDidFailToLoad(in: self.ad.placement, type: "AppOpen", failedRequests: failedRequests.value, error: error.message)
        didFailPresentHandler?(nil)
    }
    
    func didDisplay(_ ad: MAAd) {
        AdKit.storage.interstitialAdPresentedTime = Date().timeIntervalSince1970
        incrementAppOpenDisplayCount()
        didShowHandler?()
    }
    
    func didHide(_ ad: MAAd) {
        AdKit.analytics.trackAdDidHide(in: self.ad.placement, type: "AppOpen")
        didCloseHandler?()
    }
    
    func didClick(_ ad: MAAd) {
        AdKit.analytics.trackAdDidClick(in: self.ad.placement, type: "AppOpen")
        didClickHandler?()
    }
    
    func didPayRevenue(for ad: MAAd) {
        AdKit.analytics.trackAdRevenue(in: self.ad.placement, type: "AppOpen", value: ad.revenue.decimalValue, currency: "USD", network: "AppLovin", adNetwork: ad.networkName, unitId: ad.adUnitIdentifier)
    }
    
    func didFail(toDisplay ad: MAAd, withError error: MAError) {
        AdKit.analytics.trackAdDidFailToDisplay(in: self.ad.placement, type: "AppOpen")
        didFailPresentHandler?(nil)
    }
    
    private func incrementAppOpenDisplayCount() {
        let newAppOpenCount = (AdKit.storage.appOpenDisplayCount) + 1
        let newFullScreenCount = (AdKit.storage.fullScreenDisplayCount) + 1
        let newAllCount = (AdKit.storage.totalAdsDisplayCount) + 1

        AdKit.storage.appOpenDisplayCount = newAppOpenCount
        AdKit.storage.fullScreenDisplayCount = newFullScreenCount
        AdKit.storage.totalAdsDisplayCount = newAllCount

        AdKit.analytics.trackFullAdDidDisplay(
            in: ad.placement,
            type: "AppOpen",
            failedRequests: failedRequests.value,
            displayCount: newAppOpenCount,
            fullScreenDisplayCount: newFullScreenCount,
            totalAdsDisplayCount: newAllCount
        )
    }
}
