//
//  AMBannerAd.swift
//  AdKit
//

import GoogleMobileAds
import YandexMobileAds
import AppLovinSDK

class AMBannerAd: NSObject, BannerViewDelegate, AdViewDelegate, MAAdViewAdDelegate, MAAdRevenueDelegate {
    
    // MARK: - Static Methods
    
    static func get(_ ad: AdPlacement, size: Size) -> AMBannerAd {
        let key = ad.placement
        if let banner = banners[key] {
            if let time = bannersLastLoadTime[key], Date().timeIntervalSince1970 - time.timeIntervalSince1970 > bannersCountdownToRefresh {
                banner.stopAd()
                let banner = AMBannerAd(ad: ad, size: size)
                bannersLastLoadTime[key] = Date()
                banners[key] = banner
                return banner
            } else {
                return banner
            }
        } else {
            let banner = AMBannerAd(ad: ad, size: size)
            bannersLastLoadTime[key] = Date()
            banners[key] = banner
            return banner
        }
    }
    
    static func stop(_ ad: AdPlacement) {
        if let banner = banners[ad.placement] {
            banner.stopAd()
        }
    }
    
    // MARK: - Static Properties
    
    private static let bannersCountdownToRefresh = AdKit.remoteConfig.bannerAdRefreshRate
    private static var banners: [String : AMBannerAd] = [:]
    private static var bannersLastLoadTime: [String : Date] = [:]
    
    // MARK: - Enums
    
    enum Size: String {
        case regular = "BANNER"
        case large = "LARGE"
        case smart = "SMART"
        case rectangle = "RECTANGLE"
        
        var adSize: GoogleMobileAds.AdSize {
            switch self {
            case .regular:
                return AdSizeBanner
            case .large:
                return AdSizeLargeBanner
            case .smart:
                return AdSizeLargeBanner
            case .rectangle:
                return AdSizeMediumRectangle
            }
        }
    }
    
    // MARK: - Private Properties
    
    private var ad: AdPlacement
    private var size: Size
    
    private let failedRequests = ThreadSafeCounter(identifier: "banner")
    private var appLovinLoadStartDate: Date?

    // MARK: - Handlers Properties
    
    private var didLoadHandler: (() -> ())?
    private var didFailLoadHandler: ((Error?) -> ())?
    private var didClickHandler: (() -> ())?
    
    // MARK: - Dynamic Properties
    
    private var isUserSubscriber: Bool {
        return AdKit.host.hasSubscription
    }
    
    private var isAdsAvailableOnDevice: Bool {
        #if os(macOS)
            return false
        #else
            return true
        #endif
    }
    
    // MARK: - Views
    
    private var yandexBannerView: AdView?
    private var googleBannerView: BannerView?
    private var appLovinBannerView: MAAdView?
    
    // MARK: - Initializers
    
    init(ad: AdPlacement, size: Size) {
        self.ad = ad
        self.size = size
        super.init()
    }
    
    // MARK: - Setters
    
    func setDidLoadHandler(_ handler: (() -> ())?) -> AMBannerAd {
        self.didLoadHandler = handler
        return self
    }
    
    func setDidFailLoadHandler(_ handler: ((Error?) -> ())?) -> AMBannerAd {
        self.didFailLoadHandler = handler
        return self
    }
    
    func setDidClickHandler(_ handler: (() -> ())?) -> AMBannerAd {
        self.didClickHandler = handler
        return self
    }
    
    // MARK: - Ad Loading
    
    func loadAd(containerView: UIView) -> UIView? {
        AdKitLog.log("banner '\(ad.placement)': загрузка")
        let providers = AdManager.shared.getEligibleProviders(for: .banner)
        
        guard let provider = providers.first else {
            didFailLoadHandler?(NSError(domain: "AdLoader", code: -1, userInfo: [NSLocalizedDescriptionKey: "No ad providers available for Banner."]))
            return nil
        }
        
        AdKitLog.log("banner '\(ad.placement)': провайдер \(provider.rawValue)")
        switch provider {
        case .yandex:
            return loadYandexAd(containerView: containerView)
        case .appLovin:
            return loadAppLovinAd(containerView: containerView)
        case .admob:
            return loadGoogleAd(containerView: containerView)
        }
    }
    
    private func loadYandexAd(containerView: UIView) -> UIView? {
        guard isAdsAvailableOnDevice, !isUserSubscriber else {
            AdKitLog.log("banner '\(ad.placement)': Яндекс пропущен — доступна на устройстве: \(isAdsAvailableOnDevice), подписчик: \(isUserSubscriber)")
            return nil
        }
        AdKitLog.log("banner '\(ad.placement)': запрос Яндекса, юнит \(ad.yandexID)")
        
        guard containerView.frame.width > 0 else {
            return nil
        }
        
        if let bannerView = self.yandexBannerView {
            if bannerView.superview == containerView {
            } else {
                containerView.addSubview(bannerView)
                bannerView.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    bannerView.leftAnchor.constraint(equalTo: containerView.leftAnchor),
                    bannerView.topAnchor.constraint(equalTo: containerView.topAnchor),
                    bannerView.rightAnchor.constraint(equalTo: containerView.rightAnchor),
                    bannerView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
                ])
            }
        } else {
            AdKit.analytics.trackBannerAdDidRequest(
                in: self.ad.placement,
                type: "Banner",
                bannersDisplayCount: AdKit.storage.bannerAndNativeDisplayCount,
                displayCount: AdKit.storage.bannerDisplayCount,
                totalAdsDisplayCount: AdKit.storage.totalAdsDisplayCount
            )
            
            let bannerView = AdView(adUnitID: ad.yandexID, adSize: .stickySize(withContainerWidth: containerView.frame.width))
            self.yandexBannerView = bannerView
            
            bannerView.delegate = self
            
            containerView.addSubview(bannerView)
            bannerView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                bannerView.leftAnchor.constraint(equalTo: containerView.leftAnchor),
                bannerView.topAnchor.constraint(equalTo: containerView.topAnchor),
                bannerView.rightAnchor.constraint(equalTo: containerView.rightAnchor),
                bannerView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
            ])
            
            bannerView.loadAd()
        }
        return yandexBannerView
    }
    
    private func loadGoogleAd(containerView: UIView) -> UIView? {
        guard isAdsAvailableOnDevice, !isUserSubscriber else {
            return nil
        }
        
        if let bannerView = self.googleBannerView {
            if bannerView.superview == containerView {
                bannerView.isAutoloadEnabled = true
            } else {
                bannerView.isAutoloadEnabled = true
                containerView.addSubview(bannerView)
                bannerView.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    bannerView.leftAnchor.constraint(equalTo: containerView.leftAnchor),
                    bannerView.topAnchor.constraint(equalTo: containerView.topAnchor),
                    bannerView.rightAnchor.constraint(equalTo: containerView.rightAnchor),
                    bannerView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
                ])
            }
        } else {
            AdKit.analytics.trackBannerAdDidRequest(
                in: self.ad.placement,
                type: "Banner",
                bannersDisplayCount: AdKit.storage.bannerAndNativeDisplayCount,
                displayCount: AdKit.storage.bannerDisplayCount,
                totalAdsDisplayCount: AdKit.storage.totalAdsDisplayCount
            )
            let bannerView = BannerView(adSize: size.adSize)
            self.googleBannerView = bannerView
            
            bannerView.adUnitID = ad.googleID
            bannerView.delegate = self
            bannerView.rootViewController = containerView.viewController ?? UIApplication.shared.visibleViewController
            bannerView.isAutoloadEnabled = true
            bannerView.paidEventHandler = { [weak self] value in
                let winningNetwork = self?.googleBannerView?.responseInfo?.loadedAdNetworkResponseInfo?.adSourceName ?? "AdMob"
                // Раньше при уничтоженном self подставлялся кейс .others приложения —
                // событие уходило с чужим плейсментом. В пакете такого кейса нет.
                guard let self else { return }
                AdKit.analytics.trackAdRevenue(in: self.ad.placement, type: "Banner", value: value.value.decimalValue, currency: value.currencyCode, network: "AdMob", adNetwork: winningNetwork, unitId: self.ad.googleID)
            }
            
            containerView.addSubview(bannerView)
            bannerView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                bannerView.leftAnchor.constraint(equalTo: containerView.leftAnchor),
                bannerView.topAnchor.constraint(equalTo: containerView.topAnchor),
                bannerView.rightAnchor.constraint(equalTo: containerView.rightAnchor),
                bannerView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
            ])
        }
        
        return googleBannerView
    }
    
    private func loadAppLovinAd(containerView: UIView) -> UIView? {
        guard isAdsAvailableOnDevice, !isUserSubscriber else {
            return nil
        }
        
        if let bannerView = self.appLovinBannerView {
            if bannerView.superview != containerView {
                containerView.addSubview(bannerView)
                bannerView.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    bannerView.leftAnchor.constraint(equalTo: containerView.leftAnchor),
                    bannerView.topAnchor.constraint(equalTo: containerView.topAnchor),
                    bannerView.rightAnchor.constraint(equalTo: containerView.rightAnchor),
                    bannerView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
                ])
            }
            appLovinLoadStartDate = AdLoadTimeTracker.loadStarted()
            bannerView.loadAd()
            return bannerView
        }
        
        AdKit.analytics.trackBannerAdDidRequest(
            in: self.ad.placement,
            type: "Banner",
            bannersDisplayCount: AdKit.storage.bannerAndNativeDisplayCount,
            displayCount: AdKit.storage.bannerDisplayCount,
            totalAdsDisplayCount: AdKit.storage.totalAdsDisplayCount
        )
        
        let adWidth = max(containerView.layer.frame.size.width, size.adSize.size.width)
        let adHeight: CGFloat = (size == .rectangle) ? 250 : 50
        
        let bannerView = MAAdView(adUnitIdentifier: ad.appLovinID)
        bannerView.delegate = self
        bannerView.revenueDelegate = self
        bannerView.frame = CGRect(x: 0, y: 0, width: adWidth, height: adHeight)
        appLovinLoadStartDate = AdLoadTimeTracker.loadStarted()
        bannerView.loadAd()
        self.appLovinBannerView = bannerView
        
        containerView.addSubview(bannerView)
        bannerView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            bannerView.leftAnchor.constraint(equalTo: containerView.leftAnchor),
            bannerView.topAnchor.constraint(equalTo: containerView.topAnchor),
            bannerView.rightAnchor.constraint(equalTo: containerView.rightAnchor),
            bannerView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        
        return bannerView
    }
    
    func stopAd() {
        googleBannerView?.isAutoloadEnabled = false
        googleBannerView?.removeFromSuperview()
        googleBannerView = nil
        
        appLovinBannerView?.removeFromSuperview()
        appLovinBannerView = nil
    }
    
    // MARK: - GADBannerViewDelegate
    
    func bannerViewDidReceiveAd(_ bannerView: BannerView) {
        failedRequests.reset()
        AdKit.analytics.trackBannerAdDidLoad(in: ad.placement, type: "Banner",
                                                     bannersDisplayCount: AdKit.storage.bannerAndNativeDisplayCount,
                                                     displayCount: AdKit.storage.bannerDisplayCount,
                                                     totalAdsDisplayCount: AdKit.storage.totalAdsDisplayCount
)
        didLoadHandler?()
    }
    
    func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
        failedRequests.increment()
        AdKit.analytics.trackAdDidFailToLoad(in: ad.placement, type: "Banner", failedRequests: failedRequests.value, error: error.localizedDescription)
        didFailLoadHandler?(error)
    }
    
    func bannerViewDidRecordClick(_ bannerView: BannerView) {
        AdKit.analytics.trackAdDidClick(in: ad.placement, type: "Banner")
        didClickHandler?()
    }
    
    func bannerViewDidRecordImpression(_ bannerView: BannerView) {
        incrementBannerDisplayCount()
    }
    
    func bannerViewWillDismissScreen(_ bannerView: BannerView) {
        AdKit.analytics.trackAdDidHide(in: ad.placement, type: "Banner")
    }
    
    // MARK: - AdViewDelegate (Yandex)

    func adViewDidLoad(_ adView: AdView) {
        failedRequests.reset()
        AdKit.analytics.trackBannerAdDidLoad(in: ad.placement, type: "Banner",
                                                     bannersDisplayCount: AdKit.storage.bannerAndNativeDisplayCount,
                                                     displayCount: AdKit.storage.bannerDisplayCount,
                                                     totalAdsDisplayCount: AdKit.storage.totalAdsDisplayCount)
        didLoadHandler?()
    }

    func adViewDidFailLoading(_ adView: AdView, error: any Error) {
        failedRequests.increment()
        AdKit.analytics.trackAdDidFailToLoad(in: ad.placement, type: "Banner", failedRequests: failedRequests.value, error: error.localizedDescription)
        didFailLoadHandler?(error)
        
        if adView == yandexBannerView {
            yandexBannerView?.removeFromSuperview()
            yandexBannerView = nil
        }
    }

    
    func adViewDidClick(_ adView: AdView) {
        AdKit.analytics.trackAdDidClick(in: ad.placement, type: "Banner")
        didClickHandler?()
    }
    
    func adView(_ adView: AdView, didTrackImpression impressionData: (any ImpressionData)?) {
        incrementBannerDisplayCount()
        AdKit.analytics.trackBannerAdDidDisplay(
            in: ad.placement,
            type: "Banner",
            failedRequests: failedRequests.value,
            bannersDisplayCount: AdKit.storage.bannerAndNativeDisplayCount,
            displayCount: AdKit.storage.bannerDisplayCount,
            totalAdsDisplayCount: AdKit.storage.totalAdsDisplayCount
        )
        if let data = impressionData?.rawData.data(using: .utf8) {
            do {
                guard let dict = try JSONSerialization.jsonObject(with: data, options: []) as? [String : Any], let revenue = (dict["revenueUSD"] as? String)?.decimal else {
                    return
                }
                
                AdKit.analytics.trackAdRevenue(in: ad.placement, type: "Banner", value: revenue, currency: "USD", network: "Yandex")
            } catch {
                print(error.localizedDescription)
            }
        }
    }

    
    func adView(_ adView: AdView, didDismissScreen viewController: UIViewController?) {
        AdKit.analytics.trackAdDidHide(in: ad.placement, type: "Banner")
    }
    
    // MARK: - MAAdViewAdDelegate (AppLovin)

    func didLoad(_ ad: MAAd) {
        failedRequests.reset()
        let loadingTime = AdLoadTimeTracker.loadingTime(since: appLovinLoadStartDate)
        appLovinLoadStartDate = nil
        AdKit.analytics.trackBannerAdDidLoad(in: self.ad.placement, type: "Banner",bannersDisplayCount: AdKit.storage.bannerAndNativeDisplayCount,displayCount: AdKit.storage.bannerDisplayCount,            totalAdsDisplayCount: AdKit.storage.totalAdsDisplayCount,
            loadingTime: loadingTime
)
        didLoadHandler?()
    }

    func didFailToLoadAd(forAdUnitIdentifier adUnitIdentifier: String, withError error: MAError) {
        failedRequests.increment()
        AdKit.analytics.trackAdDidFailToLoad(in: self.ad.placement, type: "Banner", failedRequests: failedRequests.value, error: error.message)
        didFailLoadHandler?(nil)
    }

    func didDisplay(_ ad: MAAd) {
        incrementBannerDisplayCount()
    }

    func didClick(_ ad: MAAd) {
        AdKit.analytics.trackAdDidClick(in: self.ad.placement, type: "Banner")
        didClickHandler?()
    }

    func didHide(_ ad: MAAd) {
        AdKit.analytics.trackAdDidHide(in: self.ad.placement, type: "Banner")
    }

    func didExpand(_ ad: MAAd) {
//        AdKit.analytics.trackAdDidExpand(in: self.ad.placement, type: "Banner")
    }

    func didCollapse(_ ad: MAAd) {
//        AdKit.analytics.trackAdDidCollapse(in: self.ad.placement, type: "Banner")
    }
    
    func didPayRevenue(for ad: MAAd) {
        AdKit.analytics.trackAdRevenue(in: self.ad.placement, type: "Banner", value: ad.revenue.decimalValue, currency: "USD", network: "AppLovin", adNetwork: ad.networkName, unitId: ad.adUnitIdentifier)
    }

    func didFail(toDisplay ad: MAAd, withError error: MAError) {
        AdKit.analytics.trackAdDidFailToDisplay(in: self.ad.placement, type: "Banner")
        didFailLoadHandler?(nil)
    }
    private func incrementBannerDisplayCount() {
        let newBannerAndNativeCount = (AdKit.storage.bannerAndNativeDisplayCount) + 1
        let newBannerCount = (AdKit.storage.bannerDisplayCount) + 1
        let newAllCount = (AdKit.storage.totalAdsDisplayCount) + 1
        
        AdKit.storage.bannerAndNativeDisplayCount = newBannerAndNativeCount
        AdKit.storage.bannerDisplayCount = newBannerCount
        AdKit.storage.totalAdsDisplayCount = newAllCount
        
        AdKit.analytics.trackBannerAdDidDisplay(
            in: ad.placement,
            type: "Banner",
            failedRequests: failedRequests.value,
            bannersDisplayCount: newBannerAndNativeCount,
            displayCount: newBannerCount,
            totalAdsDisplayCount: newAllCount
        )
    }
}
