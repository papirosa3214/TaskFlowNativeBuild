import Foundation

/// Пользовательское представление без имён эмиттеров и технических команд.
struct ServiceTicketPresentation {
    let title: String
    let okCount: Int
    let errorCount: Int
    let warningCount: Int
    let preview: String

    init(summary: ServiceTicketSummary) {
        switch summary.source {
        case "autonomy-110": title = "Работа серверных механизмов"
        case "runaway-110": title = "Контроль процессов"
        case "kb-add": title = "База знаний"
        default: title = summary.title
        }
        let checks = summary.checks ?? []
        okCount = summary.okCount ?? checks.count { $0.status == "ok" }
        errorCount = summary.errorCount ?? (checks.isEmpty && summary.level == "error" ? 1 : checks.count { $0.status == "error" })
        warningCount = summary.warningCount ?? (checks.isEmpty && summary.level == "warning" ? 1 : checks.count { $0.status == "warning" })
        let problems = checks.filter { $0.status != "ok" }
        if !problems.isEmpty {
            preview = problems.prefix(2).map(\.name).joined(separator: " · ")
                + (problems.count > 2 ? " · ещё \(problems.count - 2)" : "")
        } else if !checks.isEmpty {
            preview = "Все проверки прошли в штатном режиме"
        } else {
            preview = "Состояние сервиса и результаты проверки"
        }
    }

    // MARK: - Язык строки проверки
    //
    // Владелец 16.10.2026 про сводку «Состояние системы»: «какие-то кривые
    // сыры от этих будильников всяких и мониторингов». Тексты сторожей на
    // `.110` владелец переписывать не ждёт, значит показывать факт — работа
    // приложения. Всё ниже работает с ТЕМ ЖЕ полями digest, новый источник
    // данных не заводится.

    /// Сырые имена сторожей → человеческие. Сервер шлёт оба вида вперемешку
    /// («База знаний: 3, infra-vpn-watch: 1»), и без этого владелец видит в
    /// сводке имена скриптов вместо того, что сломалось.
    ///
    /// Наполнено по живым сообщениям `digest` за 12–16.10.2026: каждое имя
    /// проверено на встречаемость, выдуманных нет. Неизвестное имя НЕ
    /// заменяется и не прячется — остаётся как пришло: явное имя сторожа
    /// полезнее выдуманного названия, которое ничего не объяснит.
    static let emitterNames: [String: String] = [
        "xray-target-guard": "Сторож VPN",
        "infra-vpn-watch": "Сторож инфраструктуры",
        "obsidian-journal-watch": "Сборка журнала",
        "repo-hygiene": "Порядок в репозиториях",
        "dropbox-hygiene": "Порядок в Dropbox",
        "mnemosyne-110": "Память .110",
        "ai-stack-update": "Обновление ИИ-стека",
        "backup": "Резервные копии",
        "traycer-link-watch": "Сторож связи с Traycer",
        "mcp-net-watch": "Сторож MCP",
        "vnc-desktop-watch": "Сторож рабочего стола",
        "svc-watch": "Сторож служб",
    ]

    /// Признаки отказа в тексте УСПЕШНОЙ проверки. Проверка может прийти со
    /// `status: ok`, а текст говорить об отказе — тогда зелёная галочка врёт.
    /// Все маркеры взяты из живых сообщений digest за 12–16.10.
    static let failureMarkers = ["не прошла", "упал", "сбой", "не работает", "недоступен", "ошибк"]

    /// `area`-заглушка: подпись без содержания. Приходит у трёх проверок из
    /// шестнадцати («обновление ИИ-стека», «VPN/прокси TaskFlow↔Linear»,
    /// «Проверка сервиса») — так на всех пяти днях наблюдения.
    static let placeholderArea = "Сервер"

    /// Заменить сырые имена сторожей на человеческие. Имена приходят в
    /// скобках перечисления («xray-target-guard: 3, База знаний: 1»), поэтому
    /// замена идёт по всему тексту и не трогает числа рядом.
    static func humanizeEmitters(_ text: String) -> String {
        var result = text
        // Длинные имена первыми, чтобы короткое совпадение не съело часть
        // более длинного ключа.
        for key in emitterNames.keys.sorted(by: { $0.count > $1.count }) {
            guard let human = emitterNames[key] else { continue }
            result = result.replacingOccurrences(of: key, with: human)
        }
        return result
    }

    /// `status: ok`, но текст говорит об отказе. Владелец должен видеть
    /// расхождение, а не зелёную галочку на зелёном противоречии.
    static func contradictsSuccess(_ message: String) -> Bool {
        let lowered = message.lowercased()
        return failureMarkers.contains { lowered.contains($0) }
    }

    /// Текст, обрывающийся на двоеточии, — незаконченная фраза. Показывать
    /// как законченный факт нельзя, поэтому дописываем, что продолжения нет.
    ///
    /// Хвост из пробелов перед дописыванием убираем: иначе в строке видно
    /// «проверка не прошла:␠␠␠␠подробности не пришли» (тест
    /// `ServiceTicketPresentationTests.test_truncatedMessageIsMarked`).
    static func markTruncated(_ message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix(":") else {
            return message
        }
        return trimmed + " подробности не пришли"
    }

    /// Текст строки целиком: человеческие имена + явная отметка, когда
    /// продолжения нет.
    static func readable(_ check: ServiceTicketCheck) -> String {
        markTruncated(humanizeEmitters(check.message))
    }

    /// Подпись `area`, если она несёт смысл; `nil` — показывать нечего.
    static func readableArea(_ check: ServiceTicketCheck) -> String? {
        let area = check.area.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !area.isEmpty, area != placeholderArea else { return nil }
        return area
    }
}
