//
//  AMNativeAd.swift
//  AdKit
//

import GoogleMobileAds
import AppLovinSDK

class AMNativeAd {
    
    // MARK: - Static Methods
    
    static func get(with adUnit: NativeAdPlacement) -> AMNativeAd {
        let key = adUnit.placement
        if let ad = ads[key], let lastLoadTime = adsLastLoadTime[key], Date().timeIntervalSince(lastLoadTime) < adsCountdownToRefresh {
            return ad
        } else {
            ads[key]?.remove()
            let ad = AMNativeAd(adUnit: adUnit)
            ads[key] = ad
            adsLastLoadTime[key] = Date()
            return ad
        }
    }
    
    // MARK: - Static Properties
    
    private static var ads: [String : AMNativeAd] = [:]
    private static var adsLastLoadTime: [String : Date] = [:]
    private static let adsCountdownToRefresh = AdKit.remoteConfig.nativeAdRefreshRate
    
    // MARK: - Private Properties
    
    private var bannerView: BannerNativeView?
    private let adUnit: NativeAdPlacement
    private let failedRequests = ThreadSafeCounter(identifier: "native")

    private init(adUnit: NativeAdPlacement) {
        self.adUnit = adUnit
    }
        
    // MARK: - Public Methods
    
    func loadAd(in view: UIView) -> BannerNativeView {
        guard bannerView == nil else {
            view.addSubview(bannerView!)
            bannerView?.translatesAutoresizingMaskIntoConstraints = false
            bannerView?.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
            bannerView?.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
            bannerView?.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true
            bannerView?.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
            return bannerView!
        }
        
        bannerView = BannerNativeView()
        bannerView?.adUnit = adUnit
        view.addSubview(bannerView!)
        bannerView?.translatesAutoresizingMaskIntoConstraints = false
        bannerView?.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
        bannerView?.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        bannerView?.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true
        bannerView?.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
        return bannerView!
    }
    
    func remove() {
        bannerView?.removeFromSuperview()
        bannerView = nil
    }
    
}
