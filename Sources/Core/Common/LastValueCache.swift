import Foundation

/// Кэш последнего значения по строковому ключу — один слот.
///
/// Нужен там, где один и тот же текст приходит кадрами подряд: растущий
/// ответ роли во время проявления. Хранить все версии не нужно — нужна
/// только последняя, предыдущие уже не придут.
///
/// Сравнение строк вместо хеширования: замер 24.10.2026 на этом маке — хеш
/// 1.8 КБ стоит 8.2 мкс, а сравнение того же экземпляра строки — 0 мкс
/// (Swift сравнивает буфер напрямую, без пересчёта хеша). На кадре
/// проявления это чистый выигрыш: кадр стоит единицы микросекунд вместо
/// десятков.
final class LastValueCache<Value>: @unchecked Sendable {
    private var key: String = ""
    private var stored: Value?
    private let lock = NSLock()

    /// Значение по ключу; nil — если слот занят другим ключом.
    func value(for key: String) -> Value? {
        lock.withLock {
            guard self.key == key else { return nil }
            return stored
        }
    }

    func set(_ value: Value, for key: String) {
        lock.withLock {
            self.key = key
            stored = value
        }
    }
}
