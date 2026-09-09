//
//  AdManager.swift
//  AdKit
//

import UIKit
import UserMessagingPlatform

// MARK: - Ad Enums

enum AdProvider: String, CaseIterable {
    case yandex = "Yandex"
    case appLovin = "AppLovin"
    case admob = "AdMob"
}

enum AdType {
    case interstitial
    case rewarded
    case native
    case appOpen
    case banner
}

class AdManager {
    
    // MARK: - Static Properties
    
    static let shared = AdManager()

    // MARK: - Static Helpers
    
    static var isRussia: Bool {
        Locale.current.regionCode?.lowercased() == "ru"
    }
    
    // MARK: - Properties
    
    private var banners: [String : AMBannerAd] = [:]
    private var interstitials: [String : AMInterstitialAd] = [:]
    private var interstitialsLoadTime: [String : Date] = [:]
    /// Интеры, которые сейчас показываются. Удерживаем их до закрытия/ошибки показа,
    /// иначе у AppLovin/Yandex (weak-делегаты у SDK-объектов) теряются колбэки
    /// didDisplay/didPayRevenue/didHide → не уходят события adDidDisplay и adRevenue.
    private var presentingInterstitials: [AMInterstitialAd] = []
    private var rewarded: [String : AMRewardedAd] = [:]
    
    // MARK: - AppOpen Properties
    
    private(set) var appOpenAd: AMAppOpenAd?
    private(set) var appOpenLoadTime: Date?
    private var isShowingAppOpenAd = false
    private let adExpirationInterval: TimeInterval = 4 * 3600
    private var backgroundTime: Date?
    private var wasInBackground: Bool = false

    // MARK: - AppOpen Cold Start Properties

    /// Сигнализирует, что cold-start ожидание завершено (реклама показана/закрыта, ошибка или таймаут).
    /// Если true — позднюю загрузку рекламы НЕ презентуем поверх уже открытого дашборда.
    private var coldStartFinished = false
    /// Колбэк «снять splash-заставку → показать дашборд». Вызывается ровно один раз.
    private var coldStartOnFinished: (() -> Void)?
    /// Таймаут именно на ЗАГРУЗКУ рекламы. Отменяется, как только реклама загрузилась.
    private var coldStartTimeoutWorkItem: DispatchWorkItem?

    // MARK: - Mediation Logic
    
    func getEligibleProviders(for adType: AdType) -> [AdProvider] {
        // Rule 1: Global Ad Permission
        guard AdKit.remoteConfig.isAdEnabled else {
            return []
        }
        
        // Rule 2: Special Flag for App Open Ads
        if adType == .appOpen, !AdKit.remoteConfig.isAppOpenAdEnabled {
            return []
        }
        
        // Rule 3: Get provider from AppSettingsDTO (backend already considers region and app version)
        guard let mediationProviderString = AdKit.appSettings.mediationProvider,
              !mediationProviderString.isEmpty else {
            return [.admob]
        }
        
        // Rule 4: Parse provider
        guard let provider = AdProvider(rawValue: mediationProviderString) else {
            return [.admob]
        }
        
        // Rule 5: Check if provider is disabled for this ad type
        let disabledProvidersConfig: String
        switch adType {
        case .interstitial:
            disabledProvidersConfig = AdKit.remoteConfig.interstitialAdDisabledProviders
        case .rewarded:
            disabledProvidersConfig = AdKit.remoteConfig.rewardedAdDisabledProviders
        case .native:
            disabledProvidersConfig = AdKit.remoteConfig.nativeAdDisabledProviders
        case .appOpen:
            disabledProvidersConfig = AdKit.remoteConfig.appOpenAdDisabledProviders
        case .banner:
            disabledProvidersConfig = AdKit.remoteConfig.bannerAdDisabledProviders
        }
        
        let disabledProviders = disabledProvidersConfig.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        if disabledProviders.contains(provider.rawValue.lowercased()) {
            return []
        }
        return [provider]
    }
    
    // MARK: - Other Properties
    
    private var navigationsCount: Int {
        get {
            AdKit.storage.screenTransitionCount
        } set {
            AdKit.storage.screenTransitionCount = newValue
        }
    }
    private var lastPresentedAdTime: Date {
        let rewarded = (AdKit.storage.rewardedAdPresentedTime ?? 0)
        let interstitial = (AdKit.storage.interstitialAdPresentedTime ?? 0)
        if rewarded > interstitial {
            return Date(timeIntervalSince1970: rewarded)
        } else {
            return Date(timeIntervalSince1970: interstitial)
        }
    }
    private var isAbleToPresentInterstitialAd: Bool {
        return navigationsCount >= Int.random(in: AdKit.remoteConfig.adPresentScreenTransitionCountFrom...AdKit.remoteConfig.adPresentScreenTransitionCountTo) && Date().timeIntervalSince1970 - lastPresentedAdTime.timeIntervalSince1970 > AdKit.remoteConfig.adPresentScreenTransitionTime
    }
    
    // MARK: - Interstitial Methods
    
    func load(_ ad: AdPlacement) {
        let key = ad.placement

        // Гейт готовности рекламы-конфига. На первом запуске Firebase RC (isAdEnabled) и app settings
        // (mediationProvider) ещё не подъехали → getEligibleProviders отдаёт [] либо admob-fallback.
        // Если создать инстанс в этот момент, он залипает мёртвым (нет провайдера → нет загрузки →
        // нет didFailToLoadAd → нет scheduleRetry), а 30-минутный кэш не даёт пересоздать его всю сессию.
        // Поэтому НЕ создаём инстанс, пока конфиг не готов — load() из viewDidAppear на следующем
        // экране повторит попытку (как это делает нативка через свои ретраи).
        let providers = getEligibleProviders(for: .interstitial)
        guard AdKit.appSettings.areSettingsLoaded, !providers.isEmpty else {
            return
        }

        guard let time = interstitialsLoadTime[key], interstitials[key] != nil else {
            interstitials[key] = AMInterstitialAd(ad: ad)
            interstitialsLoadTime[key] = Date()
            return
        }
        if Date().timeIntervalSince1970 - time.timeIntervalSince1970 > 60 * 30 {
            interstitials[key] = AMInterstitialAd(ad: ad)
            interstitialsLoadTime[key] = Date()
        }
    }
    
    func present(_ ad: AdPlacement, in viewController: UIViewController) {
        if let interstitialAd = interstitials[ad.placement] {
            // CPM-бэкофф: пока нет готового к показу интера (низкий CPM / ещё грузится) —
            // не показываем и НЕ сбрасываем счётчик/инстанс. Бэкофф-перезапрос идёт внутри инстанса,
            // показ произойдёт на следующем триггере, когда придёт интер с CPM ≥ порога.
            guard interstitialAd.isReadyToPresent() else {
                return
            }
            // Удерживаем инстанс до закрытия показа, иначе он разрушится сразу после show()
            // и weak-делегаты AppLovin/Yandex не доставят didDisplay/didPayRevenue/didHide.
            presentingInterstitials.append(interstitialAd)
            let release: () -> Void = { [weak self, weak interstitialAd] in
                self?.presentingInterstitials.removeAll { $0 === interstitialAd }
            }
            _ = interstitialAd
                .setDidCloseHandler { release() }
                .setDidFailPresentHandler { _ in release() }
                .setNoAdsAvailableHandler { release() }
            interstitialAd.present(in: viewController)
            interstitialsLoadTime[ad.placement] = nil
            interstitials[ad.placement] = nil
            navigationsCount = 0
        } else {
            guard !getEligibleProviders(for: .interstitial).isEmpty else { return }
            load(ad)
            present(ad, in: viewController)
        }
    }
    
    func presentInScreenTransition(_ ad: AdPlacement, in viewController: UIViewController) {
        // Список экранов, где интер показывать нельзя, задаёт приложение.
        if AdKit.host.interstitialExcludedScreens.contains(where: { $0 == type(of: viewController) }) {
            return
        }
        
        guard isAbleToPresentInterstitialAd else {
            navigationsCount += 1
            return
        }
        present(ad, in: viewController)
    }
    // MARK: - Preload Methods

    // MARK: - AppOpen Methods
    
    func getAppOpenLastTimePresented() -> Date? {
        backgroundTime
    }
    
    func getWainInBackGround() -> Bool {
        wasInBackground
    }
    
    func toggleWasInBackground() {
        wasInBackground.toggle()
    }
    
    func setAppOpenLastTimePresented(_ date: Date?) {
        backgroundTime = date
    }
    
    func load(_ ad: AdPlacement, completion: (() -> Void)? = nil) {
        guard !getEligibleProviders(for: .appOpen).isEmpty else {
            appOpenAd = nil
            appOpenLoadTime = nil
            completion?()
            return
        }
        
        appOpenAd = AMAppOpenAd(ad: ad)
            .setDidLoadHandler { [weak self] in
                self?.appOpenLoadTime = Date()
                completion?()
            }
            .setDidFailPresentHandler { [weak self] error in
                self?.isShowingAppOpenAd = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    guard let self = self, UIApplication.shared.applicationState == .active else { return }
                    self.load(ad)
                }
            }
            .setDidCloseHandler { [weak self] in
                self?.isShowingAppOpenAd = false
            }
            .setNoAdsAvailableHandler { [weak self] in
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    guard let self = self, UIApplication.shared.applicationState == .active else { return }
                    self.load(ad)
                }
            }
        appOpenAd?.loadAd()
    }
    
    func tryToPresentAppOpenAd(from viewController: UIViewController) {
        if !isShowingAppOpenAd {
            load(AdKit.host.appOpenPlacement) { [weak self] in
                guard let self = self else { return }
                
                if self.appOpenAd != nil && self.appOpenLoadTime != nil {
                    self.isShowingAppOpenAd = true
                    if viewController.viewIfLoaded != nil {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self.appOpenAd?.present(in: viewController)
                        }
                    } else {
                        self.isShowingAppOpenAd = false
                    }
                }
            }
        }
    }
    
    // MARK: - AppOpen Cold Start

    /// Холодный старт: грузит AppOpen и показывает его поверх splash-заставки до открытия дашборда.
    /// Если реклама не загрузилась за `timeout` (или ошибка / нет рекламы / закрытие) — вызывает `onFinished`,
    /// по которому SceneDelegate снимает заставку и открывает дашборд.
    /// Горячую ветку (`tryToPresentAppOpenAd`) не трогает.
    func loadAndPresentAppOpenForColdStart(from viewController: UIViewController,
                                           timeout: TimeInterval,
                                           onFinished: @escaping () -> Void) {
        coldStartFinished = false
        coldStartOnFinished = onFinished

        // Реклама отключена / нет провайдера — сразу открываем дашборд.
        guard !getEligibleProviders(for: .appOpen).isEmpty else {
            appOpenAd = nil
            appOpenLoadTime = nil
            finishColdStart()
            return
        }

        // Таймаут именно на ЗАГРУЗКУ: если реклама не загрузилась за timeout — открываем дашборд.
        // Как только реклама загрузилась, таймаут отменяется (дальше ждём показа/закрытия).
        let timeoutItem = DispatchWorkItem { [weak self] in
            guard let self = self, !self.coldStartFinished else { return }
            self.finishColdStart()
        }
        coldStartTimeoutWorkItem = timeoutItem
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: timeoutItem)

        appOpenAd = AMAppOpenAd(ad: AdKit.host.appOpenPlacement)
            .setDidLoadHandler { [weak self, weak viewController] in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.appOpenLoadTime = Date()

                    // Уже сдались по таймауту — рекламу не показываем (дашборд уже открыт).
                    guard !self.coldStartFinished else { return }

                    // Загрузилась вовремя — отменяем таймаут загрузки.
                    self.coldStartTimeoutWorkItem?.cancel()
                    self.coldStartTimeoutWorkItem = nil

                    // Не показываем, если нет VC или сверху открыта модалка (форма consent/ATT).
                    guard let vc = viewController,
                          vc.viewIfLoaded != nil,
                          vc.presentedViewController == nil else {
                        self.finishColdStart()
                        return
                    }

                    // Заставку НЕ снимаем здесь — она остаётся под рекламой до её закрытия (didClose).
                    self.isShowingAppOpenAd = true
                    self.appOpenAd?.present(in: vc)
                }
            }
            .setDidFailPresentHandler { [weak self] _ in
                self?.finishColdStart()
            }
            .setDidCloseHandler { [weak self] in
                self?.finishColdStart()
            }
            .setNoAdsAvailableHandler { [weak self] in
                self?.finishColdStart()
            }
        appOpenAd?.loadAd()
    }

    /// Завершает cold-start ровно один раз: сбрасывает флаги и вызывает колбэк снятия заставки.
    private func finishColdStart() {
        guard !coldStartFinished else { return }
        coldStartFinished = true
        coldStartTimeoutWorkItem?.cancel()
        coldStartTimeoutWorkItem = nil
        isShowingAppOpenAd = false
        let handler = coldStartOnFinished
        coldStartOnFinished = nil
        DispatchQueue.main.async { handler?() }
    }

    func isAppOpenAdAvailable() -> Bool {
        guard let loadTime = appOpenLoadTime else {
            return false
        }
        return Date().timeIntervalSince(loadTime) <= adExpirationInterval
    }
    
    // MARK: - Consent Methods
    
    func presentConsent(in viewController: UIViewController) {
        ConsentInformation.shared.requestConsentInfoUpdate(with: nil) { requestConsentError in
            if let consentError = requestConsentError {
                AdKit.host.presentError(consentError.localizedDescription, in: viewController)
                return
            }
            
            DispatchQueue.main.async {
                ConsentForm.loadAndPresentIfRequired(from: viewController) { loadAndPresentError in
                    if let consentError = loadAndPresentError {
                        AdKit.host.presentError(consentError.localizedDescription, in: viewController)
                    }
                    // Пользователь мог поменять согласия — переотправляем их в Adjust.
                    AdInitializer.shared.shareDMAConsent()
                }
            }
        }
    }
}

// MARK: - Ad Load Time Tracker

/// Считает loadingTime рекламы и отбрасывает замеры, пережившие уход приложения
/// в фон: иначе фоновый простой раздувает время загрузки до часов. Один общий
/// наблюдатель на весь модуль — без подписки на каждый рекламный объект.
enum AdLoadTimeTracker {
    private static var lastDidEnterBackgroundDate: Date?
    private static var didRegisterObserver = false

    /// Вызывать в начале загрузки: возвращает момент старта и гарантирует,
    /// что наблюдатель за уходом в фон уже зарегистрирован.
    static func loadStarted() -> Date {
        registerObserverIfNeeded()
        return Date()
    }

    /// Время загрузки в секундах (округл. до 2 знаков) либо nil, если замер
    /// невалиден: был уход в фон во время загрузки или часы прыгнули назад.
    static func loadingTime(since start: Date?) -> Double? {
        guard let start else { return nil }
        let now = Date()
        if let bg = lastDidEnterBackgroundDate, bg >= start, bg <= now { return nil }
        let elapsed = now.timeIntervalSince(start)
        guard elapsed >= 0 else { return nil }
        return (elapsed * 100).rounded() / 100
    }

    private static func registerObserverIfNeeded() {
        guard !didRegisterObserver else { return }
        didRegisterObserver = true
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            lastDidEnterBackgroundDate = Date()
        }
    }
}
