import Foundation

struct ContextObservability: Decodable, Sendable {
    let window: String
    let since: String
    let trackingSince: String
    let events: [Event]
    let summary: [Summary]
    let limit: Int

    struct Summary: Decodable, Identifiable, Sendable {
        let kind: String
        let scenario: String
        let calls: Int
        let succeeded: Int
        let skipped: Int
        let failed: Int
        let running: Int
        let durationMs: Int
        let inputCount: Int?
        let outputCount: Int?
        var id: String { "\(kind):\(scenario)" }
        var title: String { ContextObservability.title(scenario) }
    }
    struct Event: Decodable, Identifiable, Sendable {
        let id: String
        let kind: String
        let scenario: String
        let taskId: String?
        let subtaskId: String?
        let taskTitle: String?
        let role: String?
        let runId: String?
        let startedAt: String
        let endedAt: String?
        let durationMs: Int
        let status: String
        let reason: String?
        let inputCount: Int?
        let outputCount: Int?
        let inputTokens: Int?
        let outputTokens: Int?
        let details: [String]
        var title: String { ContextObservability.title(scenario) }
        var outcome: String {
            switch reason {
            case "disabled_or_no_key": return "Выключен или ключ не задан"
            case "disabled": return "Сценарий выключен"
            case "not_required": return "Не требовался"
            case "no_key": return "Ключ не задан"
            case "too_few_skills": return "До 6 навыков — отбор не требовался"
            case "too_few_roles": return "Меньше двух ролей — выбор не требовался"
            case "no_candidates", "empty_query", "empty": return "Нет данных для обработки"
            case "truncated": return "Часть данных не вошла в лимит контекста"
            case "applied": return "Отбор применён"
            case "selected": return "Вариант выбран"
            case "allowed": return "Запись в память разрешена"
            case "rejected": return "Запись в память отклонена"
            case "low_confidence": return "Не уверен — использован обычный подбор"
            case "no_valid_answers", "invalid_choice": return "Нет подходящей оценки — обычное поведение"
            case "empty_selection_fallback": return "Ничего не выбрал — оставлены все навыки"
            case "source_unavailable": return "Источник недоступен"
            case "context_build_failed": return "Сборка контекста не удалась после повтора"
            case "invalid_response": return "Некорректный ответ"
            case "provider_error": return "Ошибка провайдера — работа без оценки"
            case "timeout": return "Нет ответа вовремя — работа без оценки"
            default:
                switch status {
                case "running": return "Выполняется"
                case "ok": return "Выполнено"
                case "skipped": return "Пропущено"
                case "timeout": return "Время ожидания истекло"
                case "error": return "Ошибка"
                default: return "Статус неизвестен"
                }
            }
        }
        var countsText: String? {
            guard let inputCount, let outputCount else { return nil }
            if scenario == "taskContext" { return "Контекст: \(outputCount) символов" }
            if scenario == "repository" { return "Изменённых файлов: \(outputCount)" }
            return "На входе \(inputCount) → на выходе \(outputCount)"
        }
    }
    static func title(_ scenario: String) -> String {
        switch scenario {
        case "kb": "База знаний"
        case "mnemosyne": "Мнемозина"
        case "repository": "Репозиторий"
        case "dependencies": "Результаты связанных задач"
        case "collaboration": "Артефакты предыдущих шагов"
        case "history": "История задачи"
        case "taskContext": "Стартовый контекст"
        case "teamMemory": "Память команды"
        case "projectLibrary": "Библиотека проекта"
        case "skills": "Навыки под задачу"
        case "memoryRecall": "Отбор памяти"
        case "memoryWrite": "Проверка записи в память"
        case "planProfile": "Выбор шаблона плана"
        case "subtaskRole": "Роли для подзадач"
        case "connectionTest": "Проверка подключения"
        default: "Другая операция"
        }
    }
    static func dateText(_ value: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = f.date(from: value) ?? ISO8601DateFormatter().date(from: value) else { return value }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

struct JevUsage: Decodable, Sendable {
    let window: String
    let since: String
    let trackingSince: String
    let scope: String
    let hasKey: Bool
    let calls: Int
    let succeeded: Int
    let failed: Int
    let running: Int
    let inputTokens: Int
    let outputTokens: Int
    let unknownUsageCalls: Int
    let moneyStatus: String
    let scenarios: [Scenario]
    struct Scenario: Decodable, Identifiable, Sendable {
        let scenario: String
        let calls: Int
        let inputTokens: Int
        let outputTokens: Int
        let unknownUsageCalls: Int
        var id: String { scenario }
        var title: String { ContextObservability.title(scenario) }
    }
    var coverageText: String {
        unknownUsageCalls > 0
            ? "Для \(unknownUsageCalls) запросов расход не получен. Токены ниже — только известная часть."
            : "Расход получен для всех учтённых запросов."
    }
    var moneyText: String { "Стоимость и баланс провайдером не предоставлены" }
}
