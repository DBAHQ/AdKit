//
//  AppOpenSplashOverlay.swift
//  AdKit
//
//  Splash-заставка, визуально идентичная LaunchScreen.
//  Держится поверх дашборда, пока на холодном старте грузится/показывается AppOpen-реклама,
//  чтобы пользователь не видел главный экран раньше рекламы.
//

import UIKit

public final class AppOpenSplashOverlay {

    public init() {}

    // MARK: - Properties

    private var overlayView: UIView?

    // MARK: - Public Methods

    /// Добавляет заставку верхним сабвью на window (поверх rootViewController).
    public func install(on window: UIWindow) {
        guard overlayView == nil else { return }

        let view = makeSplashView()
        view.frame = window.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(view)
        overlayView = view
    }

    /// Убирает заставку (с fade-out, чтобы не было мигания при переходе к дашборду).
    public func remove(animated: Bool) {
        guard let view = overlayView else { return }
        overlayView = nil

        guard animated else {
            view.removeFromSuperview()
            return
        }

        UIView.animate(withDuration: 0.25, animations: {
            view.alpha = 0
        }, completion: { _ in
            view.removeFromSuperview()
        })
    }

    // MARK: - Private Methods

    /// Берём view из существующего LaunchScreen.storyboard — гарантирует пиксель-в-пиксель
    /// совпадение с системным launch screen. Фолбэк — вручную собранная заставка.
    private func makeSplashView() -> UIView {
        let launchVC = UIStoryboard(name: "LaunchScreen", bundle: nil).instantiateInitialViewController()
        if let view = launchVC?.view {
            return view
        }
        return makeFallbackView()
    }

    private func makeFallbackView() -> UIView {
        let container = UIView()
        container.backgroundColor = .black

        let logo = UIImageView(image: AdKit.theme.placeholderIcon)
        logo.contentMode = .scaleAspectFit
        logo.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(logo)

        NSLayoutConstraint.activate([
            logo.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            logo.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            logo.widthAnchor.constraint(equalToConstant: 128),
            logo.heightAnchor.constraint(equalToConstant: 128)
        ])

        return container
    }
}
