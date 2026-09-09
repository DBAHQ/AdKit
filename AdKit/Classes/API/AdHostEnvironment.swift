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

    /// Показать или скрыть индикатор загрузки поверх текущего экрана.
    /// Раньше делалось через `visibleViewController as? BaseViewController` и `isAnimating`.
    func setAdLoadingIndicator(visible: Bool)
}
