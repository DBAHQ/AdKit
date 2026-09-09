//
//  AdAppSettingsProviding.swift
//  AdKit
//

import Foundation

/// Настройки, приходящие с бекенда. Рекламе нужно ровно одно поле.
///
/// Бекенд уже учитывает регион и версию приложения, поэтому пакет
/// значение не перепроверяет — только разбирает.
public protocol AdAppSettingsProviding: AnyObject {

    /// Выбранный медиатор: `"AdMob"`, `"AppLovin"` или `"Yandex"`.
    /// `nil` или пустая строка означают, что настройки ещё не загружены —
    /// в этом случае пакет откатывается на AdMob.
    var mediationProvider: String? { get }
}
