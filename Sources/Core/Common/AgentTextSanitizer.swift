import Foundation

/// Чистка текста, который роль (агент) написала в свободной форме, для показа
/// владельцу. Роли цитируют служебные метки сервера и имена своих
/// инструментов — владельцу это не нужно.
///
/// Сырой текст (`result`, `humanResult`) не трогаем: на нём держится
/// детект «вернуть на доработку» через `hasPrefix("changes_requested:")`
/// в `CollaborationPlanView` и `TaskFormScreen`.
///
/// Владелец 07.10.2026: на карточке «Сервер» в подзадачах
/// «Повторная итоговая проверка» текст начинался со
/// «changes_requested: D1 (блокер...)», а в середине протекало
/// «taskflow_plan_request в этом запуске недоступен».
public enum AgentTextSanitizer {
    /// Префикс «changes_requested: » сервер ставит перед текстом замечания
    /// проверяющего; человеку он ничего не говорит — убираем полностью.
    /// Имя инструмента «taskflow_plan_request» (добавить слот в план)
    /// заменяем на человеческое описание действия.
    public static func sanitizeForOwner(_ text: String) -> String {
        var s = text
        if let r = s.range(of: "changes_requested:") {
            let after = s[r.upperBound...]
            s = after.trimmingCharacters(in: .whitespaces)
        }
        s = s.replacingOccurrences(
            of: "taskflow_plan_request",
            with: "команда добавить слот в план"
        )
        return s
    }
}