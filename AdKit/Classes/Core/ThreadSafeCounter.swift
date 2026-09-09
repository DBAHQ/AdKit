//
//  ThreadSafeCounter.swift
//  AdKit
//

import Foundation

final class ThreadSafeCounter {
    private let queue: DispatchQueue
    private var _value: Int = 0
    
    /// Инициализатор с опциональным идентификатором для уникального имени очереди
    init(identifier: String? = nil) {
        let id = identifier ?? UUID().uuidString
        queue = DispatchQueue(label: "com.adkit.threadsafe.counter.\(id)")
    }
    
    /// Текущее значение счетчика
    var value: Int {
        get {
            return queue.sync { _value }
        }
        set {
            queue.sync { _value = newValue }
        }
    }
    
    /// Инкрементировать счетчик и вернуть новое значение
    @discardableResult
    func increment() -> Int {
        return queue.sync {
            _value += 1
            return _value
        }
    }
    
    /// Сбросить счетчик в 0
    func reset() {
        queue.sync { _value = 0 }
    }
}
