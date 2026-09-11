//
//  AdKitLog.swift
//  AdKit
//
//  Диагностика рекламы. По умолчанию ВЫКЛЮЧЕНА: приложение включает её,
//  передав isLoggingEnabled: true в AdConfiguration. Работает в любой
//  конфигурации, включая Release, — чтобы можно было разобрать поведение на проде.
//
//  Уровень notice, а не debug: debug-сообщения система держит только в памяти
//  и в релизной сборке до Console.app обычно не доходят. notice сохраняется.
//
//  privacy: .public обязателен — иначе вместо текста будет <private>.
//

import Foundation
import os

public enum AdKitLog {

    /// Включается приложением через `AdConfiguration(isLoggingEnabled:)`.
    /// По умолчанию выключено — обычная сборка рекламных логов не пишет.
    static var isEnabled = false

    private static let logger = Logger(subsystem: "com.dbahq.adkit", category: "ads")

    /// Префикс на КАЖДОЙ строке и в обоих каналах, чтобы рекламные строки
    /// можно было отфильтровать грепом в общем потоке устройства.
    private static let prefix = "[AdKit]"

    static func log(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        write(message())
    }

    /// Та же запись, но доступна приложению: диагностика на стороне хоста
    /// попадает в один поток с логами пакета.
    public static func app(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        write(message())
    }

    private static func write(_ text: String) {
        let line = "\(prefix) \(text)"
        #if DEBUG
        print(line)
        #endif
        logger.notice("\(line, privacy: .public)")
    }
}
