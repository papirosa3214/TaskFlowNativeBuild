import Foundation

extension ApiChatAttachment {
    /// Пока серверный валидатор не принимает audio/mp4, .m4a приходит как octet-stream.
    var isVoiceRecording: Bool {
        mime?.hasPrefix("audio/") == true || fileName.lowercased().hasSuffix(".m4a")
    }
}

/// Отдельный чат с ролями; старые каналы owner/agents имеют другой контракт.
public struct RoleChat: Decodable, Identifiable, Sendable {
    public let id: String
    public let title: String?
    public let kind: String
    public let createdBy: String
    public let taskID: String?
    public let projectID: String?
    public let parentChatID: String?
    public var storedExecutionMode: ChatExecutionMode? = nil
    public var executionMode: ChatExecutionMode {
        ChatExecutionMode.resolve(stored: storedExecutionMode, taskID: taskID, parentChatID: parentChatID)
    }
    public let members: [RoleChatMember]
    public let lastMessage: RoleChatPreview?
    /// Непрочитанных у ТЕКУЩЕГО пользователя (миграция 055, отметка на
    /// участнике чата). Опционально: сервер до этой правки поля не слал, и
    /// старый ответ не должен ронять декодирование.
    public let unreadCount: Int?
    /// Название задачи, к которой привязан чат (`nil` — свободный). Нужно
    /// пометкой в строке списка: по ней видно, какой чат за какой задачей.
    public let taskTitle: String?
    /// Ветка от сообщения (14.10.2026): из какого чата и от какого сообщения.
    public var branchOfChatID: String? = nil
    public var branchOfMessageID: String? = nil
    /// Назначение комнаты (21.10.2026): `personal` — владелец ↔ роль,
    /// `dm` — личка ролей, `common` — Общая; `wake` («Заминки» задачи) и
    /// `handoff` — служебные сессии. `nil` — обычная сессия.
    public var roomKind: String? = nil
    /// Проект сессии — для группировки списка.
    public var projectName: String? = nil
    public var closedAt: String? = nil
    /// Ход роли в этой комнате (27.10.2026). Старый сервер поля не шлёт.
    public var turn: RoomTurn? = nil

    /// Постоянная комната: живёт в панели «Комнаты», а не в списке сессий.
    public var isPermanentRoom: Bool { roomKind == "personal" || roomKind == "dm" || roomKind == "common" }

    enum CodingKeys: String, CodingKey {
        case id, title, kind, members
        case branchOfChatID = "branch_of_chat_id"
        case branchOfMessageID = "branch_of_message_id"
        case createdBy = "created_by"
        case taskID = "task_id"
        case projectID = "project_id"
        case parentChatID = "parent_chat_id"
        case storedExecutionMode = "execution_mode"
        case lastMessage = "last_message"
        case unreadCount = "unread_count"
        case taskTitle = "task_title"
        case roomKind = "room_kind"
        case projectName = "project_name"
        case closedAt = "closed_at"
        case turn
    }

    public var unread: Int { unreadCount ?? 0 }

    /// Собеседники — участники без текущего пользователя. В личке это ровно
    /// один человек/роль, в группе — весь состав (он же идёт в заголовок).
    public func others(excluding userID: String?) -> [RoleChatMember] {
        members.filter { $0.id != userID }
    }

    public func displayTitle(excluding userID: String?) -> String {
        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        // Сервер может вернуть пустое название группы: перечисляем роли без владельца.
        let names = others(excluding: userID)
            .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return names.isEmpty ? (kind == "group" ? "Групповой чат" : "Чат") : names.joined(separator: ", ")
    }
}

public struct RoleChatMember: Decodable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let avatarColor: String?
    public let avatarURL: String?
    public let initials: String?
    public let roleKey: String?

    enum CodingKeys: String, CodingKey {
        case id, name, initials
        case roleKey = "role_key"
        case avatarColor = "avatar_color"
        case avatarURL = "avatar_url"
    }
}

public struct RoleChatPreview: Decodable, Sendable {
    public let text: String
    public let fromUserID: String?
    /// Имя отправителя — превью строки списка идёт с ним («QA: проверка
    /// прошла»); у личных чатов подпись не нужна.
    public let fromUserName: String?
    public let createdAt: String?
    /// Сколько вложений в последнем сообщении. Голосовое и файл текстом не
    /// читаются (у голосового текста может не быть вовсе), поэтому строка
    /// списка показывает «Голосовое»/«Файл» вместо пустоты.
    public let attachmentCount: Int?
    public let audioCount: Int?

    enum CodingKeys: String, CodingKey {
        case text
        case fromUserID = "from_user_id"
        case fromUserName = "from_user_name"
        case createdAt = "created_at"
        case attachmentCount = "attachment_count"
        case audioCount = "audio_count"
    }

    /// Что показывать в строке списка: текст, иначе — иконка вложения.
    public var displayText: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if (audioCount ?? 0) > 0 { return "Голосовое сообщение" }
        if (attachmentCount ?? 0) > 0 { return "Файл" }
        return ""
    }
}

/// Чат, привязанный к задаче — карточка отдаёт их списком, чтобы дать переход
/// в переписку. Сам чат в карточке не рисуется: для него есть свой экран
/// (владелец 21.09.2026, LOCK-195).
public struct ApiTaskChat: Decodable, Identifiable, Sendable, Hashable {
    public let id: String
    public let title: String?
    public let kind: String?
    public let membersCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, kind
        case membersCount = "members_count"
    }

    /// Что показать в строке карточки: название чата, иначе — по составу.
    public var displayTitle: String {
        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        return kind == "group" ? "Групповой чат" : "Чат"
    }
}

/// `/chats/:id/messages` возвращает те же поля, что общий чат, но channel=chat.
public struct RoleChatReaction: Decodable, Sendable, Equatable {
    public let userID: String
    public let emoji: String
    enum CodingKeys: String, CodingKey { case userID = "user_id"; case emoji }
}

public struct RoleChatMessage: Decodable, Identifiable, Sendable {
    public let id: String
    public let chatID: String?
    public let fromUserID: String?
    public let fromUserName: String?
    public let fromUserColor: String?
    public let fromUserAvatarURL: String?
    public let fromUserInitials: String?
    public let kind: String?
    public let replyToMessageID: String?
    public let replyToSenderName: String?
    public let text: String
    /// Структурированный ответ роли, который сервер отдаёт рядом с текстом.
    /// `text` остаётся резервом для сообщений без контракта и старой истории.
    public let roleEnvelope: JSONValue?
    /// Ответ пришёл структурированным конвертом (`role_envelope`): его рисует
    /// `ChatStructuredOutputView` нативными блоками. Тогда текст ответа в
    /// пунктах хода — та же самая информация в плоском виде (таблица markdown,
    /// виджет сырым JSON). Показывать его рядом с блоками — значит показать
    /// ответ дважды (владелец 30.10.2026).
    public var hasStructuredAnswer: Bool { roleEnvelopeJSON != nil }
    public let createdAt: String?
    public let attachments: [ApiChatAttachment]?
    /// Задача, которую роль создала этим ходом (владелец 25.09.2026,
    /// docs/ПЛАН Супер Помощник владельца/, этап 2) — есть значение → вместо текста
    /// рисуется карточка (см. RoleChatsScreen).
    public let taskID: String?
    public let taskTitle: String?
    /// Быстрые ответы (владелец 25.09.2026, docs/ПЛАН Супер Помощник владельца/) —
    /// 2-4 коротких варианта, которые предложила роль вместо того, чтобы
    /// печатать руками. Только у последнего сообщения роли есть смысл.
    public let quickReplies: [String]?
    /// Разделитель «новая сессия» (владелец 25.09.2026) — рисуется не
    /// пузырём, а меткой посередине; сама история при сбросе сессии не
    /// удаляется, разделитель просто показывает границу.
    public let isSessionMarker: Bool
    /// Шаги хода роли, которые привели к этому ответу (владелец 27.09.2026,
    /// живой ход как в Claude Code) — рисуются свёрнутой строкой «N шагов ·
    /// M с» над текстом. `nil` — ход без шагов или сообщение не от роли.
    public let steps: RoleChatSteps?
    public let reactions: [RoleChatReaction]?
    /// Сдача этапа (14.10.2026): главное из отчёта роли, `nil` — обычный ответ.
    /// Отметки пунктов checklist-виджета, сохранённые на сервере (карточка
    /// 21842242): клиент их шлёт, сервер хранит и отдаёт и клиенту, и роли.
    /// Пустой массив — отметок не было, сам блок виджета остаётся в тексте.
    public var checklistState: [ChecklistItemState]? = nil
    public var handoff: RoleChatHandoff? = nil
    public var coordination: RoleChatCoordination? = nil
    public var sequence: Int? = nil
    /// Сохранено или уже передано исполнителю (карточка b504958a, контракт §10).
    /// Признак несёт сообщение владельца, которому роль должна ответить; у
    /// ответа роли он nil — доставлять его исполнителю некуда.
    public var queueDeliveryState: ChatMessageDeliveryState? = nil
    /// Сервер разрешает отзыв только до передачи роли. nil — старый сервер.
    public var canWithdraw: Bool? = nil
    /// Прерванный ответ роли (карточка b504958a, доработка D1): сервер
    /// останавливает ход уточнением владельца и помечает ответ — `stop_reason`
    /// (почему прерван) и `partial` (сохранён частично). У сообщений человека
    /// оба поля пустые, у старого сервера их нет вовсе.
    public var stopReason: String? = nil
    public var partialFlag: RoleChatPartialFlag? = nil
    /// Ответ, разложенный сервером на готовые блоки (26.10.2026). nil — старый
    /// сервер: тогда текст раскладывает клиент, как раньше.
    public var blocks: [ChatServerBlock]? = nil
    /// Уточнение роли у владельца (26.10.2026): вопрос с вариантами и его
    /// состояние. nil — вопроса нет или сервер старый.
    public var question: ChatQuestion? = nil
    /// Preserve the existing optional Bool interface, including legacy missing fields.
    public var partial: Bool? {
        get { partialFlag?.value }
        set { partialFlag = newValue.map { RoleChatPartialFlag(value: $0) } }
    }

    /// Состояние прерывания для показа в ленте: nil — ответ не прерывали.
    public var interruption: ChatMessageInterruption? {
        ChatMessageInterruption(stopReason: stopReason, partial: partial == true)
    }

    /// Обращение получило ответ. Это статус, а не указание скрыть карточку.
    public var isFinishedCoordinationRow: Bool {
        coordination?.isAnswered == true
    }

    /// JSON для renderer чата. Серверное поле должно быть объектом конверта.
    ///
    /// Конверт кодируется ОДИН РАЗ на сообщение и кэшируется по id: содержимое
    /// `roleEnvelope` неизменно (поле `let`), а раньше `JSONEncoder` срабатывал
    /// на каждый доступ — то есть два-три раза на каждое сообщение от роли при
    /// каждом проходе `body` ленты.
    nonisolated(unsafe) private static let envelopeJSONCache = NSCache<NSString, NSString>()

    public var roleEnvelopeJSON: String? {
        guard let roleEnvelope, case .object = roleEnvelope else { return nil }
        if let cached = Self.envelopeJSONCache.object(forKey: id as NSString) { return cached as String }
        guard let data = try? JSONEncoder().encode(roleEnvelope),
              let json = String(data: data, encoding: .utf8) else { return nil }
        Self.envelopeJSONCache.setObject(json as NSString, forKey: id as NSString)
        return json
    }

    enum CodingKeys: String, CodingKey {
        case replyToMessageID = "reply_to_message_id"
        case replyToSenderName = "reply_to_sender_name"
        case id, text, kind, attachments, steps, reactions, sequence, handoff, coordination
        case checklistState = "checklist_state"
        case roleEnvelope = "role_envelope"
        case chatID = "chat_id"
        case fromUserID = "from_user_id"
        case fromUserName = "from_user_name"
        case fromUserColor = "from_user_color"
        case fromUserAvatarURL = "from_user_avatar_url"
        case fromUserInitials = "from_user_initials"
        case createdAt = "created_at"
        case taskID = "task_id"
        case taskTitle = "task_title"
        case quickReplies = "quick_replies"
        case isSessionMarker = "is_session_marker"
        case queueDeliveryState = "queue_delivery_state"
        case canWithdraw = "can_withdraw"
        case stopReason = "stop_reason"
        case partialFlag = "partial"
        case blocks
        case question
    }
}

/// Сообщение с быстрыми вариантами ответа — правило показа живёт отдельно
/// (`ChatQuickReplyPolicy`, 26.10.2026).
extension RoleChatMessage: QuickReplyMessage {}

/// Отметка одного пункта checklist-виджета. Ключи те же, что и в самом
/// виджете: `key`/`id` пункта, иначе его номер строкой — так сервер ищет
/// пункт в тексте сообщения, а не в записи клиента.
public struct ChecklistItemState: Decodable, Sendable, Equatable {
    public let widgetKey: String
    public let itemKey: String
    public let done: Bool

    public init(widgetKey: String, itemKey: String, done: Bool) {
        self.widgetKey = widgetKey
        self.itemKey = itemKey
        self.done = done
    }

    enum CodingKeys: String, CodingKey {
        case widgetKey = "widget_key"
        case itemKey = "item_key"
        case done
    }
}

public struct RoleChatCoordination: Decodable, Sendable {
    public let requesterName: String
    public let recipientName: String
    public let question: String
    public let status: String
    public let activity: String
    public let createdAt: String
    public let lastActivityAt: String
    public let answer: String?
    public let terminal: Bool
    /// Вопрос и ответ, уже разобранные сервером (26.10.2026); nil — старый сервер.
    public var questionBlocks: [ChatServerBlock]? = nil
    public var answerBlocks: [ChatServerBlock]? = nil
    /// Кого позвали и где он работает: комната субагента (28.10.2026).
    /// Комната совпадает с чатом карточки — у обращения своей комнаты нет.
    public var recipientID: String? = nil
    public var childChatID: String? = nil

    /// Ответ получен. Вопрос и ответ остаются доступны в карточке.
    /// Ошибка и отмена не считаются полученным ответом.
    public var isAnswered: Bool { status == "answered" }

    enum CodingKeys: String, CodingKey {
        case requesterName = "requester_name"
        case recipientName = "recipient_name"
        case createdAt = "created_at"
        case lastActivityAt = "last_activity_at"
        case question, status, activity, answer, terminal
        case questionBlocks = "question_blocks"
        case answerBlocks = "answer_blocks"
        case recipientID = "recipient_id"
        case childChatID = "child_chat_id"
    }
}

/// Сдача этапа в чате: выжимка отчёта роли и id полного документа.
public struct RoleChatHandoff: Decodable, Sendable, Equatable {
    public let noteID: String
    public let stepTitle: String?
    public let summary: String
    /// Выжимка, уже разобранная сервером (26.10.2026); nil — старый сервер.
    public var summaryBlocks: [ChatServerBlock]? = nil

    enum CodingKeys: String, CodingKey {
        case summary
        case summaryBlocks = "summary_blocks"
        case noteID = "note_id"
        case stepTitle = "step_title"
    }
}

/// Шаги хода роли, сохранённые вместе с ответом (`chat_messages.steps`).
public struct RoleChatSteps: Decodable, Sendable, Equatable {
    public let durationMs: Int
    public let items: [RoleChatLiveItem]
    /// Расход хода: токены, кэш, цена (сервер с 19.10.2026; старые — nil).
    public let usage: RoleTurnUsage?
    /// Файлы, которые роль поменяла за ход (сервер с 27.10.2026; старые — nil).
    let codeChanges: TurnCodeChanges?

    enum CodingKeys: String, CodingKey {
        case items, usage
        case durationMs = "duration_ms"
        case codeChanges = "code_changes"
    }

    /// Пункты шагов без текста, который уже показывает ответ.
    ///
    /// Сервер шлёт в шагах текст ответа (у конверта — плоскую
    /// markdown-копию). Напечатать и его, и собранный ответ — значит показать
    /// один и тот же ответ дважды (владелец 30.10.2026).
    public func itemsWithoutAnswerText(of message: RoleChatMessage) -> [RoleChatLiveItem] {
        RoleChatLiveTurn.withoutAnswerText(items, of: message)
    }

    public var stepCount: Int { items.filter(\.isStep).count }
    /// Есть что показать свёрнутой строкой: шаги или размышления.
    public var hasDetails: Bool { items.contains { !$0.isText } }
}

/// Расход хода роли — строка под ответом в чате. `input` — без кэша.
public struct RoleTurnUsage: Decodable, Sendable, Equatable {
    public let input: Int
    public let output: Int
    public let cacheRead: Int
    public let cacheWrite: Int
    public let costUSD: Double?
    public let generationMs: Int?
    public let model: String?
    /// Размер беседы на одном обращении к модели; nil — старый ответ.
    public let context: Int?
    /// Обращений к модели (шагов) за ответ.
    public let calls: Int?

    enum CodingKeys: String, CodingKey {
        case input, output, model, context, calls
        case cacheRead = "cache_read"
        case cacheWrite = "cache_write"
        case costUSD = "cost_usd"
        case generationMs = "generation_ms"
    }

    /// Токенов в секунду на генерации; nil — время не замерено.
    public var tokensPerSecond: Double? {
        guard let ms = generationMs, ms > 0, output > 0 else { return nil }
        return Double(output) / (Double(ms) / 1000)
    }

    /// Доля входа, прочитанная из кэша, 0…1; nil — входа нет.
    public var cacheHitRatio: Double? {
        let total = input + cacheRead + cacheWrite
        return total > 0 ? Double(cacheRead) / Double(total) : nil
    }
}

/// Элемент хода роли — кусок текста, шаг (вызов инструмента) или
/// размышление. Сервер отдаёт голое имя инструмента и короткую подпись из
/// аргументов (путь, команда); действие по-русски выбирает клиент
/// (`RoleLiveStepKind`).
public enum RoleChatLiveItem: Decodable, Sendable, Equatable, Identifiable {
    case text(String)
    case step(RoleChatLiveStep)
    case thinking(RoleChatThinking)

    public var id: String {
        switch self {
        case .text(let text): return "text-\(text.hashValue)"
        case .step(let step): return step.id
        case .thinking(let thinking): return thinking.id
        }
    }

    public var isStep: Bool {
        if case .step = self { return true }
        return false
    }

    /// Идентификатор действия: у шага и у размышления он свой, у текста — нет.
    /// По нему видно, какие пункты уже показаны (пейсер, слияние снимка).
    public var actionID: String? {
        switch self {
        case .text: return nil
        case .step(let step): return "step:" + step.id
        case .thinking(let thinking): return "thinking:" + thinking.id
        }
    }

    public var isText: Bool {
        if case .text = self { return true }
        return false
    }

    private enum CodingKeys: String, CodingKey { case kind, text, blocks }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "text":
            let text = try container.decode(String.self, forKey: .text)
            // Сервер разложил реплику на блоки (26.10.2026) — запоминаем их
            // для пейсера и экрана; старый сервер их не шлёт.
            if let blocks = try? container.decodeIfPresent([ChatLiveBlock].self, forKey: .blocks), !blocks.isEmpty {
                ChatLiveBlockRegistry.shared.register(blocks, for: text)
            }
            self = .text(text)
        case "thinking":
            self = .thinking(try RoleChatThinking(from: decoder))
        default:
            self = .step(try RoleChatLiveStep(from: decoder))
        }
    }
}

/// Размышление роли (владелец 30.09.2026): полный текст, пока идёт — растёт.
/// В чате свёрнуто в строку «Думает…»/«Размышления · 12 с»; текст виден в
/// раскрытом окошке или в шторке по тапу.
public struct RoleChatThinking: Decodable, Sendable, Equatable {
    public let id: String
    public let text: String
    public let isRunning: Bool
    public let startedAt: String?
    public let endedAt: String?

    public init(id: String, text: String, isRunning: Bool, startedAt: String? = nil, endedAt: String? = nil) {
        self.id = id
        self.text = text
        self.isRunning = isRunning
        self.startedAt = startedAt
        self.endedAt = endedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, status, blocks
        case startedAt = "started_at"
        case endedAt = "ended_at"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        isRunning = (try container.decodeIfPresent(String.self, forKey: .status) ?? "running") == "running"
        startedAt = try container.decodeIfPresent(String.self, forKey: .startedAt)
        endedAt = try container.decodeIfPresent(String.self, forKey: .endedAt)
        // Размышление, разобранное сервером, — тем же реестром, что и реплики.
        if let blocks = try? container.decodeIfPresent([ChatLiveBlock].self, forKey: .blocks), !blocks.isEmpty {
            ChatLiveBlockRegistry.shared.register(blocks, for: text)
        }
    }

    /// Сколько роль думала — для «Размышления · 12 с»; идёт — nil.
    public var durationSeconds: Int? {
        RoleChatTime.seconds(from: startedAt, to: endedAt)
    }
}

enum RoleChatTime {
    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let whole = Date.ISO8601FormatStyle()

    /// Кэш разбора дат. Лента пересчитывается на каждом снимке живого ответа
    /// (сервер шлёт их раз в 150 мс), а дата каждого сообщения истории при
    /// этом разбиралась заново — при сравнении в сортировке это разбиралось
    /// по несколько раз на сообщение. Тот же приём, что в `ChatDayLabel`.
    nonisolated(unsafe) private static let dates = NSCache<NSString, NSDate>()

    static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        if let cached = dates.object(forKey: value as NSString) { return cached as Date }
        // Сервер шлёт «yyyy-MM-dd HH:mm:ss» — такой каноничный вид разбирается
        // быстрым разборщиком из Core, без промежуточной строки и ISO8601.
        let parsed = DateFormats.sqliteUTC(value)
        if let parsed { dates.setObject(parsed as NSDate, forKey: value as NSString) }
        return parsed
    }

    static func seconds(from start: String?, to end: String?) -> Int? {
        guard let start = date(start), let end = date(end) else { return nil }
        return max(0, Int(end.timeIntervalSince(start).rounded()))
    }
}

/// Правило роста живого хода: список показанных действий только растёт.
///
/// Снимок хода приходит и позже дельт — после переподключения, разрыва
/// нумерации или сброса состояния, когда владелец написал новое сообщение. В
/// таком снимке пунктов может быть меньше, чем уже видно. Принять его значит
/// схлопнуть живой пузырь на десятки-сотни пунктов — а лента держится за низ,
/// поэтому она уезжает вниз и возвращается обратно (владелец 30.10.2026;
/// замер и разбор — `docs/2026-10-25-chat-shake.md`).
///
/// Исключение — законченный ход: там список заменяется содержимым готового
/// ответа один раз и это и есть смена строки.
enum RoleLiveTurnGrowth {
    static func accepts(shown: [String], incoming: [String], isFinal: Bool = false) -> Bool {
        if isFinal { return true }
        return Set(shown).isSubset(of: Set(incoming))
    }
}

/// Локальная очередь показа ответа. Сервер присылает накопленные снимки
/// раз в 150 мс, а экран выпускает текст с ровной скоростью по словам:
/// скорость плавно подстраивается под очередь, поэтому поток не идёт
/// рывками «пачка — пауза — пачка» (владелец 30.09.2026). Шаги и
/// размышления видны сразу, как только до них дошёл текст.
struct RoleLiveTextPacer {
    private(set) var target: [RoleChatLiveItem] = []
    private(set) var visibleCharacters: [Int] = []
    /// Текущая скорость, символов в секунду — ей же рендер проявляет хвост.
    private(set) var rate: Double = Self.minRate
    /// Когда видимый текст последний раз вырос.
    private(set) var lastRevealAt: Date = .distantPast
    private(set) var lastPresentationAt: Date = .distantPast
    private var texts: [[Character]] = []
    private var immediateText: Set<Int> = []
    private var budget: Double = 0
    /// Проявленные действия — по id, не по индексу. Сервер вправе убрать из
    /// снимка законченное пустое размышление, и индексы сдвигаются: по
    /// индексу проявленное действие терялось, видимый список обрезался, живой
    /// пузырь схлопывался на полосу, а лента, привязанная к низу, прыгала
    /// вниз и тут же обратно (владелец 25.10.2026).
    private var revealedActions: Set<String> = []
    private var actionWait: TimeInterval = 0
    static let actionInterval: TimeInterval = 0.4
    static let initialBuffer: TimeInterval = 0
    private var initialDelay: TimeInterval = Self.initialBuffer
    private var completionRemaining: TimeInterval?

    /// После сдачи остаток дописывается за `completionDrain`, а не
    /// выскакивает разом: при запасе в `targetLag` это был бы заметный
    /// скачок в конце ответа (владелец 14.10.2026: «ни задержек, ни рывков»).
    mutating func finish() {
        guard completionRemaining == nil else { return }
        let pendingActions = target.compactMap { Self.actionID($0) }.filter {
            !revealedActions.contains($0)
        }.count
        completionRemaining = max(Self.completionDrain,
            Double(pendingCharacters) / Self.maxRate
            + Double(pendingActions) * Self.actionInterval + actionWait + Self.tailWait)
        initialDelay = 0
    }
    static let completionDrain: TimeInterval = 0.8
    /// Сколько очередь стоит без новых слов — недописанное сервером слово
    /// показываем, только если продолжения долго нет.
    private var stall: TimeInterval = 0

    // Владелец 14.10.2026: текст должен идти ровно, как печать, без разгонов
    // и остановок. Запас в 0,6 с перекрывает паузы сервера между снимками,
    // а скорость меняется медленно — рывок «пачка пришла» в неё не проходит.
    // До этого было 120…1200 зн/с при запасе 0,15 с: экран гнался за сетью.
    static let minRate: Double = 60
    static let maxRate: Double = 900
    /// На сколько секунд экран в среднем отстаёт от сервера.
    static let targetLag: TimeInterval = 0.6
    /// За сколько секунд скорость подтягивается к нужной: разгон и торможение.
    static let rateRise: TimeInterval = 1.2
    static let rateFall: TimeInterval = 2.5
    /// Сколько ждать продолжения оборванного слова в конце снимка.
    static let tailWait: TimeInterval = 0.15

    mutating func ingest(_ incoming: [RoleChatLiveItem], isFinal: Bool = false) {
        // Rich blocks bypass the prose clock, including unfinished blocks whose
        // renderer shows a placeholder. Keep raw fences for the existing parser.
        var items: [RoleChatLiveItem] = []
        var immediate: Set<Int> = []
        for item in incoming {
            if case .text(let text) = item {
                for (part, isImmediate) in Self.pacingParts(text) {
                    if isImmediate { immediate.insert(items.count) }
                    items.append(.text(part))
                }
            } else { items.append(item) }
        }
        // Показанный живой ход не укорачивается. Снимок хода приходит и позже
        // дельт (переподключение, разрыв нумерации, сброс после нового
        // сообщения владельца) и вправе убрать пункт, который уже виден.
        // Принять такой список — схлопнуть пузырь и уронить ленту вниз, а
        // потом уронить её обратно, когда пункты проявятся заново (владелец
        // 30.10.2026; разбор 25.10.2026 `docs/2026-10-25-chat-shake.md`).
        guard isFinal || RoleLiveTurnGrowth.accepts(
            shown: target.compactMap { Self.actionID($0) },
            incoming: items.compactMap { Self.actionID($0) }
        ) else { return }
        immediateText = immediate
        // Текст узнаём по порядку среди текстовых пунктов: сервер их только
        // дописывает, поэтому номер текста не меняется. Действия — по id.
        var oldTexts: [(chars: [Character], visible: Int)] = []
        for index in target.indices {
            guard case .text = target[index] else { continue }
            oldTexts.append((chars: texts[index], visible: visibleCharacters[index]))
        }
        var next = Array(repeating: 0, count: items.count)
        var nextTexts: [[Character]] = Array(repeating: [], count: items.count)
        var textOrdinal = 0
        for index in items.indices {
            guard case .text(let new) = items[index] else { continue }
            let chars = Array(new)
            nextTexts[index] = chars
            if immediateText.contains(index) {
                next[index] = chars.count
            } else if textOrdinal < oldTexts.count {
                let old = oldTexts[textOrdinal]
                let shown = old.visible
                if chars.count >= shown, old.chars.count >= shown,
                   shown == 0 || Array(old.chars[0..<shown]) == Array(chars[0..<shown]) {
                    next[index] = shown
                }
            }
            textOrdinal += 1
        }
        // Проявленными остаются те же действия, что и были: по id, а не по
        // индексу — индексы сдвигаются, когда сервер убирает законченное
        // пустое размышление из снимка.
        var liveIDs = Set<String>()
        for item in items {
            if let id = Self.actionID(item) { liveIDs.insert(id) }
        }
        revealedActions = revealedActions.filter { liveIDs.contains($0) }
        target = items
        texts = nextTexts
        visibleCharacters = next
        // A final REST/socket payload can add text after the end signal.
        // Recompute its drain budget instead of flushing it on the old deadline.
        if completionRemaining != nil {
            completionRemaining = nil
            finish()
        }
    }

    private static func actionID(_ item: RoleChatLiveItem) -> String? { item.actionID }

    var pendingCharacters: Int {
        texts.indices.reduce(0) { $0 + max(0, texts[$1].count - visibleCharacters[$1]) }
    }

    var hasPendingText: Bool {
        pendingCharacters > 0 || target.contains { item in
            guard let id = Self.actionID(item) else { return false }
            return !revealedActions.contains(id)
        }
    }

    /// Шаг часов на `elapsed` секунд. Возвращает true, пока в очереди
    /// остаются символы.
    @discardableResult
    mutating func advance(elapsed: TimeInterval, now: Date = .now) -> Bool {
        if let remaining = completionRemaining {
            let next = max(0, remaining - elapsed)
            completionRemaining = next
            if next == 0 { flush(now: now); return false }
        }
        let pending = pendingCharacters
        guard hasPendingText else {
            budget = 0
            stall = 0
            return false
        }
        // В начале копим небольшой запас, чтобы сгладить следующие паузы сервера.
        if pending > 0 && initialDelay > 0 {
            initialDelay = max(0, initialDelay - elapsed)
            return true
        }
        // Скорость тянется к «очередь уйдёт за targetLag», но плавно — без
        // скачков, из-за которых поток то бежит, то встаёт.
        let desired = min(Self.maxRate, max(Self.minRate, Double(pending) / Self.targetLag))
        if let remaining = completionRemaining {
            // Дописываем остаток к сроку, не сбавляя уже набранной скорости.
            rate = min(Self.maxRate, max(rate, Double(pending) / max(remaining, 0.016)))
        } else {
            let blend = min(1, elapsed / (desired > rate ? Self.rateRise : Self.rateFall))
            rate += (desired - rate) * blend
        }
        budget += rate * elapsed
        stall += elapsed

        actionWait = max(0, actionWait - elapsed)
        guard let index = target.indices.first(where: {
            if case .text = target[$0] { return visibleCharacters[$0] < texts[$0].count }
            guard let id = Self.actionID(target[$0]) else { return false }
            return !revealedActions.contains(id)
        }) else {
            return false
        }
        if case .text = target[index] {
            // Продолжаем текст только после выдержанного интервала действия.
            guard actionWait == 0 else { return true }
        } else {
            guard actionWait == 0 else { return true }
            revealedActions.insert(Self.actionID(target[index]) ?? "")
            actionWait = Self.actionInterval
            budget = 0
            lastPresentationAt = now
            return hasPendingText
        }
        let chars = texts[index]
        // Текст, за которым уже идёт шаг, дописан; у последнего куска
        // хвостовое слово может быть оборвано снимком посередине.
        let mayGrow = index == texts.count - 1
        var shown = visibleCharacters[index]
        let before = shown
        while shown < chars.count {
            // Конец следующего слова: пробелы перед ним и само слово.
            var stop = shown
            while stop < chars.count, chars[stop].isWhitespace { stop += 1 }
            while stop < chars.count, !chars[stop].isWhitespace { stop += 1 }
            let cost = Double(stop - shown)
            if mayGrow && stop == chars.count {
                // Продолжение слова ещё может прийти. Ждём его, не копя
                // бюджет впрок (иначе после ожидания вышел бы рывок); долго
                // не приходит — показываем как есть.
                if stall < Self.tailWait {
                    budget = min(budget, cost)
                    break
                }
                budget = 0
                shown = stop
                break
            }
            if cost > budget { break }
            budget -= cost
            shown = stop
        }
        if shown > before {
            visibleCharacters[index] = shown
            lastRevealAt = now
            lastPresentationAt = now
            stall = 0
        }
        return hasPendingText
    }

    /// Показать восстановленный снимок без повторного проигрывания.
    mutating func flush(now: Date = .now) {
        for index in texts.indices { visibleCharacters[index] = texts[index].count }
        revealedActions = Set(target.compactMap { Self.actionID($0) })
        actionWait = 0
        initialDelay = 0
        lastRevealAt = .distantPast
        lastPresentationAt = .distantPast
        budget = 0
    }

    var visibleItems: [RoleChatLiveItem] {
        var result: [RoleChatLiveItem] = []
        var blocked = false
        for index in target.indices {
            switch target[index] {
            case .text:
                let count = visibleCharacters[index]
                let chars = texts[index]
                if immediateText.contains(index) {
                    result.append(target[index])
                } else if !blocked {
                    if count > 0 { result.append(.text(String(chars[0..<count]))) }
                    if count < chars.count { blocked = true }
                }
            case .step, .thinking:
                if blocked { continue }
                guard let id = Self.actionID(target[index]), revealedActions.contains(id) else {
                    blocked = true; continue
                }
                result.append(target[index])
            }
        }
        return result
    }

    /// Fence boundaries use String indices so Unicode and CRLF remain intact.
    /// Ordinary code fences are consumed as pairs and never treated as HTML.
    ///
    /// Регулярку компилируем ОДИН РАЗ: `pacingParts` зовётся на каждый снимок
    /// ответа для каждого его текстового элемента, а компиляция выражения
    /// каждый раз — это отдельная работа на каждый вызов.
    private static let fenceRegex = try? NSRegularExpression(pattern: #"(?m)^[ \t]*```([^\r\n]*)(?:\r?\n|$)"#)

    private static func pacingParts(_ text: String) -> [(String, Bool)] {
        // Куски по блокам сервера: обычный текст — по словам, остальное — сразу.
        if let blocks = ChatLiveBlockRegistry.shared.blocks(for: text) {
            let parts = blocks.filter { !$0.source.isEmpty }.map { ($0.source, !$0.isProse) }
            if !parts.isEmpty { return parts }
        }
        // Старый сервер без блоков — границы блоков ищем в тексте сами.
        guard let regex = fenceRegex else { return [(text, false)] }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var parts: [(String, Bool)] = []
        var consumed = text.startIndex
        var index = 0
        while index < matches.count {
            let opening = matches[index]
            let language = Range(opening.range(at: 1), in: text).map {
                text[$0].trimmingCharacters(in: .whitespaces).lowercased()
            } ?? ""
            let special = ChatRichContent.htmlLanguages.contains(language) || ChatRichContent.widgetLanguages.contains(language)
            let closing = index + 1 < matches.count ? matches[index + 1] : nil
            if special, let begin = Range(opening.range, in: text)?.lowerBound {
                var end = closing.flatMap { Range($0.range, in: text)?.upperBound } ?? text.endIndex
                if end < text.endIndex, text[end] == "\n" { end = text.index(after: end) }
                if consumed < begin { parts.append((String(text[consumed..<begin]), false)) }
                parts.append((String(text[begin..<end]), true))
                consumed = end
            }
            index += closing == nil ? 1 : 2
        }
        if consumed < text.endIndex { parts.append((String(text[consumed...]), false)) }
        return parts.isEmpty ? [(text, false)] : parts
    }

}

public struct RoleChatLiveStep: Decodable, Sendable, Equatable {
    public enum Status: String, Decodable, Sendable {
        case running, done, error
    }

    public let id: String
    public let tool: String
    public let detail: String?
    public let status: Status
    public let startedAt: String?
    public let endedAt: String?
    /// False when the client merely stopped animating a running step.
    public let resultReceived: Bool
    /// Точные аргументы вызова и ответ инструмента (сервер с 20.10.2026):
    /// владелец разбирает сбой шага сам. У старых снимков — nil.
    public var args: String? = nil
    public var output: String? = nil
    /// В лёгкой проекции истории (29.10.2026) тела шага не присылаются, но
    /// сервер говорит, что они есть. Тогда телефон достанет их по шагу —
    /// когда владелец раскроет шаг, а не заранее.
    public var hasArgs = false
    public var hasOutput = false

    public init(id: String, tool: String, detail: String?, status: Status,
                startedAt: String? = nil, endedAt: String? = nil, resultReceived: Bool? = nil) {
        self.id = id
        self.tool = tool
        self.detail = detail
        self.status = status
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.resultReceived = resultReceived ?? (status != .running)
    }

    private enum CodingKeys: String, CodingKey {
        case id, tool, detail, status, args, output
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case hasArgs = "has_args"
        case hasOutput = "has_output"
    }

    /// Сколько шёл шаг — для шторки с подробностями; идёт — nil.
    public var durationSeconds: Int? {
        RoleChatTime.seconds(from: startedAt, to: endedAt)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        tool = try container.decode(String.self, forKey: .tool)
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
        // Незнакомый статус (сервер новее клиента) — считаем шаг идущим,
        // а не роняем весь снимок хода.
        let raw = try container.decodeIfPresent(String.self, forKey: .status) ?? "running"
        status = Status(rawValue: raw) ?? .running
        resultReceived = status != .running
        startedAt = try container.decodeIfPresent(String.self, forKey: .startedAt)
        endedAt = try container.decodeIfPresent(String.self, forKey: .endedAt)
        args = try container.decodeIfPresent(String.self, forKey: .args)
        output = try container.decodeIfPresent(String.self, forKey: .output)
        hasArgs = try container.decodeIfPresent(Bool.self, forKey: .hasArgs) ?? false
        hasOutput = try container.decodeIfPresent(Bool.self, forKey: .hasOutput) ?? false
    }
}

/// Идущий сейчас ход роли в чате (`chats:live`, `GET /chats/:id/live`):
/// текст ответа растёт по словам, между кусками текста — шаги.
public struct RoleChatLiveTurn: Decodable, Sendable, Equatable {
    public let chatID: String
    public let userID: String
    public let name: String
    public let startedAt: String?
    public let items: [RoleChatLiveItem]
    /// Роль сейчас думает (28.09.2026): последняя законченная фраза её
    /// размышлений; "" — думает, фразы ещё нет; nil — не думает.
    public let thinking: String?
    public var triggerMessageID: String? = nil

    enum CodingKeys: String, CodingKey {
        case name, items, thinking
        case triggerMessageID = "trigger_message_id"
        case chatID = "chat_id"
        case userID = "user_id"
        case startedAt = "started_at"
    }

    /// Когда ход начался — для счётчика «идёт 42 с».
    public var startDate: Date? { RoleChatTime.date(startedAt) }

    /// Идущее размышление из элементов хода; у сервера до 30.09.2026 его
    /// нет — тогда «думает» видно только по полю `thinking`.
    public var runningThinking: RoleChatThinking? {
        for item in items.reversed() {
            if case .thinking(let thinking) = item, thinking.isRunning { return thinking }
        }
        return nil
    }
}


extension RoleChatWorkMode {
    static func available(in chat: RoleChat) -> [Self] {
        available(for: chat.composerRoleKeys)
    }
}

extension RoleChat {
    var composerRoleKeys: [String] {
        members.compactMap { member in
            member.roleKey ?? (member.id == "u-secretary" ? "secretary" : member.id.hasPrefix("role_") ? String(member.id.dropFirst(5)) : nil)
        }
    }
    var isAssistantOnly: Bool { ChatComposerPolicy.isAssistantOnly(composerRoleKeys) }
    /// Способ выполнения для отправки. До 31.10.2026 у Помощника здесь был
    /// жёсткий `.chat`; владелец это отменил: Помощник тоже умеет вести
    /// карточку, а режим по умолчанию в его комнате остаётся «в чате».
    var composerExecutionMode: ChatExecutionMode { executionMode }
}


extension RoleChatLiveTurn {
    var playbackID: String { userID + ":" + (startedAt ?? "live") }
    func ending(at date: Date = .now) -> Self {
        let end = date.ISO8601Format()
        let finishedItems = items.map { item -> RoleChatLiveItem in
            switch item {
            case .text: return item
            case .thinking(let thought):
                return .thinking(RoleChatThinking(id: thought.id, text: thought.text, isRunning: false,
                    startedAt: thought.startedAt, endedAt: thought.endedAt ?? end))
            case .step(let step):
                var ended = RoleChatLiveStep(id: step.id, tool: step.tool, detail: step.detail,
                    status: step.status == .running ? .done : step.status,
                    startedAt: step.startedAt, endedAt: step.endedAt ?? end, resultReceived: step.resultReceived)
                ended.args = step.args
                ended.output = step.output
                return .step(ended)
            }
        }
        return Self(chatID: chatID, userID: userID, name: name, startedAt: startedAt,
            items: finishedItems, thinking: nil, triggerMessageID: triggerMessageID)
    }

    func isCompleted(by message: RoleChatMessage) -> Bool {
        guard message.fromUserID == userID else { return false }
        if let triggerMessageID { return message.replyToMessageID == triggerMessageID }
        guard let start = startDate, let end = RoleChatTime.date(message.createdAt) else { return true }
        // SQLite messages have whole seconds; live events retain milliseconds.
        return end.addingTimeInterval(1) > start
    }

    /// Пункты хода без текста ответа.
    ///
    /// Ответ рисуется один раз: у конверта — нативными блоками, у обычного
    /// ответа — текстом сообщения. В пунктах хода лежит тот же ответ (у
    /// конверта — плоская markdown-копия: таблица markdown, виджет сырым
    /// JSON), поэтому текст ответа из хода убирается; реплики хода, которых
    /// в ответе нет («сейчас проверю…»), остаются. Иначе один и тот же
    /// ответ виден дважды (владелец 30.10.2026).
    func itemsWithoutAnswerText(for message: RoleChatMessage) -> [RoleChatLiveItem] {
        Self.withoutAnswerText(items, of: message)
    }

    /// Убрать из пунктов текст, который уже показывает ответ.
    ///
    /// Текст ответа лежит в пунктах хода (у конверта — плоская
    /// markdown-копия: таблица markdown, виджет сырым JSON) и в `message.text`
    /// самого ответа. Пункты, где текст уже есть в ответе, убираются;
    /// реплики хода, которых в ответе нет («сейчас проверю…»), остаются.
    /// Иначе один и тот же ответ виден дважды (владелец 30.10.2026).
    static func withoutAnswerText(_ items: [RoleChatLiveItem],
                                   of message: RoleChatMessage) -> [RoleChatLiveItem] {
        // Обычный ответ печатается текстом сообщения, дублировать его в
        // пунктах хода не нужно, но и убирать нечего: там лежит тот же
        // текст ответа вперемешку с репликами хода. Сработает только
        // ответ-конверт, у которого в `message.text` лежит плоская
        // markdown-копия нативных блоков.
        guard message.hasStructuredAnswer else { return items }
        let flat = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !flat.isEmpty else { return items }
        return items.filter { item in
            guard case .text(let text) = item else { return true }
            let part = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if part.isEmpty { return true }
            return !flat.contains(part)
        }
    }

    func completed(with message: RoleChatMessage) -> Self {
        // Содержимое хода на закрытии только растёт. Раньше список подменялся
        // на `message.steps` + текст: размышления исчезали, а если сокетный
        // ответ пришёл без шагов — исчезали ВСЕ строки шагов, пузырь проседал
        // на десятки-сотни пунктов, и `refresh()` возвращал их обратно. Это
        // второй вид «шатания» — не движение прокрутки, а усадка строки под
        // ней (ревью ленты п.1.3, владелец 30.10.2026).
        // Текст сохранённого снимка заменяет промежуточные версии по порядку,
        // а не добавляется рядом: иначе остаются обрывки и полный дубль.
        let savedTexts = (message.steps?.items ?? []).compactMap { item -> String? in
            if case .text(let text) = item { return text }; return nil
        }
        var replacedTexts = 0
        var merged = savedTexts.isEmpty ? items : items.compactMap { item -> RoleChatLiveItem? in
            guard case .text = item else { return item }
            defer { replacedTexts += 1 }
            guard replacedTexts < savedTexts.count else { return nil }
            return .text(savedTexts[replacedTexts])
        }
        var savedTextIndex = 0
        var known = Set<String>()
        for item in items {
            switch item {
            case .step(let step): known.insert("step:" + step.id)
            case .thinking(let thought): known.insert("thinking:" + thought.id)
            case .text: break
            }
        }
        for item in message.steps?.items ?? [] {
            switch item {
            case .text:
                if savedTextIndex >= replacedTexts { merged.append(item) }
                savedTextIndex += 1
            case .step(let step):
                guard !known.contains("step:" + step.id) else { continue }
                known.insert("step:" + step.id)
                merged.append(item)
            case .thinking(let thought):
                guard !known.contains("thinking:" + thought.id) else { continue }
                known.insert("thinking:" + thought.id)
                merged.append(item)
            }
        }
        // Текст ответа дописывается, а не встаёт вторым абзацем: в ленте
        // последний текстовый блок хода и есть ответ.
        // У ответа с конвертом текст ответа в пунктах хода — плоская копия
        // (таблица markdown, виджет сырым JSON). Такой текст в пузыре не
        // нужен: ответ рисует конверт нативными блоками, иначе один и тот же
        // ответ виден дважды (владелец 30.10.2026).
        merged = Self.withoutAnswerText(merged, of: message)
        let finalText = message.hasStructuredAnswer ? "" : message.text
        if !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let lastText = merged.lastIndex(where: { if case .text = $0 { return true }; return false }) {
                if case .text(let shown) = merged[lastText], finalText.count >= shown.count {
                    merged[lastText] = .text(finalText)
                }
            } else {
                merged.append(.text(finalText))
            }
        }
        return Self(chatID: chatID, userID: userID, name: name, startedAt: startedAt,
             items: merged, thinking: nil,
             triggerMessageID: triggerMessageID)
    }
}

/// Идентичность строки ленты.
///
/// Раньше id строки строился как «reply:автор:на что ответ». Такая пара НЕ
/// уникальна: одна роль отвечает на одно сообщение несколькими строками —
/// сам ответ и служебные строки координации («Ответ получен», «Ход завершился
/// ошибкой») — и все они получали ОДИН id. SwiftUI на одинаковых id в
/// ForEach переиспользует строки: пузырь одного ответа встаёт на место
/// другого, текст пропадает, а лента прыгает (владелец 22.10.2026: «текста
/// нет, но он всё равно где-то»).
///
/// Теперь своя строка на каждое сообщение. Исключение — сообщение,
/// ЗАВЕРШИВШЕЕ живой ход: оно занимает строку хода, чтобы при доигрывании
/// ответа строка не пересоздавалась (пересоздание рвёт переменную высоту и
/// сбрасывает якорь прокрутки).
enum RoleChatRowID {
    static func message(_ messageID: String) -> String { "msg:\(messageID)" }
    static func turn(_ playbackID: String) -> String { "turn:\(playbackID)" }
    /// Строка для сообщения: своя или строка завершённого хода.
    static func message(_ messageID: String, completedTurn playbackID: String?) -> String {
        guard let playbackID else { return message(messageID) }
        return turn(playbackID)
    }
}

/// SQLite sequence is shared by REST and WebSocket; ties on older servers retain input order.
enum RoleChatMessageOrder {
    static func mergingSnapshot(_ snapshot: [RoleChatMessage], current: [RoleChatMessage], receivedAfterRequest: Set<String>) -> [RoleChatMessage] {
        var byID = Dictionary(snapshot.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        for message in current where receivedAfterRequest.contains(message.id) { byID[message.id] = message }
        // Идентификаторы снимка — в множество один раз: поиск по массиву внутри
        // `filter` давал O(n·m) сравнений на каждый `refresh`.
        let snapshotIDs = Set(snapshot.map(\.id))
        let order = snapshot.map(\.id) + current.filter { message in byID[message.id] != nil && !snapshotIDs.contains(message.id) }.map(\.id)
        var seen: Set<String> = []
        return sorted(order.compactMap { id in
            guard seen.insert(id).inserted else { return nil }
            return byID[id]
        })
    }

    static func sorted(_ messages: [RoleChatMessage]) -> [RoleChatMessage] {
        messages.enumerated().sorted { lhs, rhs in
            if isOrderedBefore(lhs.element, rhs.element) { return true }
            if isOrderedBefore(rhs.element, lhs.element) { return false }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    /// Вставка сообщения в ленту по серверному порядку.
    ///
    /// Раньше на КАЖДОЕ новое сообщение сортировалась вся лента: сортировка
    /// разбирала даты заново для каждой пары, а лента пересчитывается на
    /// каждом снимке живого ответа — это и было главным тормозом отрисовки.
    /// Теперь сообщение встаёт на своё место (по `sequence` — это rowid
    /// таблицы сообщений), а лента не трогается.
    static func inserting(_ message: RoleChatMessage, into messages: [RoleChatMessage]) -> [RoleChatMessage] {
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            var result = messages
            result[index] = message
            return result
        }
        var result = messages
        result.insert(message, at: insertionIndex(for: message, in: result))
        return result
    }

    /// Место нового сообщения: после всех, что не новее него. Обычное
    /// сообщение приходит последним — тогда сравнений ровно одно.
    static func insertionIndex(for message: RoleChatMessage, in messages: [RoleChatMessage]) -> Int {
        guard let last = messages.last else { return 0 }
        if isNotOrderedAfter(last, message) { return messages.count }
        var index = 0
        while index < messages.count, isNotOrderedAfter(messages[index], message) { index += 1 }
        return index
    }

    /// `sequence` (rowid) — основной порядок; у старого сервера его нет,
    /// тогда по дате создания.
    private static func isOrderedBefore(_ lhs: RoleChatMessage, _ rhs: RoleChatMessage) -> Bool {
        if let a = lhs.sequence, let b = rhs.sequence { return a < b }
        let a = RoleChatTime.date(lhs.createdAt) ?? .distantPast
        let b = RoleChatTime.date(rhs.createdAt) ?? .distantPast
        return a < b
    }

    /// «lhs не новее rhs» — для вставки: равные по времени сообщения держат
    /// порядок поступления, новое встаёт после них.
    private static func isNotOrderedAfter(_ lhs: RoleChatMessage, _ rhs: RoleChatMessage) -> Bool {
        if let a = lhs.sequence, let b = rhs.sequence { return a <= b }
        let a = RoleChatTime.date(lhs.createdAt) ?? .distantPast
        let b = RoleChatTime.date(rhs.createdAt) ?? .distantPast
        return a <= b
    }
}

public struct RoleChatPartialFlag: Decodable, Sendable, Equatable {
    public let value: Bool

    public init(value: Bool) { self.value = value }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let flag = try? container.decode(Bool.self) {
            value = flag
        } else if let number = try? container.decode(Int.self) {
            value = number != 0
        } else if let text = try? container.decode(String.self) {
            value = ["1", "true", "yes"].contains(text.lowercased())
        } else {
            value = false
        }
    }
}

/// Семя проявления при открытии комнаты (владелец 03.11.2026).
///
/// Короткий кэш/`lastMessages` мог содержать не всю историю. Тогда первое
/// обновление с сервера приносило «новые» id, и последний ответ снова
/// проявлялся блоками. Пока семя не зафиксировано первым снимком — ничего
/// не анимируем; в семя входит всё, что уже на экране после этого снимка.
enum RoleChatRevealSeed {
    static func settle(current: Set<String>?, snapshotIDs: [String], settled: Bool) -> (seed: Set<String>, settled: Bool) {
        if settled { return (current ?? [], true) }
        return ((current ?? []).union(snapshotIDs), true)
    }

    static func shouldReveal(
        messageID: String,
        seed: Set<String>?,
        settled: Bool,
        isLast: Bool,
        nearBottom: Bool,
        closedTurnMessageIDs: Set<String>
    ) -> Bool {
        guard settled else { return false }
        guard nearBottom, isLast else { return false }
        guard !closedTurnMessageIDs.contains(messageID) else { return false }
        guard let seed else { return false }
        return !seed.contains(messageID)
    }
}

