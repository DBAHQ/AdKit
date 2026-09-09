//
//  AdTheme.swift
//  AdKit
//

import UIKit

/// Оформление рекламных вью. Приложение задаёт свои цвета и шрифты —
/// пакет ничего не знает про ассеты конкретного приложения.
///
/// Значения по умолчанию повторяют нынешнюю жёлтую тему TradingGuru,
/// чтобы переезд не поменял внешний вид.
public struct AdTheme {

    // MARK: - Цвета

    /// Фон подложек под иконку и медиа, пока картинка не загрузилась.
    public var mediaBackground: UIColor

    /// Заголовок объявления.
    public var titleColor: UIColor

    /// Описание объявления.
    public var bodyColor: UIColor

    /// Фон бейджа «Ad».
    public var adBadgeBackground: UIColor

    /// Текст бейджа «Ad».
    public var adBadgeTextColor: UIColor

    /// Фон кнопки действия.
    public var actionBackground: UIColor

    /// Текст кнопки действия.
    public var actionTitleColor: UIColor

    // MARK: - Шрифты

    public var titleFont: UIFont
    public var bodyFont: UIFont
    public var adBadgeFont: UIFont
    public var actionFont: UIFont

    // MARK: - Ресурсы

    /// Заглушка вместо иконки, когда рекламная сеть её не прислала.
    public var placeholderIcon: UIImage?

    public init(
        mediaBackground: UIColor,
        titleColor: UIColor = .white,
        bodyColor: UIColor = UIColor.white.withAlphaComponent(0.7),
        adBadgeBackground: UIColor,
        adBadgeTextColor: UIColor,
        actionBackground: UIColor,
        actionTitleColor: UIColor = .black,
        titleFont: UIFont = .systemFont(ofSize: 15, weight: .semibold),
        bodyFont: UIFont = .systemFont(ofSize: 12),
        adBadgeFont: UIFont = .systemFont(ofSize: 12, weight: .semibold),
        actionFont: UIFont = .systemFont(ofSize: 13, weight: .semibold),
        placeholderIcon: UIImage? = nil
    ) {
        self.mediaBackground = mediaBackground
        self.titleColor = titleColor
        self.bodyColor = bodyColor
        self.adBadgeBackground = adBadgeBackground
        self.adBadgeTextColor = adBadgeTextColor
        self.actionBackground = actionBackground
        self.actionTitleColor = actionTitleColor
        self.titleFont = titleFont
        self.bodyFont = bodyFont
        self.adBadgeFont = adBadgeFont
        self.actionFont = actionFont
        self.placeholderIcon = placeholderIcon
    }
}
