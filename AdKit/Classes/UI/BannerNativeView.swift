//
//  BannerNativeView.swift
//  AdKit
//
import UIKit
import GoogleMobileAds
import AppLovinSDK

class BannerNativeView: NativeAdView, NativeAdDelegate, NativeAdLoaderDelegate, MANativeAdDelegate, MAAdDelegate, MAAdRevenueDelegate {
    
    // MARK: - Private Properties

    // Tag'и для MANativeAdViewBinder — AppLovin (xcframework) рендерит ассеты по tag'ам,
    // прямое присваивание свойств (mediaContentView и т.п.) из xcframework не работает.
    private static let alTitleTag = 1
    private static let alBodyTag = 2
    private static let alCtaTag = 3
    private static let alMediaTag = 4
    private static let alIconTag = 5
    private static let alOptionsTag = 6

    /// Сторона иконки рекламодателя в media-режиме (примерно по высоте CTA-кнопки).
    private static let compactIconSide: CGFloat = 28

    var adUnit: NativeAdPlacement! {
        didSet {
            if oldValue?.id != adUnit.id || oldValue?.appLovinID != adUnit.appLovinID {
                cleanupAd()
            }
            loadAd()
        }
    }
    var adLoader: AdLoader?
    private var appLovinNativeAdLoader: MANativeAdLoader?
    private var appLovinNativeAd: MAAd?
    private let failedRequests = ThreadSafeCounter(identifier: "native")
    private var appLovinLoadStartDate: Date?
    private var fallbackTimer: Timer?
    private var backoffTimer: Timer?
    private var isAdLoaded = false
    private var isLoadingAd = false
    /// Показ (adDidDisplay) засчитывается один раз на загруженное объявление.
    /// Сбрасывается при показе нового объявления и в cleanupAd, чтобы повторный вход
    /// вьюхи в окно (didMoveToWindow на таб-экранах) не плодил фантомный adDidDisplay.
    private var didReportDisplay = false
    private var configReadyObserver: NSObjectProtocol?
    private var bannerView: UIView?
    private var isAdLoadTriggered = false
    private var loadRetryCount = 0
    private let maxLoadRetries = 3
    /// Режим отрисовки нативки (media-вью или иконка) фиксируется на время жизни одного объявления:
    /// RC-ключ может доехать между вёрсткой контейнера и колбэком загрузки, и если значение сменится
    /// посреди цикла — SDK привяжет ассет к вью, которой нет в иерархии (пустой серый слот).
    private var cachedShowsMedia: Bool?
    private var showsMedia: Bool {
        if let cached = cachedShowsMedia { return cached }
        let value = adUnit.showsMediaContent
        cachedShowsMedia = value
        return value
    }
    private var refreshTimer: Timer?
    /// Сколько раз подряд повтор упёрся в невидимый экран. Пауза растёт от 2 с к 30 с:
    /// без этого вью, экран которой давно закрыт, дёргала загрузку каждые 2 с до конца сессии.
    private var visibilityRetryCount = 0
    
    private lazy var containerView: ContainerView = {
        let view = ContainerView()
        view.edgeInsets = UIEdgeInsets(top: 2, left: 2, bottom: 2, right: 2)
        view.stackView.spacing = 8
        view.stackView.alignment = .center
        return view
    }()
    private lazy var iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.backgroundColor = AdKit.theme.mediaBackground
        imageView.layer.masksToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.widthAnchor.constraint(equalToConstant: 120).isActive = true
        imageView.heightAnchor.constraint(equalToConstant: 120).isActive = true
        return imageView
    }()
    /// Media-вью для AdMob (картинка/видео). В media-режиме встаёт НА МЕСТО иконки (слот 120×120).
    /// Используется только в media-режиме (RC-ключ `showMediaInNativeAd`).
    private lazy var googleMediaView: MediaView = {
        let mediaView = MediaView()
        mediaView.translatesAutoresizingMaskIntoConstraints = false
        mediaView.contentMode = .scaleAspectFill
        mediaView.clipsToBounds = true
        mediaView.layer.cornerRadius = 8
        mediaView.backgroundColor = AdKit.theme.mediaBackground
        mediaView.widthAnchor.constraint(equalToConstant: 120).isActive = true
        mediaView.heightAnchor.constraint(equalToConstant: 120).isActive = true
        return mediaView
    }()
    /// Иконка рекламодателя в media-режиме. Показ иконки обязателен по правилам сетей, а слот
    /// картинки занят media-вью, поэтому иконка встаёт слева от CTA-кнопки маленьким квадратом.
    /// Размер жёстко фиксирован: сеть вставляет внутрь свою вью, и от её intrinsic-размера
    /// контейнер раздувается на всю высоту баннера.
    private lazy var compactIconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.backgroundColor = AdKit.theme.mediaBackground
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 6
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.setContentHuggingPriority(.required, for: .vertical)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.widthAnchor.constraint(equalToConstant: Self.compactIconSide).isActive = true
        imageView.heightAnchor.constraint(equalToConstant: Self.compactIconSide).isActive = true
        return imageView
    }()
    private lazy var titleTextStackView: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [titleStackView, textLabel, actionStackView])
        stackView.axis = .vertical
        stackView.spacing = 4
        return stackView
    }()
    private lazy var titleStackView: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [titleLabel])
        stackView.axis = .horizontal
        stackView.spacing = 4
        return stackView
    }()
    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.font = AdKit.theme.titleFont
        label.textColor = AdKit.theme.titleColor
        label.numberOfLines = 1
        label.text = ""
        return label
    }()
    private lazy var adLabel: UILabel = {
        let label = UILabel()
        label.font = AdKit.theme.adBadgeFont
        label.textColor = AdKit.theme.adBadgeTextColor
        label.numberOfLines = 1
        label.text = "Ad"
        label.textAlignment = .center
        label.backgroundColor = AdKit.theme.adBadgeBackground
        label.layer.cornerRadius = 4
        label.layer.masksToBounds = true
        label.heightAnchor.constraint(equalToConstant: 20).isActive = true
        label.widthAnchor.constraint(equalToConstant: 20).isActive = true
        return label
    }()
    private lazy var textLabel: UILabel = {
        let label = UILabel()
        label.font = AdKit.theme.bodyFont
        label.textColor = AdKit.theme.bodyColor
        label.numberOfLines = 2
        label.text = ""
        return label
    }()
    private lazy var actionStackView: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [actionRowStackView])
        stackView.alignment = .leading
        stackView.axis = .vertical
        stackView.spacing = 4
        return stackView
    }()
    /// Строка «иконка + кнопка». В icon-режиме иконка скрыта и строка равна одной кнопке.
    private lazy var actionRowStackView: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [compactIconImageView, actionButton])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 8
        return stackView
    }()
    
    private lazy var actionButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = AdKit.theme.actionBackground
        config.baseForegroundColor = AdKit.theme.actionTitleColor
        config.title = ""
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = AdKit.theme.actionFont
            return outgoing
        }
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14)
        config.cornerStyle = .capsule

        let button = UIButton()
        button.configuration = config
        return button
    }()
    
    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        
        if superview != nil {
            observeConfigReadyIfNeeded()
            applyContainerViews()
            setupInterface()
        } else {
            stopObservingConfigReady()
            cleanupAd()
        }
    }

    deinit {
        stopObservingConfigReady()
        refreshTimer?.invalidate()
        fallbackTimer?.invalidate()
        backoffTimer?.invalidate()
    }

    // MARK: - Готовность конфига

    /// На первом запуске Remote Config приезжает уже после того, как вью
    /// попросила рекламу и получила пустой список провайдеров. Ждём сигнала
    /// и повторяем попытку — иначе место остаётся пустым до конца сессии.
    private func observeConfigReadyIfNeeded() {
        guard configReadyObserver == nil else { return }
        configReadyObserver = NotificationCenter.default.addObserver(
            forName: AdKit.configDidBecomeReadyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, !self.isAdLoaded, !self.isLoadingAd else { return }
            AdKitLog.log("native '\(self.adUnit?.placement ?? "-")': конфиг приехал, повторяю загрузку")
            self.loadAd()
        }
    }

    private func stopObservingConfigReady() {
        guard let observer = configReadyObserver else { return }
        NotificationCenter.default.removeObserver(observer)
        configReadyObserver = nil
    }
    
    override func willMove(toSuperview newSuperview: UIView?) {
        super.willMove(toSuperview: newSuperview)
        
        if newSuperview != nil && superview == nil {
        }
    }
    
    override func didMoveToWindow() {
        super.didMoveToWindow()

        guard window != nil else {
            // Вью ушла с экрана. Таймеры без этого крутились бы вечно: объект держит
            // статический кэш AMNativeAd, и `cleanupAd` для него уже не вызовется.
            // Работу возобновим здесь же, когда вью вернётся в окно.
            AdKitLog.log("native '\(adUnit?.placement ?? "-")': ушла из окна — таймеры остановлены")
            stopAutoRefreshTimer()
            backoffTimer?.invalidate()
            backoffTimer = nil
            visibilityRetryCount = 0
            return
        }

        if alpha > 0, let ad = appLovinNativeAd {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.didDisplay(ad)
            }
        }

        if isAdLoaded {
            startAutoRefreshTimer()
        } else if !isLoadingAd {
            loadAd()
        }
    }
    
    
    override func layoutSubviews() {
        super.layoutSubviews()
        if frame.width > 0 && !isAdLoadTriggered {
            isAdLoadTriggered = true
            loadAd()
        }
    }
    
    // MARK: - Public Methods
    
    func reloadAd() {
        cleanupAd()
        loadAd()
    }
    
    // MARK: - Setups

    /// Кладёт в контейнер вью под текущий режим: в media-режиме на месте иконки — MediaView
    /// (картинка/видео), иначе обычная иконка. Слот в обоих случаях 120×120.
    private func applyContainerViews() {
        containerView.setViews(showsMedia
                               ? [googleMediaView, titleTextStackView]
                               : [iconImageView, titleTextStackView])
        // Иконка рядом с кнопкой нужна только в media-режиме; появится, когда придёт ассет.
        compactIconImageView.isHidden = true
    }

    /// Подхватывает смену RC-ключа `showMediaInNativeAd` на границе циклов загрузки
    /// (между объявлениями, а не посреди одного) и перестраивает контейнер.
    private func syncMediaModeIfNeeded() {
        let current = adUnit.showsMediaContent
        guard cachedShowsMedia != current else { return }
        cachedShowsMedia = current
        guard superview != nil else { return }
        applyContainerViews()
    }
    
    private func setupInterface() {
        guard superview != nil else { return }
        backgroundColor = .clear
        
        addSubview(containerView)
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.leftAnchor.constraint(equalTo: leftAnchor).isActive = true
        containerView.topAnchor.constraint(equalTo: topAnchor).isActive = true
        containerView.rightAnchor.constraint(equalTo: rightAnchor).isActive = true
        containerView.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
        
        addSubview(adLabel)
        adLabel.translatesAutoresizingMaskIntoConstraints = false
        adLabel.rightAnchor.constraint(equalTo: rightAnchor, constant: -12).isActive = true
        adLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12).isActive = true

        iconImageView.backgroundColor = AdKit.theme.mediaBackground
        iconImageView.layer.cornerRadius = 20
        
        alpha = 0
    }
    private func cleanupAd() {
        fallbackTimer?.invalidate()
        fallbackTimer = nil
        backoffTimer?.invalidate()
        backoffTimer = nil
        stopAutoRefreshTimer()

        if let googleLoader = adLoader {
            googleLoader.delegate = nil
            adLoader = nil
        }
        isAdLoaded = false
        isLoadingAd = false
        didReportDisplay = false
        appLovinNativeAd = nil
        nativeAd = nil
        alpha = 0
        isAdLoadTriggered = false
        loadRetryCount = 0

        bannerView?.removeFromSuperview()
        bannerView = nil
        
        for subview in subviews {
            if subview is MANativeAdView {
                subview.removeFromSuperview()
            }
        }
        containerView.isHidden = false
        adLabel.isHidden = false
    }

    // MARK: - Auto Refresh
    private func startAutoRefreshTimer() {
        stopAutoRefreshTimer()

        let refreshInterval = AdKit.remoteConfig.nativeBannerRefreshTime
        guard refreshInterval > 0 else {
            AdKitLog.log("рефреш native '\(adUnit?.placement ?? "-")': выключен, nativeBannerRefreshTime = 0")
            return
        }
        AdKitLog.log("рефреш native '\(adUnit?.placement ?? "-")': таймер взведён на \(refreshInterval) с")

        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: false) { [weak self] _ in
            self?.refreshAd()
        }
    }

    /// Авто-обновление с учётом CPM-бэкоффа. Для AppLovin грузим новое объявление В ФОНЕ, НЕ убирая
    /// текущее с экрана: замена произойдёт в didLoadNativeAd только при CPM ≥ порога, иначе бэкофф и
    /// на экране остаётся прежнее. Для AdMob/Yandex — прежнее поведение (cleanup + загрузка).
    private func refreshAd() {
        AdKitLog.log("рефреш native '\(adUnit?.placement ?? "-")': сработал таймер")
        guard isHostScreenVisible() else {
            // Вне окна таймер не перевзводим: вью может быть уже выброшенной вместе с экраном,
            // и это крутилось бы до конца сессии. Рефреш вернёт didMoveToWindow.
            guard window != nil else {
                AdKitLog.log("рефреш native '\(adUnit?.placement ?? "-")': вью вне окна, таймер остановлен")
                return
            }
            AdKitLog.log("рефреш native '\(adUnit?.placement ?? "-")': экран не виден, перевзвожу таймер")
            // Экран перекрыт, но вью в окне — запрос НЕ делаем, перевзводим таймер,
            // чтобы рефреш сам возобновился, когда экран снова станет видимым.
            startAutoRefreshTimer()
            return
        }
        if AdManager.shared.getEligibleProviders(for: .native).first == .appLovin {
            // Перевзводим таймер СРАЗУ (loadAppLovinAd не делает cleanup, таймер уцелеет):
            // авто-рефреш продолжится, даже если эта загрузка не пришлёт коллбэк (AppLovin
            // иногда молчит во время показа интера). Следующий цикл создаст новый лоадер вместо
            // зависшего. На успешной загрузке таймер перевзведётся ещё раз в didLoadNativeAd.
            startAutoRefreshTimer()
            loadAppLovinAd()
        } else {
            reloadAd()
        }
    }

    private func stopAutoRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - Visibility (запрос рекламы только когда экран реально виден)

    /// VC, которому принадлежит эта вью (через responder chain).
    private var owningViewController: UIViewController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let vc = current as? UIViewController { return vc }
            responder = current.next
        }
        return nil
    }

    /// Экран-владелец рекламы сейчас реально на экране у пользователя: вью в окне,
    /// приложение активно, а VC-владелец — текущий видимый верхний экран (с учётом
    /// вложенных child-VC). alpha самой вью НЕ учитываем — важна видимость экрана.
    private func isHostScreenVisible() -> Bool {
        guard window != nil else { return false }
        guard UIApplication.shared.applicationState == .active else { return false }
        guard let owner = owningViewController,
              let visible = UIApplication.shared.visibleViewController else { return false }
        if owner === visible { return true }
        var parent = visible.parent
        while let current = parent { if current === owner { return true }; parent = current.parent }
        parent = owner.parent
        while let current = parent { if current === visible { return true }; parent = current.parent }
        return false
    }

    /// Единый гейт перед реальным запросом рекламы (первичная загрузка, ретрай, рефреш).
    /// Если экран не виден — гасим флаги загрузки и запрещаем запрос; пока реклама не
    /// загружена, периодически перепроверяем, чтобы подгрузить её, когда экран станет видимым.
    private func canRequestAd(_ source: String) -> Bool {
        guard isHostScreenVisible() else {
            isLoadingAd = false
            isAdLoadTriggered = false
            if !isAdLoaded {
                scheduleVisibilityRetry()
            }
            return false
        }
        visibilityRetryCount = 0
        return true
    }

    private func scheduleVisibilityRetry() {
        stopAutoRefreshTimer()

        // Вью вне окна — ждать нечего: загрузку перезапустит didMoveToWindow.
        guard window != nil else {
            AdKitLog.log("native '\(adUnit?.placement ?? "-")': вне окна, повтор не планируем")
            visibilityRetryCount = 0
            return
        }

        // Экран в окне, но сверху другой (модалка, таб): ждём и пробуем снова, постепенно
        // разряжая попытки, чтобы не молотить раз в 2 с всё время, пока экран перекрыт.
        let delay = min(2.0 * pow(2.0, Double(visibilityRetryCount)), 30.0)
        visibilityRetryCount += 1
        AdKitLog.log("native '\(adUnit?.placement ?? "-")': экран не виден, повтор через \(delay) с")
        refreshTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.loadAd()
        }
    }

    private func loadAd() {
        guard !isLoadingAd else {
            return
        }

        syncMediaModeIfNeeded()
        isLoadingAd = true
        isAdLoaded = false

        let providers = AdManager.shared.getEligibleProviders(for: .native)

        guard let provider = providers.first else {
            AdKitLog.log("native '\(adUnit.placement)': провайдеров нет, загрузка отменена")
            isLoadingAd = false
            return
        }
        AdKitLog.log("native '\(adUnit.placement)': провайдер \(provider.rawValue)")
        // Помечаем, что начальная загрузка уже запущена, чтобы layoutSubviews
        // не дёрнул loadAd() повторно (иначе уходит двойной adDidRequest).
        isAdLoadTriggered = true

        switch provider {
        case .appLovin:
            loadAppLovinAd()
        case .admob:
            loadGoogleAd()
        case .yandex:
            loadBannerAd()
        }
    }
    
    private func loadBannerAd() {
        guard canRequestAd("Banner") else { return }
        guard let bannerPlacement = adUnit.bannerFallback else {
            AdKitLog.log("native '\(adUnit.placement)': нет баннерного фолбэка для Яндекса")
            isLoadingAd = false
            return
        }
        let bannerAd = AMBannerAd.get(bannerPlacement, size: .large)
        
        // 1. Сначала устанавливаем обработчики успеха и провала
        bannerAd.setDidLoadHandler { [weak self] in
            self?.isLoadingAd = false
            self?.isAdLoaded = true
            self?.alpha = 1.0
            self?.loadRetryCount = 0
        }
        
        bannerAd.setDidFailLoadHandler { [weak self] error in
            guard let self = self else { return }
            self.isLoadingAd = false
            if self.loadRetryCount < self.maxLoadRetries {
                self.loadRetryCount += 1
                Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
                    self?.loadAd()
                }
            }
        }

        // 2. Только потом пытаемся загрузить рекламу
        self.bannerView = bannerAd.loadAd(containerView: self)

        // 3. Проверяем, вернулся ли nil (например, если view еще не готов)
        if self.bannerView == nil {
            isLoadingAd = false
            if self.loadRetryCount < self.maxLoadRetries {
                self.loadRetryCount += 1
                Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
                    self?.loadAd()
                }
            }
            return
        }

        containerView.isHidden = true
        adLabel.isHidden = true
    }
    
    private func loadGoogleAd() {
        guard canRequestAd("AdMob") else { return }
        AdKit.analytics.trackBannerAdDidRequest(
            in: adUnit.placement,
            type: "Native",
            bannersDisplayCount: AdKit.storage.bannerAndNativeDisplayCount,
            displayCount: AdKit.storage.nativeDisplayCount,
            totalAdsDisplayCount: AdKit.storage.totalAdsDisplayCount
        )
        let options = MultipleAdsAdLoaderOptions()
        options.numberOfAds = 1
        adLoader = AdLoader(adUnitID: adUnit.id, rootViewController: nil, adTypes: [.native], options: [options])
        adLoader?.delegate = self
        let request = GoogleMobileAds.Request()
        request.requestAgent = "TradingGuruNativeAd"
        adLoader?.load(request)
    }
    
    private func loadAppLovinAd() {
        // Сбрасываем флаг, чтобы пришедшее (в т.ч. по бэкоффу) объявление прошло в рендер.
        isAdLoaded = false

        guard canRequestAd("AppLovin") else { return }
        AdKit.analytics.trackBannerAdDidRequest(
            in: adUnit.placement,
            type: "Native",
            bannersDisplayCount: AdKit.storage.bannerAndNativeDisplayCount,
            displayCount: AdKit.storage.nativeDisplayCount,
            totalAdsDisplayCount: AdKit.storage.totalAdsDisplayCount
        )
        
        appLovinNativeAdLoader = MANativeAdLoader(adUnitIdentifier: adUnit.appLovinID)
        appLovinNativeAdLoader?.nativeAdDelegate = self
        appLovinNativeAdLoader?.revenueDelegate = self

        appLovinLoadStartDate = AdLoadTimeTracker.loadStarted()
        appLovinNativeAdLoader?.loadAd()
    }

    /// Перезапрос загрузки AppLovin после CPM-бэкоффа. Если экран не виден — откладываем
    /// перезапрос и пробуем снова позже (не грузим рекламу на невидимом экране).
    private func scheduleAppLovinBackoffReload(after delay: TimeInterval) {
        AdKitLog.log("бэкофф native '\(adUnit?.placement ?? "-")': перезапрос через \(delay) с")
        backoffTimer?.invalidate()
        backoffTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            guard self.isHostScreenVisible() else {
                self.scheduleAppLovinBackoffReload(after: delay)
                return
            }
            self.loadAppLovinAd()
        }
    }
    
    private func createNativeAdView(for ad: MAAd) -> MANativeAdView? {
        let nativeAdView = MANativeAdView()
        nativeAdView.backgroundColor = .clear

        let newContainerView = ContainerView()
        newContainerView.edgeInsets = UIEdgeInsets(top: 2, left: 2, bottom: 2, right: 2)
        newContainerView.stackView.spacing = 8
        newContainerView.stackView.alignment = .center

        let newIconImageView = UIImageView()
        newIconImageView.backgroundColor = AdKit.theme.mediaBackground
        newIconImageView.layer.masksToBounds = true
        newIconImageView.layer.cornerRadius = 8
        newIconImageView.translatesAutoresizingMaskIntoConstraints = false
        newIconImageView.widthAnchor.constraint(equalToConstant: 120).isActive = true
        newIconImageView.heightAnchor.constraint(equalToConstant: 120).isActive = true

        let newTitleLabel = UILabel()
        newTitleLabel.font = AdKit.theme.titleFont
        newTitleLabel.textColor = AdKit.theme.titleColor
        newTitleLabel.numberOfLines = 1

        let newTextLabel = UILabel()
        newTextLabel.font = AdKit.theme.bodyFont
        newTextLabel.textColor = AdKit.theme.bodyColor
        newTextLabel.numberOfLines = 2

        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = AdKit.theme.actionBackground
        config.baseForegroundColor = AdKit.theme.actionTitleColor
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = AdKit.theme.actionFont
            return outgoing
        }
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14)
        config.cornerStyle = .capsule

        let newActionButton = UIButton()
        newActionButton.configuration = config
        
        let newTitleStackView = UIStackView(arrangedSubviews: [newTitleLabel])
        newTitleStackView.axis = .horizontal
        newTitleStackView.spacing = 4
        
        // Иконка рекламодателя рядом с кнопкой — обязательный ассет, а слот картинки в media-режиме
        // занят media-вью. Размер жёстко фиксирован: вставленная сетью вью иначе раздувает контейнер.
        let newCompactIconImageView = UIImageView()
        newCompactIconImageView.backgroundColor = AdKit.theme.mediaBackground
        newCompactIconImageView.contentMode = .scaleAspectFill
        newCompactIconImageView.clipsToBounds = true
        newCompactIconImageView.layer.cornerRadius = 6
        newCompactIconImageView.translatesAutoresizingMaskIntoConstraints = false
        newCompactIconImageView.setContentHuggingPriority(.required, for: .vertical)
        newCompactIconImageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        newCompactIconImageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        newCompactIconImageView.widthAnchor.constraint(equalToConstant: Self.compactIconSide).isActive = true
        newCompactIconImageView.heightAnchor.constraint(equalToConstant: Self.compactIconSide).isActive = true

        let newActionRowStackView = UIStackView(arrangedSubviews: showsMedia
                                                ? [newCompactIconImageView, newActionButton]
                                                : [newActionButton])
        newActionRowStackView.axis = .horizontal
        newActionRowStackView.alignment = .center
        newActionRowStackView.spacing = 8

        let newActionStackView = UIStackView(arrangedSubviews: [newActionRowStackView])
        newActionStackView.alignment = .leading
        newActionStackView.axis = .vertical
        newActionStackView.spacing = 4
        
        let newTitleTextStackView = UIStackView(arrangedSubviews: [newTitleStackView, newTextLabel, newActionStackView])
        newTitleTextStackView.axis = .vertical
        newTitleTextStackView.spacing = 4

        // Тегируем ассеты — SDK привяжет их через binder (см. bindViews ниже).
        newTitleLabel.tag = Self.alTitleTag
        newTextLabel.tag = Self.alBodyTag
        newActionButton.tag = Self.alCtaTag

        // В media-режиме на месте иконки — media-контейнер (SDK рендерит туда картинку/видео по tag'у).
        if showsMedia {
            let mediaContainer = UIView()
            mediaContainer.translatesAutoresizingMaskIntoConstraints = false
            mediaContainer.backgroundColor = AdKit.theme.mediaBackground
            mediaContainer.clipsToBounds = true
            mediaContainer.layer.cornerRadius = 8
            mediaContainer.tag = Self.alMediaTag
            mediaContainer.widthAnchor.constraint(equalToConstant: 120).isActive = true
            mediaContainer.heightAnchor.constraint(equalToConstant: 120).isActive = true
            // Иконку SDK рендерит в компактную вью рядом с кнопкой.
            newCompactIconImageView.tag = Self.alIconTag
            newContainerView.setViews([mediaContainer, newTitleTextStackView])
        } else {
            newIconImageView.tag = Self.alIconTag
            newContainerView.setViews([newIconImageView, newTitleTextStackView])
        }

        nativeAdView.addSubview(newContainerView)
        newContainerView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            newContainerView.leftAnchor.constraint(equalTo: nativeAdView.leftAnchor),
            newContainerView.topAnchor.constraint(equalTo: nativeAdView.topAnchor),
            newContainerView.rightAnchor.constraint(equalTo: nativeAdView.rightAnchor),
            newContainerView.bottomAnchor.constraint(equalTo: nativeAdView.bottomAnchor)
        ])
        
        // Добавляем Ad label
        let newAdLabel = UILabel()
        newAdLabel.font = AdKit.theme.adBadgeFont
        newAdLabel.textColor = AdKit.theme.adBadgeTextColor
        newAdLabel.numberOfLines = 1
        newAdLabel.text = "Ad"
        newAdLabel.textAlignment = .center
        newAdLabel.backgroundColor = AdKit.theme.adBadgeBackground
        newAdLabel.layer.cornerRadius = 4
        newAdLabel.layer.masksToBounds = true
        newAdLabel.heightAnchor.constraint(equalToConstant: 20).isActive = true
        newAdLabel.widthAnchor.constraint(equalToConstant: 20).isActive = true
        
        nativeAdView.addSubview(newAdLabel)
        newAdLabel.translatesAutoresizingMaskIntoConstraints = false
        newAdLabel.rightAnchor.constraint(equalTo: nativeAdView.rightAnchor, constant: -12).isActive = true
        newAdLabel.bottomAnchor.constraint(equalTo: nativeAdView.bottomAnchor, constant: -12).isActive = true
        
        // Контейнер под AdChoices/privacy-иконку (options view) — AppLovin ожидает его для нативки.
        let optionsContainer = UIView()
        optionsContainer.translatesAutoresizingMaskIntoConstraints = false
        optionsContainer.tag = Self.alOptionsTag
        nativeAdView.addSubview(optionsContainer)
        NSLayoutConstraint.activate([
            optionsContainer.topAnchor.constraint(equalTo: nativeAdView.topAnchor),
            optionsContainer.rightAnchor.constraint(equalTo: nativeAdView.rightAnchor),
            optionsContainer.widthAnchor.constraint(equalToConstant: 20),
            optionsContainer.heightAnchor.constraint(equalToConstant: 20)
        ])

        // Привязка ассетов к SDK по tag'ам через binder — обязательно для xcframework-дистрибутива
        // AppLovin: прямое присваивание свойств (mediaContentView и т.п.) не регистрируется SDK,
        // из-за чего media не рендерилась (серый квадрат).
        let binder = MANativeAdViewBinder(builderBlock: { builder in
            builder.titleLabelTag = Self.alTitleTag
            builder.bodyLabelTag = Self.alBodyTag
            builder.callToActionButtonTag = Self.alCtaTag
            builder.optionsContentViewTag = Self.alOptionsTag
            // Иконка биндится в обоих режимах: в media-режиме — в компактную вью у кнопки.
            builder.iconImageViewTag = Self.alIconTag
            if self.showsMedia {
                builder.mediaContentViewTag = Self.alMediaTag
            }
        })
        nativeAdView.bindViews(with: binder)

        if let nativeAd = ad.nativeAd {
            newTitleLabel.text = nativeAd.title
            newTextLabel.text = nativeAd.body
            newActionButton.setTitle(nativeAd.callToAction, for: .normal)

            let iconImage = nativeAd.icon?.image
            if showsMedia {
                newCompactIconImageView.image = iconImage
                // Прячем только когда ассета нет вовсе: картинку может дорисовать сам SDK
                // при renderNativeAdView, даже если сейчас image ещё nil.
                newCompactIconImageView.isHidden = nativeAd.icon == nil
            } else {
                newIconImageView.image = iconImage
            }
        }
        
        return nativeAdView
    }
    
    // MARK: - MANativeAdDelegate (AppLovin)
    
    // MARK: - MANativeAdDelegate (AppLovin)
    
    func didLoadNativeAd(_ nativeAdView: MANativeAdView?, for ad: MAAd) {

        if isAdLoaded { return }

        // CPM-бэкофф: сравниваем доходность загруженного объявления с базовым CPM сессии ДО показа.
        let decision = AdCPMBackoffManager.shared.evaluateNative(revenue: ad.revenue, adUnitID: ad.adUnitIdentifier)
        if case .backoff(let delay, let cpmLevel) = decision {
            // Низкий CPM — не показываем это объявление, оставляем на экране прежнее (если есть).
            AdKit.analytics.trackAdDidSkipPresent(in: adUnit.placement, type: "Native", failedRequests: failedRequests.value, cpmLevel: cpmLevel)
            appLovinNativeAdLoader = nil
            isLoadingAd = false
            // На время бэкоффа гасим авто-рефреш, чтобы он не грузил рекламу параллельно
            // с бэкофф-таймером. Перезагрузками управляет только бэкофф-таймер; рефреш
            // вернётся на успешном показе (startAutoRefreshTimer в SHOW-пути).
            stopAutoRefreshTimer()
            // isAdLoaded НЕ трогаем — будущее хорошее объявление должно отрендериться.
            scheduleAppLovinBackoffReload(after: delay)
            return
        }

        isAdLoaded = true
        loadRetryCount = 0
        isLoadingAd = false

        fallbackTimer?.invalidate()
        fallbackTimer = nil
        
        failedRequests.reset()
        let loadingTime = AdLoadTimeTracker.loadingTime(since: appLovinLoadStartDate)
        appLovinLoadStartDate = nil
        AdKit.analytics.trackBannerAdDidLoad(in: adUnit.placement, type: "Native",
                                                     bannersDisplayCount: AdKit.storage.bannerAndNativeDisplayCount,
                                                     displayCount: AdKit.storage.nativeDisplayCount,
                                                     totalAdsDisplayCount: AdKit.storage.totalAdsDisplayCount,
                                                     loadingTime: loadingTime
)
        self.appLovinNativeAd = ad
        didReportDisplay = false

        let adViewToUse: MANativeAdView?
        if let sdkProvidedView = nativeAdView {
            adViewToUse = sdkProvidedView
        } else {
            adViewToUse = createNativeAdView(for: ad)
        }
        
        guard let finalAdView = adViewToUse else {
            loadGoogleAd()
            return
        }
        containerView.isHidden = true
        adLabel.isHidden = true

        // Убираем ранее показанное объявление (актуально для случая «бэкофф → хороший показ»),
        // чтобы новое не наложилось на старое.
        for subview in subviews where subview is MANativeAdView {
            subview.removeFromSuperview()
        }

        addSubview(finalAdView)
        finalAdView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            finalAdView.leftAnchor.constraint(equalTo: leftAnchor),
            finalAdView.topAnchor.constraint(equalTo: topAnchor),
            finalAdView.rightAnchor.constraint(equalTo: rightAnchor),
            finalAdView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // Прогоняем layout ДО рендера: media-контейнер должен иметь реальный размер (120×120),
        // иначе медиатор вставляет media-сабвью по фрейму 0×0 → пустой (серый) контейнер.
        setNeedsLayout()
        layoutIfNeeded()

        // Кастомная (manual) вьюха вернулась nil'ом от SDK → ад рендерим в неё через loader.
        // renderNativeAdView заполняет ВСЕ ассеты, включая media (без него — серый квадрат).
        if nativeAdView == nil {
            _ = appLovinNativeAdLoader?.renderNativeAdView(finalAdView, with: ad)
        }
        alpha = 1.0
        startAutoRefreshTimer()
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.didDisplay(ad)
        }
    }
    
    func didClickNativeAd(for ad: MAAd) {
        AdKit.analytics.trackAdDidClick(in: adUnit.placement, type: "Native")
    }
    
    func didFailToLoadNativeAd(forAdUnitIdentifier adUnitIdentifier: String, withError error: MAError) {
        isLoadingAd = false
        fallbackTimer?.invalidate()
        fallbackTimer = nil

        failedRequests.increment()
        AdKit.analytics.trackAdDidFailToLoad(in: adUnit.placement, type: "Native", failedRequests: failedRequests.value, error: error.message)

        if loadRetryCount < maxLoadRetries {
            loadRetryCount += 1
            Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
                self?.loadAd()
            }
        } else {
            // Исчерпаны быстрые ретраи (обычно из-за no-fill: «MAX returned no eligible ads»).
            // НЕ сдаёмся навсегда — запускаем авто-рефреш, чтобы периодически перезапрашивать
            // (reuse существующего таймера, без нового): объявление подхватится, когда появится
            // филл. loadRetryCount сбросим, чтобы следующий цикл снова имел свои быстрые ретраи.
            loadRetryCount = 0
            startAutoRefreshTimer()
        }
    }
    
    // MARK: - MAAdDelegate (AppLovin)
    
    func didLoad(_ ad: MAAd) {
    }
    
    func didFailToLoadAd(forAdUnitIdentifier adUnitIdentifier: String, withError error: MAError) {
        // Тот же лимит, что и в didFailToLoadNativeAd: без него это бесконечный
        // перезапрос раз в секунду до конца сессии.
        guard loadRetryCount < maxLoadRetries else { return }
        loadRetryCount += 1
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            self?.loadAd()
        }
    }
    func didDisplay(_ ad: MAAd) {
        guard !didReportDisplay else {
            return
        }
        didReportDisplay = true
        let level = AdCPMBackoffManager.shared.cpmLevel(revenue: ad.revenue, adUnitID: ad.adUnitIdentifier)
        incrementNativeDisplayCount(cpmLevel: level)
    }
    
    func didClick(_ ad: MAAd) {
        AdKit.analytics.trackAdDidClick(in: adUnit.placement, type: "Native")
    }
    
    func didHide(_ ad: MAAd) {
    }
    
    func didPayRevenue(for ad: MAAd) {
        AdKit.analytics.trackAdRevenue(in: adUnit.placement, type: "Native", value: ad.revenue.decimalValue, currency: "USD", network: "AppLovin", adNetwork: ad.networkName, unitId: ad.adUnitIdentifier)
    }
    
    // MARK: - GADNativeAdLoaderDelegate
    
    func didClickNativeAd(_ ad: MAAd) {
    }
    
    func didFail(toDisplay ad: MAAd, withError error: MAError) {
    }
    
    func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            if self.isAdLoaded { return }
            self.isAdLoaded = true
            DispatchQueue.main.async {
                self.loadRetryCount = 0
                self.failedRequests.reset()
                self.isLoadingAd = false
                AdKit.analytics.trackBannerAdDidLoad(in: self.adUnit.placement, type: "Native",
                                                             bannersDisplayCount: AdKit.storage.bannerAndNativeDisplayCount,
                                                             displayCount: AdKit.storage.nativeDisplayCount,
                                                             totalAdsDisplayCount: AdKit.storage.totalAdsDisplayCount
)
                self.nativeAd = nativeAd
                self.nativeAd?.delegate = self
                
                nativeAd.paidEventHandler = { [weak self] adValue in
                    guard let self = self else { return }
                    let winningNetwork = self.nativeAd?.responseInfo.loadedAdNetworkResponseInfo?.adSourceName ?? "AdMob"
                    AdKit.analytics.trackAdRevenue(in: self.adUnit.placement, type: "Native", value: adValue.value.decimalValue, currency: adValue.currencyCode, network: "AdMob", adNetwork: winningNetwork, unitId: self.adUnit.id)
                }
                
                // UI обновления
                self.titleLabel.text = nativeAd.headline
                self.textLabel.text = nativeAd.body
                self.actionButton.setTitle(nativeAd.callToAction, for: .normal)

                // Связываем UI элементы с GADNativeAdView для обработки кликов
                self.headlineView = self.titleLabel
                self.bodyView = self.textLabel
                self.callToActionView = self.actionButton

                // В media-режиме в слоте картинки — MediaView (картинка/видео), иначе иконка.
                // Ассет неактивного режима отвязываем, иначе после смены RC-ключа GADNativeAdView
                // остаётся связан с вью, которой уже нет в иерархии.
                if self.showsMedia {
                    self.googleMediaView.mediaContent = nativeAd.mediaContent
                    self.mediaView = self.googleMediaView
                    // Иконка обязательна к показу — рисуем её рядом с CTA-кнопкой.
                    self.compactIconImageView.image = nativeAd.icon?.image
                    self.compactIconImageView.isHidden = nativeAd.icon == nil
                    self.iconView = self.compactIconImageView
                } else {
                    self.iconImageView.image = nativeAd.icon?.image
                    self.iconView = self.iconImageView
                    self.mediaView = nil
                }
                self.alpha = 1.0
                self.startAutoRefreshTimer()
            }
        }
    }
    
    func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
        isLoadingAd = false
        failedRequests.increment()
        AdKit.analytics.trackAdDidFailToLoad(in: adUnit.placement,
                                                    type: "Native",
                                                    failedRequests: failedRequests.value,
                                                    error: "Code: \((error as NSError).code) \(error.localizedDescription)")
        
        if loadRetryCount < maxLoadRetries {
            loadRetryCount += 1
            Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
                self?.loadAd()
            }
        }
    }
    
    // MARK: - GADNativeAdDelegate
    
    func nativeAdDidRecordImpression(_ nativeAd: NativeAd) {
        incrementNativeDisplayCount()
    }

    func nativeAdDidRecordClick(_ nativeAd: NativeAd) {
        AdKit.analytics.trackAdDidClick(in: adUnit.placement, type: "Native")
    }

    func nativeAdWillPresentScreen(_ nativeAd: NativeAd) {
    }

    func nativeAdWillDismissScreen(_ nativeAd: NativeAd) {
    }

    func nativeAdDidDismissScreen(_ nativeAd: NativeAd) {
    }

    func nativeAdWillLeaveApplication(_ nativeAd: NativeAd) {
    }
    
    private func incrementNativeDisplayCount(cpmLevel: Double? = nil) {
        let newBannerAndNativeCount = (AdKit.storage.bannerAndNativeDisplayCount) + 1
        let newNativeCount = (AdKit.storage.nativeDisplayCount) + 1
        let newAllCount = (AdKit.storage.totalAdsDisplayCount) + 1
        
        AdKit.storage.bannerAndNativeDisplayCount = newBannerAndNativeCount
        AdKit.storage.nativeDisplayCount = newNativeCount
        AdKit.storage.totalAdsDisplayCount = newAllCount
        
        
        AdKit.analytics.trackBannerAdDidDisplay(
            in: adUnit.placement,
            type: "Native",
            failedRequests: failedRequests.value,
            bannersDisplayCount: newBannerAndNativeCount,
            displayCount: newNativeCount,
            totalAdsDisplayCount: newAllCount,
            cpmLevel: cpmLevel
        )
    }}
