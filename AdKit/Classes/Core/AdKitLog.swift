//
//  AdKitLog.swift
//  AdKit
//
//  Диагностика только для отладочных сборок. В Release тело функции пустое,
//  вызовы выкидываются оптимизатором.
//
//  Пишем и в print, и в os_log:
//  - print виден в консоли Xcode, когда приложение запущено из Xcode;
//  - os_log виден в Console.app и в `log stream` с Mac, когда устройство
//    работает само по себе. Без него на реальном девайсе логов просто нет.
//
//  privacy: .public обязателен: иначе Console.app покажет <private> вместо текста.
//

import Foundation
import os

public enum AdKitLog {

    private static let logger = Logger(subsystem: "com.dbahq.adkit", category: "ads")

    static func log(_ message: @autoclosure () -> String) {
        #if DEBUG
        let text = message()
        print("[AdKit] \(text)")
        logger.debug("\(text, privacy: .public)")
        #endif
    }

    /// Та же запись, но доступна приложению: диагностика на стороне хоста
    /// попадает в один поток с логами пакета и одинаково видна на устройстве.
    public static func app(_ message: @autoclosure () -> String) {
        #if DEBUG
        let text = message()
        print("[AdKit] \(text)")
        logger.debug("\(text, privacy: .public)")
        #endif
    }
}
