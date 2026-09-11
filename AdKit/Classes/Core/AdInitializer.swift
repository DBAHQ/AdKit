//
//  AdInitializer.swift
//  AdKit
//

import UIKit
import AdSupport
import AdjustSdk
import AppTrackingTransparency
import GoogleMobileAds
import VungleAdsSDK
import YandexMobileAds
import AppLovinSDK
import UserMessagingPlatform
import FBAudienceNetwork


public class AdInitializer: NSObject {
    
    // MARK: - Singleton Instance
    
    public static let shared = AdInitializer()
    
    // MARK: - Properties
    
    private var isAppLovinInitialized = false
    private var hasRequestedConsent = false
    private var isRequestingATT = false
    
    // MARK: - Initialization
    
    private override init() {}
    
    // MARK: - Public Methods
    
    public func initializeAllSDKs() {
        applySdkLoggingSettings()
        FBAdSettings.setDataProcessingOptions([])
        updateMetaTrackingStatus()

        MobileAds.initializeSDK()
        GoogleMobileAds.MobileAds.shared.start()
        initializeAppLovinSDK()
        initializeAdPreloading()
        preloadAppOpenAd()
    }

    /// Подробные логи самих рекламных SDK. Включаются тем же флагом
    /// `AdConfiguration(isLoggingEnabled:)`, что и логи пакета.
    ///
    /// Ставить надо до инициализации SDK — позже они настройку не перечитывают.
    /// У Google Mobile Ads рантайм-переключателя нет: её verbose включается
    /// только аргументом запуска -GADDebugMode.
    private func applySdkLoggingSettings() {
        let isEnabled = AdKitLog.isEnabled

        ALSdk.shared().settings.isVerboseLoggingEnabled = isEnabled
        FBAdSettings.setLogLevel(isEnabled ? FBAdLogLevel.verbose : FBAdLogLevel.none)
    }
    
    private func updateMetaTrackingStatus() {
        let status = ATTrackingManager.trackingAuthorizationStatus
        guard status != .notDetermined else { return }
        let isAuthorized = status == .authorized
        FBAdSettings.setAdvertiserTrackingEnabled(isAuthorized)
        ALPrivacySettings.setHasUserConsent(isAuthorized)
    }
    
    public func requestConsentAndATT() {
        // ATT is requested FIRST and independently of Google's UMP consent flow.
        // Previously ATT was chained AFTER the UMP network call, so a hung/slow
        // `requestConsentInfoUpdate` callback could prevent the Apple tracking
        // prompt from ever appearing. We now show ATT first, then run UMP consent
        // once the user has responded.
        requestATT { [weak self] in
            // Колбэк ATT прилетает с фонового потока Adjust — UMP/UIKit трогаем только на main.
            DispatchQueue.main.async {
                self?.requestConsent()
            }
        }
    }
    
    private func initializeAppLovinSDK() {
        if !isAppLovinInitialized {
            guard let appLovinSdkKey = Bundle.main.infoDictionary?["AppLovinSdkKey"] as? String else { return }
            
            let initConfig = ALSdkInitializationConfiguration(sdkKey: appLovinSdkKey) { builder in
                builder.mediationProvider = ALMediationProviderMAX
            }
            ALSdk.shared().initialize(with: initConfig) { sdkConfig in
                self.isAppLovinInitialized = true
                // Рекламный SDK поднят — самое раннее осмысленное время для AppOpen.
                AdManager.shared.preloadAppOpen()
                // eventService доступен только после инициализации — сливаем
                // события, накопленные до этого момента (app_open и т.п.).
                AdKit.analytics.adSDKDidInitialize()
            }
        }
    }
    
    /// AppOpen запрашивается как можно раньше: ждать, пока до него дойдёт
    /// SceneDelegate, значит потерять больше двух секунд из бюджета заставки.
    private func preloadAppOpenAd() {
        AdManager.shared.preloadAppOpen()
    }

    private func initializeAdPreloading() {
        let interstitialAdUnitIDs = AdKit.host.preloadedInterstitialPlacements
            .compactMap { $0.googleID }
            .filter { !$0.isEmpty }
        
        for adUnitID in interstitialAdUnitIDs {
            AMAdPreloadManager.shared.startPreloading(adUnitID: adUnitID)
        }
    }
    
    public func requestConsent() {
        guard !hasRequestedConsent else {
            return
        }
        hasRequestedConsent = true
        
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            return
        }
        
        var topViewController = rootViewController
        while let presented = topViewController.presentedViewController {
            topViewController = presented
        }
        
        let parameters = RequestParameters()
        
        #if DEBUG
        let debugSettings = DebugSettings()
        debugSettings.testDeviceIdentifiers = [ASIdentifierManager.shared().advertisingIdentifier.uuidString]
        debugSettings.geography = .EEA
        parameters.debugSettings = debugSettings
        #endif
        
        ConsentInformation.shared.requestConsentInfoUpdate(with: parameters) { [weak self] _ in
            DispatchQueue.main.async {
                ConsentForm.loadAndPresentIfRequired(from: topViewController) { _ in
                    // Здесь ATT уже пройден, а согласия только что записаны — отправляем их.
                    self?.shareDMAConsent()
                }
            }
        }
    }
    
    public func requestATT(completion: (() -> Void)? = nil) {
        // DMA-согласия должны уехать до endFirstSessionDelay(), иначе они не попадут
        // в первую сессию и Google не засчитает install.
        shareDMAConsent()

        let currentStatus = ATTrackingManager.trackingAuthorizationStatus
        guard currentStatus == .notDetermined else {
            updateMetaTrackingStatus()
            // Статус ATT уже определён — снимаем задержку первой сессии Adjust.
            Adjust.endFirstSessionDelay()
            completion?()
            return
        }

        guard !isRequestingATT else {
            completion?()
            return
        }
        isRequestingATT = true

        // The ATT prompt is only presented while the app is in the `.active`
        // state. If we are not active yet (e.g. called during launch / a scene
        // transition), defer the request until the app becomes active so the
        // system prompt is not silently dropped.
        requestATTWhenActive(completion: completion)
    }

    private func requestATTWhenActive(completion: (() -> Void)?) {
        if UIApplication.shared.applicationState == .active {
            performATTRequest(completion: completion)
        } else {
            var observer: NSObjectProtocol?
            observer = NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                if let observer = observer {
                    NotificationCenter.default.removeObserver(observer)
                }
                self?.performATTRequest(completion: completion)
            }
        }
    }

    private func performATTRequest(completion: (() -> Void)?) {
        Adjust.requestAppTrackingAuthorization { [weak self] status in
            self?.isRequestingATT = false
            let isAuthorized = (status == 3) // ATTrackingManager.AuthorizationStatus.authorized
            FBAdSettings.setAdvertiserTrackingEnabled(isAuthorized)
            ALPrivacySettings.setHasUserConsent(isAuthorized)
            // Пользователь ответил на ATT — отправляем первую сессию Adjust с корректным IDFA-статусом.
            Adjust.endFirstSessionDelay()
            completion?()
        }
    }
    
    // MARK: - Google DMA Consent

    /// Google Advertising Products в списке вендоров TCF.
    private static let googleTCFVendorID = 755

    /// Передаёт в Adjust согласия пользователя для Google (требование DMA).
    /// Без них Google Ads не связывает install с кампанией и не оптимизирует закупку:
    /// в логах Adjust это warning'и eea_missing_or_invalid / ad_user_data_missing /
    /// ad_personalization_missing_or_invalid.
    /// Значения берём из TCF-строки, которую пишет в UserDefaults форма Google UMP.
    public func shareDMAConsent() {
        // Пока UMP не отработал (.unknown), согласий мы не знаем. Отправить в такой момент —
        // значит соврать Google про регион, поэтому молчим и ждём вызова после формы.
        guard ConsentInformation.shared.consentStatus != .unknown else { return }

        // gdprApplies = 1 — UMP определил пользователя как EEA/UK. В нерегулируемых регионах
        // форма не показывается и TCF-ключей нет вообще — это и есть не-EEA, ключ просто отсутствует.
        let isEEA = UserDefaults.standard.object(forKey: "IABTCF_gdprApplies") as? Int == 1

        let adUserData: Bool
        let adPersonalization: Bool

        if isEEA {
            let hasGoogleConsent = hasTCFConsent(at: Self.googleTCFVendorID, in: "IABTCF_VendorConsents")
            // Purpose 1 — доступ к данным на устройстве, без него нельзя передавать рекламный ID.
            adUserData = hasGoogleConsent
                && hasTCFConsent(at: 1, in: "IABTCF_PurposeConsents")
            // Purpose 3 и 4 — построение профиля и показ персонализированной рекламы.
            adPersonalization = hasGoogleConsent
                && hasTCFConsent(at: 3, in: "IABTCF_PurposeConsents")
                && hasTCFConsent(at: 4, in: "IABTCF_PurposeConsents")
        } else {
            // Вне EEA действие DMA не распространяется — ограничений нет.
            adUserData = true
            adPersonalization = true
        }

        guard let thirdPartySharing = ADJThirdPartySharing(isEnabled: nil) else { return }
        thirdPartySharing.addGranularOption("google_dma", key: "eea", value: isEEA ? "1" : "0")
        thirdPartySharing.addGranularOption("google_dma", key: "ad_user_data", value: adUserData ? "1" : "0")
        thirdPartySharing.addGranularOption("google_dma", key: "ad_personalization", value: adPersonalization ? "1" : "0")
        Adjust.trackThirdPartySharing(thirdPartySharing)
    }

    /// TCF-строки согласий — это последовательности символов '0'/'1',
    /// где позиция N (считая с единицы) соответствует purpose или вендору с номером N.
    private func hasTCFConsent(at position: Int, in key: String) -> Bool {
        guard let bits = UserDefaults.standard.string(forKey: key),
              position > 0,
              position <= bits.count else { return false }

        let index = bits.index(bits.startIndex, offsetBy: position - 1)
        return bits[index] == "1"
    }

    public func presentAdInspector(in viewController: UIViewController) {
        guard let providerName = AdKit.appSettings.mediationProvider,
              let provider = AdProvider(rawValue: providerName) else {
            ALSdk.shared().showMediationDebugger()
            return
        }
        
        switch provider {
        case .admob:
            GoogleMobileAds.MobileAds.shared.presentAdInspector(from: viewController)
        case .appLovin:
            ALSdk.shared().showMediationDebugger()
        case .yandex:
            return
        }
    }
}
