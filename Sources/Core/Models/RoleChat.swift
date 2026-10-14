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
    public let members: [RoleChatMember]
    public let lastMessage: RoleChatPreview?
    /// Непрочитанных у ТЕКУЩЕГО пользователя (миграция 055, отметка на
    /// участнике чата). Опционально: сервер до этой правки поля не слал, и
    /// старый ответ не должен ронять декодирование.
    public let unreadCount: Int?
    /// Название задачи, к которой привязан чат (`nil` — свободный). Нужно
    /// пометкой в строке списка: по ней видно, какой чат за какой задачей.
    public let taskTitle: String?

    enum CodingKeys: String, CodingKey {
        case id, title, kind, members
        case createdBy = "created_by"
        case taskID = "task_id"
        case projectID = "project_id"
        case parentChatID = "parent_chat_id"
        case lastMessage = "last_message"
        case unreadCount = "unread_count"
        case taskTitle = "task_title"
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
    public let createdAt: String?
    public let attachments: [ApiChatAttachment]?
    /// Задача, которую роль создала этим ходом (владелец 25.09.2026,
    /// docs/ПЛАН Супер Секретарь/, этап 2) — есть значение → вместо текста
    /// рисуется карточка (см. RoleChatsScreen).
    public let taskID: String?
    public let taskTitle: String?
    /// Быстрые ответы (владелец 25.09.2026, docs/ПЛАН Супер Секретарь/) —
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
    public var handoff: RoleChatHandoff? = nil
    public var sequence: Int? = nil

    enum CodingKeys: String, CodingKey {
        case replyToMessageID = "reply_to_message_id"
        case replyToSenderName = "reply_to_sender_name"
        case id, text, kind, attachments, steps, reactions, sequence, handoff
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
    }
}

/// Сдача этапа в чате: выжимка отчёта роли и id полного документа.
public struct RoleChatHandoff: Decodable, Sendable, Equatable {
    public let noteID: String
    public let stepTitle: String?
    public let summary: String

    enum CodingKeys: String, CodingKey {
        case summary
        case noteID = "note_id"
        case stepTitle = "step_title"
    }
}

/// Шаги хода роли, сохранённые вместе с ответом (`chat_messages.steps`).
public struct RoleChatSteps: Decodable, Sendable, Equatable {
    public let durationMs: Int
    public let items: [RoleChatLiveItem]

    enum CodingKeys: String, CodingKey {
        case items
        case durationMs = "duration_ms"
    }

    public var stepCount: Int { items.filter(\.isStep).count }
    /// Есть что показать свёрнутой строкой: шаги или размышления.
    public var hasDetails: Bool { items.contains { !$0.isText } }
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

    public var isText: Bool {
        if case .text = self { return true }
        return false
    }

    private enum CodingKeys: String, CodingKey { case kind, text }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "text":
            self = .text(try container.decode(String.self, forKey: .text))
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
        case id, text, status
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
    }

    /// Сколько роль думала — для «Размышления · 12 с»; идёт — nil.
    public var durationSeconds: Int? {
        RoleChatTime.seconds(from: startedAt, to: endedAt)
    }
}

enum RoleChatTime {
    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let whole = Date.ISO8601FormatStyle()

    static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let normalized = value.count == 19 && value.contains(" ")
            ? value.replacingOccurrences(of: " ", with: "T") + "Z" : value
        return (try? fractional.parse(normalized)) ?? (try? whole.parse(normalized))
    }

    static func seconds(from start: String?, to end: String?) -> Int? {
        guard let start = date(start), let end = date(end) else { return nil }
        return max(0, Int(end.timeIntervalSince(start).rounded()))
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
    private var revealedActions: Set<Int> = []
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
        completionRemaining = Self.completionDrain
        initialDelay = 0
        actionWait = 0
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

    mutating func ingest(_ incoming: [RoleChatLiveItem]) {
        // Rich blocks bypass the prose clock, including unfinished blocks whose
        // renderer shows a placeholder. Keep raw fences for the existing parser.
        var items: [RoleChatLiveItem] = []
        immediateText = []
        for item in incoming {
            if case .text(let text) = item {
                for (part, immediate) in Self.pacingParts(text) {
                    if immediate { immediateText.insert(items.count) }
                    items.append(.text(part))
                }
            } else { items.append(item) }
        }
        var next = Array(repeating: 0, count: items.count)
        var nextTexts: [[Character]] = Array(repeating: [], count: items.count)
        for index in items.indices {
            guard case .text(let new) = items[index] else { continue }
            let chars = Array(new)
            nextTexts[index] = chars
            if immediateText.contains(index) { next[index] = chars.count; continue }
            guard index < target.count, case .text = target[index] else { continue }
            let old = texts[index]
            let shown = visibleCharacters[index]
            if chars.count >= shown, old.count >= shown, chars[0..<shown] == old[0..<shown] {
                next[index] = shown
            }
        }
        revealedActions = revealedActions.filter { index in
            guard index < items.count, index < target.count else { return false }
            switch (target[index], items[index]) {
            case (.step(let old), .step(let new)): return old.id == new.id
            case (.thinking(let old), .thinking(let new)): return old.id == new.id
            default: return false
            }
        }
        target = items
        texts = nextTexts
        visibleCharacters = next
    }

    var pendingCharacters: Int {
        texts.indices.reduce(0) { $0 + max(0, texts[$1].count - visibleCharacters[$1]) }
    }

    var hasPendingText: Bool {
        pendingCharacters > 0 || target.indices.contains {
            if case .text = target[$0] { return false }
            return !revealedActions.contains($0)
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
            rate = max(rate, Double(pending) / max(remaining, 0.016))
            actionWait = 0
        } else {
            let blend = min(1, elapsed / (desired > rate ? Self.rateRise : Self.rateFall))
            rate += (desired - rate) * blend
        }
        budget += rate * elapsed
        stall += elapsed

        actionWait = max(0, actionWait - elapsed)
        guard let index = target.indices.first(where: {
            if case .text = target[$0] { return visibleCharacters[$0] < texts[$0].count }
            return !revealedActions.contains($0)
        }) else {
            return false
        }
        if case .text = target[index] {
            // Продолжаем текст только после выдержанного интервала действия.
            guard actionWait == 0 else { return true }
        } else {
            guard actionWait == 0 else { return true }
            revealedActions.insert(index)
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
        revealedActions = Set(target.indices.filter {
            if case .text = target[$0] { return false }; return true
        })
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
                guard revealedActions.contains(index) else { blocked = true; continue }
                result.append(target[index])
            }
        }
        return result
    }

    /// Fence boundaries use String indices so Unicode and CRLF remain intact.
    /// Ordinary code fences are consumed as pairs and never treated as HTML.
    private static func pacingParts(_ text: String) -> [(String, Bool)] {
        let pattern = #"(?m)^[ \t]*```([^\r\n]*)(?:\r?\n|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [(text, false)] }
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

    public init(id: String, tool: String, detail: String?, status: Status,
                startedAt: String? = nil, endedAt: String? = nil) {
        self.id = id
        self.tool = tool
        self.detail = detail
        self.status = status
        self.startedAt = startedAt
        self.endedAt = endedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, tool, detail, status
        case startedAt = "started_at"
        case endedAt = "ended_at"
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
        startedAt = try container.decodeIfPresent(String.self, forKey: .startedAt)
        endedAt = try container.decodeIfPresent(String.self, forKey: .endedAt)
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


/// Selected before sending; retries retain the original mode.
public enum RoleChatWorkMode: String, CaseIterable, Codable {
    case work, plan, deepResearch = "deep_research"
    var title: String {
        switch self { case .work: "Работа"; case .plan: "Планирование"; case .deepResearch: "Глубокое исследование" }
    }
    var symbol: String {
        switch self { case .work: "bolt"; case .plan: "list.bullet.clipboard"; case .deepResearch: "magnifyingglass" }
    }
    static func available(in chat: RoleChat) -> [Self] {
        chat.members.contains { $0.roleKey == "researcher" || $0.id == "role_researcher" }
            ? [.work, .plan, .deepResearch] : [.work, .plan]
    }
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
                return .step(RoleChatLiveStep(id: step.id, tool: step.tool, detail: step.detail,
                    status: step.status == .running ? .done : step.status,
                    startedAt: step.startedAt, endedAt: step.endedAt ?? end))
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

    func completed(with message: RoleChatMessage) -> Self {
        Self(chatID: chatID, userID: userID, name: name, startedAt: startedAt,
             items: (message.steps?.items ?? []) + (message.text.isEmpty ? [] : [.text(message.text)]), thinking: nil)
    }
}

/// SQLite sequence is shared by REST and WebSocket; ties on older servers retain input order.
enum RoleChatMessageOrder {
    static func mergingSnapshot(_ snapshot: [RoleChatMessage], current: [RoleChatMessage], receivedAfterRequest: Set<String>) -> [RoleChatMessage] {
        var byID = Dictionary(snapshot.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        for message in current where receivedAfterRequest.contains(message.id) { byID[message.id] = message }
        let order = snapshot.map(\.id) + current.filter { message in byID[message.id] != nil && !snapshot.contains(where: { $0.id == message.id }) }.map(\.id)
        var seen: Set<String> = []
        return sorted(order.compactMap { id in
            guard seen.insert(id).inserted else { return nil }
            return byID[id]
        })
    }

    static func sorted(_ messages: [RoleChatMessage]) -> [RoleChatMessage] {
        messages.enumerated().sorted { lhs, rhs in
            if let a = lhs.element.sequence, let b = rhs.element.sequence, a != b { return a < b }
            let a = RoleChatTime.date(lhs.element.createdAt) ?? .distantPast
            let b = RoleChatTime.date(rhs.element.createdAt) ?? .distantPast
            return a == b ? lhs.offset < rhs.offset : a < b
        }.map(\.element)
    }
}
