//
//  AMInterstitialAd.swift
//  AdKit
//


import GoogleMobileAds
import YandexMobileAds
import AppLovinSDK

public class AMInterstitialAd: NSObject, FullScreenContentDelegate, InterstitialAdLoaderDelegate, InterstitialAdDelegate, MAAdDelegate, MAAdRevenueDelegate, PreloadDelegate {
    
    // MARK: - Properties
    
    private var ad: AdPlacement
    private var yandexInterstitial: YandexMobileAds.InterstitialAd?
    private var googleInterstitial: GoogleMobileAds.InterstitialAd?
    private var appLovinInterstitial: MAInterstitialAd?
    private var interstitialPresentAttempts = 0
    private var retryAttempt = 0
    private var retryTimer: Timer?
    private var isRetrying = false
    /// CPM-бэкофф: интер считается готовым к показу только если его CPM прошёл порог.
    private var isCPMApproved = false
    private var cpmBackoffTimer: Timer?
    private let maxRetryInterval: TimeInterval = 64
    private lazy var yandexInterstitialAdLoader: InterstitialAdLoader = {
        let loader = InterstitialAdLoader()
        loader.delegate = self
        return loader
    }()
    private let failedRequests = ThreadSafeCounter(identifier: "interstitial")
    private var appLovinLoadStartDate: Date?

    // MARK: - Handlers Properties
    
    private var didShowHandler: (() -> ())?
    private var didLoadHandler: (() -> ())?
    private var didCloseHandler: (() -> ())?
    private var didFailPresentHandler: ((Error?) -> ())?
    private var didClickHandler: (() -> ())?
    private var noAdsAvailableHandler: (() -> ())?
    
    // MARK: - Inits
    
    public init(ad: AdPlacement) {
        self.ad = ad
        super.init()
        self.loadAd()
    }
    
    // MARK: - Ad Loading
    
    private func loadAd() {
            // 1. Получаем список доступных провайдеров
            let providers = AdManager.shared.getEligibleProviders(for: .interstitial)
            
            // 2. Берем первого провайдера из списка
            guard let provider = providers.first else {
                let error = NSError(domain: "AdLoader", code: -1, userInfo: [NSLocalizedDescriptionKey: "No ad providers available for interstitial."])
                noAdsAvailableHandler?()
                didFailPresentHandler?(error)
                return
            }
            
            // 3. Загружаем рекламу от этого провайдера
            switch provider {
            case .yandex:
                loadYandexAd()
            case .appLovin:
                loadAppLovinAd()
            case .admob:
                AMAdPreloadManager.shared.startPreloading(adUnitID: self.ad.googleID, delegate: self)
                if AMAdPreloadManager.shared.isAdAvailable(for: self.ad.googleID) {
                    failedRequests.reset()
                    AdKit.analytics.trackFullAdDidLoad(
                        in: self.ad.placement,
                        type: "Interstitial",
                        displayCount: AdKit.storage.interstitialDisplayCount,
                        fullScreenDisplayCount: AdKit.storage.fullScreenDisplayCount,
                        totalAdsDisplayCount: AdKit.storage.totalAdsDisplayCount
                    )
                    didLoadHandler?()
                }
            }
        }
    
    private func loadYandexAd() {
        AdKit.analytics.trackFullAdDidRequest(
            in: self.ad.placement,
            type: "Interstitial",
            displayCount: AdKit.storage.interstitialDisplayCount,
            fullScreenDisplayCount: AdKit.storage.fullScreenDisplayCount,
            totalAdsDisplayCount: AdKit.storage.totalAdsDisplayCount
        )
        let configuration = AdRequestConfiguration(adUnitID: self.ad.yandexID)
        self.yandexInterstitialAdLoader.loadAd(with: configuration)
    }
    
    private func loadGoogleAd() {
        AdKit.analytics.trackFullAdDidRequest(
            in: self.ad.placement,
            type: "Interstitial",
            displayCount: AdKit.storage.interstitialDisplayCount,
            fullScreenDisplayCount: AdKit.storage.fullScreenDisplayCount,
            totalAdsDisplayCount: AdKit.storage.totalAdsDisplayCount
        )
        
        let request = Request()
        GoogleMobileAds.InterstitialAd.load(with: self.ad.googleID, request: request) { [weak self] (ad, error) in
            guard let self = self else { return }
            if let error = error {
                failedRequests.increment()
                self.didFailPresentHandler?(error)
                AdKit.analytics.trackAdDidFailToLoad(in: self.ad.placement,
                     type: "Interstitial",
                     failedRequests: failedRequests.value,
                     error: error.localizedDescription)
                return
            }
            
            failedRequests.reset()
            AdKit.analytics.trackFullAdDidLoad(
                in: self.ad.placement,
                type: "Interstitial",
                displayCount: AdKit.storage.interstitialDisplayCount,
                fullScreenDisplayCount: AdKit.storage.fullScreenDisplayCount,
                totalAdsDisplayCount: AdKit.storage.totalAdsDisplayCount
            )
            
            self.googleInterstitial = ad
            self.googleInterstitial?.fullScreenContentDelegate = self
            self.googleInterstitial?.paidEventHandler = { value in
                let winningNetwork = self.googleInterstitial?.responseInfo.loadedAdNetworkResponseInfo?.adSourceName ?? "AdMob"
                AdKit.analytics.trackAdRevenue(in: self.ad.placement, type: "Interstitial", value: value.value.decimalValue, currency: value.currencyCode, network: "AdMob", adNetwork: winningNetwork, unitId: self.ad.googleID)
            }
            self.didLoadHandler?()
        }
    }
    
    private func loadAppLovinAd() {
        AdKit.analytics.trackFullAdDidRequest(
            in: self.ad.placement,
            type: "Interstitial",
            displayCount: AdKit.storage.interstitialDisplayCount,
            fullScreenDisplayCount: AdKit.storage.fullScreenDisplayCount,
            totalAdsDisplayCount: AdKit.storage.totalAdsDisplayCount
        )
        appLovinInterstitial = MAInterstitialAd(adUnitIdentifier: self.ad.appLovinID)
        appLovinInterstitial?.delegate = self
        appLovinInterstitial?.revenueDelegate = self
        appLovinLoadStartDate = AdLoadTimeTracker.loadStarted()
        appLovinInterstitial?.load()
    }
    
    // MARK: - Ad Presentation
    
    public func present(in viewController: UIViewController) {
            if yandexInterstitial != nil {
                presentYandex(in: viewController)
            } else if appLovinInterstitial != nil {
                presentAppLovin(in: viewController)
            } else if googleInterstitial != nil || AMAdPreloadManager.shared.isAdAvailable(for: self.ad.googleID) {
                presentGoogle(in: viewController)
            } else {
                // Если ничего не загружено, пытаемся загрузить снова
                loadAd()
            }
        }
    
    private func presentYandex(in viewController: UIViewController) {
        if let ad = yandexInterstitial {
            ad.show(from: viewController)
            
            // Переустанавливаем делегат сразу после показа
            DispatchQueue.main.async {
                ad.delegate = self
            }
            
            // Проверим через секунду
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if ad.delegate == nil {
                    ad.delegate = self
                }
            }
        } else {
            if interstitialPresentAttempts < 1500 {
                interstitialPresentAttempts += 1
                Timer.scheduledTimer(withTimeInterval: 0.01, repeats: false) { _ in
                    self.present(in: viewController)
                }
            } else {
                noAdsAvailableHandler?()
            }
        }
    }
    
    private func presentGoogle(in viewController: UIViewController) {
        // Сначала проверяем прелоад-кэш
        if AMAdPreloadManager.shared.isAdAvailable(for: self.ad.googleID),
           let ad = AMAdPreloadManager.shared.getAd(for: self.ad.googleID) {
            // Получаем готовый ad из кэша
            ad.fullScreenContentDelegate = self
            ad.paidEventHandler = { value in
                let winningNetwork = ad.responseInfo.loadedAdNetworkResponseInfo?.adSourceName ?? "AdMob"
                AdKit.analytics.trackAdRevenue(in: self.ad.placement, type: "Interstitial", value: value.value.decimalValue, currency: value.currencyCode, network: "AdMob", adNetwork: winningNetwork, unitId: self.ad.googleID)
            }
            ad.present(from: viewController)
        } else if let ad = googleInterstitial {
            // Используем ранее загруженный ad (для совместимости)
            ad.present(from: viewController)
        } else {
            if interstitialPresentAttempts < 1500 {
                interstitialPresentAttempts += 1
                Timer.scheduledTimer(withTimeInterval: 0.01, repeats: false) { _ in
                    self.present(in: viewController)
                }
            } else {
                noAdsAvailableHandler?()
            }
        }
    }
    
    private func presentAppLovin(in viewController: UIViewController) {
        if let ad = appLovinInterstitial, ad.isReady, isCPMApproved {
            ad.show(forPlacement: self.ad.appLovinID, customData: nil, viewController: viewController)
        } else {
            if interstitialPresentAttempts < 1500 {
                interstitialPresentAttempts += 1
                Timer.scheduledTimer(withTimeInterval: 0.01, repeats: false) { _ in
                    self.presentAppLovin(in: viewController)
                }
            } else {
                noAdsAvailableHandler?()
            }
        }
    }
    
    // MARK: - Setters
    
    public func setDidShowHandler(_ handler: (() -> ())?) -> AMInterstitialAd {
        self.didShowHandler = handler
        return self
    }

    public func setDidLoadHandler(_ handler: (() -> ())?) -> AMInterstitialAd {
        self.didLoadHandler = handler
        return self
    }

    public func setDidCloseHandler(_ handler: (() -> ())?) -> AMInterstitialAd {
        self.didCloseHandler = handler
        return self
    }

    public func setDidFailPresentHandler(_ handler: ((Error?) -> ())?) -> AMInterstitialAd {
        self.didFailPresentHandler = handler
        return self
    }

    public func setDidClickHandler(_ handler: (() -> ())?) -> AMInterstitialAd {
        self.didClickHandler = handler
        return self
    }

    public func setNoAdsAvailableHandler(_ handler: (() -> ())?) -> AMInterstitialAd {
        self.noAdsAvailableHandler = handler
        return self
    }
    
    // MARK: - GADFullScreenContentDelegate
    
    public func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {
        AdKit.storage.interstitialAdPresentedTime = Date().timeIntervalSince1970
        incrementInterstitialDisplayCount()
        didShowHandler?()
    }
    
    public func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        AdKit.analytics.trackAdDidFailToDisplay(in: self.ad.placement, type: "Interstitial")
        didFailPresentHandler?(error)
    }

    public func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        AdKit.analytics.trackAdDidHide(in: self.ad.placement, type: "Interstitial")
        didCloseHandler?()
    }

    public func adDidRecordClick(_ ad: FullScreenPresentingAd) {
        AdKit.analytics.trackAdDidClick(in: self.ad.placement, type: "Interstitial")
        didClickHandler?()
    }
    
    // MARK: - PreloadDelegate
    
    @objc public func adAvailable(forPreloadID preloadID: String, responseInfo: ResponseInfo) {
        failedRequests.reset()
        AdKit.analytics.trackFullAdDidLoad(
            in: self.ad.placement,
            type: "Interstitial",
            displayCount: AdKit.storage.interstitialDisplayCount,
            fullScreenDisplayCount: AdKit.storage.fullScreenDisplayCount,
            totalAdsDisplayCount: AdKit.storage.totalAdsDisplayCount
        )
        didLoadHandler?()
    }

    @objc public func adsExhausted(forPreloadID preloadID: String) {
        // SDK автоматически загрузит новые
    }

    @objc public func adFailedToPreload(forPreloadID preloadID: String, error: Error) {
        failedRequests.increment()
        didFailPresentHandler?(error)
        AdKit.analytics.trackAdDidFailToLoad(
            in: self.ad.placement,
            type: "Interstitial",
            failedRequests: failedRequests.value,
            error: error.localizedDescription
        )
    }

    
    // MARK: - InterstitialAdLoaderDelegate (Yandex)
    
    public func interstitialAdLoader(_ adLoader: InterstitialAdLoader, didLoad interstitialAd: YandexMobileAds.InterstitialAd) {
        failedRequests.reset()
        AdKit.analytics.trackFullAdDidLoad(
            in: self.ad.placement,
            type: "Interstitial",
            displayCount: AdKit.storage.interstitialDisplayCount,
            fullScreenDisplayCount: AdKit.storage.fullScreenDisplayCount,
            totalAdsDisplayCount: AdKit.storage.totalAdsDisplayCount
        )
        yandexInterstitial = interstitialAd
        yandexInterstitial?.delegate = self
        didLoadHandler?()
    }
    
    public func interstitialAdLoader(_ adLoader: InterstitialAdLoader, didFailToLoadWithError error: AdRequestError) {
        failedRequests.increment()
        didFailPresentHandler?(error.error)
        AdKit.analytics.trackAdDidFailToLoad(in: ad.placement, type: "Interstitial", failedRequests: failedRequests.value, error: error.error.localizedDescription)
    }
    
    // MARK: - InterstitialAdDelegate (Yandex)
    
    public func interstitialAdDidShow(_ interstitialAd: YandexMobileAds.InterstitialAd) {
        AdKit.storage.interstitialAdPresentedTime = Date().timeIntervalSince1970
        didShowHandler?()
    }

    
    public func interstitialAd(_ interstitialAd: YandexMobileAds.InterstitialAd, didTrackImpressionWith impressionData: (any ImpressionData)?) {
        
        
        incrementInterstitialDisplayCount()
        if let data = impressionData?.rawData.data(using: .utf8) {
            do {
                guard let dict = try JSONSerialization.jsonObject(with: data, options: []) as? [String : Any] else {
                    return
                }
                            
                guard let revenue = (dict["revenueUSD"] as? String)?.decimal else {
                    if let revenueDouble = dict["revenueUSD"] as? Double {
                        let revenue = Decimal(revenueDouble)
                        AdKit.analytics.trackAdRevenue(in: ad.placement, type: "Interstitial", value: revenue, currency: "USD", network: "Yandex")
                        return
                    }
                    return
                }
                AdKit.analytics.trackAdRevenue(in: ad.placement, type: "Interstitial", value: revenue, currency: "USD", network: "Yandex")
                
            } catch {
            }
        }
    }
    
    public func interstitialAd(_ interstitialAd: YandexMobileAds.InterstitialAd, didFailToShowWithError error: any Error) {
        AdKit.analytics.trackAdDidFailToDisplay(in: self.ad.placement, type: "Interstitial")
        didFailPresentHandler?(error)
    }
    
    public func interstitialAdDidDismiss(_ interstitialAd: YandexMobileAds.InterstitialAd) {
        AdKit.analytics.trackAdDidHide(in: self.ad.placement, type: "Interstitial")
        didCloseHandler?()
    }
    
    public func interstitialAdDidClick(_ interstitialAd: YandexMobileAds.InterstitialAd) {
        AdKit.analytics.trackAdDidClick(in: self.ad.placement, type: "Interstitial")
        didClickHandler?()
    }
    // MARK: - MAInterstitialAdDelegate (AppLovin)
    
    public func didLoad(_ ad: MAAd) {
        retryAttempt = 0
        retryTimer?.invalidate()
        retryTimer = nil
        isRetrying = false
        failedRequests.reset()
        let loadingTime = AdLoadTimeTracker.loadingTime(since: appLovinLoadStartDate)
        appLovinLoadStartDate = nil

        // CPM-бэкофф: оцениваем доходность ДО того, как считать интер готовым к показу.
        let decision = AdCPMBackoffManager.shared.evaluateInterstitial(revenue: ad.revenue, adUnitID: ad.adUnitIdentifier)
        if case .backoff(let delay, let cpmLevel) = decision {
            // Низкий CPM — интер не готов к показу, перезапрашиваем загрузку через бэкофф-интервал.
            isCPMApproved = false
            AdKit.analytics.trackAdDidSkipPresent(in: self.ad.placement, type: "Interstitial", failedRequests: failedRequests.value, cpmLevel: cpmLevel)
            scheduleCPMBackoffReload(after: delay)
            return
        }
        isCPMApproved = true

        AdKit.analytics.trackFullAdDidLoad(
            in: self.ad.placement,
            type: "Interstitial",
            displayCount: AdKit.storage.interstitialDisplayCount,
            fullScreenDisplayCount: AdKit.storage.fullScreenDisplayCount,
            totalAdsDisplayCount: AdKit.storage.totalAdsDisplayCount,
            loadingTime: loadingTime
        )
        didLoadHandler?()
    }

    /// Перезапрос загрузки AppLovin-интера после CPM-бэкоффа.
    private func scheduleCPMBackoffReload(after delay: TimeInterval) {
        AdKitLog.log("бэкофф inter '\(ad.placement)': перезапрос через \(delay) с")
        cpmBackoffTimer?.invalidate()
        cpmBackoffTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self = self, UIApplication.shared.applicationState == .active else { return }
            self.loadAppLovinAd()
        }
    }

    /// Готов ли интер к показу. Для AppLovin учитываем CPM-аппрув; прочие сети — по их готовности.
    public func isReadyToPresent() -> Bool {
        if appLovinInterstitial != nil {
            return isCPMApproved && (appLovinInterstitial?.isReady ?? false)
        } else if yandexInterstitial != nil {
            return true
        } else if googleInterstitial != nil || AMAdPreloadManager.shared.isAdAvailable(for: self.ad.googleID) {
            return true
        }
        return false
    }

    public func didFailToLoadAd(forAdUnitIdentifier adUnitIdentifier: String, withError error: MAError) {
        failedRequests.increment()
        AdKit.analytics.trackAdDidFailToLoad(in: self.ad.placement, type: "Interstitial", failedRequests: failedRequests.value, error: error.message)
        didFailPresentHandler?(nil)
        scheduleRetry()
    }
    
    public func didDisplay(_ ad: MAAd) {
        AdKit.storage.interstitialAdPresentedTime = Date().timeIntervalSince1970
        let level = AdCPMBackoffManager.shared.cpmLevel(revenue: ad.revenue, adUnitID: ad.adUnitIdentifier)
        incrementInterstitialDisplayCount(cpmLevel: level)
        didShowHandler?()
    }
    
    public func didHide(_ ad: MAAd) {
        AdKit.analytics.trackAdDidHide(in: self.ad.placement, type: "Interstitial")
        didCloseHandler?()
    }
    
    public func didClick(_ ad: MAAd) {
        AdKit.analytics.trackAdDidClick(in: self.ad.placement, type: "Interstitial")
        didClickHandler?()
    }
    
    public func didPayRevenue(for ad: MAAd) {
        AdKit.analytics.trackAdRevenue(in: self.ad.placement, type: "Interstitial", value: ad.revenue.decimalValue, currency: "USD", network: "AppLovin", adNetwork: ad.networkName, unitId: ad.adUnitIdentifier)
    }
    
    public func didFail(toDisplay ad: MAAd, withError error: MAError) {
        AdKit.analytics.trackAdDidFailToDisplay(in: self.ad.placement, type: "Interstitial")
        didFailPresentHandler?(nil)
        scheduleRetry()
    }
    
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
    
    private func incrementInterstitialDisplayCount(cpmLevel: Double? = nil) {
        let newInterstitialCount = (AdKit.storage.interstitialDisplayCount) + 1
        let newFullScreenCount = (AdKit.storage.fullScreenDisplayCount) + 1
        let newAllCount = (AdKit.storage.totalAdsDisplayCount) + 1

        AdKit.storage.interstitialDisplayCount = newInterstitialCount
        AdKit.storage.fullScreenDisplayCount = newFullScreenCount
        AdKit.storage.totalAdsDisplayCount = newAllCount

        AdKit.analytics.trackFullAdDidDisplay(
            in: ad.placement,
            type: "Interstitial",
            failedRequests: failedRequests.value,
            displayCount: newInterstitialCount,
            fullScreenDisplayCount: newFullScreenCount,
            totalAdsDisplayCount: newAllCount,
            cpmLevel: cpmLevel
        )
    }
}
