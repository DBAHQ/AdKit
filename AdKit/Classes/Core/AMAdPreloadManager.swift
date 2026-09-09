//
//  AMAdPreloadManager.swift
//  AdKit
//

import GoogleMobileAds

class AMAdPreloadManager: NSObject, PreloadDelegate {
    
    // MARK: - Singleton
    
    static let shared = AMAdPreloadManager()
    
    // MARK: - Properties
    
    private var preloadedAdUnitIDs: Set<String> = []
    private var delegateMap: [String: WeakObjectContainer<NSObject & PreloadDelegate>] = [:]
    
    // MARK: - Initialization
    
    private override init() {
        super.init()
    }
    
    // MARK: - Public Methods
    
    func startPreloading(adUnitID: String, delegate: (NSObject & PreloadDelegate)? = nil) {
        guard !preloadedAdUnitIDs.contains(adUnitID) else { return }
        
        let request = Request()
        let config = PreloadConfigurationV2(adUnitID: adUnitID, request: request)
         config.bufferSize = 3
        
        if let delegate = delegate {
            delegateMap[adUnitID] = WeakObjectContainer(object: delegate)
        }
        
        InterstitialAdPreloader.shared.preload(
            for: adUnitID,
            configuration: config,
            delegate: self
        )
        
        preloadedAdUnitIDs.insert(adUnitID)
    }
    
    func stopPreloading(adUnitID: String) {
        InterstitialAdPreloader.shared.stopPreloadingAndRemoveAds(for: adUnitID)
        preloadedAdUnitIDs.remove(adUnitID)
        delegateMap.removeValue(forKey: adUnitID)
    }
    
    func isAdAvailable(for adUnitID: String) -> Bool {
        return InterstitialAdPreloader.shared.isAdAvailable(with: adUnitID)
    }
    
    func getAd(for adUnitID: String) -> InterstitialAd? {
        return InterstitialAdPreloader.shared.ad(with: adUnitID)
    }
    
    // MARK: - PreloadDelegate
    
    func adAvailable(forPreloadID preloadID: String, responseInfo: ResponseInfo) {
        delegateMap[preloadID]?.object?.adAvailable(forPreloadID: preloadID, responseInfo: responseInfo)
    }
    
    func adsExhausted(forPreloadID preloadID: String) {
        delegateMap[preloadID]?.object?.adsExhausted(forPreloadID: preloadID)
    }
    
    func adFailedToPreload(forPreloadID preloadID: String, error: Error) {
        delegateMap[preloadID]?.object?.adFailedToPreload(forPreloadID: preloadID, error: error)
    }
}

class WeakObjectContainer<T: AnyObject> {
    weak var object: T?
    
    init(object: T) {
        self.object = object
    }
}
