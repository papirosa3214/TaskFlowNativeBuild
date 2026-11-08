import Foundation

/// Карточки работ — задачи, которые система завела под инцидент (`incident_key`
/// на сервере): диагностика, починка, «Устранение: …».
///
/// Владелец 08.11.2026: такие карточки — обычные задачи в «Все задачи», просто
/// в своей группе. Отдельная дверь из «Состояния системы» больше не нужна:
/// «мне не надо их искать в каких-то других отделах».
enum TaskWorkCards {
    /// Карточка работы: ключ инцидента непустой. Пустая строка и `nil` —
    /// обычная задача владельца.
    static func isWorkCard(incidentKey: String?) -> Bool {
        guard let key = incidentKey?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return !key.isEmpty
    }

    /// Делит набор на обычные задачи и карточки работ, сохраняя порядок внутри
    /// каждой группы.
    static func split<T>(_ items: [T], incidentKey: (T) -> String?) -> (ordinary: [T], work: [T]) {
        var ordinary: [T] = []
        var work: [T] = []
        for item in items {
            if isWorkCard(incidentKey: incidentKey(item)) {
                work.append(item)
            } else {
                ordinary.append(item)
            }
        }
        return (ordinary, work)
    }
}
