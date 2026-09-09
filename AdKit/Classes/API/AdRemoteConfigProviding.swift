//
//  AdRemoteConfigProviding.swift
//  AdKit
//

import Foundation

/// Рекламные флаги из Remote Config.
///
/// В приложениях это `ABManager`, работающий поверх Firebase Remote Config.
/// Пакет читает значения в момент обращения — реализация обязана отдавать
/// актуальные данные, а не снимок на момент старта.
public protocol AdRemoteConfigProviding: AnyObject {

    // MARK: - Глобальные выключатели

    /// Общий выключатель всей рекламы.
    var isAdEnabled: Bool { get }

    /// Отдельный выключатель App Open.
    var isAppOpenAdEnabled: Bool { get }

    /// Показывать ли баннеры.
    var isBannerAdsPresenting: Bool { get }

    // MARK: - Провайдеры, отключённые для типа рекламы

    /// Формат строки — `"Yandex, AppLovin"`, регистр и пробелы не важны.
    var interstitialAdDisabledProviders: String { get }
    var rewardedAdDisabledProviders: String { get }
    var nativeAdDisabledProviders: String { get }
    var appOpenAdDisabledProviders: String { get }
    var bannerAdDisabledProviders: String { get }

    // MARK: - Частота обновления

    var bannerAdRefreshRate: Double { get }
    var nativeAdRefreshRate: Double { get }
    var nativeBannerRefreshTime: Double { get }

    // MARK: - Показ полноэкранной рекламы

    /// Диапазон числа переходов между экранами до показа интерстишла.
    var adPresentScreenTransitionCountFrom: Int { get }
    var adPresentScreenTransitionCountTo: Int { get }

    /// Минимальный интервал между показами полноэкранной рекламы, сек.
    var adPresentScreenTransitionTime: Double { get }

    /// Сколько минимум приложение должно пробыть в фоне, чтобы показать App Open.
    var appBackgroundMinTimeToShowAppOpenAd: Double { get }

    // MARK: - Нативка и rewarded

    /// Показывать медиа-контент (видео) в нативной рекламе.
    var showMediaInNativeAd: Bool { get }

    /// Выдавать ли награду, если rewarded не загрузился.
    var rewardedAdFallbackEnabled: Bool { get }

    // MARK: - CPM-бэкофф

    /// Общий выключатель фильтрации по CPM.
    var isCpmBackoffEnabled: Bool { get }

    /// Порог CPM в процентах от базового значения сессии.
    var cpmThresholdPercentNative: Double { get }
    var cpmThresholdPercentInter: Double { get }

    /// Интервалы повторных запросов после бэкоффа, сек.
    var nativeBackoffIntervalsSec: [TimeInterval] { get }
    var interBackoffIntervalsSec: [TimeInterval] { get }

    /// Через сколько минут в фоне сессия считается новой и базовый CPM сбрасывается.
    var adSessionTimeoutMin: Double { get }
}
