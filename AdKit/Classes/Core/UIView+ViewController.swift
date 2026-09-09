//
//  UIView+ViewController.swift
//  AdKit
//
//  Копия расширения приложения. Internal — снаружи пакета не видно,
//  поэтому одноимённое расширение в приложении с ним не конфликтует.
//

import UIKit

extension UIView {

    var viewController: UIViewController? {
        var responder: UIResponder? = self
        while responder != nil {
            if let viewController = responder as? UIViewController {
                return viewController
            }
            responder = responder?.next
        }
        return nil
    }
}
