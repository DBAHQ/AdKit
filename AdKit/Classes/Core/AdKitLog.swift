//
//  AdKitLog.swift
//  AdKit
//
//  Диагностика только для отладочных сборок. В Release тело функции пустое,
//  вызовы выкидываются оптимизатором.
//

import Foundation

enum AdKitLog {

    static func log(_ message: @autoclosure () -> String) {
        #if DEBUG
        print("[AdKit] \(message())")
        #endif
    }
}
