import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import PhotosUI
import UIKit
import QuickLook

/// Своё сообщение, которое уже видно в ленте, но сервер его ещё не принял
/// (или не принял совсем — `failed`). Как в мессенджерах: пузырь появляется
/// сразу по нажатию «Отправить», без ожидания сети.
private struct PendingOutgoing: Identifiable, Equatable {
    let id: String
    let text: String
    let attachments: [ApiChatAttachment]
    let mode: RoleChatWorkMode
    let executionMode: ChatExecutionMode
    var failed = false
}

struct RoleChatRoomScreen: View {
    @Environment(SecretaryVoiceViewModel.self) private var voiceSession: SecretaryVoiceViewModel?
    @Environment(SessionStore.self) private var session
    @Environment(TaskStore.self) private var taskStore
    @Environment(\.dismiss) private var dismiss
    @State private var chat: RoleChat
    @State private var messages: [RoleChatMessage] = []
    /// Лента получена с сервера хотя бы раз. До этого пустой `messages`
    /// значит «ещё грузится», а не «сообщений нет» (26.10.2026: при каждом
    /// открытии чата мелькала пустая страница «Пока нет сообщений»).
    @State private var hasLoadedMessages = false
    @State private var draft = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    /// Последнее сообщение, до которого чат уже отмечен прочитанным (LOCK-206).
    @State private var markedReadMessageID: String?
    /// Карточка задачи в сообщении (владелец 25.09.2026, этап 2 «Супер
    /// Помощника владельца») — открывает её шторкой, тот же приём, что у ChatBubble.
    @State private var pendingTaskID: String?
    @State private var voice = RoleChatVoiceController()
    @State private var isFileImporterPresented = false
    /// Меню «+» (владелец 26.09.2026): фото/файл/камера.
    @State private var isPhotoPickerPresented = false
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var isCameraPresented = false
    @State private var pendingAttachments: [ApiChatAttachment] = []
    @State private var isUploadingAttachment = false
    @State private var openingAttachmentIDs: Set<String> = []
    @State private var previewAttachmentURL: URL?
    @State private var player = VoicePlayer()
    @State private var pendingVoices: [VoiceMessage] = []
    @State private var pendingVoiceModes: [UUID: RoleChatWorkMode] = [:]
    @State private var uploadedVoiceIDs: [UUID: String] = [:]
    @State private var sendingVoiceIDs: Set<UUID> = []
    /// Режим выбора сообщений: включается из меню «…» или долгим нажатием на
    /// сообщение. В нём панель ввода заменяется полосой выбора, а тап по
    /// сообщению отмечает его (владелец 21.09.2026: «долгое нажатие максимум
    /// активирует эту функцию выбора, чтобы я потом протыкал и удалил»).
    @State private var isSelecting = false
    @State private var selectedMessageIDs: Set<String> = []
    @State private var isDeleteSelectedConfirmOpen = false
    @State private var isClearChatConfirmOpen = false
    @State private var isDetailsPresented = false
    @State private var isContentsPresented = false
    @State private var branchChat: RoleChat?
    /// Панель субагентов чата открыта (владелец 28.10.2026).
    @State private var isSubagentsOpen = false
    @Environment(\.openRoute) private var openRoute
    @State private var isBranchPresented = false
    @State private var isBranching = false
    /// Сообщение, которое только что скопировали: рядом со значком на
    /// полторы секунды видна надпись «Скопировано» (владелец 14.10.2026).
    @State private var copiedMessageID: String?
    /// Текст, открытый в «Выделить текст» — системное выделение с ручками.
    @State private var selectingText: SelectableMessageText?
    @State private var contentsTargetID: String?
    /// Сколько последних сообщений рисует лента (владелец 07.11.2026: «пять
    /// моих и пять ответов, дальше пусть подгружаются»). Ленивая лента
    /// угадывала высоту десятков длинных сообщений, и после отправки высота
    /// скакала 30 000 → 63 000 → 57 000 pt — лента улетала вверх. Старые
    /// сообщения лежат в памяти и дорисовываются по 10, когда долистал вверх.
    @State private var feedWindow = RoleChatFeedWindow.step
    @Environment(RealtimeClient.self) private var realtime
    @State private var realtimeObserver = RealtimeObserverSlot<UUID>()
    @State private var roomEventRevision = 0
    /// Счётчик для строки рабочего плана роли (21.10.2026).
    @State private var workPlanRevision = 0
    @State private var workPlanEvent: JSONValue?
    @State private var refreshRevision = 0
    @State private var messageEventRevisions: [String: Int] = [:]
    /// Кто сейчас готовит ответ: userId → имя. Наполняет только сервер
    /// (`chats:typing`) — на время, пока роль действительно отвечает.
    @State private var typists: [String: String] = [:]
    /// Текущий инструмент по тайписту (userId → имя инструмента с сервера,
    /// например "read"/"edit"/"bash") — только пока `active == true` и
    /// сервер прислал `tool`. Живёт ровно как `typists`: без истории.
    @State private var typistTools: [String: String] = [:]
    /// Живые ходы и их дельты — в наблюдаемом хранилище (06.11.2026): экран
    /// при отрисовке читает только паспорта ходов, текст хода — строка хода,
    /// и порция ответа не перерисовывает экран целиком (`RoleChatLiveStore`).
    @State private var liveStore = RoleChatLiveStore()
    /// Идущие ходы ролей (userId → снимок): текст по словам и шаги
    /// (`chats:live`, 27.09.2026). Рисуются и в группах. Только для
    /// обработчиков событий — при отрисовке читать `liveStore.slots`.
    private var liveTurns: [String: RoleChatLiveTurn] {
        get { liveStore.turns }
        nonmutating set { liveStore.turns = newValue }
    }
    @State private var restoredTurnIDs: Set<String> = []
    @State private var endedTurnIDs: Set<String> = []
    /// Ходы, чей ответ сервер закрыл остановкой: подпись «Ответ получен»
    /// под ними была бы неправдой (владелец 30.10.2026).
    @State private var stoppedTurnIDs: Set<String> = []
    /// Ход дельтами (27.10.2026): состояние по роли и роли, у которых сервер
    /// уже шлёт дельты, — их старый полный снимок `chats:live` пропускаем.
    /// Только для обработчиков событий — при отрисовке читать
    /// `liveStore.activityNames` / `activityTools`.
    private var liveDeltas: [String: RoleChatLiveTurnState] {
        get { liveStore.deltas }
        nonmutating set { liveStore.deltas = newValue }
    }
    @State private var deltaUsers: Set<String> = []
    @State private var liveSnapshotLoading = false
    /// Final messages stay in the paced queue until their text/actions are shown.
    @State private var completingTurns: [String: RoleChatLiveTurn] = [:]
    /// Строка ленты для каждого сообщения. Своя у каждого сообщения; у
    /// сообщения, ЗАВЕРШИВШЕГО живой ход, — строка хода: пока ход доигрывает
    /// ответ, сообщение скрыто, и при его появлении строка не должна
    /// пересоздаваться (пересоздание рвёт высоту и сбрасывает якорь
    /// прокрутки). Раньше id строился как «reply:автор:на что ответ», а такая
    /// пара не уникальна — ответ роли и служебные строки координации получали
    /// один id, и SwiftUI переиспользовал строки: текст пропадал, лента
    /// прыгала (владелец 22.10.2026).
    @State private var rowIDByMessageID: [String: String] = [:]
    /// Какое сообщение закрыло живой ход: ход прячет из ленты ровно ЭТО
    /// сообщение, а не все ответы того же автора подряд.
    @State private var completedMessageIDByTurn: [String: String] = [:]
    /// Сообщения, которые закрыли живой ход. Их шаги рисуются в той же форме
    /// и тем же составом, что и в живом пузыре: иначе на смене строки лента
    /// теряет сотни пунктов высоты и шатается (владелец 30.10.2026).
    @State private var closedTurnMessageIDs: Set<String> = []
    /// Сообщения, уже лежавшие в ленте при открытии: не переигрываем проявление
    /// (владелец 03.11.2026 — «открываю чат, и у меня проявляется текст»).
    @State private var seedMessageIDs: Set<String>? = nil
    /// Первый полный снимок после открытия уже вошёл в семя.
    @State private var historySeedSettled = false
    /// Пункты хода такими, какими их видел владелец к моменту закрытия.
    /// Свои сообщения в пути: видны сразу, до ответа сервера.
    @State private var pendingOutgoing: [PendingOutgoing] = []
    @State private var discussionStatus: RoleChatDiscussion? = nil
    /// Идёт запрос «Остановить» — кнопка не жмётся дважды.
    @State private var isStopping = false
    @State private var pendingVoiceExecutionModes: [UUID: ChatExecutionMode] = [:]
    @State private var workMode: RoleChatWorkMode = .work
    /// Столбец участников справа (владелец 20.10.2026) — помнит, открыт ли.
    @State private var noticeMessage: String?
    /// Идёт сжатие сессии этой роли — плашка «Сжимаю…» над лентой (владелец
    /// 07.11.2026: «нажал сжать — никакой реакции»).
    @State private var compactingRoleName: String?
    @State private var modelChoice = ChatModelChoice()
    @State private var workspaceChoice = ChatWorkspaceChoice()
    @State private var composerControls = ChatComposerControlStore()
    @State private var showsComposerCommands = false
    @State private var showsSessionPanel = false
    @State private var pendingSessionAttachment: ChatAttachmentSource?
    /// Команды ленты. Лентой владеет таблица (`ChatFeedVirtualList`): экран
    /// только просит её подвинуться, а не ведёт смещение сам.
    @State private var feedScroll = ChatFeedScrollHandle()
    @State private var chatIsNearBottom = true
    /// Лента идёт в движении от руки владельца. По этому признаку дорисовываются
    /// старые сообщения: при открытии короткого чата верх виден сразу, и
    /// автодорисовка увозила ленту от низа (07.11.2026).
    @State private var chatIsScrolling = false
    /// Коалесцер в ссылочной коробке, а не в `@State`: запись в `@State`
    /// обесценивает вью, поэтому раньше КАЖДОЕ событие сокета — в том числе
    /// из другого чата — пересобирало всю ленту, проекцию и выдержки (ревью
    /// потока событий п.B1). Коробка меняет состояние молча.
    @State private var eventBatch = ChatEventBatchBox()
    @FocusState private var composerFocused: Bool
    private let api = APIClient()

    private var readingPreview: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["TASKFLOW_CHAT_READING_PREVIEW"] == "1"
        #else
        false
        #endif
    }

    private var pacesLiveText: Bool {
        false
    }

    #if DEBUG
    static var readingPreviewChat: RoleChat {
        if ProcessInfo.processInfo.environment["TASKFLOW_CHAT_ORDER_PREVIEW"] == "1" {
            return try! JSONDecoder().decode(RoleChat.self, from: Data(#"{"id":"reading-preview","title":"Порядок ответов","kind":"group","created_by":"preview-owner","members":[{"id":"role_code_orchestrator","name":"Оркестратор"},{"id":"role_architect","name":"Архитектор"}]}"#.utf8))
        }
        return try! JSONDecoder().decode(RoleChat.self, from: Data(#"{"id":"reading-preview","title":"Исследователь","kind":"direct","created_by":"preview-owner","members":[{"id":"role_researcher","name":"Исследователь","role_key":"researcher"}]}"#.utf8))
    }

    private static let structuredOutputPreviewJSON = #"""
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

    private static var structuredOutputPreviewMessages: [RoleChatMessage] {
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

    private static func correctnessMessages(stress: Bool = false) -> [RoleChatMessage] {
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

    private static var readingPreviewMessages: [RoleChatMessage] {
        try! JSONDecoder().decode([RoleChatMessage].self, from: Data(#"[{"id":"previous","is_session_marker":false,"text":"Расскажи о результате","from_user_id":"preview-owner","created_at":"2026-10-10T18:00:00Z"},{"id":"finished","is_session_marker":false,"text":"Ответ начинается здесь. Короткий готовый результат.","from_user_id":"role_researcher","created_at":"2026-10-10T18:01:00Z"}]"#.utf8))
    }
    private static func readingPreviewTurn(long: Bool) -> RoleChatLiveTurn {
        if ProcessInfo.processInfo.environment["TASKFLOW_ACTION_LABELS_PREVIEW"] == "1" {
            return RoleChatLiveTurn(chatID: "reading-preview", userID: "role_researcher", name: "Исследователь", startedAt: nil,
                items: RoleActionPreview.items, thinking: nil)
        }
        return         RoleChatLiveTurn(chatID: "reading-preview", userID: "role_researcher", name: "Исследователь", startedAt: nil,
            items: [.text(long ? "Ответ начинается здесь. " + String(repeating: "Подробное пояснение результата. ", count: 60) + "КОНЕЦ ДЛИННОГО ОТВЕТА" : "Ответ начинается здесь. Короткое пояснение.")], thinking: nil)
    }

    /// Пункты идущего хода для стенда шатания: реальный порядок с сервера —
    /// «размышление, шаг, шаг, размышление, шаг…» (база TaskFlow, 25.10.2026).
    private static func shakePreviewItems() -> [RoleChatLiveItem] {
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
    #endif

    init(chat: RoleChat) {
        _chat = State(initialValue: chat)
        // Лента — это локальная база (05.11.2026): своей копии в памяти у
        // экрана больше нет, иначе пришедшее, пока чат был закрыт, на экран
        // не попадало.
        if let local = try? LocalStore.shared.messages(chatID: chat.id), !local.isEmpty {
            // Локальная база: переписка открывается сразу, без сети.
            _messages = State(initialValue: local)
            _hasLoadedMessages = State(initialValue: true)
            _seedMessageIDs = State(initialValue: Set(local.map(\.id)))
        } else if let cached = APIClient().cachedRoleChatMessages(id: chat.id) {
            _messages = State(initialValue: cached)
            _hasLoadedMessages = State(initialValue: true)
            _seedMessageIDs = State(initialValue: Set(cached.map(\.id)))
        } else {
            // Пустая комната: пустое семя уже зафиксировано — новые ответы проявятся.
            _seedMessageIDs = State(initialValue: [])
            _historySeedSettled = State(initialValue: true)
        }
        let saved = UserDefaults.standard.string(forKey: "roleChat.mode." + chat.createdBy + "." + chat.id)
        let mode = saved.flatMap(RoleChatWorkMode.init(rawValue:)) ?? .work
        _workMode = State(initialValue: chat.hasOwnSettings ? ChatSessionWorkModePolicy.visibleSelection(mode) : (RoleChatWorkMode.available(in: chat).contains(mode) ? mode : .work))
        #if DEBUG
        if readingPreview {
            // Предпросмотр задаёт ленту сразу, без запроса к серверу.
            _hasLoadedMessages = State(initialValue: true)
            let structuredOutputPreview = ProcessInfo.processInfo.environment["TASKFLOW_STRUCTURED_OUTPUT_PREVIEW"] == "1"
            _messages = State(initialValue: structuredOutputPreview ? Self.structuredOutputPreviewMessages : Array(Self.readingPreviewMessages.prefix(1)))
            if structuredOutputPreview {
                _liveStore = State(initialValue: RoleChatLiveStore(turns: [:]))
            } else if ProcessInfo.processInfo.environment["TASKFLOW_CHAT_ORDER_PREVIEW"] == "1" {
                _liveStore = State(initialValue: RoleChatLiveStore(turns: [
                    "role_code_orchestrator": RoleChatLiveTurn(chatID:"reading-preview",userID:"role_code_orchestrator",name:"Оркестратор",startedAt:"2026-10-10T18:00:01Z",items:[.text("ПЕРВЫЙ ОТВЕТ ОРКЕСТРАТОРА")],thinking:nil),
                    "role_architect": RoleChatLiveTurn(chatID:"reading-preview",userID:"role_architect",name:"Архитектор",startedAt:"2026-10-10T18:00:02Z",items:[.text("ВТОРОЙ ОТВЕТ АРХИТЕКТОРА")],thinking:nil)
                ]))
            } else {
                _liveStore = State(initialValue: RoleChatLiveStore(turns: ["role_researcher": Self.readingPreviewTurn(long: false)]))
            }
            if !structuredOutputPreview && ProcessInfo.processInfo.environment["TASKFLOW_CHAT_CORRECTNESS_PREVIEW"] == "1" {
                _messages = State(initialValue: Self.correctnessMessages())
                _liveStore = State(initialValue: RoleChatLiveStore(turns: [
                    "role_code_orchestrator": RoleChatLiveTurn(chatID: "reading-preview", userID: "role_code_orchestrator", name: "Оркестратор", startedAt: "2026-10-11T14:20:51.500Z", items: [.text("```widget\n{\"type\":\"card\""), .text("```html\n<button>Готовый интерактив")], thinking: nil, triggerMessageID: "question-1"),
                    "role_architect": RoleChatLiveTurn(chatID: "reading-preview", userID: "role_architect", name: "Архитектор", startedAt: "2026-10-11T14:20:51.700Z", items: [.text("ВТОРОЙ ОТВЕТ")], thinking: nil, triggerMessageID: "question-2")
                ]))
            }
            if !structuredOutputPreview && ProcessInfo.processInfo.environment["TASKFLOW_CHAT_STRESS_PREVIEW"] == "1" {
                _messages = State(initialValue: Self.correctnessMessages(stress: true))
                _liveStore = State(initialValue: RoleChatLiveStore(turns: [:]))
            }
            if !structuredOutputPreview && ProcessInfo.processInfo.environment["TASKFLOW_CHAT_SHAKE_PREVIEW"] == "1" {
                // Стенд шатания (25.10.2026): длинная переписка + идущий ход
                // роли. Пункты повторяют реальный порядок с сервера —
                // «размышление, шаг, шаг, размышление, шаг…» — pacer
                // проявляет их по одному, как в бою.
                _messages = State(initialValue: Self.correctnessMessages(stress: true))
                _liveStore = State(initialValue: RoleChatLiveStore(turns: [
                    "role_builder": RoleChatLiveTurn(chatID: "reading-preview", userID: "role_builder",
                        name: "Разработчик", startedAt: "2026-10-25T03:00:00Z",
                        items: Self.shakePreviewItems(at: 0), thinking: nil)
                ]))
            }
        }
        #endif
    }

    var body: some View {
        ZStack {
            // Владелец 25.09.2026: фон экрана ЗДЕСЬ — на самом верхнем
            // уровне, а не за панелью композера, и без ограничения edges
            // (регион .keyboard входит в .ignoresSafeArea() по умолчанию).
            // Иначе в углах системной клавиатуры (у неё скруглённые верхние
            // углы) сквозь скругление просвечивал фон корневого UIWindow
            // (чёрный) — композер стоит НАД клавиатурой, его собственный фон
            // до этого места физически не достаёт.
            TFScreenFill()
            composerRoom
        }
        // Роли, которых позвали субагентами, — та же выезжающая панель, что
        // у комнат; портрет открывает комнату субагента (владелец 28.10.2026).
        .overlay(alignment: .trailing) {
            let subagents = SubagentRailItem.items(messages: messages, members: chat.members, chatID: chat.id)
            if !subagents.isEmpty {
                ChatEdgeRail(isOpen: $isSubagentsOpen, openLabel: "Субагенты", closedLabel: "Показать субагентов", identifier: "chat.subagentsRail") {
                    SubagentRailPanel(items: subagents) { openRoute?(.roleChat(id: $0.id)) }
                }
            }
        }
        .quickLookPreview($previewAttachmentURL)
        .task(id: chat.id + ":" + (chat.taskID ?? "") + ":" + String(workPlanRevision) + ":" + String(refreshRevision)) {
            await loadDiscussionStatus()
        }
        .onChange(of: previewAttachmentURL) { oldURL, newURL in
            if newURL == nil, let oldURL {
                try? FileManager.default.removeItem(at: oldURL.deletingLastPathComponent())
            }
        }
        #if DEBUG
        .task { await runShakePreview() }
        #endif
    }

    #if DEBUG
    /// Стенд шатания (25.10.2026): снимки живого хода приходят каждые 150 мс,
    /// как их шлёт сервер (LIVE_BROADCAST_MS). Клиент тянет их тем же кодом,
    /// что и в бою: pacer проявляет действия, лента привязана к низу.
    private func runShakePreview() async {
        guard ProcessInfo.processInfo.environment["TASKFLOW_CHAT_SHAKE_PREVIEW"] == "1" else { return }
        for tick in 1...24 {
            try? await Task.sleep(for: .milliseconds(150))
            if tick == 20 {
                // Ход закончился: живой пузырь сменяется ответом роли.
                liveTurns["role_builder"] = nil
                let rows: [[String: Any]] = [
                    ["id": "preview-answer", "text": "Проверил первую часть: полоса появляется вместо строки. Дописал вывод. Правку внёс.",
                     "from_user_id": "role_builder", "from_user_name": "Разработчик",
                     "created_at": "2026-10-25T03:00:10Z", "is_session_marker": false]
                ]
                let replies = try! JSONDecoder().decode([RoleChatMessage].self,
                                                       from: JSONSerialization.data(withJSONObject: rows))
                for reply in replies { insertIncoming(reply) }
                continue
            }
            liveTurns["role_builder"] = RoleChatLiveTurn(chatID: "reading-preview", userID: "role_builder",
                name: "Разработчик", startedAt: "2026-10-25T03:00:00Z",
                items: Self.shakePreviewItems(at: tick), thinking: nil)
        }
    }
    #endif

    /// Snapshot belongs to this room; cancelled requests cannot replace it.
    private func loadDiscussionStatus() async {
        let chatID = chat.id
        guard let taskID = chat.taskID else {
            discussionStatus = nil
            return
        }
        do {
            let all = try await api.taskDiscussions(taskID: taskID)
            guard !Task.isCancelled, chat.id == chatID, chat.taskID == taskID else { return }
            discussionStatus = all.first { $0.chatID == chatID }
        } catch {
            guard !Task.isCancelled, chat.id == chatID, chat.taskID == taskID else { return }
            // Older servers have no discussion routes. Never invent a delivery state.
            discussionStatus = nil
        }
    }

    private var discussionStatusBar: some View {
        Group {
            if let discussion = discussionStatus {
                VStack(alignment: .leading, spacing: TFSpacing.xs) {
                    Text(discussion.statusTitle).tfText(.action)
                    if let detail = discussion.statusDetail {
                        Text(detail).tfText(.meta).foregroundStyle(Color.tfDim)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, TFSpacing.lg)
                .padding(.vertical, TFSpacing.xs)
                .hintAnchor(HintAnchorID.chatDiscussionDelivery)
                .accessibilityIdentifier("chat.discussionStatus")
            }
        }
    }

    /// Личку ролей владелец читает, не будучи участником: писать в неё нельзя.
    private var isReadOnlyDirectRoom: Bool {
        chat.roomKind == "dm" && !chat.members.contains { $0.id == session.currentUser?.id }
    }

    /// Роль, с которой открыт личный чат: в комнате ролей и в общей комнате
    /// стартовый экран не показываем — там приветствовать некого.
    private var starterMember: RoleChatMember? {
        // Личка двух ролей: владелец в ней не участвует — приветствовать некого.
        guard chat.members.contains(where: { $0.id == session.currentUser?.id }) else { return nil }
        let roles = chat.members.filter { member in
            member.roleKey != nil || member.id == "u-secretary" || member.id.hasPrefix("role_")
        }
        guard roles.count == 1 else { return nil }
        return roles.first
    }

    /// Окно сессии. Отдельное свойство, а не вызов в `.sheet`: длинный список
    /// аргументов иначе не компилируется («unable to type-check»).
    private var sessionPanelSheet: some View {
        // Контекст — по роли чата: у Помощника это `u-secretary`, у остальных
        // ролей — их учётка. Раньше здесь было жёстко `u-secretary`, и в чате
        // с любой другой ролью показывалось «Нет замера» (владелец 29.10.2026).
        let contextSnapshot = composerControls.contexts[sessionContextRoleID]
        let sessionRoles = chat.composerRoleKeys
        let working = liveStore.hasTurns || !typists.isEmpty
        return ChatSessionPanel(
            chat: chat,
            choice: modelChoice,
            workspace: workspaceChoice,
            context: contextSnapshot,
            controls: composerControls,
            isWorking: working,
            onRefresh: refreshSession,
            onAttachmentSource: handleAttachmentSource,
            workMode: $workMode,
            chatRoles: sessionRoles)
    }

    private func refreshSession() async {
        await modelChoice.load(chat: chat)
        await workspaceChoice.load(chat: chat)
        await composerControls.load(chat: chat)
    }

    /// Вложения из окна сессии: фото, файл, камера.
    private func handleAttachmentSource(_ source: ChatAttachmentSource) {
        if showsSessionPanel {
            pendingSessionAttachment = source
            showsSessionPanel = false
        } else {
            presentAttachmentSource(source)
        }
    }

    private func sessionPopoverDidDismiss() {
        guard let source = pendingSessionAttachment else { return }
        pendingSessionAttachment = nil
        presentAttachmentSource(source)
    }

    private func presentAttachmentSource(_ source: ChatAttachmentSource) {
        switch source {
        case .photo: isPhotoPickerPresented = true
        case .file: isFileImporterPresented = true
        case .camera: isCameraPresented = true
        }
    }

    /// Правки быстрых действий владельцем (владелец 29.10.2026).
    @State private var quickActionStore = RoleChatQuickActionStore()
    /// Режим правки карточек на стартовом экране.
    @State private var isEditingQuickActions = false
    /// Карточка, которую правят сейчас.
    @State private var editedQuickActionIndex: Int?

    /// Ключ роли для хранения правок быстрых действий.
    private var quickActionRoleKey: String {
        starterRoleKey ?? ""
    }

    /// Карточки быстрых действий с учётом правок владельца.
    private func starterWithOverrides(for member: RoleChatMember) -> RoleChatStarter {
        let base = RoleChatStarters.starter(for: starterRoleKey)
        let overrides = quickActionStore.overrides(for: quickActionRoleKey)
        guard !overrides.isEmpty else { return base }
        return RoleChatStarter(
            roleKey: base.roleKey,
            greeting: base.greeting,
            commands: RoleChatQuickActions.effectiveCommands(for: base, overrides: overrides))
    }

    /// Лист правки карточки: название и промпт.
    private var quickActionEditorSheet: some View {
        let base = RoleChatStarters.starter(for: starterRoleKey)
        guard starterMember != nil,
              let index = editedQuickActionIndex,
              base.commands.indices.contains(index) else {
            return AnyView(EmptyView())
        }
        let command = base.commands[index]
        return AnyView(RoleChatQuickActionEditor(
            stockCommand: command,
            initial: RoleChatQuickActions.override(for: index, in: base,
                                                  overrides: quickActionStore.overrides(for: quickActionRoleKey)),
            onSave: { override in
                quickActionStore.setOverride(override, index: index, roleKey: quickActionRoleKey)
            },
            onReset: {
                quickActionStore.reset(index: index, roleKey: quickActionRoleKey)
            }))
    }

    /// Описания ролей из реестра: ключ роли — «чем занимается».
    private func loadRoleSummaries() async {
        guard roleSummaries.isEmpty else { return }
        guard let list = try? await api.rolesList(all: true) else { return }
        var next: [String: String] = [:]
        for profile in list {
            guard let summary = profile.summary, !summary.isEmpty else { continue }
            next[profile.role] = summary
            if let account = profile.accountID { next[account] = summary }
        }
        roleSummaries = next
    }

    /// Описание роли из реестра ролей: чем она занимается (владелец
    /// 29.10.2026: стартовый экран должен быть «богат information», а не
    /// только приветствием).
    @State private var roleSummaries: [String: String] = [:]

    private func roleSummary(for member: RoleChatMember) -> String? {
        if let key = member.roleKey, let summary = roleSummaries[key], !summary.isEmpty {
            return summary
        }
        if let summary = roleSummaries[member.id], !summary.isEmpty { return summary }
        return nil
    }

    /// Учётка роли, чей контекст показываем в окне сессии.
    private var sessionContextRoleID: String {
        if let member = starterMember { return member.id }
        return "u-secretary"
    }

    /// Ключ роли для каталога приветствий.
    private var starterRoleKey: String? {
        guard let member = starterMember else { return nil }
        if let key = member.roleKey { return key }
        if member.id == "u-secretary" { return "secretary" }
        if member.id.hasPrefix("role_") { return String(member.id.dropFirst(5)) }
        return nil
    }

    private var composerContent: some View {
        VStack(spacing: 0) {
            // Карточки назначений личной комнаты (владелец 08.11.2026): роль —
            // родитель, работа по слоту идёт в общей комнате задачи, карточка
            // ведёт именно туда. Над лентой, как «Задача чата» ниже.
            if chat.roomKind == "personal" {
                ChatChildAssignmentsStrip(chatID: chat.id) { roomID in
                    openRoute?(.roleChat(id: roomID))
                }
                .keyboardDismissShield(isActive: composerFocused) { composerFocused = false }
            }
            // Над лентой, а не поверх неё: подложки нет, и текст под подпись не заходит.
            if let taskID = chat.taskID {
                TaskCardLink(taskID: taskID) {
                    Label { Text("Задача чата").foregroundStyle(Color.tfText) } icon: { Image(systemName: "checklist").foregroundStyle(Color.tfRed) }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, TFSpacing.screenHorizontal)
                        .padding(.vertical, TFSpacing.sm)
                }
                .keyboardDismissShield(isActive: composerFocused) { composerFocused = false }
            }
            // Панель участников переехала в корень раздела «Чаты» и стала
            // панелью комнат (владелец 21.10.2026); состав чата — в «О чате».
            // Рабочий план роли — висячей карточкой поверх ленты (28.10.2026):
            // лента прокручивается под ней, по бокам остаётся прозрачной.
            messageScroll
                .keyboardDismissShield(isActive: composerFocused) { composerFocused = false }
                .safeAreaInset(edge: .bottom, spacing: 0) { composerFooter }
        }
    }

    /// Панели лежат поверх ленты; кнопка «вниз» не участвует в расчёте inset.
    private var composerFooter: some View {
        VStack(spacing: 0) {
            ChatWorkPlanStrip(chatID: chat.id, members: chat.members, revision: workPlanRevision, event: workPlanEvent)
            discussionStatusBar
            if !mentionCandidates.isEmpty {
                mentionSuggestions
            }
            let slashCommands = ChatSlashCommand.suggestions(for: draft, from: composerControls.commands)
            if !slashCommands.isEmpty {
                ChatSlashSuggestions(commands: slashCommands) { command in
                    draft = command.inserting(into: draft)
                    composerFocused = true
                }
            }
            if !pendingAttachments.isEmpty {
                HStack {
                    ForEach(pendingAttachments) { attachment in
                        Label(attachment.fileName, systemImage: "paperclip")
                            .lineLimit(1)
                        Button { pendingAttachments.removeAll { $0.id == attachment.id } } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel("Убрать вложение")
                    }
                }
                .padding(.horizontal, TFSpacing.lg)
            }
        }
        .chatComposerBar {
            if isSelecting {
                selectionBar
            } else if isReadOnlyDirectRoom {
                // Личка двух ролей: владелец читает, пишет — в личной комнате роли.
                Text("Личная переписка ролей — только чтение")
                    .tfText(.action)
                    .foregroundStyle(Color.tfDim)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, TFSpacing.md)
                    .accessibilityIdentifier("chat.readOnlyDirect")
            } else {
                ChatVoiceComposer(
                    text: $draft,
                    placeholder: "Сообщение",
                    canSendText: (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingAttachments.isEmpty)
                        && !isSending && !isUploadingAttachment
                        && (!chat.isAssistantOnly || (modelChoice.isReady && !modelChoice.isSaving)),
                    voice: voice,
                    onAttachmentSource: handleAttachmentSource,
                    onSendText: { Task { await send() } },
                    onSendVoice: sendVoicePreview,
                    onDiscardVoice: { _ in },
                    workMode: chat.hasOwnSettings ? $workMode : nil,
                    availableModes: RoleChatWorkMode.available(in: chat),
                    // Чат задачи работает на модели и в папке роли: выбирать нечего.
                    modelChoice: chat.hasOwnSettings ? modelChoice : nil,
                    workspaceChoice: chat.hasOwnSettings ? workspaceChoice : nil,
                    // Модель/папка/вложения — в окне сессии; в композере только
                    // три полоски (владелец 03.11.2026).
                    sessionControls: nil,
                    // Настройки есть только у личного чата: в чате задачи и группе
                    // левая кнопка открывает вложения (владелец 05.11.2026).
                    onOpenSession: chat.hasOwnSettings ? { showsSessionPanel = true } : nil,
                    sessionAttachments: { source in
                        switch source {
                        case .photo: isPhotoPickerPresented = true
                        case .file: isFileImporterPresented = true
                        case .camera: isCameraPresented = true
                        }
                    },
                    sessionWorkMode: $workMode,
                    sessionAvailableWorkModes: ChatSessionWorkModePolicy.allModes,
                    onShowCommands: chat.hasOwnSettings ? { showsComposerCommands = true } : nil,
                    // Собачка: роли этого чата, кроме меня. Тот же справочник,
                    // что у подсказок при наборе «@» (RoleChatsScreen
                    // mentionCandidates), только берётся по нажатию, а не по
                    // набору (владелец 11.10.2026: «ее все время от руки
                    // писать не охоту»).
                    // Вдвоём выбирать не из кого — кнопка появляется, когда
                    // участников больше двух (владелец 14.10.2026).
                    mentionCandidates: chat.members.count > 2
                        ? chat.mentionMembers(excluding: session.currentUser?.id) : [],
                    isResponding: liveStore.hasTurns || !typists.isEmpty,
                    isStopping: isStopping,
                    onStop: { Task { await stopTurns() } },
                    focus: $composerFocused,
                    sessionPopoverPresented: $showsSessionPanel,
                    sessionPopoverContent: chat.hasOwnSettings ? { AnyView(sessionPanelSheet) } : nil,
                    onSessionPopoverDismiss: sessionPopoverDidDismiss
                )
            }

        }
        .overlay(alignment: .top) {
            if !chatIsNearBottom && !isSelecting {
                ChatScrollToBottomButton {
                    feedScroll.scrollToBottom()
                }
                // Вся зона нажатия выше footer; нижний край пилюли — с зазором 4 pt.
                // Offset не передаёт пользовательский alignment guide в стек footer.
                .offset(y: -TFHitTarget.min - TFSpacing.xs)
            }
        }
    }

    private var composerNavigation: some View {
        composerContent
        .tint(Color.tfText)
        .navigationTitle(chat.displayTitle(excluding: session.currentUser?.id))
        .navigationBarTitleDisplayMode(.inline)
        // Ветка от сообщения — отдельный чат поверх основного; «назад»
        // возвращает в основной разговор (владелец 14.10.2026).
        .navigationDestination(isPresented: $isBranchPresented) {
            if let branchChat { RoleChatRoomScreen(chat: branchChat) }
        }
        .tfSheet(item: $selectingText) { item in
            SelectableTextSheet(text: item.text)
        }
        .tfSheet(isPresented: $isContentsPresented) {
            RoleChatContentsSheet(messages: visibleMessages, currentUserID: session.currentUser?.id) { id in
                isContentsPresented = false
                contentsTargetID = id
            }
        }
        .toolbar {
            #if DEBUG
            if readingPreview && ProcessInfo.processInfo.environment["TASKFLOW_MEMBER_SWIPE_PREVIEW"] != "1" {
                if ProcessInfo.processInfo.environment["TASKFLOW_CHAT_CORRECTNESS_PREVIEW"] == "1" {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Сигнал конца") {
                            for userID in Array(liveTurns.keys) { markLiveTurnEnded(userID) }
                        }.accessibilityIdentifier("chat.preview.end-live")
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Завершить оба") {
                            let rows: [[String: Any]] = [
                                ["id": "answer-1", "text": "ПЕРВЫЙ ОТВЕТ\n\n```widget\n{\"type\":\"card\",\"title\":\"Готовый виджет\",\"body\":\"Содержимое уже готово\"}\n```\n\n```html\n<button onclick=\"this.textContent='Нажато'\">Готовый интерактив</button>\n```", "from_user_id": "role_code_orchestrator", "created_at": "2026-10-11 14:20:52", "sequence": 3, "reply_to_message_id": "question-1", "is_session_marker": false],
                                ["id": "answer-2", "text": "ВТОРОЙ ОТВЕТ", "from_user_id": "role_architect", "created_at": "2026-10-11 14:20:51", "sequence": 4, "reply_to_message_id": "question-2", "is_session_marker": false]
                            ]
                            let replies = try! JSONDecoder().decode([RoleChatMessage].self, from: JSONSerialization.data(withJSONObject: rows))
                            for reply in replies { insertIncoming(reply) }
                        }.accessibilityIdentifier("chat.preview.complete-both")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") {
                        let done = try! JSONDecoder().decode(RoleChatMessage.self, from: Data(#"{"id":"done-orchestrator","from_user_id":"role_code_orchestrator","from_user_name":"Оркестратор","text":"ПЕРВЫЙ ОТВЕТ ОРКЕСТРАТОРА","created_at":"2026-10-10T18:00:03Z","is_session_marker":false}"#.utf8))
                        insertIncoming(done)
                    }.accessibilityIdentifier("chat.preview.finish-first")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        liveTurns["role_researcher"] = Self.readingPreviewTurn(long: true)
                    } label: { Image(systemName: "arrow.down.to.line") }
                    .accessibilityLabel("Длинный ответ")
                    Button {
                        let message = Self.readingPreviewMessages.last!
                        messages.append(message)
                        liveTurns = [:]
                    } label: { Image(systemName: "checkmark") }
                    .accessibilityLabel("Завершить ответ")
                }
            }
            #endif

            // Шапка — ещё и вход в состав: владелец 21.09.2026 — «нет
            // возможности понять, кто в этом чате присутствует». Тап открывает
            // название и участников.
            ToolbarItem(placement: .principal) {
                Button { isDetailsPresented = true } label: {
                    HStack(spacing: TFSpacing.sm) {
                        if chat.kind == "group" {
                            TFGroupAvatar(identity: chat.projectID ?? chat.id, size: .md)
                        }
                        VStack(spacing: 1) {
                        Text(chat.displayTitle(excluding: session.currentUser?.id))
                            // Кегль из шкалы (было системное `.headline`):
                            // ступень `.title` даёт те же 17 semibold.
                            .tfText(.title)
                            .lineLimit(1)
                        Text("\(chat.members.count) \(participantsWord(chat.members.count))")
                            .tfText(.caption)
                            .foregroundStyle(Color.tfSub)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Чат: название и участники")
            }
            if isSelecting {
                ToolbarItem(placement: .topBarLeading) {
                    Button { exitSelection() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Отменить выбор")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        isDeleteSelectedConfirmOpen = true
                    } label: {
                        Text(selectedMessageIDs.isEmpty
                             ? "Удалить"
                             : "Удалить (\(selectedMessageIDs.count))")
                    }
                    .disabled(selectedMessageIDs.isEmpty)
                }
            } else {
                if session.currentUser?.role == .owner, chat.kind == "direct",
                   chat.members.contains(where: { $0.id == "u-secretary" }), let voiceSession {
                    ToolbarItem(placement: .topBarTrailing) {
                        TFIconButton("waveform", label: "Голосовой разговор с Помощником владельца") {
                            Task { await voiceSession.start(chatID: chat.id) }
                        }
                        .accessibilityIdentifier("chat.voice.start")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isContentsPresented = true } label: {
                        Image(systemName: "list.bullet.indent")
                    }
                    .accessibilityLabel("Содержание чата")
                    .accessibilityIdentifier("chat.contents")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        // Меню «…» построено как соседние меню приложения
                        // (`ChatScreen`, `TodaySectionView`, `VoiceModelsScreen`):
                        // действия — `Label`, связанные группы — `Section`,
                        // выбор из списка — ПОДМЕНЮ `Menu`, выбранное отмечено
                        // галочкой (владелец 21.09.2026: «посмотри, как у нас
                        // троеточия и подменю, и сделай ровно так же»).
                        Section {
                            // Привязка к задаче — только создателю: сервер
                            // остальным отвечает 403.
                            if chat.createdBy == session.currentUser?.id {
                                Menu {
                                    if taskStore.tasks.isEmpty {
                                        Text("Нет задач")
                                    } else {
                                        ForEach(taskStore.tasks) { task in
                                            Button {
                                                Task { await bindTask(task.id) }
                                            } label: {
                                                if task.id == chat.taskID {
                                                    Label(task.title, systemImage: "checkmark")
                                                } else {
                                                    Text(task.title)
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    Label(chat.taskID == nil ? "Привязать к задаче" : "Сменить задачу",
                                          systemImage: "checklist")
                                }
                                if chat.taskID != nil {
                                    Button { Task { await bindTask(nil) } } label: {
                                        Label("Отвязать от задачи", systemImage: "xmark.circle")
                                    }
                                }
                            }
                        }
                        Section {
                            Button { enterSelection(selecting: nil) } label: {
                                Label("Выбрать сообщения", systemImage: "checkmark.circle")
                            }
                            // Владелец 25.09.2026: «очистить чат не надо —
                            // надо по сессиям потом полистать». История не
                            // трогается, сбрасывается только память роли.
                            // 06.11.2026: и в чате с Помощником — из панели
                            // «Сессия» кнопку убрали 05.11, и новую сессию
                            // начать стало негде.
                            Button { Task { await newSession() } } label: {
                                Label("Новая сессия", systemImage: "arrow.triangle.2.circlepath")
                            }
                            compactMenuItem
                            ShareLink(item: RoleChatTranscript(title: chat.displayTitle(excluding: session.currentUser?.id),
                                                               messages: visibleMessages),
                                      preview: SharePreview("Чат")) {
                                Label("Экспорт", systemImage: "square.and.arrow.up")
                            }
                        }
                        if session.currentUser?.role == .owner {
                            Section {
                                Button(role: .destructive) {
                                    isClearChatConfirmOpen = true
                                } label: {
                                    Label("Удалить все сообщения", systemImage: "trash")
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("Ещё")
                }
            }
        }
    }

    private var composerSession: some View {
        composerNavigation
        .task { await connectRealtime() }
        .task { await followLocalStore() }
        .onDisappear { realtimeObserver.clear(remove: realtime.removeObserver) }
        .onChange(of: realtime.connectionRevision) {
            guard realtimeObserver.isActive else { return }
            // За время разрыва сигнал «закончил» мог потеряться.
            typists = [:]
            typistTools = [:]
            Task {
                await refresh()
                await loadLiveTurns()
            }
        }
        .task {
            if !readingPreview { await refresh() }
        }
        .alert("Ошибка чата", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Повторить") { Task { await refresh() } }
            Button("Закрыть", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .alert(noticeMessage ?? "", isPresented: Binding(
            get: { noticeMessage != nil },
            set: { if !$0 { noticeMessage = nil } }
        )) { Button("Готово", role: .cancel) { noticeMessage = nil } }
        .tfSheet(isPresented: Binding(
            get: { editedQuickActionIndex != nil },
            set: { if !$0 { editedQuickActionIndex = nil } }
        )) {
            quickActionEditorSheet
        }
        .tfSheet(isPresented: $isDetailsPresented) {
            RoleChatDetailsSheet(chat: chat, onChanged: { updated in
                chat = updated
                Task { await refresh() }
            }, onDeleted: { dismiss() })
        }
        // `alert`, не `confirmationDialog`: иначе на части экранов вылезает
        // пузырь с хвостиком-указателем у кнопки (владелец 03.11.2026).
        .alert("Удалить выбранные сообщения?", isPresented: $isDeleteSelectedConfirmOpen) {
            Button("Удалить (\(selectedMessageIDs.count))", role: .destructive) {
                Task { await deleteSelected() }
            }
            Button("Отмена", role: .cancel) {}
        }
        .alert("Удалить все сообщения чата?", isPresented: $isClearChatConfirmOpen) {
            Button("Удалить все", role: .destructive) { Task { await clearChat() } }
            Button("Отмена", role: .cancel) {}
        }
    }

    private var composerRoom: some View {
        composerSession
        .fileImporter(isPresented: $isFileImporterPresented, allowedContentTypes: [.item]) { result in
            handleFileImport(result)
        }
        .photosPicker(isPresented: $isPhotoPickerPresented, selection: $photoPickerItem, matching: .images)
        .onChange(of: photoPickerItem) { _, item in
            guard let item else { return }
            photoPickerItem = nil
            Task { await uploadPickedPhoto(item) }
        }
        .fullScreenCover(isPresented: $isCameraPresented) {
            CameraCaptureView(
                onCapture: { image in
                    isCameraPresented = false
                    Task { await uploadCameraPhoto(image) }
                },
                onCancel: { isCameraPresented = false }
            )
            .ignoresSafeArea()
        }
        .onChange(of: voice.errorMessage) { _, reason in
            if let reason { errorMessage = reason }
        }
        .onChange(of: workMode) { _, mode in
            UserDefaults.standard.set(mode.rawValue, forKey: "roleChat.mode." + chat.createdBy + "." + chat.id)
        }
        .onChange(of: chat.members.map(\.id)) { _, _ in
            if chat.hasOwnSettings {
                workMode = ChatSessionWorkModePolicy.visibleSelection(workMode)
            } else if !RoleChatWorkMode.available(in: chat).contains(workMode) { workMode = .work }
        }
        .task(id: chat.members.map(\.id)) {
            await modelChoice.load(chat: chat)
            await workspaceChoice.load(chat: chat)
            await loadRoleSummaries()
        }
        .task(id: chat.members.map(\.id).joined(separator: ":") + ":" + (messages.last?.id ?? "")) {
            await composerControls.load(chat: chat)
        }
        .tfSheet(isPresented: $showsComposerCommands) {
            ChatCommandPicker(commands: composerControls.commands, errorText: composerControls.errorText,
                              onRefresh: { Task { await composerControls.load(chat: chat) } }) { command in
                draft = command.inserting(into: draft)
                composerFocused = true
            }
        }
        .onDisappear { voice.cancel(); player.stop() }
        .taskCardSheet(taskID: $pendingTaskID)
    }

    /// Лента следует за локальной базой (05.11.2026). Всё, что туда легло —
    /// догрузка при открытии, фоновая синхронизация по сокету, пока чат был
    /// закрыт, — встаёт в ленту тем же путём, что сообщение из сокета
    /// (`insertIncoming`): живой ход автора закрывается, лента не прыгает.
    /// Удалённое владельцем стирается из базы там же, где из ленты.
    private func followLocalStore() async {
        if readingPreview { return }
        do {
            for try await stored in LocalStore.shared.messageUpdates(chatID: chat.id) {
                let onScreen = Set(messages.map(\.id))
                for message in stored where !onScreen.contains(message.id) {
                    insertIncoming(message)
                }
            }
        } catch {
            // Подписка оборвалась (база недоступна) — лента остаётся на
            // догрузке с сервера, как раньше.
        }
    }

    private func connectRealtime() async {
        if readingPreview { return }
        // Живые события (22.09.2026): новое сообщение этого чата — сразу
        // перечитываем ленту; «печатает» — ровно по сигналу сервера.
        let chatID = chat.id
        let apply: (RealtimeEvent) -> Void = { event in
            switch event {
            case .unknown("chat:withdrawn", .object(let payload)) where payload["chat_id"]?.stringValue == chatID:
                if let id = payload["message_id"]?.stringValue {
                    messages.removeAll { $0.id == id }
                    selectedMessageIDs.remove(id)
                }
            case .unknown("chat:work_plan", let payload):
                workPlanEvent = payload
            case .roleChatMessage(let id, let message) where id == chatID:
                roomEventRevision += 1
                workPlanRevision += 1
                // Сервер прислал готовое сообщение — вставляем его сразу,
                // без перечитывания ленты (01.10.2026: пузырь ответа
                // появлялся с задержкой и лента вздрагивала).
                if let message { insertIncoming(message) } else { Task { await refresh() } }
            case .roleChatTyping(let id, let userID, let name, let active, let tool) where id == chatID:
                roomEventRevision += 1
                if active {
                    typists[userID] = name.isEmpty ? "Участник" : name
                    typistTools[userID] = tool
                } else {
                    typists[userID] = nil
                    typistTools[userID] = nil
                }
            case .roleChatLive(let id, let userID, let turn, let messageID) where id == chatID:
                // Роль уже идёт дельтами — полный снимок того же хода лишний.
                guard !deltaUsers.contains(userID) else { return }
                roomEventRevision += 1
                if let turn {
                    showLiveTurn(turn, userID: userID)
                } else {
                    endLiveTurn(userID: userID, messageID: messageID)
                }
            case .roleChatLiveDelta(let delta) where delta.chatID == chatID:
                roomEventRevision += 1
                applyLiveDelta(delta)
            case .roleChatLiveInterrupt(let event) where event.chatID == chatID:
                // Ход ждёт ответа владельца: в живом ходе — «Ждёт вашего
                // ответа», кнопки — карточка вопроса из его сообщения.
                guard var state = liveDeltas[event.userID], state.apply(event) else { return }
                roomEventRevision += 1
                liveDeltas[event.userID] = state
                showLiveTurn(state.liveTurn, userID: event.userID)
            default:
                break
            }
        }
        // События, пришедшие почти разом (ход роли, «печатает», готовое
        // сообщение), применяются одним обновлением: лента перекладывается
        // один раз, а не на каждое событие (владелец 27.10.2026).
        guard !Task.isCancelled else { return }
        realtimeObserver.replace(add: {
            realtime.addObserver { event in
                guard eventBatch.enqueue(event) else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: ChatEventCoalescer<RealtimeEvent>.window)
                    eventBatch.drain().forEach(apply)
                }
            }
        }, remove: realtime.removeObserver)
        // Чат открыт посреди ответа роли — подтягиваем, что уже сделано.
        await loadLiveTurns()
    }

    private func showLiveTurn(_ turn: RoleChatLiveTurn, userID: String) {
        // Журнал: у роли появляется ход с другим номером, пока прежний ещё
        // в ленте, — так выглядит вторая строка «Работает» (скрин 9486).
        if let previous = liveTurns[userID], previous.playbackID != turn.playbackID {
            ClientLog.shared.add("chat=\(chat.id) turn:new-playback user=\(userID) old=\(previous.playbackID) new=\(turn.playbackID) ended=\(endedTurnIDs.contains(turn.playbackID)) completing=\(completingTurns.count) slots=\(liveStore.slots.count)")
        }
        guard !endedTurnIDs.contains(turn.playbackID) else { return }
        if let trigger = turn.triggerMessageID, hasAnswer(on: trigger, from: userID) { return }
        if let previous = liveTurns[userID], previous.playbackID != turn.playbackID {
            // Тот же ход, а время начала снимок прислал другое (`started_at`
            // приходит и пустым, и с другой точностью). Это не новый ход:
            // объект не подменяем — иначе строку снесёт и текст поедет
            // заново (ревью ленты п.1.7).
            if let trigger = previous.triggerMessageID, trigger == turn.triggerMessageID {
                liveTurns[userID] = mergeLiveTurn(turn, over: previous)
                return
            }
            // Новый ход роли не стирает прежний: тот остаётся в ленте на своём
            // месте, пока его ответ не встанет вместо него (владелец 30.10.2026).
            parkLiveTurnIfUnanswered(previous, userID: userID)
        }
        liveTurns[userID] = turn
    }

    /// Слить пришедший ход с уже показанным: строка ленты остаётся той же
    /// (время начала и id — прежние), состав пунктов не укорачивается.
    private func mergeLiveTurn(_ incoming: RoleChatLiveTurn,
                               over previous: RoleChatLiveTurn) -> RoleChatLiveTurn {
        let shown = previous.items.compactMap(\.actionID)
        let next = incoming.items.compactMap(\.actionID)
        let items = RoleLiveTurnGrowth.accepts(shown: shown, incoming: next)
            ? incoming.items : previous.items
        return RoleChatLiveTurn(chatID: incoming.chatID, userID: incoming.userID, name: incoming.name,
                                startedAt: previous.startedAt, items: items,
                                thinking: incoming.thinking,
                                triggerMessageID: incoming.triggerMessageID ?? previous.triggerMessageID)
    }

    /// Ход, который сменился новым: доигрывает своё на прежнем месте.
    ///
    /// Он уже не может расти (сервер его остановил), поэтому фиксируем
    /// законченный вид и убираем из «идущих»: снимок того же хода больше не
    /// вернёт его как новый.
    private func parkLiveTurn(_ turn: RoleChatLiveTurn) {
        guard !turn.items.isEmpty || turn.thinking != nil else { return }
        guard completingTurns[turn.playbackID] == nil else { return }
        completingTurns[turn.playbackID] = turn.ending()
        endedTurnIDs.insert(turn.playbackID)
        // Ход сменился, не доведя ответ до сохранённого сообщения: его
        // закрыла остановка, а не конец работы.
        stoppedTurnIDs.insert(turn.playbackID)
    }

    /// Ход сменился, но ответ на его вопрос ещё не пришёл. Если ответ уже в
    /// ленте, ход не нужен: сообщение и есть его место.
    private func parkLiveTurnIfUnanswered(_ turn: RoleChatLiveTurn, userID: String) {
        if let trigger = turn.triggerMessageID, hasAnswer(on: trigger, from: userID) { return }
        parkLiveTurn(turn)
    }

    private func endLiveTurn(userID: String, messageID: String?) {
        if let messageID, let message = messages.first(where: { $0.id == messageID }) {
            // REST may have loaded the final message before chat:new.
            // Use the same completion path as the socket delivery.
            insertIncoming(message)
            return
        }
        typists[userID] = nil
        typistTools[userID] = nil
        markLiveTurnEnded(userID)
        // Ответа в ленте ещё нет (ход без ответа, потерянный
        // chat:new или старый сервер): сначала дочитываем
        // ленту и только потом убираем живой пузырь — без
        // мгновения пустоты между ними.
        let finishedStart: String? = liveTurns[userID]?.startedAt
        Task { await finishLiveTurn(userID: userID, messageID: messageID, startedAt: finishedStart) }
    }

    /// Ход дельтами: start заводит состояние, patch дописывает, end
    /// заканчивает ход тем же путём, что и старый снимок. Пропуск номера или
    /// незнакомый ход — перечитываем снимок.
    private func applyLiveDelta(_ delta: RoleChatLiveDelta) {
        let userID = delta.userID
        if case .start = delta { ClientLog.shared.add("chat=\(chat.id) live:start user=\(userID)") }
        // Запись того же значения в состояние экрана тоже будит его — на
        // каждую порцию ответа; вставляем только новую роль.
        if !deltaUsers.contains(userID) { deltaUsers.insert(userID) }
        if case .start(let state) = delta {
            liveDeltas[userID] = state
            showLiveTurn(state.liveTurn, userID: userID)
            return
        }
        guard var state = liveDeltas[userID] else {
            Task { await loadLiveTurns() }
            return
        }
        switch state.apply(delta) {
        case .applied:
            liveDeltas[userID] = state
            showLiveTurn(state.liveTurn, userID: userID)
        case .ended(let messageID):
            ClientLog.shared.add("chat=\(chat.id) live:end user=\(userID) message=\(messageID ?? "-")")
            liveDeltas[userID] = nil
            endLiveTurn(userID: userID, messageID: messageID)
        case .needsSnapshot:
            Task { await loadLiveTurns() }
        case .ignored:
            break
        }
    }

    private func finishLiveTurn(userID: String, messageID: String?, startedAt: String?) async {
        await refresh()
        let currentStart: String? = liveTurns[userID]?.startedAt
        guard currentStart == startedAt else { return }
        if let messageID, let message = messages.first(where: { $0.id == messageID }) {
            insertIncoming(message)
        } else {
            liveTurns[userID] = nil
        }
    }

    /// Лента чата на нативной коллекции.
    ///
    /// Владелец 10.11.2026: «давай все же сделаем уже по полной… поведение ленты
    /// прям нравится, ноль тупняка, в отличие от моего чата». Раньше лента была
    /// `ScrollView` с обычным `VStack`: все строки окна монтировались сразу,
    /// вместе со всеми сегментами ответов (22–27 тыс. pt на окно), а высоту
    /// подсказывал сам SwiftUI. Теперь строки живут только в видимой части,
    /// высота каждой измерена по содержимому, а ячейки переиспользуются —
    /// `ChatFeedVirtualList` (`Sources/Chat/Feed/ChatFeedVirtualList.swift`).
    /// Правила прокрутки — `ChatFeedScrollPolicy`, проверяются тестом на хосте.
    private var messageScroll: some View {
        let orderedFeed = feedItems
        let dayDividers = dayDividerTitles(orderedFeed)
        // Выдержки «в ответ на» — один проход по ленте на кадр. Раньше каждая
        // строка искала свой вопрос по всей истории (`first(where:)`), то есть
        // квадратичный поиск на каждое обновление живым ходом (разбор
        // 25-26.10.2026, `docs/2026-10-25-chat-window-behaviour.md`).
        let replyExcerpts = Self.replyExcerpts(from: messages)
        let feedByID = Dictionary(orderedFeed.map { ($0.id, $0) },
                                  uniquingKeysWith: { first, _ in first })
        // Идентификатор строки голосового — строкой: у `VoiceMessage` он UUID.
        let voicesByID = Dictionary(pendingVoices.map { (Self.voiceRowID($0), $0) },
                                    uniquingKeysWith: { first, _ in first })
        let typing = !visibleTypists.isEmpty
        // Строка ленты — идентификатор и версия содержимого: пересобираются
        // только строки, у которых версия сменилась.
        var rows: [ChatFeedVirtualRow] = []
        if messages.isEmpty || (orderedFeed.isEmpty && pendingVoices.isEmpty) {
            rows.append(ChatFeedVirtualRow(id: Self.emptyRowID, version: roomEventRevision))
        }
        rows += orderedFeed.map { item in
            ChatFeedVirtualRow(id: item.id, version: rowVersion(item))
        }
        rows += pendingVoices.map { item in
            ChatFeedVirtualRow(id: Self.voiceRowID(item), version: rowVersion(pendingVoice: item))
        }
        if typing {
            rows.append(ChatFeedVirtualRow(id: Self.typingRowID,
                                           version: roomEventRevision &+ visibleTypists.count))
        }
        return ChatFeedVirtualList(rows: rows,
                                   contentKey: chat.id,
                                   handle: feedScroll,
                                   estimatedHeight: { id in
                                       Self.estimatedRowHeight(id: id, feedByID: feedByID,
                                                               voicesByID: voicesByID)
                                   },
                                   onNearBottomChange: { chatIsNearBottom = $0 },
                                   onScrollingChange: { chatIsScrolling = $0 },
                                   onNearTop: { growFeedWindow() },
                                   row: { id in
                                       feedRow(id: id, feedByID: feedByID, voicesByID: voicesByID,
                                               dayDividers: dayDividers,
                                               replyExcerpts: replyExcerpts)
                                   })
            .tfScreenBackground()
            .accessibilityIdentifier("chat.feed")
            .overlay(alignment: .top) {
                if let compactingRoleName {
                    HStack(spacing: TFSpacing.sm) {
                        TFLoading(.inline)
                        Text("Сжимаю сессию «\(compactingRoleName)»…")
                            .tfText(.meta)
                            .foregroundStyle(Color.tfChatText)
                    }
                    .padding(.horizontal, TFSpacing.md)
                    .padding(.vertical, TFSpacing.sm)
                    .background(Color.tfTile, in: Capsule())
                    .padding(.top, TFSpacing.sm)
                }
            }
            .onChange(of: contentsTargetID) { _, id in
                guard let id else { return }
                // Переход по оглавлению к старому сообщению: окно раскрываем до
                // него — иначе строки в ленте ещё нет и прокручивать некуда.
                if let index = visibleMessages.firstIndex(where: { $0.id == id }) {
                    feedWindow = max(feedWindow, visibleMessages.count - index)
                }
                let feedID = feedItems.first { $0.message?.id == id }?.id ?? id
                Task { @MainActor in
                    // Окно дорисовывается в этом же проходе; одну короткую
                    // паузу даём, чтобы строка успела стать ячейкой.
                    try? await Task.sleep(for: .milliseconds(60))
                    feedScroll.scroll(to: feedID, anchor: .top, animated: false)
                }
                contentsTargetID = nil
            }
    }

    /// Оценка высоты строки до измерения: ~38 знаков в строке, строка ~21 pt.
    /// Без неё UIKit держит смещение по грубой оценке и поправляет его на ходу
    /// — прокрутка выглядит «липкой» (владелец 10.11.2026).
    private static func estimatedRowHeight(id: String, feedByID: [String: FeedItem],
                                   voicesByID: [String: VoiceMessage]) -> CGFloat {
        if id == typingRowID { return 40 }
        if voicesByID[id] != nil { return 90 }
        guard let item = feedByID[id] else { return 240 }
        if item.liveSlot != nil { return 320 }
        let text = item.message?.text ?? ""
        guard !text.isEmpty else { return 120 }
        let lines = CGFloat(text.count) / 38
        return min(6000, 120 + lines * 21)
    }

    /// Идентификаторы служебных строк ленты (не сообщения сервера).
    private static let typingRowID = "typing-line"
    private static let emptyRowID = "feed-empty"

    /// Версия строки истории: событие по этому сообщению (сокет, отправка,
    /// остановка) и режим выбора. Всё остальное строку не пересобирает.
    private func rowVersion(_ item: FeedItem) -> Int {
        var version = roomEventRevision
        if let message = item.message {
            version = messageEventRevisions[message.id] ?? 0
        }
        version = version &* 4
        if isSelecting { version += 1 }
        return version
    }

    private static func voiceRowID(_ message: VoiceMessage) -> String {
        "voice-" + message.id.uuidString
    }

    private func rowVersion(pendingVoice message: VoiceMessage) -> Int {
        var version = roomEventRevision &* 4
        if sendingVoiceIDs.contains(message.id) { version += 2 }
        if message.transcript == .pending { version += 1 }
        return version
    }

    /// Одна строка ленты по её идентификатору.
    @ViewBuilder
    private func feedRow(id: String, feedByID: [String: FeedItem],
                         voicesByID: [String: VoiceMessage],
                         dayDividers: [String: String],
                         replyExcerpts: [String: String]) -> some View {
        if id == Self.emptyRowID {
            emptyFeedRow
        } else if id == Self.typingRowID {
            typingFeedRow
        } else if let voice = voicesByID[id] {
            pendingVoiceRow(voice)
        } else if let item = feedByID[id] {
            VStack(alignment: .leading, spacing: TFSpacing.md) {
                if let title = dayDividers[item.id] {
                    ChatFeedDivider(title: title)
                }
                if let slot = item.liveSlot {
                    // Текст хода читает строка хода, а не экран: порция ответа
                    // перерисовывает только её. Доигрывающий ход — в ТОЙ ЖЕ
                    // ветке, иначе очередь печати терялась и ответ выпадал
                    // целиком (владелец 06.11.2026).
                    RoleChatLiveSlotView(store: liveStore, slot: slot,
                                         completing: item.completingTurn) { turn in
                        liveTurnRow(turn, replyExcerpts: replyExcerpts)
                    }
                } else if let pending = item.pending {
                    outgoingRow(pendingMessage(pending), pending: pending,
                                replyExcerpts: replyExcerpts)
                } else if let message = item.message {
                    if isOutgoingRow(item) {
                        outgoingRow(message, pending: nil, replyExcerpts: replyExcerpts)
                    } else {
                        messageRow(message, replyExcerpts: replyExcerpts)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var emptyFeedRow: some View {
        if hasLoadedMessages {
            // Личный чат с ролью: вместо пустого состояния — приветствие роли и
            // быстрые команды (владелец 29.10.2026, макет
            // `mockups/role-chat-start/`).
            if let starterMember {
                RoleChatStartView(member: starterMember,
                                  starter: starterWithOverrides(for: starterMember),
                                  roleSummary: roleSummary(for: starterMember),
                                  onCommand: { prompt in
                    draft = prompt
                    composerFocused = true
                },
                                  onEditCommand: { index in
                    editedQuickActionIndex = index
                },
                                  isEditingCommands: isEditingQuickActions,
                                  onToggleEditing: {
                    isEditingQuickActions.toggle()
                })
                .hintAnchor(HintAnchorID.chatRoleStart)
            } else {
                TFEmptyState(
                    icon: "bubble.left",
                    text: "Пока нет сообщений",
                    description: "Напишите первое сообщение."
                )
            }
        } else {
            TFLoading(.block)
                .accessibilityLabel("Загрузка сообщений")
        }
    }

    @ViewBuilder
    private var typingFeedRow: some View {
        if chat.kind != "group", let onlyUserID = visibleTypists.keys.first,
           let tool = typingTool(onlyUserID) {
            RoleStepLine(name: visibleTypists[onlyUserID] ?? "Роль", tool: tool)
        } else {
            RoleChatTypingLine(names: visibleTypists.values.sorted())
        }
    }

    /// Ещё не отправленное голосовое: имя и иконка берутся из текущей сессии —
    /// сообщения с сервера для него пока нет.
    @ViewBuilder
    private func pendingVoiceRow(_ message: VoiceMessage) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            VoiceMessageBubble(
                message: message,
                player: player,
                style: RoleChatVoiceStyle.own,
                header: AnyView(ownSenderLine)
            )
            if sendingVoiceIDs.contains(message.id) {
                TFLoading(.inline)
            } else if message.transcript != .pending {
                Button("Повторить отправку") { Task { await sendVoice(message.id) } }
                    .tfText(.meta)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    /// Дорисовать старые сообщения. Решение — `RoleChatFeedWindow` (08.11.2026):
    /// только под рукой владельца и только когда над окном есть скрытые.
    private func growFeedWindow() {
        let hidden = visibleMessages.count - feedWindow
        guard RoleChatFeedWindow.shouldGrow(hidden: hidden, nearTop: true,
                                            scrolling: chatIsScrolling) else { return }
        // Старые строки появляются НАД видимой частью: коллекция сама
        // компенсирует смещение, лента не прыгает.
        feedWindow = RoleChatFeedWindow.grown(window: feedWindow)
    }

    /// Живой ход виден и в группе: у каждого ответа своя подпись роли.
    /// Идущие ходы — только паспорта (текст читает строка хода), доигрывающие
    /// — целиком: они меняются редко. Один ход — одна строка: доигрывающий
    /// вытесняет идущий с тем же `playbackID`.
    private var visibleLiveRows: [(slot: RoleChatLiveSlot, completing: RoleChatLiveTurn?)] {
        let completing = Dictionary(completingTurns.values.map { ($0.playbackID, $0) },
                                    uniquingKeysWith: { _, last in last })
        let live = liveStore.slots.filter { completing[$0.playbackID] == nil }
        let slots = RoleChatLiveSlots.visibleSorted(live + completing.values.map(RoleChatLiveStore.slot(for:)))
        return slots.map { (slot: $0, completing: completing[$0.playbackID]) }
    }

    private var visibleMessages: [RoleChatMessage] {
        messages.filter { message in
            // Карточка обращения после ответа остаётся в ленте с ответом
            // (владелец 28.10.2026; правило 21.10 «исчезает» отменено).
            // Прячем только то сообщение, которое закрыло живой ход: пока
            // ход доигрывает ответ, его текст уже в живом пузыре. Раньше
            // скрывалось ЛЮБОЕ сообщение того же автора, попавшее в окно
            // времени хода, — из-за этого из ленты пропадали ответы.
            // Пустой доигрывающий ход не монтируется — тогда сообщение
            // не прячем (иначе ответ виден только после перезахода).
            return !completingTurns.keys.contains { playbackID in
                guard let turn = completingTurns[playbackID],
                      RoleChatLiveCompletion.shouldHoldSavedMessage(for: turn) else { return false }
                if let completed = completedMessageIDByTurn[playbackID] { return completed == message.id }
                // Ход восстановлен после перезапуска приложения: какое
                // сообщение его закрыло — неизвестно, берём прежнее правило.
                return turn.isCompleted(by: message)
            }
        }
    }

    private struct FeedItem: Identifiable {
        let id: String
        let dateString: String?
        let position: Int
        let message: RoleChatMessage?
        /// Идущий ход: только паспорт, текст читает строка хода.
        var liveSlot: RoleChatLiveSlot? = nil
        /// Доигрывающий ход — целиком.
        var completingTurn: RoleChatLiveTurn? = nil
        var pending: PendingOutgoing? = nil
        let date: Date
    }
    private var feedItems: [FeedItem] {
        // Видимые сообщения и ходы — один раз на сборку ленты: раньше каждое
        // свойство считалось дважды, и вся история проходилась лишний раз
        // на каждую пачку событий живого хода (06.11.2026).
        let visibleMessages = Array(self.visibleMessages.suffix(feedWindow))
        let liveRows = self.visibleLiveRows
        let history = visibleMessages.enumerated().map { index, message in
            return FeedItem(id: feedItemID(for: message),
                dateString: message.createdAt, position: index, message: message,
                date: RoleChatTime.date(message.createdAt) ?? .distantPast)
        }
        let live = liveRows.enumerated().map { index, row in
            FeedItem(id: RoleChatRowID.turn(row.slot.playbackID), dateString: row.slot.startedAt,
                position: messages.count + index, message: nil,
                liveSlot: row.slot, completingTurn: row.completing,
                date: row.slot.startDate ?? .distantFuture)
        }
        // История уже упорядочена серверной последовательностью. Не сортируем
        // её повторно по часам: точность даты и порядок доставки различаются.
        let plan = ChatTimelineProjection.project(
            messages: visibleMessages.map { .init(id: $0.id, anchorMessageID: feedAnchor(for: $0)) },
            turns: liveRows.map {
                .init(playbackID: $0.slot.playbackID, anchorMessageID: $0.slot.triggerMessageID)
            })
        // Keep the existing row IDs when a live reply becomes its saved message.
        var messagesByID: [String: FeedItem] = [:]
        for item in history {
            if let id = item.message?.id { messagesByID[id] = item }
        }
        var turnsByID: [String: FeedItem] = [:]
        for item in live {
            if let id = item.liveSlot?.playbackID { turnsByID[id] = item }
        }
        let timeline: [FeedItem] = plan.compactMap { item in
            switch item.kind {
            case .message: return item.messageID.flatMap { messagesByID[$0] }
            case .liveTurn: return item.turnPlaybackID.flatMap { turnsByID[$0] }
            case .pending: return nil
            }
        }
        // Сообщения «в пути» — в той же ленте, в конце. После ответа сервера
        // их строку занимает отправленное сообщение (`rowIDByMessageID`):
        // тот же ForEach, тот же id и тот же вид — строка не пересоздаётся.
        let outgoing = pendingOutgoing.enumerated().map { index, pending in
            FeedItem(id: pending.id, dateString: nil, position: messages.count + live.count + index,
                     message: nil, pending: pending, date: .distantFuture)
        }
        return timeline + outgoing
    }

    /// Строка своего сообщения, которое было пузырём «в пути».
    private func isOutgoingRow(_ item: FeedItem) -> Bool {
        item.pending != nil || item.id.hasPrefix("local-")
    }

    /// Keep the same row identity while a live reply becomes its saved message.
    /// Replacing `playbackID` with the server message ID made LazyVStack tear
    /// down one variable-height row and insert another at the same position,
    /// which could reset the reader's scroll anchor during completion.
    ///
    /// Своя строка у каждого сообщения. Строки не строятся из пары
    /// «автор + на что ответ»: она не уникальна (ответ роли и служебные
    /// строки координации отвечают на одно сообщение), и одинаковые id в
    /// ForEach заставляли SwiftUI переиспользовать строки — текст пропадал, а
    /// лента прыгала (владелец 22.10.2026).
    private func feedItemID(for message: RoleChatMessage) -> String {
        rowIDByMessageID[message.id] ?? RoleChatRowID.message(message.id)
    }

    /// Ответ роли, закрытый остановкой (прерван владельцем или оборвался
    /// ошибкой), стоит сразу после своего вопроса — там, где стоял его живой
    /// ход. Сервер дописывает такой ответ уже после нового сообщения владельца,
    /// и без этого правила в ленте два вопроса подряд, а работа роли ниже
    /// второго (владелец 30.10.2026).
    private func feedAnchor(for message: RoleChatMessage) -> String? {
        guard message.stopReason != nil, let question = message.replyToMessageID else { return nil }
        return question
    }


    /// Перед какими элементами ленты стоит полоса с датой: первый с датой и
    /// каждый, где день сменился. Элемент без разбираемой даты (живой ход
    /// без `startedAt`) дня не начинает и не прерывает — иначе после своего
    /// сообщения появлялась лишняя «Сегодня» (владелец 14.10.2026).
    private func dayDividerTitles(_ feed: [FeedItem]) -> [String: String] {
        var result: [String: String] = [:]
        var previousDay: String?
        for item in feed {
            guard let day = ChatDayLabel.dayKey(raw: item.dateString), day != previousDay else { continue }
            previousDay = day
            result[item.id] = ChatDayLabel.dividerTitle(raw: item.dateString)
        }
        return result
    }

    /// Вставить сообщение из сокета: новое — в конец, известное — заменить.
    /// Живой пузырь автора уходит тем же кадром, что появляется готовый, —
    /// лента не прыгает. Свой пузырь «в пути» с тем же текстом тоже уходит:
    /// сервер его принял.
    private func insertIncoming(_ message: RoleChatMessage) {
        roomEventRevision += 1
        messageEventRevisions[message.id] = roomEventRevision
        // Ответ уже был в ленте до прихода готового сообщения (перечитывание
        // успело раньше сокета). Владелец его уже видел: доигрывать тот же
        // текст в пузыре не нужно — иначе ответ виден трижды и висит пауза
        // до конца доигрывания (владелец 07.11.2026).
        let alreadyShown = messages.contains { $0.id == message.id }
        let mine = message.fromUserID == session.currentUser?.id
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if let index = messages.firstIndex(where: { $0.id == message.id }) {
                messages[index] = message
            } else {
                // Вставка по серверному порядку: раньше тут сортировалась вся
                // лента, и на каждом снимке живого ответа даты разбирались
                // заново — это и было главным тормозом ленты.
                messages = RoleChatMessageOrder.inserting(message, into: messages)
            }
            if let author = message.fromUserID, !mine {
                if let turn = liveTurns[author], turn.isCompleted(by: message) {
                    completeLiveTurn(turn, with: message, alreadyShown: alreadyShown)
                    liveTurns[author] = nil
                    restoredTurnIDs.remove(turn.playbackID)
                    typists[author] = nil
                    typistTools[author] = nil
                    liveDeltas[author] = nil
                } else if let parked = parkedTurn(answering: message, author: author) {
                    // Ответ прерванного хода: ход уже доигрывает на своём
                    // месте, и сообщение занимает его строку, а не встаёт
                    // второй раз ниже (владелец 30.10.2026).
                    completeLiveTurn(parked, with: message, alreadyShown: alreadyShown)
                } else if message.replyToMessageID != nil {
                    typists[author] = nil
                    typistTools[author] = nil
                    liveDeltas[author] = nil
                }
            }
            if mine, let index = pendingOutgoing.firstIndex(where: { !$0.failed && $0.text == message.text }) {
                // Сервер принял наше сообщение: готовое занимает строку
                // пузыря «в пути» — лента не дёргается на смене карточки.
                rowIDByMessageID[message.id] = pendingOutgoing[index].id
                pendingOutgoing.remove(at: index)
            }
        }
        if !mine && message.id != markedReadMessageID {
            let id = message.id
            Task {
                if (try? await api.markRoleChatRead(id: chat.id)) != nil { markedReadMessageID = id }
            }
        }
    }

    /// Готовый ответ сразу заменяет живой ход. История действий остаётся
    /// на сервере и в карточке задачи, но в завершённой строке чата не нужна.
    /// Переход не зависит от callback анимации: end может прийти раньше ответа.
    private func completeLiveTurn(_ turn: RoleChatLiveTurn, with message: RoleChatMessage,
                                  alreadyShown: Bool = false) {
        // Ответ уже в ленте: пузыря не будет, и строку сообщения ему не
        // отдаём — пусть остаётся своей (владелец 07.11.2026).
        if !alreadyShown { rowIDByMessageID[message.id] = RoleChatRowID.turn(turn.playbackID) }
        closedTurnMessageIDs.insert(message.id)
        completingTurns[turn.playbackID] = nil
        completedMessageIDByTurn[turn.playbackID] = nil
        endedTurnIDs.insert(turn.playbackID)
        stoppedTurnIDs.remove(turn.playbackID)
    }

    /// Ход, который сменился новым и ждёт свой сохранённый ответ: по нему
    /// сообщение ложится на место доигрывающего хода.
    private func parkedTurn(answering message: RoleChatMessage,
                            author: String) -> RoleChatLiveTurn? {
        completingTurns.values.first { turn in
            turn.userID == author
                && completedMessageIDByTurn[turn.playbackID] == nil
                && turn.isCompleted(by: message)
        }
    }

    /// Своё сообщение в пути: тот же пузырь, что у отправленного, но
    /// приглушён; не ушло — подпись и «Повторить».
    /// Своё сообщение: пока оно «в пути» и после доставки — один и тот же вид,
    /// меняется только прозрачность.
    private func outgoingRow(_ message: RoleChatMessage, pending: PendingOutgoing?,
                             replyExcerpts: [String: String]) -> some View {
        VStack(alignment: .trailing, spacing: TFSpacing.xs) {
            // Выбор и удаление для него не имеют смысла — на сервере его нет.
            messageBubbleRow(message, replyExcerpts: replyExcerpts)
                .allowsHitTesting(pending == nil)
                .opacity(pending.map { $0.failed ? 1 : 0.6 } ?? 1)
            if let pending, pending.failed {
                HStack(spacing: TFSpacing.sm) {
                    Label("Не отправлено", systemImage: "exclamationmark.circle")
                        .foregroundStyle(Color.tfRed)
                    Button("Повторить") { Task { await deliver(pending.id) } }
                    Button("Убрать", role: .destructive) {
                        pendingOutgoing.removeAll { $0.id == pending.id }
                    }
                }
                .tfText(.meta)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func pendingMessage(_ pending: PendingOutgoing) -> RoleChatMessage {
        RoleChatMessage(
            id: pending.id,
            chatID: chat.id,
            fromUserID: session.currentUser?.id,
            fromUserName: session.currentUser?.name,
            fromUserColor: nil,
            fromUserAvatarURL: nil,
            fromUserInitials: nil,
            kind: nil,
            replyToMessageID: nil,
            replyToSenderName: nil,
            text: pending.text,
            roleEnvelope: nil,
            createdAt: nil,
            attachments: pending.attachments,
            taskID: nil,
            taskTitle: nil,
            quickReplies: nil,
            isSessionMarker: false,
            steps: nil,
            reactions: nil
        )
    }

    private func stopTurns() async {
        guard !isStopping else { return }
        isStopping = true
        defer { isStopping = false }
        do { try await api.stopRoleChat(chatID: chat.id) }
        catch { errorMessage = error.localizedDescription }
    }

    /// «Печатает» — пока у роли нет ни текста, ни шагов; дальше вместо
    /// точек растёт её живой пузырь.
    /// Роль, приславшая дельты хода, берёт строку из них; `chats:typing` —
    /// только для старого сервера (27.10.2026).
    private var visibleTypists: [String: String] {
        let live = Set(visibleLiveRows.map(\.slot.userID))
        var result = typists.filter { !deltaUsers.contains($0.key) }
        for (userID, name) in liveStore.activityNames {
            result[userID] = name
        }
        return result.filter { !live.contains($0.key) }
    }

    private func typingTool(_ userID: String) -> String? {
        guard deltaUsers.contains(userID) else { return typistTools[userID] }
        return liveStore.activityTools[userID]
    }

    private func liveTurnRow(_ turn: RoleChatLiveTurn, replyExcerpts: [String: String]) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.xs) {
            replyContext(messageID: turn.triggerMessageID, sender: nil, excerpts: replyExcerpts)
            RoleLiveTurnBubble(turn: turn, showsName: chat.kind == "group", isComplete: endedTurnIDs.contains(turn.playbackID),
                               isStopped: stoppedTurnIDs.contains(turn.playbackID), pacesText: pacesLiveText,
                               // Законченный ход показывается сразу: если
                               // лента пересоберёт строку, пузырь не должен
                               // схлопнуться и заново проявиться — от этого
                               // низ ленты дёргался (владелец 30.10.2026).
                               startsWithSnapshot: restoredTurnIDs.contains(turn.playbackID)
                                   || endedTurnIDs.contains(turn.playbackID),
                               onPlaybackComplete: {
                                   ClientLog.shared.add("chat=\(chat.id) playback:done turn=\(turn.playbackID)")
                                   completingTurns[turn.playbackID] = nil
                                   endedTurnIDs.insert(turn.playbackID)
                                   stoppedTurnIDs.remove(turn.playbackID)
                               })
        }
    }

    /// Ответ роли уже есть в ленте: служебные строки координации («Ответ
    /// получен», «Ход завершился ошибкой») ответом НЕ считаются — иначе
    /// живой ход не показывался бы, хотя текст ответа ещё не пришёл.
    private func hasAnswer(on trigger: String, from userID: String) -> Bool {
        messages.contains { message in
            message.fromUserID == userID
                && message.replyToMessageID == trigger
                && message.kind != "system"
        }
    }

    private func markLiveTurnEnded(_ userID: String) {
        guard let turn = liveTurns[userID] else { return }
        endedTurnIDs.insert(turn.playbackID)
        liveTurns[userID] = turn.ending()
        typists[userID] = nil
        typistTools[userID] = nil
    }

    private func loadLiveTurns() async {
        let revision = roomEventRevision
        guard !liveSnapshotLoading else { return }
        liveSnapshotLoading = true
        defer { liveSnapshotLoading = false }
        guard let snapshot = try? await api.roleChatLiveSnapshot(id: chat.id) else { return }
        // Состояние дельт берём, даже если за время запроса пришли события:
        // дельты идут каждые 150 мс, и снимок иначе не прижился бы никогда.
        // Своё не трогаем, если оно того же хода и не старее снимка.
        for state in snapshot.states {
            if !deltaUsers.contains(state.userID) { deltaUsers.insert(state.userID) }
            if let current = liveDeltas[state.userID], current.turnID == state.turnID, current.seq >= state.seq { continue }
            liveDeltas[state.userID] = state
            let turn = state.liveTurn
            restoredTurnIDs.insert(turn.playbackID)
            showLiveTurn(turn, userID: state.userID)
        }
        guard revision == roomEventRevision else { return }
        let turns = snapshot.turns.filter { turn in
            !endedTurnIDs.contains(turn.playbackID)
                && !(turn.triggerMessageID.map { hasAnswer(on: $0, from: turn.userID) } ?? false)
        }
        let previous = liveTurns
        var merged: [String: RoleChatLiveTurn] = [:]
        for turn in turns {
            if let old = previous[turn.userID], old.playbackID != turn.playbackID,
               let trigger = old.triggerMessageID, trigger == turn.triggerMessageID {
                merged[turn.userID] = mergeLiveTurn(turn, over: old)
            } else {
                merged[turn.userID] = turn
            }
        }
        liveTurns = merged
        // Ход, которого в снимке уже нет (владелец написал новое сообщение,
        // сервер остановил работу), не исчезает с экрана: он доигрывает на
        // своём месте, пока не встанет его ответ (владелец 30.10.2026).
        for (userID, turn) in previous where liveTurns[userID]?.playbackID != turn.playbackID {
            parkLiveTurnIfUnanswered(turn, userID: userID)
        }
        restoredTurnIDs = Set(turns.map(\.playbackID))
        typists = Dictionary(turns.map { ($0.userID, $0.name) }, uniquingKeysWith: { _, last in last })
        typistTools = typistTools.filter { liveTurns[$0.key] != nil }
    }

    /// Полоса выбора вместо панели ввода: отметить всё или снять отметки.
    private var selectionBar: some View {
        HStack(spacing: TFSpacing.md) {
            Button(allMessagesSelected ? "Снять выбор" : "Выбрать все") {
                if allMessagesSelected {
                    selectedMessageIDs.removeAll()
                } else {
                    selectedMessageIDs = Set(messages.map(\.id))
                }
            }
            .disabled(messages.isEmpty)
            Spacer(minLength: TFSpacing.md)
            Text("Выбрано: \(selectedMessageIDs.count)")
                .tfText(.action)
                .foregroundStyle(Color.tfSub)
        }
        .padding(.horizontal, TFSpacing.lg)
        .padding(.vertical, TFSpacing.md)
    }

    private var allMessagesSelected: Bool {
        !messages.isEmpty && selectedMessageIDs.count == messages.count
    }

    /// «1 участник / 2 участника / 5 участников» — тот же разбор исключений
    /// 11–14, что у `DirectoryPluralize`, но для слова «участник».
    private func participantsWord(_ count: Int) -> String {
        let mod100 = count % 100
        if mod100 >= 11 && mod100 <= 14 { return "участников" }
        switch count % 10 {
        case 1: return "участник"
        case 2, 3, 4: return "участника"
        default: return "участников"
        }
    }

    private func enterSelection(selecting id: String?) {
        isSelecting = true
        selectedMessageIDs = id.map { [$0] } ?? []
    }

    private func exitSelection() {
        isSelecting = false
        selectedMessageIDs.removeAll()
    }

    private func toggleSelection(_ id: String) {
        if selectedMessageIDs.contains(id) { selectedMessageIDs.remove(id) }
        else { selectedMessageIDs.insert(id) }
    }

    private func deleteSelected() async {
        let ids = selectedMessageIDs
        guard !ids.isEmpty else { return }
        // Сразу с экрана (владелец 07.11.2026: «нажал удалить — должно сразу
        // удалиться»); сервер следом, не вышло — перечитываем ленту.
        messages.removeAll { ids.contains($0.id) }
        exitSelection()
        do {
            try await api.deleteRoleChatMessages(chatID: chat.id, ids: Array(ids))
            try? LocalStore.shared.deleteMessages(chatID: chat.id, ids: Array(ids))
        } catch {
            errorMessage = error.localizedDescription
            await refresh()
        }
    }

    /// Новая сессия (владелец 25.09.2026, docs/ПЛАН Супер Помощник владельца/):
    /// сбрасывает память роли, история остаётся — сервер сам вставляет
    /// метку-разделитель, которую здесь просто дописываем в ленту.
    /// «Сжать» (владелец 20.10.2026). В чате с несколькими ролями — выбор роли.
    @ViewBuilder private var compactMenuItem: some View {
        let roles = chat.others(excluding: session.currentUser?.id).filter { $0.roleKey != nil }
        if roles.count > 1 {
            Menu {
                ForEach(roles) { member in
                    Button(member.name) { Task { await compact(member) } }
                }
            } label: { Label("Сжать сессию", systemImage: "arrow.down.right.and.arrow.up.left") }
        } else if let member = roles.first {
            Button { Task { await compact(member) } } label: {
                Label("Сжать сессию", systemImage: "arrow.down.right.and.arrow.up.left")
            }
        }
    }

    private func compact(_ member: RoleChatMember) async {
        guard compactingRoleName == nil else { return }
        compactingRoleName = member.name
        defer { compactingRoleName = nil }
        do {
            try await api.compactRoleChatSession(chatID: chat.id, roleID: member.id)
            noticeMessage = "Сессия «\(member.name)» сжата."
            await composerControls.load(chat: chat)
        } catch { errorMessage = error.localizedDescription }
    }

    private func newSession(roleID selectedRoleID: String? = nil) async {
        guard let roleID = selectedRoleID ?? chat.others(excluding: session.currentUser?.id).first?.id else { return }
        do {
            let marker = try await api.newRoleChatSession(chatID: chat.id, roleID: roleID)
            if !messages.contains(where: { $0.id == marker.id }) { messages.append(marker) }
            await composerControls.load(chat: chat)
        } catch { errorMessage = error.localizedDescription }
    }

    private func clearChat() async {
        messages = []
        exitSelection()
        do {
            try await api.deleteRoleChatMessages(chatID: chat.id)
            try? LocalStore.shared.deleteAllMessages(chatID: chat.id)
        } catch {
            errorMessage = error.localizedDescription
            await refresh()
        }
    }

    /// Привязать чат к задаче (`taskID == nil` — отвязать). Сервер отвечает
    /// обновлённым чатом, поэтому локальный состав переписки перечитывать не
    /// нужно — меняется только сама привязка.
    private func bindTask(_ taskID: String?) async {
        do {
            chat = try await api.bindRoleChatToTask(id: chat.id, taskID: taskID)
        } catch { errorMessage = error.localizedDescription }
    }

    @ViewBuilder
    private func messageRow(_ message: RoleChatMessage, replyExcerpts: [String: String]) -> some View {
        if let coordination = message.coordination {
            RoleCoordinationCard(coordination: coordination) {
                try await api.stopRoleCoordination(chatID: chat.id, messageID: message.id)
            }
            .hintAnchor(HintAnchorID.chatCoordination)
        } else if let memoryUpdate = message.memoryUpdate {
            memoryUpdateChipRow(memoryUpdate)
        } else if message.isSessionMarker {
            sessionMarkerRow(message)
        } else if isFlatReply(message) {
            flatReplyRow(message, replyExcerpts: replyExcerpts)
        } else {
            messageBubbleRow(message, replyExcerpts: replyExcerpts)
        }
    }

    /// Ответы ролей — по всей ширине в личных и групповых чатах.
    /// Свои сообщения, голосовые и сообщения других людей в группе — в пузырях.
    /// Это только оформление: состав чата и правила адресации не меняются.
    private func isFlatReply(_ message: RoleChatMessage) -> Bool {
        guard message.fromUserID != session.currentUser?.id else { return false }
        guard chat.kind != "group" || isAgentReply(message) else { return false }
        return !(message.attachments?.contains { $0.isVoiceRecording } ?? false)
    }

    @ViewBuilder
    private func replyContext(messageID: String?, sender: String?,
                              excerpts: [String: String]) -> some View {
        if let messageID, let excerpt = excerpts[messageID] {
            Text("В ответ на: " + excerpt)
                .tfText(.meta)
                .foregroundStyle(Color.tfSub)
                .lineLimit(2)
                .accessibilityIdentifier("chat.replyTo." + messageID)
        } else if messageID != nil {
            Text("В ответ на сообщение" + (sender.map { " · " + $0 } ?? ""))
                .tfText(.meta)
                .foregroundStyle(Color.tfSub)
        }
    }

    /// Тексты сообщений по id — для строки «В ответ на». Один проход вместо
    /// поиска по всей ленте в каждой строке.
    static func replyExcerpts(from messages: [RoleChatMessage]) -> [String: String] {
        var result: [String: String] = [:]
        result.reserveCapacity(messages.count)
        for message in messages {
            let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            result[message.id] = text.isEmpty ? "Вложение" : text
        }
        return result
    }

    /// Тело шага по запросу.
    ///
    /// В истории сообщений шаги приходят без вывода инструмента и аргументов
    /// вызова (29.10.2026, «телефон — чисто окошко»): они весили 3,2 МБ на
    /// 20 чатов, а рисуются только в раскрытой шторке шага. Владелец раскрыл
    /// шаг — телефон спросил ровно этот шаг.
    private func stepDetailLoader(for message: RoleChatMessage) -> ((String) async -> RoleChatLiveStep?)? {
        let chatID = chat.id
        let messageID = message.id
        return { stepID in
            try? await api.messageStep(chatID: chatID, messageID: messageID, stepID: stepID)
        }
    }

    private func flatReplyRow(_ message: RoleChatMessage, replyExcerpts: [String: String]) -> some View {
        HStack(alignment: .top, spacing: TFSpacing.sm) {
            if isSelecting {
                Image(systemName: selectedMessageIDs.contains(message.id)
                      ? "checkmark.circle.fill" : "circle")
                    .tfTypeFont(size: 20)
                    .foregroundStyle(selectedMessageIDs.contains(message.id)
                                     ? Color.tfRed : Color.tfDim)
            }
            VStack(alignment: .leading, spacing: TFSpacing.sm) {
                // Ответ роли подписан внизу (replyFooter), сверху — только чужой.
                if !isAgentReply(message) { senderLine(message, color: Color.tfSub) }
                replyContext(messageID: message.replyToMessageID, sender: message.replyToSenderName,
                             excerpts: replyExcerpts)
                // Текст и карточка задачи — вместе, а не вместо: раньше
                // карточка подменяла всё сообщение, и вопрос роли пропадал
                // (владелец 14.10.2026: «приходит только виджет»).
                if !message.text.isEmpty || message.roleEnvelopeJSON != nil {
                    roleMessageContent(message, allowsCommands: session.currentUser?.role == .owner && !isSelecting)
                .environment(\.continueSlotPlan, slotContinueAction(for: message))
                }
                if let handoff = message.handoff {
                    ChatHandoffCard(handoff: handoff)
                }
                // Уточнение роли у владельца (26.10.2026): форма с вариантами
                // ответа. Рисуется под ответом роли — там, где владелец её
                // ждёт.
                if let question = message.question {
                    RoleQuestionCard(question: question) { answers, note in
                        try await self.api.answerChatQuestion(chatID: self.chat.id,
                                                             questionID: question.id,
                                                             answers: answers,
                                                             note: note)
                        await self.refresh()
                    }
                }
                // Быстрые варианты ответа — у своего сообщения (26.10.2026).
                if !isSelecting, let replies = quickReplies(for: message) {
                    quickReplyRow(replies)
                }
                if let taskID = message.taskID, taskID != chat.taskID {
                    SecretaryDraftCard(taskID: taskID) { pendingTaskID = taskID }
                }
                nonVoiceAttachments(message)
                if isAgentReply(message) && !isSelecting { messageActions(message) }
            }
            // Долгое нажатие по ответу собеседника открывает меню действий
            // (владелец 26.10.2026): весь набор, включая ветвление.
            .contextMenu { if !isSelecting { messageContextMenu(message, isMine: false) } }
        }
        .contentShape(Rectangle())
        .overlay {
            if isSelecting {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { toggleSelection(message.id) }
            }
        }
    }

    /// Разделитель «новая сессия» (владелец 25.09.2026) — не пузырь,
    /// центрированная метка, как разрыв даты в iMessage.
    private func sessionMarkerRow(_ message: RoleChatMessage) -> some View {
        HStack {
            Spacer()
            TFPill(surface: .tfCard, capsule: true) {
                Text("Новая сессия")
                    .tfText(.caption)
                    .foregroundStyle(Color.tfDim)
                    .padding(.horizontal, TFSpacing.md)
                    .padding(.vertical, 4)
            }
            Spacer()
        }
    }

    /// Тихий чип наблюдателя памяти — как «Навык подключён», без пузыря ответа.
    private func memoryUpdateChipRow(_ update: RoleChatMemoryUpdate) -> some View {
        HStack {
            Spacer()
            TFPill(surface: .tfCard, capsule: true) {
                HStack(spacing: TFSpacing.xs) {
                    Image(systemName: "brain")
                        .tfTypeFont(size: 12, weight: .medium)
                    Text(update.chipLabel)
                        .tfText(.caption)
                        .lineLimit(1)
                }
                .foregroundStyle(Color.tfDim)
                .padding(.horizontal, TFSpacing.md)
                .padding(.vertical, 4)
            }
            .accessibilityIdentifier("chat.memoryUpdateChip")
            .accessibilityLabel(update.chipLabel)
            Spacer()
        }
    }

    private func messageBubbleRow(_ message: RoleChatMessage, replyExcerpts: [String: String]) -> some View {
        let mine = message.fromUserID == session.currentUser?.id
        let hasAudio = message.attachments?.contains { $0.isVoiceRecording } ?? false
        return HStack(alignment: .top, spacing: TFSpacing.sm) {
            if isSelecting {
                // Отметка выбора слева от сообщения — как в почте и Teams.
                Image(systemName: selectedMessageIDs.contains(message.id)
                      ? "checkmark.circle.fill" : "circle")
                    .tfTypeFont(size: 20)
                    .foregroundStyle(selectedMessageIDs.contains(message.id)
                                     ? Color.tfRed : Color.tfDim)
                    .padding(.top, TFSpacing.md)
            }
            if mine { Spacer(minLength: 48) }
            VStack(alignment: .leading, spacing: TFSpacing.xs) {
                // Иконка отправителя — вплотную слева от его имени, внутри
                // сообщения сверху (владелец 21.09.2026). Раньше она стояла
                // отдельным столбцом сбоку и у своих сообщений не рисовалась
                // вовсе, хотя иконка есть у всех.
                //
                // У голосового своя подложка — пузырь, поэтому там эта строка
                // уезжает ВНУТРЬ пузыря, а не висит над ним отдельно.
                // У ответа роли подпись внизу, рядом с кнопками (владелец
                // 14.10.2026, по образцу: кто ответил и за сколько — в конце).
                if !hasAudio && (mine || !isAgentReply(message)) {
                    if mine {
                        senderLine(message, color: Color.tfSub)
                            .hintAnchor(HintAnchorID.chatOwnMessageCopy)
                    } else {
                        senderLine(message, color: Color.tfSub)
                    }
                }
                replyContext(messageID: message.replyToMessageID, sender: message.replyToSenderName,
                             excerpts: replyExcerpts)
                ForEach(message.attachments?.filter { $0.isVoiceRecording } ?? []) { attachment in
                    RoleChatRemoteVoiceBubble(
                        attachment: attachment,
                        message: message,
                        player: player,
                        api: api,
                        isOwn: mine,
                        header: AnyView(senderLine(message, color: mine ? Color.tfSub : Color.tfPaper.opacity(0.85)))
                    )
                }
                nonVoiceAttachments(message)
                // Карточка задачи (владелец 25.09.2026, этап 2 «Супер
                // Помощника владельца») — раньше была только у Помощника владельца
                // (ChatBubble.swift, message.fromUserId == secretaryID),
                // здесь — для любой роли, отправитель не важен.
                // Кроме чата самой задачи: его сообщения наследуют её
                // task_id, и карточка подменяла КАЖДОЕ сообщение — текста не
                // было видно вовсе (владелец 07.10.2026).
                // Текст и карточка — вместе (владелец 14.10.2026): карточка
                // больше не подменяет сообщение.
                if (!message.text.isEmpty || message.roleEnvelopeJSON != nil) && !hasAudio {
                    if mine {
                        Text(message.text)
                            .tfText(.body)
                            .textSelection(.enabled)
                            .foregroundStyle(Color.tfText)
                    } else {
                        // В группе ответ роли использует тот же разбор контракта.
                        roleMessageContent(message, allowsCommands: session.currentUser?.role == .owner && !isSelecting)
                .environment(\.continueSlotPlan, slotContinueAction(for: message))
                    }
                }
                if let handoff = message.handoff {
                    ChatHandoffCard(handoff: handoff)
                }
                if let taskID = message.taskID, taskID != chat.taskID {
                    SecretaryDraftCard(taskID: taskID) { pendingTaskID = taskID }
                }
                // Признак доставки под СВОИМ сообщением (карточка b504958a,
                // контракт §10): «Сохранено» — сообщение лежит в ленте,
                // «Передано исполнителю» — роль взяла его в работу. Под
                // ответом роли признака нет: доставки «исполнителю» там не
                // бывает, и значок сбивал бы владельца с толку.
                if let delivery = ChatDeliveryBadgePolicy.badge(
                    for: message,
                    isOwnMessage: mine,
                    isAgentReply: isAgentReply(message)
                ) {
                    ChatDeliveryBadge(state: delivery)
                        .hintAnchor(HintAnchorID.chatDeliveryBadge)
                }
                if !mine && isAgentReply(message) && !isSelecting {
                    messageActions(message)
                }
            }
            // Долгое нажатие по своему сообщению даёт те же действия, кроме
            // ветвления (владелец 26.10.2026).
            .contextMenu { if !isSelecting { messageContextMenu(message, isMine: mine) } }
            .padding(hasAudio ? 0 : TFSpacing.md)
            // Как поле рутины: почти чёрный фон и тонкая тёмно-красная
            // окантовка у своего; чужое — та же подложка, кромка слабее
            // (владелец 03.11.2026). Без `clipShape` после обводки.
            .background {
                if !hasAudio {
                    RoundedRectangle(cornerRadius: TFRadius.lg, style: .continuous)
                        .fill(Color.tfFieldDark)
                }
            }
            // Без рамки: в чате окантовки нет ни у чего (владелец 06.11.2026).
            if !mine { Spacer(minLength: 48) }
        }
        // Долгое нажатие только ВКЛЮЧАЕТ выбор — с этим сообщением уже
        // отмеченным; дальше отмечаешь тапами (владелец 21.09.2026). В самом
        // режиме выбора тап по сообщению отмечает его, а внутренние кнопки
        // (воспроизведение) перекрыты прозрачным слоем, чтобы не срабатывали.
        .contentShape(Rectangle())
        .overlay {
            if isSelecting {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { toggleSelection(message.id) }
            }
        }
    }

    /// Отметки checklist-виджета уходят на сервер (карточка 21842242): роль
    /// читает их операцией `taskflow_checklist_state`, а состояние приходит с
    /// сервера — поэтому отметка переживает перезапуск приложения. Контекст
    /// только там, где блок виджета есть: у сообщения без него отправлять
    /// нечего.
    private func checklistContext(for message: RoleChatMessage) -> ChecklistSyncContext? {
        guard message.text.contains("```widget") || message.roleEnvelopeJSON?.contains("```widget") == true
        else { return nil }
        let chatID = chat.id
        let messageID = message.id
        return ChecklistSyncContext(
            chatID: chatID,
            messageID: messageID,
            seed: message.checklistState ?? []
        ) { item in
            try await api.setRoleChatChecklistItem(chatID: chatID, messageID: messageID, item: item)
        }
    }

    private func isAgentReply(_ message: RoleChatMessage) -> Bool {
        message.fromUserID?.hasPrefix("role_") == true || message.fromUserID == "u-secretary" || chat.members.contains { $0.id == message.fromUserID && $0.roleKey != nil }
    }


    /// Кнопка «Продолжить» под планом: только пока слот заблокирован.
    private func slotContinueAction(for message: RoleChatMessage) -> (@MainActor @Sendable () async throws -> Void)? {
        guard message.slotResumable == true else { return nil }
        let chatID = chat.id, messageID = message.id, client = api
        return { try await client.continueSlot(chatID: chatID, messageID: messageID) }
    }

    @ViewBuilder
    private func roleMessageContent(_ message: RoleChatMessage, allowsCommands: Bool) -> some View {
        let checklist = checklistContext(for: message)
        // Ответ в конверте рисуется той же разметкой, что и во время печати
        // (текст, заголовки, таблицы, виджеты, код), а не карточками отчёта:
        // два способа рисовать один ответ давали скачок высоты при подмене
        // (владелец 07.11.2026: «в пизду эти отчёты, если из-за них весь
        // головняк»). Текст сообщения сервер уже собрал из блоков конверта.
        //
        // Перевод (владелец 08.11.2026): просим его для каждой реплики, как
        // только она появилась на экране, и показываем готовые переводы. Блоки
        // и чек-лист относятся к оригиналу — при переводе их не подмешиваем,
        // иначе половина ответа осталась бы английской.
        let shown = RoleTranslator.shared.display(message.text)
        let original = shown == message.text
        RoleReplyMarkdown(text: shown, allowsCommands: allowsCommands,
                          checklist: original ? checklist : nil,
                          serverBlocks: original ? message.blocks : nil)
            .equatable()
            .roleTranslationRequests([message.text])
    }

    private func copyMessage(_ message: RoleChatMessage) {
        UIPasteboard.general.string = message.text
        copiedMessageID = message.id
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if copiedMessageID == message.id { copiedMessageID = nil }
        }
    }

    private func messageActions(_ message: RoleChatMessage) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.xs) {
            // Прерванный ответ (уточнение владельца остановило ход) не должен
            // выглядеть как завершённый (карточка b504958a, доработка D1).
            if let interruption = message.interruption {
                ChatInterruptionBadge(interruption: interruption, isPartial: message.partial == true)
            }
            if let usage = message.steps?.usage { RoleTurnUsageRow(usage: usage) }
            if let changes = message.steps?.codeChanges {
                TurnCodeChangesRow(changes: changes) { text in
                    draft = draft.isEmpty ? text : draft + "\n\n" + text
                    composerFocused = true
                }
            }
            messageActionRow(message)
        }
    }

    private func messageActionRow(_ message: RoleChatMessage) -> some View {
        // Владелец 26.10.2026: значки-действия под ответом убраны — копировать,
        // выделить, поделиться и ответвление есть в меню по долгому нажатию.
        // Под ответом осталась только подпись: кто ответил, сколько думал, время.
        replyFooter(message)
    }

    /// Подпись ответа роли внизу: иконка, имя, сколько думала, время.
    private func replyFooter(_ message: RoleChatMessage) -> some View {
        HStack(spacing: TFSpacing.xs) {
            RoleChatAvatar(message: message, size: .sm)
            Text(message.fromUserName ?? "Участник")
                .tfText(.caption)
            if let ms = message.steps?.durationMs, ms > 0 {
                Text("· \(Self.turnDuration(ms))")
                    .tfText(.caption)
            }
            if let time = ChatMessageTime.label(raw: message.createdAt) {
                Text("· \(time)")
                    .tfText(.caption)
                    .opacity(0.7)
            }
        }
        .lineLimit(1)
    }

    static func turnDuration(_ ms: Int) -> String {
        let seconds = max(1, ms / 1000)
        return seconds < 60 ? "\(seconds) с" : "\(seconds / 60) мин \(seconds % 60) с"
    }

    private func openBranch(from message: RoleChatMessage) async {
        guard !isBranching else { return }
        isBranching = true
        defer { isBranching = false }
        do {
            branchChat = try await api.createChatBranch(chatID: chat.id, messageID: message.id)
            isBranchPresented = true
        } catch { errorMessage = error.localizedDescription }
    }

    private func messageActionButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            // Владелец 20.10.2026: значки мельче и одного размера — 14 pt в
            // одинаковом квадрате 16×16; зона нажатия по-прежнему 44×44.
            Image(systemName: symbol)
                .tfTypeFont(size: 14, weight: .regular)
                .frame(width: 16, height: 16)
                .frame(width: TFHitTarget.min, height: TFHitTarget.min)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }

    /// Меню действий по долгому нажатию (владелец 26.10.2026): у своих
    /// сообщений и у собеседника одинаковый, вместе с ответвлением —
    /// ветка доступна от любого сообщения (владелец 08.11.2026). Набор описан в одном месте, чтобы новые действия не
    /// приходилось проставлять дважды.
    @ViewBuilder
    private func messageContextMenu(_ message: RoleChatMessage, isMine: Bool) -> some View {
        if !message.text.isEmpty {
            Button { selectingText = SelectableMessageText(text: message.text) } label: {
                Label("Выделить текст", systemImage: "text.cursor")
            }
            Button { copyMessage(message) } label: {
                Label("Скопировать текст", systemImage: "doc.on.doc")
            }
        }
        Button { exportMessage(message) } label: {
            Label("Сохранить или поделиться", systemImage: "square.and.arrow.up")
        }
        if isMine && message.canWithdraw == true
            && !liveStore.triggerIDs.contains(message.id)
            && !completingTurns.values.contains(where: { $0.triggerMessageID == message.id })
            && !messages.contains(where: { $0.replyToMessageID == message.id && isAgentReply($0) }) {
            Button(role: .destructive) { Task { await withdrawMessage(message) } } label: {
                Label("Убрать сообщение", systemImage: "trash")
            }
        }
        // Ответвление доступно от ЛЮБОГО сообщения и в любой комнате —
        // владелец 08.11.2026: «одна родительская личная, а дальше дочка,
        // поддочка»; раньше пункт был только у реплик собеседника.
        if !message.text.isEmpty {
            Button { Task { await openBranch(from: message) } } label: {
                Label("Ответвление: обсудить в отдельном чате", systemImage: "arrow.triangle.branch")
            }
            .disabled(isBranching)
        }
    }

    private func withdrawMessage(_ message: RoleChatMessage) async {
        guard message.fromUserID == session.currentUser?.id, message.canWithdraw == true else { return }
        do {
            try await api.withdrawRoleChatMessage(chatID: chat.id, messageID: message.id)
            try? LocalStore.shared.deleteMessages(chatID: chat.id, ids: [message.id])
            messages.removeAll { $0.id == message.id }
            selectedMessageIDs.remove(message.id)
        } catch {
            // Состояние могло измениться, пока меню было открыто: сервер
            // повторно проверяет начало работы и сохраняет взятое сообщение.
            await refresh()
            errorMessage = error.localizedDescription
        }
    }

    private func exportMessage(_ message: RoleChatMessage) {
        do {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("message-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent("TaskFlow-сообщение.md")
            try message.text.write(to: url, atomically: true, encoding: .utf8)
            guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }), let root = scene.keyWindow?.rootViewController else { return }
            var top = root
            while let presented = top.presentedViewController { top = presented }
            let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            if let popover = controller.popoverPresentationController {
                popover.sourceView = top.view
                popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            top.present(controller, animated: true)
        } catch { errorMessage = error.localizedDescription }
    }

    @ViewBuilder
    private func nonVoiceAttachments(_ message: RoleChatMessage) -> some View {
        ForEach(message.attachments?.filter { !$0.isVoiceRecording } ?? []) { attachment in
            Button {
                Task { await openAttachment(attachment) }
            } label: {
                if attachment.mime?.hasPrefix("image/") == true {
                    VStack(alignment: .leading, spacing: TFSpacing.xs) {
                        ChatAttachmentImage(attachmentId: attachment.id, fileName: attachment.fileName)
                        Text(attachment.fileName)
                            .tfText(.caption)
                            .foregroundStyle(Color.tfSub)
                            .lineLimit(1)
                    }
                } else {
                    ChatFileChip(fileName: attachment.fileName)
                }
            }
            .buttonStyle(.plain)
            .disabled(openingAttachmentIDs.contains(attachment.id))
            .overlay {
                if openingAttachmentIDs.contains(attachment.id) { TFLoading(.inline) }
            }
            .accessibilityLabel("Открыть \(attachment.fileName)")
        }
    }

    private func openAttachment(_ attachment: ApiChatAttachment) async {
        guard openingAttachmentIDs.insert(attachment.id).inserted else { return }
        defer { openingAttachmentIDs.remove(attachment.id) }
        do {
            let data = try await api.downloadAttachment(id: attachment.id)
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("taskflow-chat-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let safeName = URL(fileURLWithPath: attachment.fileName).lastPathComponent
            let url = directory.appendingPathComponent(safeName.isEmpty ? "attachment" : safeName)
            try data.write(to: url, options: .atomic)
            previewAttachmentURL = url
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Иконка отправителя вплотную слева от имени — одна и та же строка и в
    /// текстовом сообщении, и внутри голосового пузыря. Цвет подписи зависит
    /// от подложки: на карточке — приглушённый, на заливке пузыря — белый.
    private func senderLine(_ message: RoleChatMessage, color: Color) -> some View {
        HStack(spacing: TFSpacing.sm) {
            RoleChatAvatar(message: message, size: .lg)
            Text(message.fromUserName ?? "Участник")
                .tfText(.meta)
                .foregroundStyle(color)
            // Время — и у своих, и у ответов (владелец 14.10.2026). У
            // сообщения «в пути» его ещё нет.
            if let time = ChatMessageTime.label(raw: message.createdAt) {
                Text(time)
                    .tfText(.caption)
                    .foregroundStyle(color.opacity(0.7))
            }
        }
    }

    /// Строка отправителя для голосового, которое ещё не отправлено: на
    /// сервере его пока нет, поэтому имя и иконка берутся из сессии.
    private var ownSenderLine: some View {
        HStack(spacing: TFSpacing.sm) {
            RoleChatAvatar(user: session.currentUser, size: .lg)
            Text(session.currentUser?.name ?? "Вы")
                .tfText(.meta)
                .foregroundStyle(Color.tfSub)
        }
    }

    /// Курсор догрузки: максимальный `sequence` уже известного сообщения.
    ///
    /// `nil` — локальной истории нет, тогда сервер отдаёт чат целиком.
    /// Иначе спрашиваем только НОВОЕ (`after`): повторный вход в комнату
    /// должен стоить ноль байт, а не всю историю заново.
    private var messagesCursor: Int? {
        guard !messages.isEmpty else { return nil }
        return try? LocalStore.shared.maxSequence(chatID: chat.id)
    }

    private func refresh() async {
        refreshRevision += 1
        let revision = refreshRevision
        let eventRevision = roomEventRevision
        let cursor = messagesCursor
        do {
            async let chatRequest = api.roleChat(id: chat.id)
            // Сырое тело: его же кладём в локальную базу, чтобы переписка
            // открывалась сразу и без сети.
            async let messagesPage = api.roleChatMessagesPage(
                id: chat.id,
                after: cursor,
                limit: cursor.map { _ in 50 }
            )
            let (updatedChat, page) = try await (chatRequest, messagesPage)
            let updatedMessages = try api.decode(APIClient.RoleChatMessagesSyncEnvelope.self, from: page.data).messages
            guard revision == refreshRevision else { return }
            chat = updatedChat
            // В локальную базу — сырое ответ сервера.
            try? LocalStore.shared.upsertMessages(chatID: chat.id, payload: page.data)
            if page.hasMore != nil {
                // Сервер отдал признак «есть ещё» — умеет постраничную выдачу.
                // Значит, догружать новое можно порциями.
                LocalStore.shared.setSyncState(SyncStateKeys.chatsPaging, "1")
            }
            // Снимок может менять текст и контекст ответа без изменения ID.
            // Объединяем его с событиями, пришедшими уже после начала запроса.
            do {
                for message in updatedMessages where !messages.contains(where: { $0.id == message.id }) {
                    guard let author = message.fromUserID else { continue }
                    // Ход, который этот ответ закрывает, мог уже смениться
                    // новым и доигрывать на своём месте (`parkedTurn`).
                    let closesLive = liveTurns[author]?.isCompleted(by: message) ?? false
                    let closesParked = parkedTurn(answering: message, author: author) != nil
                    if closesLive || closesParked { insertIncoming(message) }
                }
                let receivedAfterRequest = Set(messageEventRevisions.filter { $0.value > eventRevision }.map(\.key))
                if cursor == nil {
                    // Полный снимок: он и есть вся история.
                    messages = RoleChatMessageOrder.mergingSnapshot(updatedMessages, current: messages, receivedAfterRequest: receivedAfterRequest)
                } else {
                    // Только новые сообщения: старая история уже на экране,
                    // поэтому снимок — это новые плюс те, что в ленте.
                    messages = RoleChatMessageOrder.mergingSnapshot(
                        updatedMessages + messages,
                        current: messages,
                        receivedAfterRequest: receivedAfterRequest
                    )
                }
                hasLoadedMessages = true
                // Первый снимок при открытии — история. Добираем семя после
                // короткого кэша, иначе последний ответ снова проявляется.
                if !historySeedSettled {
                    let settled = RoleChatRevealSeed.settle(
                        current: seedMessageIDs,
                        snapshotIDs: messages.map(\.id),
                        settled: historySeedSettled
                    )
                    seedMessageIDs = settled.seed
                    historySeedSettled = settled.settled
                }
            }
            // Комната открыта — всё в ней прочитано. Отметку двигает только
            // этот вызов (LOCK-206), а новых сообщений при повторном входе
            // может и не быть: курсор уже стоит после них, и порция пустая.
            // Поэтому смотрим на последнее известное сообщение, а не на
            // пришедшие сейчас (владелец 08.11.2026: «семёрка продолжает
            // висеть» после открытия комнаты).
            if let lastID = messages.last?.id, lastID != markedReadMessageID {
                if (try? await api.markRoleChatRead(id: chat.id)) != nil {
                    markedReadMessageID = lastID
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            hasLoadedMessages = true
        }
    }

    /// Варианты у сообщения `message`: их место в ленте — сразу под ним.
    /// Пусто, если сообщение не от роли, вариантов нет, сообщение не своё
    /// или это не последнее видимое сообщение (своё сообщение владельца уже
    /// сняло актуальность).
    ///
    /// Список — ВИДИМЫЕ сообщения: скрытые служебные строки варианты не
    /// отменяют (26.10.2026, была жалоба «кнопок не видно у вопроса»).
    private func quickReplies(for message: RoleChatMessage) -> [String]? {
        ChatQuickReplyPolicy.replies(for: message, in: visibleMessages, ownerID: session.currentUser?.id)
    }

    /// То же стекло, что у капсулы поля ввода (`voiceCapsuleSurface`) —
    /// владелец 26.09.2026: «почему у композера фон есть, а тут нет» —
    /// плоская заливка читалась плашкой, голый контур без заливки — как
    /// дыра; нужна была именно системная капсула, а не то и не другое.
    private func quickReplyPillStyle<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .font(.body)
            .foregroundStyle(Color.tfText)
            .padding(.horizontal, TFSpacing.md)
            .padding(.vertical, TFSpacing.sm)
            // Быстрый ответ — кнопка, вид как у кнопок приложения: полупрозрачный
            // красный и тёмно-красная кромка (владелец 06.11.2026).
            .background(Color.tfRed.opacity(0.18), in: Capsule())
            .overlay {
                Capsule().strokeBorder(Color.tfButtonEdge, lineWidth: TFBorder.width)
            }
    }

    /// Владелец 26.09.2026: плашки крепятся к сообщению роли, в ленте, а не
    /// в отдельном оверлее над композером. Раскладка — переносом строк
    /// (сколько влезает в строку, столько и встаёт, лишнее уходит на
    /// следующую), а не одна горизонтально скроллящаяся строка: владелец
    /// прямо попросил «так и клади, не в столбик» вместо горизонтального
    /// скролла или одного варианта на строку.
    private func quickReplyRow(_ replies: [String]) -> some View {
        FlowLayout(spacing: TFSpacing.sm) {
            ForEach(replies, id: \.self) { reply in
                Button {
                    draft = reply
                    Task { await send() }
                } label: {
                    quickReplyPillStyle { Text(reply) }
                }
                .buttonStyle(.plain)
                .disabled(isSending)
            }
        }
        .padding(.vertical, TFSpacing.xs)
    }

    private func send() async {
        guard !chat.isAssistantOnly || (modelChoice.isReady && !modelChoice.isSaving) else {
            errorMessage = modelChoice.errorText ?? "Дождитесь сохранения настроек сессии."
            return
        }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!text.isEmpty || !pendingAttachments.isEmpty), !isSending, !isUploadingAttachment else { return }
        let pending = PendingOutgoing(id: "local-\(UUID().uuidString)", text: text,
                                      attachments: pendingAttachments, mode: workMode, executionMode: chat.composerExecutionMode)
        draft = ""
        pendingAttachments = []
        // Отправил — лента идёт к низу: своё сообщение должно попасть в кадр.
        // Низ держит сама таблица ленты (`followsBottom`), отдельного механизма
        // прокрутки рядом нет: два механизма спорили за offset (30.10.2026).
        feedScroll.scrollToBottom()
        ClientLog.shared.add("chat=\(chat.id) send")
        pendingOutgoing.append(pending)
        await deliver(pending.id)
    }

    /// Отправить (или повторить) сообщение из «в пути». Отправки идут по
    /// одной — порядок в ленте тот же, что порядок нажатий.
    private func deliver(_ pendingID: String) async {
        guard let pending = pendingOutgoing.first(where: { $0.id == pendingID }), !isSending else { return }
        isSending = true
        defer { isSending = false }
        if let index = pendingOutgoing.firstIndex(where: { $0.id == pendingID }) {
            pendingOutgoing[index].failed = false
        }
        do {
            let message = try await api.sendRoleChatMessage(chatID: chat.id, text: pending.text,
                                                            attachmentIDs: pending.attachments.map(\.id), mode: pending.mode, executionMode: pending.executionMode,
                                                            model: chat.isAssistantOnly ? nil : modelChoice.selected)
            pendingOutgoing.removeAll { $0.id == pendingID }
            if !messages.contains(where: { $0.id == message.id }) {
                // Своё отправленное сообщение занимает строку пузыря «в
                // пути»: строка не пересоздаётся, лента не прыгает.
                rowIDByMessageID[message.id] = pending.id
                messages = RoleChatMessageOrder.inserting(message, into: messages)
            }
        } catch {
            if let index = pendingOutgoing.firstIndex(where: { $0.id == pendingID }) {
                pendingOutgoing[index].failed = true
            }
        }
    }

    // MARK: - Упоминание через «@»

    /// Набираемое упоминание в конце черновика: «…@Раз» → «Раз». `nil` —
    /// упоминание сейчас не идёт. «@» засчитывается только в начале текста
    /// или после пробела — иначе сработало бы на адресе почты.
    private var mentionQuery: String? {
        guard let at = draft.lastIndex(of: "@") else { return nil }
        if at > draft.startIndex {
            let before = draft[draft.index(before: at)]
            guard before.isWhitespace else { return nil }
        }
        let query = draft[draft.index(after: at)...]
        guard !query.contains(where: { $0.isWhitespace }) else { return nil }
        return String(query)
    }

    /// Справочник для «@» — участники этого чата, кроме меня: сервер
    /// отвечает только ролями, которые есть в чате. Сначала совпадения с
    /// начала имени, потом по вхождению.
    private var mentionCandidates: [RoleChatMember] {
        guard !isSelecting, let query = mentionQuery?.lowercased() else { return [] }
        let others = chat.mentionMembers(excluding: session.currentUser?.id)
        guard !query.isEmpty else { return others }
        let matching = others.filter { $0.name.lowercased().contains(query) }
        return matching.filter { $0.name.lowercased().hasPrefix(query) }
            + matching.filter { !$0.name.lowercased().hasPrefix(query) }
    }

    private var mentionSuggestions: some View {
        TFCard(padding: 0, surface: .card, radius: nil) {
            VStack(spacing: 0) {
                ForEach(mentionCandidates) { member in
                    Button { insertMention(member) } label: {
                        HStack(spacing: TFSpacing.md) {
                            RoleMemberAvatar(member: member, size: .md)
                            Text(member.name)
                                .tfText(.body)
                                .foregroundStyle(Color.tfText)
                            Spacer()
                        }
                        .padding(.horizontal, TFSpacing.lg)
                        .padding(.vertical, TFSpacing.sm)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// «…@Раз» → «…@Разработчик » — пробел в конце, чтобы продолжение
    /// набора не слилось с именем и подсказка закрылась.
    private func insertMention(_ member: RoleChatMember) {
        guard let at = draft.lastIndex(of: "@") else { return }
        draft = String(draft[..<at]) + "@\(member.name) "
    }

    private func sendVoicePreview(_ message: VoiceMessage) async -> Bool {
        if !pendingVoices.contains(where: { $0.id == message.id }) {
            pendingVoices.append(message)
            pendingVoiceModes[message.id] = workMode
            pendingVoiceExecutionModes[message.id] = chat.composerExecutionMode
        }
        await sendVoice(message.id)
        // Запись передана ленте; при сетевой ошибке в ней остаётся повтор.
        return true
    }

    private func handleFileImport(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        Task {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            isUploadingAttachment = true
            defer { isUploadingAttachment = false }
            do {
                let data = try Data(contentsOf: url)
                let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                let attachment = try await api.uploadRoleChatAttachment(fileName: url.lastPathComponent,
                                                                        data: data, mime: mime)
                pendingAttachments.append(attachment)
            } catch { errorMessage = error.localizedDescription }
        }
    }

    /// Фото из галереи (владелец 26.09.2026, пункт «Фото» в «+»). JPEG —
    /// `PhotosPickerItem` сам даёт исходные данные оригинала любого формата,
    /// но сервер/лента ожидают предсказуемый тип; пережимаем в JPEG 0.9,
    /// как это уже делает камера ниже.
    private func uploadPickedPhoto(_ item: PhotosPickerItem) async {
        isUploadingAttachment = true
        defer { isUploadingAttachment = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let jpeg = image.jpegData(compressionQuality: 0.9) else { return }
            let attachment = try await api.uploadRoleChatAttachment(fileName: "photo.jpg", data: jpeg, mime: "image/jpeg")
            pendingAttachments.append(attachment)
        } catch { errorMessage = error.localizedDescription }
    }

    /// Снимок камерой (владелец 26.09.2026, пункт «Камера» в «+»).
    private func uploadCameraPhoto(_ image: UIImage) async {
        isUploadingAttachment = true
        defer { isUploadingAttachment = false }
        guard let jpeg = image.jpegData(compressionQuality: 0.9) else { return }
        do {
            let attachment = try await api.uploadRoleChatAttachment(fileName: "camera.jpg", data: jpeg, mime: "image/jpeg")
            pendingAttachments.append(attachment)
        } catch { errorMessage = error.localizedDescription }
    }

    private func sendVoice(_ id: UUID) async {
        guard !chat.isAssistantOnly || (modelChoice.isReady && !modelChoice.isSaving) else {
            errorMessage = modelChoice.errorText ?? "Дождитесь сохранения настроек сессии."
            return
        }
        guard let message = pendingVoices.first(where: { $0.id == id }),
              message.transcript != .pending,
              sendingVoiceIDs.insert(id).inserted else { return }
        defer { sendingVoiceIDs.remove(id) }
        do {
            let attachmentID: String
            if let existing = uploadedVoiceIDs[id] {
                attachmentID = existing
            } else {
                let data = try Data(contentsOf: message.audioURL)
                let attachment = try await api.uploadRoleChatAttachment(
                    fileName: message.audioURL.lastPathComponent, data: data, mime: "application/octet-stream"
                )
                attachmentID = attachment.id
                uploadedVoiceIDs[id] = attachmentID
            }
            let text: String
            if case .ready(let recognized) = message.transcript { text = recognized }
            else { text = "" }
            let sent = try await api.sendRoleChatMessage(chatID: chat.id, text: text, attachmentIDs: [attachmentID], mode: pendingVoiceModes[id] ?? workMode, executionMode: pendingVoiceExecutionModes[id] ?? chat.composerExecutionMode, model: chat.isAssistantOnly ? nil : modelChoice.selected)
            if !messages.contains(where: { $0.id == sent.id }) { messages.append(sent) }
            pendingVoices.removeAll { $0.id == id }
            pendingVoiceModes[id] = nil
            pendingVoiceExecutionModes[id] = nil
            uploadedVoiceIDs.removeValue(forKey: id)
        } catch { errorMessage = error.localizedDescription }
    }
}
