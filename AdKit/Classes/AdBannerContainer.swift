//
//  AdBannerContainer.swift
//  AdKit
//

import UIKit

/// Единственное, что нужно приложению от баннерной и нативной рекламы: вставить
/// её в свой контейнер. Всё остальное — загрузка, ретраи, делегаты рекламных SDK,
/// обновление по таймеру — внутри пакета.
///
/// Фасад существует, чтобы не делать публичными сами классы: они реализуют
/// протоколы делегатов AdMob, AppLovin и Яндекса, и публичный класс потребовал бы
/// `public` у нескольких десятков методов, не имеющих отношения к API пакета.
public enum AdBannerContainer {

    /// Обычный баннер. Возвращает вставленную вью или `nil`, если показывать нечего.
    @discardableResult
    public static func installBanner(_ placement: AdPlacement, in container: UIView) -> UIView? {
        AdKitLog.log("контейнер: баннер для '\(placement.placement)'")
        return AMBannerAd.get(placement, size: .large).loadAd(containerView: container)
    }

    /// Нативная реклама. Возвращает вставленную вью.
    @discardableResult
    public static func installNative(_ placement: NativeAdPlacement, in container: UIView) -> UIView {
        AdKitLog.log("контейнер: нативка для '\(placement.placement)'")
        return AMNativeAd.get(with: placement).loadAd(in: container)
    }
}
