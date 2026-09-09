//
//  AdStorage.swift
//  AdKit
//

import Foundation

/// Небольшое постоянное хранилище, нужное рекламе. В приложениях это `AppStorage`
/// поверх `UserDefaults` — пакет своих ключей не заводит, чтобы после переезда
/// счётчики у пользователей не обнулились.
public protocol AdStorage: AnyObject {

    // MARK: - Показ полноэкранной рекламы

    /// Сколько переходов между экранами прошло с последнего показа интерстишла.
    var screenTransitionCount: Int { get set }

    /// Время последнего показа интерстишла, `timeIntervalSince1970`.
    var interstitialAdPresentedTime: TimeInterval? { get set }

    /// Время последнего показа rewarded, `timeIntervalSince1970`.
    var rewardedAdPresentedTime: TimeInterval? { get set }

    // MARK: - Счётчики показов (уходят в аналитику)

    var totalAdsDisplayCount: Int { get set }
    var fullScreenDisplayCount: Int { get set }
    var bannerAndNativeDisplayCount: Int { get set }
    var interstitialDisplayCount: Int { get set }
    var rewardedDisplayCount: Int { get set }
    var appOpenDisplayCount: Int { get set }
    var bannerDisplayCount: Int { get set }
    var nativeDisplayCount: Int { get set }
}
