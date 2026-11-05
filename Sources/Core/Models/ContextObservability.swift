import Foundation

struct ContextObservability: Decodable, Sendable {
    let window: String
    let since: String
    let trackingSince: String
    let events: [Event]
    let summary: [Summary]
    let limit: Int
    /// Модели контекста. nil — старый сервер.
    var models: Models? = nil

    struct Models: Decodable, Sendable, Equatable {
        let embedding: String
        let jev: String?
        let observer: String?
    }

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
        var lastAt: String? = nil
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
        var outcome: String { ContextObservability.outcome(reason: reason, status: status) }
        var countsText: String? {
            guard let inputCount, let outputCount else { return nil }
            if scenario == "taskContext" { return "Контекст: \(outputCount) символов" }
            if scenario == "repository" { return "Изменённых файлов: \(outputCount)" }
            return "На входе \(inputCount) → на выходе \(outputCount)"
        }
    }
    static func outcome(reason: String?, status: String) -> String {
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
    /// Когда срабатывает и что делает источник. Показывается рядом со статистикой.
    static func note(_ scenario: String) -> String? {
        switch scenario {
        case "taskContext": "При запуске этапа: собирает стартовый контекст роли"
        case "kb": "При запуске этапа: ищет уроки в базе знаний"
        case "mnemosyne": "При запуске этапа: ищет в рабочей памяти"
        case "repository": "При запуске этапа: смотрит изменения в ветке"
        case "dependencies": "При запуске этапа: берёт результаты связанных задач"
        case "collaboration": "При запуске этапа: берёт артефакты прошлых этапов"
        case "history": "При запуске этапа: читает ленту задачи"
        case "teamMemory": "Подбирает записи памяти команды под задачу"
        case "projectLibrary": "Подбирает заметки проекта под задачу"
        case "skills": "Модель отбирает навыки под задачу"
        case "memoryRecall": "Модель отбирает, что из памяти показать роли"
        case "memoryWrite": "Модель решает, стоит ли запись в памяти"
        case "thoughtReview": "Модель проверяет ход рассуждений роли"
        case "reportReview": "Модель проверяет отчёт роли"
        case "chatIntent": "Модель определяет намерение сообщения в чате"
        case "planProfile": "Модель выбирает шаблон плана"
        case "subtaskRole": "Модель подбирает роли для подзадач"
        case "memory": "Векторы для записи и поиска в памяти"
        case "taskMatch": "Векторы для подбора задач по смыслу"
        case "chat": "Векторы для поиска по чату"
        default: nil
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
        case "thoughtReview": "Проверка хода роли"
        case "reportReview": "Проверка отчёта"
        case "chatIntent": "Намерение в чате"
        case "memory": "Эмбеддинг: память"
        case "taskMatch": "Эмбеддинг: подбор задач"
        case "chat": "Эмбеддинг: чат"
        case "probe": "Эмбеддинг: проверка"
        case "other": "Эмбеддинг: прочее"
        default: "Другая операция"
        }
    }
    static func dateText(_ value: String) -> String {
        // Общий кэшированный разборщик ISO8601 из Core: свой `ISO8601DateFormatter`
        // создавался на каждый вызов.
        guard let date = DateFormats.iso8601(value) else { return value }
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

/// Контекст одной задачи: участвовал ли каждый источник, по всей задаче и по этапам.
struct TaskContextObservability: Decodable, Sendable, Equatable {
    struct Source: Decodable, Identifiable, Sendable, Equatable {
        let kind: String
        let scenario: String
        let calls: Int
        let succeeded: Int
        let skipped: Int
        let failed: Int
        let lastAt: String?
        let lastReason: String?
        var id: String { "\(kind):\(scenario)" }
    }
    struct StageSource: Decodable, Identifiable, Sendable, Equatable {
        let kind: String
        let scenario: String
        let calls: Int
        let status: String
        let reason: String?
        let inputCount: Int?
        let outputCount: Int?
        let details: [String]
        var id: String { "\(kind):\(scenario)" }
    }
    let trackingSince: String
    let models: ContextObservability.Models
    let summary: [Source]
    let stages: [String: [StageSource]]
}

