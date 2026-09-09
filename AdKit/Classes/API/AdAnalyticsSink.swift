//
//  AdAnalyticsSink.swift
//  AdKit
//

import Foundation

/// Приёмник рекламных событий. В приложениях это `AnalyticsManager`,
/// раздающий события в Mixpanel, Firebase, Adjust и AppMetrica.
///
/// Сигнатуры повторяют существующие один в один, чтобы адаптер в приложении
/// был тонким и события не поменяли форму при переезде на пакет.
public protocol AdAnalyticsSink: AnyObject {

    // MARK: - Полноэкранная реклама

    func trackFullAdDidRequest(in placement: String, type: String, displayCount: Int, fullScreenDisplayCount: Int, totalAdsDisplayCount: Int)
    func trackFullAdDidLoad(in placement: String, type: String, displayCount: Int, fullScreenDisplayCount: Int, totalAdsDisplayCount: Int, loadingTime: Double?)
    func trackFullAdDidDisplay(in placement: String, type: String, failedRequests: Int, displayCount: Int, fullScreenDisplayCount: Int, totalAdsDisplayCount: Int, cpmLevel: Double?)

    // MARK: - Баннеры и нативка

    func trackBannerAdDidRequest(in placement: String, type: String, bannersDisplayCount: Int, displayCount: Int, totalAdsDisplayCount: Int)
    func trackBannerAdDidLoad(in placement: String, type: String, bannersDisplayCount: Int, displayCount: Int, totalAdsDisplayCount: Int, loadingTime: Double?)
    func trackBannerAdDidDisplay(in placement: String, type: String, failedRequests: Int, bannersDisplayCount: Int, displayCount: Int, totalAdsDisplayCount: Int, cpmLevel: Double?)

    // MARK: - Общие события

    func trackAdDidFailToLoad(in placement: String, type: String, failedRequests: Int, error: String?)
    func trackAdDidSkipPresent(in placement: String, type: String, failedRequests: Int, cpmLevel: Double)
    func trackAdDidFailToDisplay(in placement: String, type: String)
    func trackAdDidHide(in placement: String, type: String)
    func trackAdDidClick(in placement: String, type: String)
    func trackAdDidReward(in placement: String, type: String)
    func trackAdRevenue(in placement: String, type: String, value: Decimal, currency: String, network: String, adNetwork: String, unitId: String)

    /// Рекламный SDK поднялся. Раньше уходило в `AppLovinEventTracker`.
    func adSDKDidInitialize()
}

// Значения по умолчанию: в протоколе их объявить нельзя, а в коде пакета
// эти аргументы почти всегда одинаковые.
public extension AdAnalyticsSink {

    func trackFullAdDidLoad(in placement: String, type: String, displayCount: Int, fullScreenDisplayCount: Int, totalAdsDisplayCount: Int) {
        trackFullAdDidLoad(in: placement, type: type, displayCount: displayCount, fullScreenDisplayCount: fullScreenDisplayCount, totalAdsDisplayCount: totalAdsDisplayCount, loadingTime: nil)
    }

    func trackFullAdDidDisplay(in placement: String, type: String, failedRequests: Int, displayCount: Int, fullScreenDisplayCount: Int, totalAdsDisplayCount: Int) {
        trackFullAdDidDisplay(in: placement, type: type, failedRequests: failedRequests, displayCount: displayCount, fullScreenDisplayCount: fullScreenDisplayCount, totalAdsDisplayCount: totalAdsDisplayCount, cpmLevel: nil)
    }

    func trackBannerAdDidLoad(in placement: String, type: String, bannersDisplayCount: Int, displayCount: Int, totalAdsDisplayCount: Int) {
        trackBannerAdDidLoad(in: placement, type: type, bannersDisplayCount: bannersDisplayCount, displayCount: displayCount, totalAdsDisplayCount: totalAdsDisplayCount, loadingTime: nil)
    }

    func trackBannerAdDidDisplay(in placement: String, type: String, failedRequests: Int, bannersDisplayCount: Int, displayCount: Int, totalAdsDisplayCount: Int) {
        trackBannerAdDidDisplay(in: placement, type: type, failedRequests: failedRequests, bannersDisplayCount: bannersDisplayCount, displayCount: displayCount, totalAdsDisplayCount: totalAdsDisplayCount, cpmLevel: nil)
    }

    // Без failedRequests — иначе сигнатура совпала бы с требованием протокола
    // и вызов ушёл бы сам в себя.
    func trackAdDidFailToLoad(in placement: String, type: String, error: String?) {
        trackAdDidFailToLoad(in: placement, type: type, failedRequests: 0, error: error)
    }

    func trackAdDidFailToLoad(in placement: String, type: String) {
        trackAdDidFailToLoad(in: placement, type: type, failedRequests: 0, error: nil)
    }

    func trackAdRevenue(in placement: String, type: String, value: Decimal, currency: String, network: String) {
        trackAdRevenue(in: placement, type: type, value: value, currency: currency, network: network, adNetwork: "", unitId: "")
    }
}
