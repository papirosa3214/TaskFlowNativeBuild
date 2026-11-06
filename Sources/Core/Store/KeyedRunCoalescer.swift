import Foundation

/// Склейка одновременных прогонов по ключу.
///
/// Зачем. Каждое событие «новое сообщение» запускало отдельную догрузку
/// страницы сообщений, и пока роль отвечает, телефон за одну секунду
/// запрашивал одну и ту же страницу семь раз (журнал сервера 06.11.2026).
/// Здесь правило: пока по ключу идёт прогон, новые запросы его не множат, а
/// ставят отметку «повторить». После прогона — ровно один повтор, если за это
/// время что-то пришло, иначе ключ освобождается. Новое не теряется: повтор
/// стартует уже после того, как пришло последнее событие.
///
/// Без сети и без UIKit — проверяется на маке (`Tools/test_keyed_run_coalescer.py`).
struct KeyedRunCoalescer {
    private var running: Set<String> = []
    private var dirty: Set<String> = []

    /// `true` — прогон по ключу начат; `false` — уже идёт, отмечен повтор.
    mutating func begin(_ key: String) -> Bool {
        if running.contains(key) {
            dirty.insert(key)
            return false
        }
        running.insert(key)
        return true
    }

    /// Прогон закончился. `true` — за время прогона пришёл новый запрос, нужен
    /// ещё один прогон (ключ остаётся занятым); `false` — ключ освобождён.
    mutating func finish(_ key: String) -> Bool {
        if dirty.remove(key) != nil { return true }
        running.remove(key)
        return false
    }
}
