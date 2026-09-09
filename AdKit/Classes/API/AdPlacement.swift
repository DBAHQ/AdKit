//
//  AdPlacement.swift
//  AdKit
//

import Foundation

/// Место показа полноэкранной или баннерной рекламы.
///
/// Реализуется в приложении — обычно тем же `enum`, что и раньше
/// (`TGAdBanner`, `TGAdInterstitial`, `TGAdRewarded`, `TGAdOpen`).
/// Пакет не знает и не должен знать, какие экраны есть в приложении.
public protocol AdPlacement {

    /// Ad unit AdMob.
    var googleID: String { get }

    /// Ad unit AppLovin MAX.
    var appLovinID: String { get }

    /// Ad unit Яндекса.
    var yandexID: String { get }

    /// Имя места для аналитики.
    var placement: String { get }
}

/// Место показа нативной рекламы. Отличается от `AdPlacement` тем,
/// что у Яндекса нативки нет, зато есть флаг медиа-контента.
public protocol NativeAdPlacement {

    /// Ad unit AdMob.
    var id: String { get }

    /// Ad unit AppLovin MAX.
    var appLovinID: String { get }

    /// Имя места для аналитики.
    var placement: String { get }

    /// Показывать ли видео/медиа вместо статичной иконки.
    var showsMediaContent: Bool { get }
}
