import Foundation

/// Потокобезопасный кэш разобранных значений по строковому ключу.
///
/// Нужен там, где модель разбирает один и тот же текст на каждом проходе
/// `body`: JSON-конверт роли, разобранный markdown, дерево заметок. Ключ —
/// сам разбираемый текст, значение — готовый результат. Размер ограничен,
/// чтобы кэш не рос вместе с историей.
final class ParsedValueCache<Value>: @unchecked Sendable {
    private let limit: Int
    private var storage: [String: Value] = [:]
    private let lock = NSLock()

    init(limit: Int = 64) {
        self.limit = max(1, limit)
    }

    func value(for key: String) -> Value? {
        lock.withLock { storage[key] }
    }

    func set(_ value: Value, for key: String) {
        lock.withLock {
            if storage[key] == nil, storage.count >= limit {
                // Вытесняем произвольную запись: порядок вставки не храним —
                // важно только, чтобы кэш не разрастался.
                if let victim = storage.keys.first { storage.removeValue(forKey: victim) }
            }
            storage[key] = value
        }
    }
}
