//
//  AdCPMBackoffManager.swift
//  AdKit
//
//  Управляет CPM-бэкоффом рекламы: фиксирует базовый CPM первого показа в сессии
//  (по AppLovin ad unit ID) и решает, показывать ли загруженное объявление или
//  уйти в бэкофф (не показывать, перезапросить через интервал).
//
//  Сессия живёт ровно adSessionTimeoutMin от своего старта (момент фиксации первого
//  baseline). Состояние хранится ТОЛЬКО в памяти и НЕ переживает полный перезапуск:
//  любой холодный старт (cold start) — это новая сессия. В рамках одного запуска
//  возврат из фона позже adSessionTimeoutMin также начинает новую сессию.
//

import UIKit

public final class AdCPMBackoffManager {

    // MARK: - Static Properties

    public static let shared = AdCPMBackoffManager()

    // MARK: - Types

    enum Decision {
        /// Показать объявление (первый показ-baseline, CPM >= порога или revenue недоступен).
        case show
        /// Не показывать, перезапросить загрузку через `delay` секунд.
        /// `cpmLevel` — на сколько % CPM отличается от базового первого показа сессии.
        /// Ниже базового → положительное (напр. 25.0 = на 25% ниже); выше базового → со знаком
        /// минус (напр. -25.0 = на 25% выше). Для аналитики adDidSkipPresent.
        case backoff(delay: TimeInterval, cpmLevel: Double)
    }

    private struct State {
        /// revenue первого показанного объявления этого ad unit ID (nil = ещё не задан).
        var baselineRevenue: Double?
        /// Сколько подряд «плохих» CPM пришло — индекс в массиве бэкофф-интервалов.
        var badStreak: Int = 0
    }

    // MARK: - Private Properties

    /// Состояние per AppLovin ad unit ID. Только в памяти → cold start = новая сессия.
    private var states: [String: State] = [:]
    /// Момент старта текущей сессии (фиксация первого baseline). Сессия живёт adSessionTimeoutMin.
    private var sessionStartDate: Date?

    // MARK: - Lifecycle

    private init() {}

    // MARK: - Public Methods

    /// Оценивает загруженное нативное объявление AppLovin до показа пользователю.
    /// - Parameters:
    ///   - revenue: `MAAd.revenue` загруженного объявления (USD за показ, 0 = недоступно).
    ///   - adUnitID: `MAAd.adUnitIdentifier` — ключ, по которому ведётся baseline/бэкофф.
    func evaluateNative(revenue: Double, adUnitID: String) -> Decision {
        evaluate(revenue: revenue,
                 adUnitID: adUnitID,
                 thresholdPercent: AdKit.remoteConfig.cpmThresholdPercentNative,
                 intervals: AdKit.remoteConfig.nativeBackoffIntervalsSec,
                 label: "Native")
    }

    /// Оценивает загруженный интерстишл AppLovin до показа пользователю.
    /// - Parameters:
    ///   - revenue: `MAAd.revenue` загруженного объявления (USD за показ, 0 = недоступно).
    ///   - adUnitID: `MAAd.adUnitIdentifier` — ключ, по которому ведётся baseline/бэкофф.
    func evaluateInterstitial(revenue: Double, adUnitID: String) -> Decision {
        evaluate(revenue: revenue,
                 adUnitID: adUnitID,
                 thresholdPercent: AdKit.remoteConfig.cpmThresholdPercentInter,
                 intervals: AdKit.remoteConfig.interBackoffIntervalsSec,
                 label: "Inter")
    }

    /// Вызывать при возврате приложения на передний план — чтобы устаревшая сессия
    /// сбросилась сразу, не дожидаясь следующей загрузки рекламы.
    public func appWillEnterForeground() {
        AdKitLog.log("бэкофф: возврат из фона, проверяю срок сессии")
        expireSessionIfNeeded()
    }

    /// На сколько % CPM отличается от базового первого показа сессии (ниже базового → положительное,
    /// выше базового → со знаком минус; для аналитики). nil — если baseline не задан или revenue недоступен.
    func cpmLevel(revenue: Double, adUnitID: String) -> Double? {
        guard AdKit.remoteConfig.isCpmBackoffEnabled else { return nil }
        guard revenue > 0, let baseline = states[adUnitID]?.baselineRevenue, baseline > 0 else { return nil }
        return ((1.0 - (revenue / baseline)) * 100.0 * 100).rounded() / 100
    }

    // MARK: - Core

    /// Общая логика CPM-бэкоффа. baseline/бэкофф ведутся per `adUnitID`; native и inter
    /// используют разные ad unit ID, поэтому общий словарь состояний их не путает.
    private func evaluate(revenue: Double,
                          adUnitID: String,
                          thresholdPercent percent: Double,
                          intervals: [TimeInterval],
                          label: String) -> Decision {
        let decision = evaluateCore(revenue: revenue, adUnitID: adUnitID, thresholdPercent: percent, intervals: intervals, label: label)
        let baseline = states[adUnitID]?.baselineRevenue
        switch decision {
        case .show:
            AdKitLog.log("бэкофф \(label): показываем — revenue \(revenue), baseline \(baseline.map { "\($0)" } ?? "не задан"), порог \(percent)%")
        case let .backoff(delay, cpmLevel):
            AdKitLog.log("бэкофф \(label): ПРОПУСК — revenue \(revenue) ниже порога, cpmLevel \(String(format: "%.1f", cpmLevel))%, перезапрос через \(delay) с")
        }
        return decision
    }

    private func evaluateCore(revenue: Double,
                              adUnitID: String,
                              thresholdPercent percent: Double,
                              intervals: [TimeInterval],
                              label: String) -> Decision {
        // Kill-switch: CPM-фильтрация отключена в Remote Config → показываем всё без проверки.
        guard AdKit.remoteConfig.isCpmBackoffEnabled else {
            return .show
        }
        expireSessionIfNeeded()

        // CPM недоступен (тест-режим / ещё не посчитан) — показываем, baseline не портим.
        guard revenue > 0 else {
            return .show
        }

        var state = states[adUnitID] ?? State()

        // Первый валидный показ этого ad unit ID в сессии — становится базовым CPM.
        guard let baseline = state.baselineRevenue else {
            state.baselineRevenue = revenue
            state.badStreak = 0
            states[adUnitID] = state
            startSessionIfNeeded()
            AdKitLog.log("бэкофф \(label): baseline сессии установлен = \(revenue) (юнит \(adUnitID))")
            return .show
        }

        let threshold = baseline * percent / 100.0
        AdKitLog.log("бэкофф \(label): revenue \(revenue) против порога \(threshold) (baseline \(baseline) × \(percent)%), подряд плохих \(state.badStreak)")

        if revenue >= threshold {
            // Хороший CPM — показываем, сбрасываем бэкофф-счётчик.
            state.badStreak = 0
            states[adUnitID] = state
            return .show
        } else {
            // Плохой CPM — уходим в бэкофф.
            let index = min(state.badStreak, max(intervals.count - 1, 0))
            let delay = intervals.isEmpty ? 15 : intervals[index]
            // На сколько % CPM ниже базового (выше базового → со знаком минус), округляем до 2 знаков.
            let cpmLevel = ((1.0 - (revenue / baseline)) * 100.0 * 100).rounded() / 100
            state.badStreak += 1
            states[adUnitID] = state
            return .backoff(delay: delay, cpmLevel: cpmLevel)
        }
    }

    // MARK: - Session Handling

    /// Фиксирует старт сессии в момент установки первого baseline (если ещё не зафиксирован).
    private func startSessionIfNeeded() {
        guard sessionStartDate == nil else { return }
        sessionStartDate = Date()
        AdKitLog.log("бэкофф: старт сессии, таймаут \(AdKit.remoteConfig.adSessionTimeoutMin) мин")
    }

    /// Если с момента старта сессии прошло больше adSessionTimeoutMin — сессия окончена:
    /// сбрасываем все базовые CPM и бэкофф-счётчики. Зависит только от прошедшего времени.
    private func expireSessionIfNeeded() {
        guard let start = sessionStartDate else { return }

        let timeout = AdKit.remoteConfig.adSessionTimeoutMin * 60.0
        if Date().timeIntervalSince(start) > timeout {
            AdKitLog.log("бэкофф: сессия истекла (\(AdKit.remoteConfig.adSessionTimeoutMin) мин) — сбрасываю baseline и счётчики")
            states.removeAll()
            sessionStartDate = nil
        }
    }
}
