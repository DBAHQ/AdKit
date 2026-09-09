//
//  AdHostEnvironment.swift
//  AdKit
//

import UIKit

/// Всё, что пакету нужно знать о приложении-хосте.
public protocol AdHostEnvironment: AnyObject {

    /// Боевая сборка. В отладочной подставляются тестовые ad unit.
    var isProduction: Bool { get }

    /// Регион пользователя — Россия. Влияет на выбор медиатора и на консент.
    var isRussia: Bool { get }

    /// Экраны, на которых интерстишл показывать нельзя.
    /// Раньше это был захардкоженный `excludedScreens` внутри `AdManager`.
    var interstitialExcludedScreens: [UIViewController.Type] { get }

    /// Место показа App Open. Оно в приложении одно, но ad unit'ы у всех разные.
    var appOpenPlacement: AdPlacement { get }

    /// Показать пользователю ошибку рекламного консента. Вид алерта — на стороне
    /// приложения, чтобы пакет не тащил его ассеты и стили.
    func presentError(_ message: String, in viewController: UIViewController)

    /// У пользователя оплачена подписка — баннеры ему не показываются.
    var hasSubscription: Bool { get }

    /// Места интерстишлов, которые нужно предзагружать при старте.
    /// Раньше это был захардкоженный `getAllAdUnits(for:)` внутри `AdManager`.
    var preloadedInterstitialPlacements: [AdPlacement] { get }

    /// Показать или скрыть индикатор загрузки поверх текущего экрана.
    /// Раньше делалось через `visibleViewController as? BaseViewController` и `isAnimating`.
    func setAdLoadingIndicator(visible: Bool)
}
