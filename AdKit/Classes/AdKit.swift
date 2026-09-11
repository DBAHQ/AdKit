//
//  AdKit.swift
//  AdKit
//

import Foundation

/// Всё, что приложение обязано передать пакету до первого обращения к рекламе.
public struct AdConfiguration {

    public let remoteConfig: AdRemoteConfigProviding
    public let appSettings: AdAppSettingsProviding
    public let analytics: AdAnalyticsSink
    public let storage: AdStorage
    public let host: AdHostEnvironment
    public let theme: AdTheme

    public init(
        remoteConfig: AdRemoteConfigProviding,
        appSettings: AdAppSettingsProviding,
        analytics: AdAnalyticsSink,
        storage: AdStorage,
        host: AdHostEnvironment,
        theme: AdTheme
    ) {
        self.remoteConfig = remoteConfig
        self.appSettings = appSettings
        self.analytics = analytics
        self.storage = storage
        self.host = host
        self.theme = theme
    }
}

/// Пространство имён и точка входа пакета.
public enum AdKit {

    /// Версия пакета. Совпадает с версией в podspec.
    public static let version = "0.1.0"

    /// Пакет шлёт это уведомление, когда приложение сообщило о приходе конфига.
    /// Рекламные вью на него переподписываются и повторяют неудавшуюся загрузку.
    public static let configDidBecomeReadyNotification = Notification.Name("AdKit.configDidBecomeReady")

    /// ⚠️ ВРЕМЕННЫЙ ТЕСТОВЫЙ РЕЖИМ.
    ///
    /// Форсирует провайдера прямо в медиации пакета, минуя ВСЕ правила:
    /// isAdEnabled, отдельный флаг AppOpen, mediationProvider с бекенда и
    /// список отключённых провайдеров. Нужен, чтобы прогнать CPM-бэкофф на
    /// AppLovin, у которого есть реальная выручка с показа.
    ///
    /// Существует только в отладочных сборках: в Release этого свойства нет,
    /// и обращение к нему не скомпилируется. Поэтому в стор он уехать не может.
    ///
    /// Поставить nil, когда проверка закончится.
    #if DEBUG
    public static var debugForcedProvider: AdProvider? = .appLovin
    #endif

    private static var storedConfiguration: AdConfiguration?

    /// Настроен ли пакет. Полезно, чтобы не дёргать рекламу слишком рано.
    public static var isConfigured: Bool { storedConfiguration != nil }

    /// Вызывается один раз, в `application(_:didFinishLaunchingWithOptions:)`,
    /// до любого обращения к рекламе.
    public static func configure(_ configuration: AdConfiguration) {
        #if DEBUG
        // В отладке подменяем аналитику и хранилище на логирующие обёртки:
        // так в консоль попадает каждое событие и каждая запись счётчика.
        storedConfiguration = AdConfiguration(
            remoteConfig: configuration.remoteConfig,
            appSettings: configuration.appSettings,
            analytics: LoggingAnalyticsSink(wrapping: configuration.analytics),
            storage: LoggingAdStorage(wrapping: configuration.storage),
            host: configuration.host,
            theme: configuration.theme
        )
        #else
        storedConfiguration = configuration
        #endif
        AdKitLog.log("настроен, версия \(version)")
    }

    /// Доступ к настройкам изнутри пакета.
    static var configuration: AdConfiguration {
        guard let configuration = storedConfiguration else {
            preconditionFailure(
                "AdKit не настроен. Вызовите AdKit.configure(_:) в didFinishLaunchingWithOptions "
                + "до первого обращения к рекламе."
            )
        }
        return configuration
    }

    /// Приложение зовёт это, когда приехал Remote Config или настройки бекенда.
    /// Можно звать сколько угодно раз — лишние вызовы просто перезапустят
    /// загрузки, которые и так не удались.
    public static func configDidBecomeReady() {
        guard isConfigured else { return }
        AdKitLog.log("конфиг приехал — повторяю отложенные загрузки")
        NotificationCenter.default.post(name: configDidBecomeReadyNotification, object: nil)
    }

    // Короткие псевдонимы, чтобы перенесённый код читался как прежде.
    static var remoteConfig: AdRemoteConfigProviding { configuration.remoteConfig }
    static var appSettings: AdAppSettingsProviding { configuration.appSettings }
    static var analytics: AdAnalyticsSink { configuration.analytics }
    static var storage: AdStorage { configuration.storage }
    static var host: AdHostEnvironment { configuration.host }
    static var theme: AdTheme { configuration.theme }
}
