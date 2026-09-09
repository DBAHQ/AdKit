//
//  AdStorage.swift
//  AdKit
//

import Foundation

/// Небольшое постоянное хранилище, нужное рекламе. В приложениях это `AppStorage`
/// поверх `UserDefaults` — пакет свои ключи не заводит, чтобы после переезда
/// счётчики у пользователей не обнулились.
public protocol AdStorage: AnyObject {

    /// Сколько переходов между экранами прошло с последнего показа интерстишла.
    var screenTransitionCount: Int { get set }

    /// Время последнего показа интерстишла, `timeIntervalSince1970`.
    var interstitialAdPresentedTime: TimeInterval? { get set }

    /// Время последнего показа rewarded, `timeIntervalSince1970`.
    var rewardedAdPresentedTime: TimeInterval? { get set }
}
