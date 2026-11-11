import SwiftUI

#if DEBUG
/// Отладочные стенды экрана чата (предпросмотр чтения, порядка, стресса,
/// шатания). Вынесены из боевого файла 11.11.2026 (аудит плавности п.14).
extension RoleChatRoomScreen {
    static var readingPreviewChat: RoleChat {
        if ProcessInfo.processInfo.environment["TASKFLOW_CHAT_ORDER_PREVIEW"] == "1" {
            return try! JSONDecoder().decode(RoleChat.self, from: Data(#"{"id":"reading-preview","title":"Порядок ответов","kind":"group","created_by":"preview-owner","members":[{"id":"role_code_orchestrator","name":"Оркестратор"},{"id":"role_architect","name":"Архитектор"}]}"#.utf8))
        }
        return try! JSONDecoder().decode(RoleChat.self, from: Data(#"{"id":"reading-preview","title":"Исследователь","kind":"direct","created_by":"preview-owner","members":[{"id":"role_researcher","name":"Исследователь","role_key":"researcher"}]}"#.utf8))
    }

    static let structuredOutputPreviewJSON = #"""
    {
      "schema_version": 1,
      "ok": true,
      "output": [
        {"type": "text", "text": "Сверил **план с текущим состоянием**. Ниже — короткий итог и ход проверки."},
        {"type": "heading", "text": "Проверка результата"},
        {"type": "status", "title": "Проверка источников", "code": "passed", "text": "Все три источника доступны"},
        {"type": "table", "title": "Сверка этапов", "columns": ["Этап", "Статус", "Заметка"], "rows": [["Сверка", "Готово", "Длинная ячейка для проверки переноса текста на несколько строк внутри одной строки таблицы без наложения на соседние данные"], ["Итог", "В работе", "Следующая строка"]]},
        {"type": "progress", "title": "Готовность", "current": 3, "total": 4, "label": "3 из 4 проверок", "unit": "этапа"},
        {"type": "chart", "title": "Результаты по дням", "kind": "bar", "unit": "проверок", "points": [{"label": "Пн", "value": 4}, {"label": "Вт", "value": 7}, {"label": "Ср", "value": 5}]},
        {"type": "diagram", "title": "Ход работы", "kind": "chain", "items": [{"label": "Вход", "state": "done"}, {"label": "Анализ", "state": "done"}, {"label": "Проверка", "state": "in_progress"}, {"label": "Передача", "state": "queued"}]},
        {"type": "report", "report_kind": "intermediate", "sections": {
          "result": [{"type": "text", "text": "Подтвердил основной вывод."}],
          "work": [{"type": "list", "items": ["Сверены три источника.", "Сопоставлены этапы плана."]}],
          "checks": [{"label": "Доступность источников", "status": "passed", "detail": "Все три доступны"}],
          "limitations": [{"type": "text", "text": "Один источник обновляется с задержкой."}],
          "materials": [{"kind": "document", "title": "Исходная спецификация", "ref": "docs/spec.md"}]
        }},
        {"type": "text", "text": "Виджет из ответа:\n```widget\n{\"type\":\"card\",\"title\":\"Проверочный виджет\",\"body\":\"Отрисован внутри JSON-ответа чата.\"}\n```"}
      ],
      "artifacts": [],
      "plan_artifact": null,
      "error": null,
      "next_hint": "После проверки оформить итоговый отчёт.",
      "needs_human": false
    }
    """#

    static var structuredOutputPreviewMessages: [RoleChatMessage] {
        let block: String
        if ProcessInfo.processInfo.environment["TASKFLOW_STRUCTURED_OUTPUT_INVALID_PREVIEW"] == "1" {
            block = "```tf-json\n{\"schema_version\":1,\"ok\":true,\"output\":[{\"type\":\"report\"}\n```"
        } else {
            block = "```tf-json\n\(structuredOutputPreviewJSON)\n```"
        }
        let envelope = (try? JSONSerialization.jsonObject(with: Data(structuredOutputPreviewJSON.utf8))) as? [String: Any]
        let serverEnvelope: [String: Any] = [
            "contract": "role.v1", "ok": true,
            "output": "Это фактический формат ответа сервера сегодня. Старые сообщения и текущие роли продолжают читаться.",
            "artifacts": [], "error": NSNull(), "next_hint": NSNull(), "needs_human": false
        ]
        let serverAnswer: [String: Any] = ["id": "structured-server-answer", "text": "Это фактический формат ответа сервера сегодня.", "role_envelope": serverEnvelope, "from_user_id": "role_researcher", "from_user_name": "Исследователь", "created_at": "2026-10-17T10:00:01Z", "sequence": 2, "reply_to_message_id": "structured-question", "is_session_marker": false]
        var answer: [String: Any] = ["id": "structured-answer", "text": block, "from_user_id": "role_researcher", "from_user_name": "Исследователь", "created_at": "2026-10-17T10:00:02Z", "sequence": 3, "reply_to_message_id": "structured-question", "is_session_marker": false]
        if ProcessInfo.processInfo.environment["TASKFLOW_STRUCTURED_OUTPUT_INVALID_PREVIEW"] != "1", let envelope {
            answer["role_envelope"] = envelope
        }
        let rows: [[String: Any]] = [
            ["id": "structured-question", "text": "Покажи, как выглядит структурированный результат.", "from_user_id": "preview-owner", "created_at": "2026-10-17T10:00:00Z", "sequence": 1, "is_session_marker": false],
            serverAnswer,
            answer
        ]
        return try! JSONDecoder().decode([RoleChatMessage].self, from: JSONSerialization.data(withJSONObject: rows))
    }

    static func correctnessMessages(stress: Bool = false) -> [RoleChatMessage] {
        let rows: [[String: Any]] = stress ? (0..<300).map { index in
            ["id": "history-\(index)", "text": "Сообщение \(index). " + String(repeating: "Подробный текст результата для проверки прокрутки. ", count: 6),
             "from_user_id": index.isMultiple(of: 2) ? "preview-owner" : "role_architect",
             "created_at": "2026-10-11 14:20:50", "is_session_marker": false, "sequence": index]
        } : [
            ["id": "question-1", "text": "ПЕРВЫЙ ВОПРОС", "from_user_id": "preview-owner", "created_at": "2026-10-11 14:20:50", "sequence": 1, "is_session_marker": false],
            ["id": "question-2", "text": "ВТОРОЙ ВОПРОС", "from_user_id": "preview-owner", "created_at": "2026-10-11 14:20:51", "sequence": 2, "is_session_marker": false]
        ]
        return try! JSONDecoder().decode([RoleChatMessage].self, from: JSONSerialization.data(withJSONObject: rows))
    }

    static var readingPreviewMessages: [RoleChatMessage] {
        try! JSONDecoder().decode([RoleChatMessage].self, from: Data(#"[{"id":"previous","is_session_marker":false,"text":"Расскажи о результате","from_user_id":"preview-owner","created_at":"2026-10-10T18:00:00Z"},{"id":"finished","is_session_marker":false,"text":"Ответ начинается здесь. Короткий готовый результат.","from_user_id":"role_researcher","created_at":"2026-10-10T18:01:00Z"}]"#.utf8))
    }
    static func readingPreviewTurn(long: Bool) -> RoleChatLiveTurn {
        if ProcessInfo.processInfo.environment["TASKFLOW_ACTION_LABELS_PREVIEW"] == "1" {
            return RoleChatLiveTurn(chatID: "reading-preview", userID: "role_researcher", name: "Исследователь", startedAt: nil,
                items: RoleActionPreview.items, thinking: nil)
        }
        return         RoleChatLiveTurn(chatID: "reading-preview", userID: "role_researcher", name: "Исследователь", startedAt: nil,
            items: [.text(long ? "Ответ начинается здесь. " + String(repeating: "Подробное пояснение результата. ", count: 60) + "КОНЕЦ ДЛИННОГО ОТВЕТА" : "Ответ начинается здесь. Короткое пояснение.")], thinking: nil)
    }

    /// Пункты идущего хода для стенда шатания: реальный порядок с сервера —
    /// «размышление, шаг, шаг, размышление, шаг…» (база TaskFlow, 25.10.2026).
    static func shakePreviewItems() -> [RoleChatLiveItem] {
        let steps: [(String, String)] = [
            ("read", "Sources/Core/Models/RoleChat.swift"),
            ("bash", "rg defaultScrollAnchor Sources"),
            ("edit", "Sources/Features/Roles/RoleActionGroup.swift"),
            ("bash", "npm run build"),
            ("read", "docs/2026-10-24-chat-smoothness-plan.md"),
            ("grep", "scrollPosition Sources/Chat"),
            ("write", "docs/2026-10-25-chat-shake.md"),
            ("bash", "xcodebuild -scheme TaskFlow build"),
            ("read", "AGENT-WORK-SCOPES.md"),
            ("edit", "Sources/Features/Roles/RoleLiveTurnView.swift")
        ]
        var items: [RoleChatLiveItem] = []
        for (index, step) in steps.enumerated() {
            items.append(.thinking(RoleChatThinking(id: "thinking-\(index)", text: "Размышление \(index)", isRunning: true,
                startedAt: "2026-10-25T03:00:0\(index % 10)Z")))
            items.append(.step(RoleChatLiveStep(id: "step-\(index)", tool: step.0, detail: step.1, status: .done,
                startedAt: "2026-10-25T03:00:0\(index % 10)Z", endedAt: "2026-10-25T03:00:0\(index % 10)Z")))
        }
        return items
    }

    /// Снимок живого хода на тике стенда — повторяет фазы сервера: сначала
    /// размышление с растущим текстом, потом шаги, в конце ответ роли.
    static func shakePreviewItems(at tick: Int) -> [RoleChatLiveItem] {
        let start = "2026-10-25T03:00:00Z"
        func thinking(_ id: String, _ text: String, _ running: Bool) -> RoleChatLiveItem {
            .thinking(RoleChatThinking(id: id, text: text, isRunning: running, startedAt: start,
                endedAt: running ? nil : "2026-10-25T03:00:05Z"))
        }
        func step(_ id: String, _ tool: String, _ detail: String, _ running: Bool) -> RoleChatLiveItem {
            .step(RoleChatLiveStep(id: id, tool: tool, detail: detail, status: running ? .running : .done,
                startedAt: start, endedAt: running ? nil : "2026-10-25T03:00:05Z"))
        }
        var items: [RoleChatLiveItem] = []
        // Фаза 1: размышление (текст растёт), затем шаг.
        items.append(thinking("thinking-0", tick <= 1 ? "" : "Сверяю, что именно прыгает", tick < 4))
        if tick >= 4 { items.append(step("step-0", "read", "Sources/Core/Models/RoleChat.swift", tick < 5)) }
        // Фаза 2: второе размышление и второй шаг.
        if tick >= 6 {
            items.append(thinking("thinking-1", tick <= 6 ? "" : "Проверяю раскладку", tick < 8))
            items.append(step("step-1", "bash", "rg defaultScrollAnchor Sources", tick < 9))
        }
        // Фаза 3: ответ роли ПРИХОДИТ В СЕРЕДИНЕ хода (так и пишут роли:
        // «проверил первую часть» → снова инструменты → дописал).
        if tick >= 8 { items.append(.text("Проверил первую часть: полоса появляется вместо строки.")) }
        // Фаза 4: после текста снова инструменты.
        if tick >= 9 && tick < 11 {
            items.append(thinking("thinking-2", "", true))
        }
        if tick >= 9 { items.append(step("step-2", "edit", "Sources/Features/Roles/RoleActionGroup.swift", tick < 10)) }
        // Фаза 5: сервер прячет законченное ПУСТОЕ размышление (snapshot,
        // chatLiveTurn.ts): список пунктов снимка от этого становится короче —
        // клиент обязан пережить это без прыжка ленты.
        if tick >= 12 { items.append(.text("Проверил первую часть: полоса появляется вместо строки. Дописал вывод.")) }
        if tick >= 14 {
            items.append(.text("Проверил первую часть: полоса появляется вместо строки. Дописал вывод. Правку внёс."))
        }
        return items
    }
}
#endif
