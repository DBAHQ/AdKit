//
//  AMBannerAd.swift
//  AdKit
//

import GoogleMobileAds
import YandexMobileAds
import AppLovinSDK

/// Прослойка между контейнером приложения и вью рекламной сети.
///
/// Нужна ровно ради одного: поймать момент, когда баннер уходит с экрана (pop,
/// смена вкладки) и когда возвращается. Сами SDK этого не отслеживают — `MAAdView`
/// и `BannerView` крутят авто-рефреш, пока живы, даже в отрыве от окна. А живут они
/// до конца сессии: `AMBannerAd` лежит в статическом кэше по плейсменту и никем не
/// выбрасывается. В итоге каждый посещённый экран оставлял за собой баннер, который
/// до конца сессии слал `adDidLoad` со своим (давно закрытым) плейсментом.
final class BannerHostView: UIView {

    /// Слабая: владелец — `AMBannerAd`, который сам держит эту вью.
    weak var ad: AMBannerAd?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            ad?.pauseAutoRefresh()
        } else {
            ad?.resumeAutoRefresh()
        }
    }
}

class AMBannerAd: NSObject, BannerViewDelegate, AdViewDelegate, MAAdViewAdDelegate, MAAdRevenueDelegate {
    
    // MARK: - Static Methods
    
    static func get(_ ad: AdPlacement, size: Size) -> AMBannerAd {
        let key = ad.placement
        if let banner = banners[key] {
            if let time = bannersLastLoadTime[key], Date().timeIntervalSince1970 - time.timeIntervalSince1970 > bannersCountdownToRefresh {
                AdKitLog.log("кэш banner '\(key)': истёк TTL \(bannersCountdownToRefresh) с, пересоздаю")
                banner.stopAd()
                let banner = AMBannerAd(ad: ad, size: size)
                bannersLastLoadTime[key] = Date()
                banners[key] = banner
                return banner
            } else {
                AdKitLog.log("кэш banner '\(key)': отдаю из кэша, TTL \(bannersCountdownToRefresh) с ещё не истёк")
                return banner
            }
        } else {
            AdKitLog.log("кэш banner '\(key)': в кэше пусто, создаю (TTL \(bannersCountdownToRefresh) с\(bannersCountdownToRefresh == 0 ? " — обновление по TTL выключено" : ""))")
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
    
    /// Вычисляемое, а не `static let`: раньше значение фиксировалось при первом
    /// обращении, а на первом запуске это происходило до прихода Remote Config —
    /// и нулевой TTL держался до конца сессии.
    private static var bannersCountdownToRefresh: Double { AdKit.remoteConfig.bannerAdRefreshRate }
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
    /// Одна на всё время жизни объекта: переезжает из контейнера в контейнер вместе
    /// с вью сети, поэтому подписка на уход с экрана не теряется между показами.
    private var hostView: BannerHostView?
    private var isAutoRefreshPaused = false
    /// Сеть, под которую собрана текущая вью. Провайдер может смениться между
    /// попытками: настройки бэкенда приезжают позже Remote Config.
    private var attachedProvider: AdProvider?
    /// Было ли хоть одно успешно загруженное объявление в этом объекте.
    private var hasEverLoaded = false
    /// Повтор отложен до возвращения контейнера на экран.
    private var needsReloadWhenVisible = false
    private weak var lastContainerView: UIView?
    private var configReadyObserver: NSObjectProtocol?
    
    // MARK: - Initializers
    
    init(ad: AdPlacement, size: Size) {
        self.ad = ad
        self.size = size
        super.init()
        observeConfigReady()
    }

    deinit {
        if let configReadyObserver {
            NotificationCenter.default.removeObserver(configReadyObserver)
        }
    }

    /// На чистой установке баннер уходит в сеть раньше, чем приезжают настройки
    /// бэкенда: `mediationProvider` ещё пуст, провайдер выбирается запасным (AdMob),
    /// и такой запрос обычно не наливается. Второй попытки не было — место оставалось
    /// пустым до перезапуска приложения. Нативка этим не болела: у неё свои повторы.
    private func observeConfigReady() {
        configReadyObserver = NotificationCenter.default.addObserver(
            forName: AdKit.configDidBecomeReadyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reloadIfNeverLoaded()
        }
    }

    /// Повтор только пока объявления вообще не было: дальше загрузками управляет
    /// авто-рефреш сети, и дёргать её своими запросами не нужно.
    private func reloadIfNeverLoaded() {
        guard !hasEverLoaded, let container = lastContainerView else { return }

        // Контейнер мог уехать под другой плейсмент: приложение снимает нашу прослойку
        // и ставит туда свою. Тогда повторять нечего — иначе мы вернём в чужой контейнер
        // баннер брошенного плейсмента, и он будет крутить там свой рефреш.
        guard let host = hostView, host.superview != nil else {
            AdKitLog.log("banner '\(ad.placement)': прослойка снята с контейнера — повтор не нужен")
            needsReloadWhenVisible = false
            return
        }

        guard container.window != nil else {
            AdKitLog.log("banner '\(ad.placement)': конфиг приехал, но контейнер вне окна — повтор отложен")
            needsReloadWhenVisible = true
            return
        }

        AdKitLog.log("banner '\(ad.placement)': объявления так и не было, повторяю с новым конфигом")
        _ = loadAd(containerView: container)
    }

    /// Смена сети между попытками: прежнюю вью надо убрать, иначе она останется
    /// в прослойке вторым слоем и будет держать свой рефреш.
    private func discardNetworkViews() {
        googleBannerView?.isAutoloadEnabled = false
        googleBannerView?.removeFromSuperview()
        googleBannerView = nil

        appLovinBannerView?.stopAutoRefresh()
        appLovinBannerView?.removeFromSuperview()
        appLovinBannerView = nil

        yandexBannerView?.removeFromSuperview()
        yandexBannerView = nil

        isAutoRefreshPaused = false
    }

    /// Объявление наконец пришло — повторы больше не нужны.
    private func noteLoadSucceeded() {
        hasEverLoaded = true
        needsReloadWhenVisible = false
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
        lastContainerView = containerView
        needsReloadWhenVisible = false
        let providers = AdManager.shared.getEligibleProviders(for: .banner)
        
        guard let provider = providers.first else {
            didFailLoadHandler?(NSError(domain: "AdLoader", code: -1, userInfo: [NSLocalizedDescriptionKey: "No ad providers available for Banner."]))
            return nil
        }
        
        if let attachedProvider, attachedProvider != provider {
            AdKitLog.log("banner '\(ad.placement)': провайдер сменился \(attachedProvider.rawValue) → \(provider.rawValue), убираю прежнюю вью")
            discardNetworkViews()
        }
        attachedProvider = provider
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
            attachBanner(bannerView, to: containerView)
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
            
            attachBanner(bannerView, to: containerView)
            
            bannerView.loadAd()
        }
        return hostView
    }
    
    private func loadGoogleAd(containerView: UIView) -> UIView? {
        guard isAdsAvailableOnDevice, !isUserSubscriber else {
            return nil
        }
        
        if let bannerView = self.googleBannerView {
            attachBanner(bannerView, to: containerView)
            resumeAutoRefresh()
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
            
            attachBanner(bannerView, to: containerView)
        }
        
        return hostView
    }
    
    private func loadAppLovinAd(containerView: UIView) -> UIView? {
        guard isAdsAvailableOnDevice, !isUserSubscriber else {
            return nil
        }
        
        if let bannerView = self.appLovinBannerView {
            attachBanner(bannerView, to: containerView)
            resumeAutoRefresh()
            appLovinLoadStartDate = AdLoadTimeTracker.loadStarted()
            bannerView.loadAd()
            return hostView
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
        
        attachBanner(bannerView, to: containerView)
        
        return hostView
    }
    
    func stopAd() {
        pauseAutoRefresh()

        googleBannerView?.removeFromSuperview()
        googleBannerView = nil
        
        appLovinBannerView?.removeFromSuperview()
        appLovinBannerView = nil

        hostView?.ad = nil
        hostView?.removeFromSuperview()
        hostView = nil
    }

    // MARK: - Auto Refresh

    /// Вью сети живёт внутри прослойки пакета, а не прямо в контейнере приложения:
    /// приложение вольно выбрасывать и переиспользовать контейнеры, а прослойка одна
    /// и переезжает вместе с баннером, сохраняя подписку на появление/уход с экрана.
    @discardableResult
    private func attachBanner(_ adView: UIView, to containerView: UIView) -> BannerHostView {
        let host: BannerHostView
        if let existing = hostView {
            host = existing
        } else {
            host = BannerHostView()
            host.ad = self
            host.backgroundColor = .clear
            hostView = host
        }

        if host.superview !== containerView {
            host.removeFromSuperview()
            containerView.addSubview(host)
            host.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                host.leftAnchor.constraint(equalTo: containerView.leftAnchor),
                host.topAnchor.constraint(equalTo: containerView.topAnchor),
                host.rightAnchor.constraint(equalTo: containerView.rightAnchor),
                host.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
            ])
        }

        if adView.superview !== host {
            adView.removeFromSuperview()
            host.addSubview(adView)
            adView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                adView.leftAnchor.constraint(equalTo: host.leftAnchor),
                adView.topAnchor.constraint(equalTo: host.topAnchor),
                adView.rightAnchor.constraint(equalTo: host.rightAnchor),
                adView.bottomAnchor.constraint(equalTo: host.bottomAnchor)
            ])
        }

        return host
    }

    /// Баннер ушёл с экрана. Рефреш сети сам не останавливается: `AMBannerAd` лежит
    /// в статическом кэше, вью сети держится за него — и до конца сессии подгружает
    /// новые объявления, отправляя `adDidLoad` с плейсментом закрытого экрана.
    /// У Яндекса авто-рефреша нет: его `AdView` грузится только явным `loadAd()`.
    func pauseAutoRefresh() {
        guard !isAutoRefreshPaused else { return }
        isAutoRefreshPaused = true
        appLovinBannerView?.stopAutoRefresh()
        googleBannerView?.isAutoloadEnabled = false
        AdKitLog.log("banner '\(ad.placement)': ушёл с экрана — авто-рефреш на паузе")
    }

    /// Баннер снова на экране — возвращаем рефреш.
    func resumeAutoRefresh() {
        if isAutoRefreshPaused {
            isAutoRefreshPaused = false
            appLovinBannerView?.startAutoRefresh()
            googleBannerView?.isAutoloadEnabled = true
            AdKitLog.log("banner '\(ad.placement)': снова на экране — авто-рефреш возобновлён")
        }

        if needsReloadWhenVisible {
            reloadIfNeverLoaded()
        }
    }

    /// Ответ сети пришёл, когда баннера на экране уже нет: контроллер успел уйти вместе
    /// с прослойкой, и `didMoveToWindow` не пришёл (вью уничтожили, а не сняли с окна).
    /// Гасим рефреш прямо в колбэке — это последний рубеж, после него хвост обрывается.
    /// Само событие отправляем: это честный ответ на запрос с ещё открытого экрана.
    private func pauseAutoRefreshIfDetached() {
        guard hostView?.window == nil else { return }
        pauseAutoRefresh()
    }
    
    // MARK: - GADBannerViewDelegate
    
    func bannerViewDidReceiveAd(_ bannerView: BannerView) {
        pauseAutoRefreshIfDetached()
        noteLoadSucceeded()
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
        pauseAutoRefreshIfDetached()
        noteLoadSucceeded()
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
        pauseAutoRefreshIfDetached()
        noteLoadSucceeded()
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
