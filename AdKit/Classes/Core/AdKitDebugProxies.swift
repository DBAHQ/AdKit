//
//  AdKitDebugProxies.swift
//  AdKit
//
//  Обёртки над аналитикой и хранилищем, которые логируют всё, что через них
//  проходит. Подставляются автоматически в AdKit.configure.
//  Работают и в Release — чтобы поведение можно было разобрать на проде.
//

import Foundation

// MARK: - Аналитика

/// Печатает каждое рекламное событие с параметрами и передаёт его дальше.
final class LoggingAnalyticsSink: AdAnalyticsSink {

    private let wrapped: AdAnalyticsSink

    init(wrapping wrapped: AdAnalyticsSink) {
        self.wrapped = wrapped
    }

    private func event(_ name: String, _ details: String) {
        AdKitLog.log("событие \(name) — \(details)")
    }

    func trackFullAdDidRequest(in placement: String, type: String, displayCount: Int, fullScreenDisplayCount: Int, totalAdsDisplayCount: Int) {
        event("adDidRequest", "\(type) '\(placement)', показов типа \(displayCount), полноэкранных \(fullScreenDisplayCount), всего \(totalAdsDisplayCount)")
        wrapped.trackFullAdDidRequest(in: placement, type: type, displayCount: displayCount, fullScreenDisplayCount: fullScreenDisplayCount, totalAdsDisplayCount: totalAdsDisplayCount)
    }

    func trackFullAdDidLoad(in placement: String, type: String, displayCount: Int, fullScreenDisplayCount: Int, totalAdsDisplayCount: Int, loadingTime: Double?) {
        event("adDidLoad", "\(type) '\(placement)', загрузка \(loadingTime.map { String(format: "%.2f с", $0) } ?? "—")")
        wrapped.trackFullAdDidLoad(in: placement, type: type, displayCount: displayCount, fullScreenDisplayCount: fullScreenDisplayCount, totalAdsDisplayCount: totalAdsDisplayCount, loadingTime: loadingTime)
    }

    func trackFullAdDidDisplay(in placement: String, type: String, failedRequests: Int, displayCount: Int, fullScreenDisplayCount: Int, totalAdsDisplayCount: Int, cpmLevel: Double?) {
        event("adDidDisplay", "\(type) '\(placement)', неудачных запросов \(failedRequests), показов типа \(displayCount), всего \(totalAdsDisplayCount), cpmLevel \(cpmLevel.map { String(format: "%.1f", $0) } ?? "—")")
        wrapped.trackFullAdDidDisplay(in: placement, type: type, failedRequests: failedRequests, displayCount: displayCount, fullScreenDisplayCount: fullScreenDisplayCount, totalAdsDisplayCount: totalAdsDisplayCount, cpmLevel: cpmLevel)
    }

    func trackBannerAdDidRequest(in placement: String, type: String, bannersDisplayCount: Int, displayCount: Int, totalAdsDisplayCount: Int) {
        event("adDidRequest", "\(type) '\(placement)', баннеров \(bannersDisplayCount), показов типа \(displayCount), всего \(totalAdsDisplayCount)")
        wrapped.trackBannerAdDidRequest(in: placement, type: type, bannersDisplayCount: bannersDisplayCount, displayCount: displayCount, totalAdsDisplayCount: totalAdsDisplayCount)
    }

    func trackBannerAdDidLoad(in placement: String, type: String, bannersDisplayCount: Int, displayCount: Int, totalAdsDisplayCount: Int, loadingTime: Double?) {
        event("adDidLoad", "\(type) '\(placement)', загрузка \(loadingTime.map { String(format: "%.2f с", $0) } ?? "—")")
        wrapped.trackBannerAdDidLoad(in: placement, type: type, bannersDisplayCount: bannersDisplayCount, displayCount: displayCount, totalAdsDisplayCount: totalAdsDisplayCount, loadingTime: loadingTime)
    }

    func trackBannerAdDidDisplay(in placement: String, type: String, failedRequests: Int, bannersDisplayCount: Int, displayCount: Int, totalAdsDisplayCount: Int, cpmLevel: Double?) {
        event("adDidDisplay", "\(type) '\(placement)', баннеров \(bannersDisplayCount), всего \(totalAdsDisplayCount), cpmLevel \(cpmLevel.map { String(format: "%.1f", $0) } ?? "—")")
        wrapped.trackBannerAdDidDisplay(in: placement, type: type, failedRequests: failedRequests, bannersDisplayCount: bannersDisplayCount, displayCount: displayCount, totalAdsDisplayCount: totalAdsDisplayCount, cpmLevel: cpmLevel)
    }

    func trackAdDidFailToLoad(in placement: String, type: String, failedRequests: Int, error: String?) {
        event("adDidFailToLoad", "\(type) '\(placement)', попытка \(failedRequests), ошибка: \(error ?? "—")")
        wrapped.trackAdDidFailToLoad(in: placement, type: type, failedRequests: failedRequests, error: error)
    }

    func trackAdDidSkipPresent(in placement: String, type: String, failedRequests: Int, cpmLevel: Double) {
        event("adDidSkipPresent", "\(type) '\(placement)', cpmLevel \(String(format: "%.1f", cpmLevel))")
        wrapped.trackAdDidSkipPresent(in: placement, type: type, failedRequests: failedRequests, cpmLevel: cpmLevel)
    }

    func trackAdDidFailToDisplay(in placement: String, type: String) {
        event("adDidFailToDisplay", "\(type) '\(placement)'")
        wrapped.trackAdDidFailToDisplay(in: placement, type: type)
    }

    func trackAdDidHide(in placement: String, type: String) {
        event("adDidHide", "\(type) '\(placement)'")
        wrapped.trackAdDidHide(in: placement, type: type)
    }

    func trackAdDidClick(in placement: String, type: String) {
        event("adDidClick", "\(type) '\(placement)'")
        wrapped.trackAdDidClick(in: placement, type: type)
    }

    func trackAdDidReward(in placement: String, type: String) {
        event("adDidReward", "\(type) '\(placement)'")
        wrapped.trackAdDidReward(in: placement, type: type)
    }

    func trackAdRevenue(in placement: String, type: String, value: Decimal, currency: String, network: String, adNetwork: String, unitId: String) {
        event("adRevenue", "\(type) '\(placement)', \(value) \(currency), сеть \(network), победитель \(adNetwork.isEmpty ? "—" : adNetwork), юнит \(unitId.isEmpty ? "—" : unitId)")
        wrapped.trackAdRevenue(in: placement, type: type, value: value, currency: currency, network: network, adNetwork: adNetwork, unitId: unitId)
    }

    func adSDKDidInitialize() {
        event("sdkDidInitialize", "рекламный SDK поднялся")
        wrapped.adSDKDidInitialize()
    }
}

// MARK: - Хранилище

/// Печатает каждую запись счётчика в виде «было → стало». Чтения не логируются:
/// они происходят на каждое событие и утопили бы лог.
final class LoggingAdStorage: AdStorage {

    private let wrapped: AdStorage

    init(wrapping wrapped: AdStorage) {
        self.wrapped = wrapped
    }

    private func note(_ name: String, _ old: Any?, _ new: Any?) {
        AdKitLog.log("счётчик \(name): \(old.map { "\($0)" } ?? "нет") → \(new.map { "\($0)" } ?? "нет")")
    }

    var screenTransitionCount: Int {
        get { wrapped.screenTransitionCount }
        set { note("screenTransitionCount", wrapped.screenTransitionCount, newValue); wrapped.screenTransitionCount = newValue }
    }

    var interstitialAdPresentedTime: TimeInterval? {
        get { wrapped.interstitialAdPresentedTime }
        set { note("interstitialAdPresentedTime", wrapped.interstitialAdPresentedTime, newValue); wrapped.interstitialAdPresentedTime = newValue }
    }

    var rewardedAdPresentedTime: TimeInterval? {
        get { wrapped.rewardedAdPresentedTime }
        set { note("rewardedAdPresentedTime", wrapped.rewardedAdPresentedTime, newValue); wrapped.rewardedAdPresentedTime = newValue }
    }

    var totalAdsDisplayCount: Int {
        get { wrapped.totalAdsDisplayCount }
        set { note("totalAdsDisplayCount", wrapped.totalAdsDisplayCount, newValue); wrapped.totalAdsDisplayCount = newValue }
    }

    var fullScreenDisplayCount: Int {
        get { wrapped.fullScreenDisplayCount }
        set { note("fullScreenDisplayCount", wrapped.fullScreenDisplayCount, newValue); wrapped.fullScreenDisplayCount = newValue }
    }

    var bannerAndNativeDisplayCount: Int {
        get { wrapped.bannerAndNativeDisplayCount }
        set { note("bannerAndNativeDisplayCount", wrapped.bannerAndNativeDisplayCount, newValue); wrapped.bannerAndNativeDisplayCount = newValue }
    }

    var interstitialDisplayCount: Int {
        get { wrapped.interstitialDisplayCount }
        set { note("interstitialDisplayCount", wrapped.interstitialDisplayCount, newValue); wrapped.interstitialDisplayCount = newValue }
    }

    var rewardedDisplayCount: Int {
        get { wrapped.rewardedDisplayCount }
        set { note("rewardedDisplayCount", wrapped.rewardedDisplayCount, newValue); wrapped.rewardedDisplayCount = newValue }
    }

    var appOpenDisplayCount: Int {
        get { wrapped.appOpenDisplayCount }
        set { note("appOpenDisplayCount", wrapped.appOpenDisplayCount, newValue); wrapped.appOpenDisplayCount = newValue }
    }

    var bannerDisplayCount: Int {
        get { wrapped.bannerDisplayCount }
        set { note("bannerDisplayCount", wrapped.bannerDisplayCount, newValue); wrapped.bannerDisplayCount = newValue }
    }

    var nativeDisplayCount: Int {
        get { wrapped.nativeDisplayCount }
        set { note("nativeDisplayCount", wrapped.nativeDisplayCount, newValue); wrapped.nativeDisplayCount = newValue }
    }
}
