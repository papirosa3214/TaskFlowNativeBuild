import Foundation

/// Уточнение роли у владельца из чата (серверный вопрос, 26.10.2026).
///
/// Формат — как в пакете `@juicesharp/rpiv-ask-user-question`: от одного до
/// четырёх вопросов, у каждого от двух до четырёх вариантов с пояснением.
/// Сервер — источник истины: он присылает вопрос в сообщении роли и хранит
/// его состояние (открыт / отвечен), клиент только рисует и отправляет ответ.
///
/// Старый сервер поля не присылает — тогда `question` остаётся `nil`, и лента
/// рисуется как раньше.
public struct ChatQuestion: Decodable, Sendable, Equatable {
    /// Идентификатор вопроса — по нему владелец шлёт ответ.
    public let id: String
    /// `open` — ждём ответа, `answered` — ответ получен.
    public let status: String
    /// Сами вопросы (1–4).
    public let questions: [ChatQuestionItem]
    /// Ответ владельца; `nil`, пока не отвечено.
    public let answer: [ChatQuestionAnswerEntry]?
    /// Когда вопрос задан (для подписи «ждём ответа с …»).
    public let createdAt: String?

    /// Ответ получен — карточка показывает выбранное и не даёт ответить снова.
    public var isAnswered: Bool { status == "answered" }

    enum CodingKeys: String, CodingKey {
        case id, status, questions, answer
        case createdAt = "created_at"
    }

    public init(id: String, status: String, questions: [ChatQuestionItem],
                answer: [ChatQuestionAnswerEntry]? = nil, createdAt: String? = nil) {
        self.id = id
        self.status = status
        self.questions = questions
        self.answer = answer
        self.createdAt = createdAt
    }

    /// Разбор не бросает: битый вопрос не должен рушить всё сообщение —
    /// лента важнее одного поля. Неизвестные или сломанные куски просто
    /// не рисуются.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? ""
        status = (try? c.decode(String.self, forKey: .status)) ?? "open"
        questions = (try? c.decode([ChatQuestionItem].self, forKey: .questions)) ?? []
        answer = try? c.decode([ChatQuestionAnswerEntry].self, forKey: .answer)
        createdAt = try? c.decode(String.self, forKey: .createdAt)
    }
}

/// Один вопрос с вариантами ответа.
public struct ChatQuestionItem: Decodable, Sendable, Equatable, Identifiable {
    /// Текст вопроса — то, что роль спрашивает.
    public let question: String
    /// Короткая метка (чип) — до 16 символов, необязательная.
    public let header: String?
    /// Варианты ответа: 2–4 штуки.
    public let options: [ChatQuestionOption]
    /// Можно выбрать несколько вариантов.
    public let multiSelect: Bool

    public var id: String { question }

    enum CodingKeys: String, CodingKey {
        case question, header, options
        case multiSelect = "multi_select"
    }

    public init(question: String, header: String? = nil,
                options: [ChatQuestionOption], multiSelect: Bool = false) {
        self.question = question
        self.header = header
        self.options = options
        self.multiSelect = multiSelect
    }

    /// Сервер может назвать поле и по-разному (`multiSelect` / `multi_select`) —
    /// берём любой из двух ключей.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let extra = try decoder.container(keyedBy: ExtraKeys.self)
        question = (try? c.decode(String.self, forKey: .question)) ?? ""
        header = try? c.decode(String.self, forKey: .header)
        options = (try? c.decode([ChatQuestionOption].self, forKey: .options)) ?? []
        multiSelect = (try? c.decode(Bool.self, forKey: .multiSelect))
            ?? (try? extra.decode(Bool.self, forKey: .camelMultiSelect))
            ?? false
    }

    private enum ExtraKeys: String, CodingKey {
        case camelMultiSelect = "multiSelect"
    }
}

/// Вариант ответа: короткая метка и пояснение — что выбор значит.
public struct ChatQuestionOption: Decodable, Sendable, Equatable, Identifiable {
    public let label: String
    public let description: String?

    public var id: String { label }

    enum CodingKeys: String, CodingKey {
        case label, description
    }

    public init(label: String, description: String? = nil) {
        self.label = label
        self.description = description
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = (try? c.decode(String.self, forKey: .label)) ?? ""
        description = try? c.decode(String.self, forKey: .description)
    }
}

/// Ответ владельца по одному вопросу: выбранные метки и свой текст.
public struct ChatQuestionAnswerEntry: Codable, Sendable, Equatable {
    /// Номер вопроса в массиве — по нему ответ и разбирается обратно.
    public let questionIndex: Int
    /// Метки выбранных вариантов (пусто, если владелец ответил своим текстом).
    public let selected: [String]
    /// Свой ответ словами — как «Type something.» в пакете.
    public let custom: String?

    public init(questionIndex: Int, selected: [String], custom: String? = nil) {
        self.questionIndex = questionIndex
        self.selected = selected
        self.custom = custom
    }

    /// Ответ не пустой: хоть что-то выбрано или написано.
    public var isEmpty: Bool {
        selected.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            && (custom?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    enum CodingKeys: String, CodingKey {
        case questionIndex, selected, custom
    }

    /// Разбор терпим к обоим написаниям номера вопроса.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let snake = try decoder.container(keyedBy: SnakeKeys.self)
        questionIndex = (try? c.decode(Int.self, forKey: .questionIndex))
            ?? (try? snake.decode(Int.self, forKey: .questionIndex))
            ?? 0
        selected = (try? c.decode([String].self, forKey: .selected)) ?? []
        custom = try? c.decode(String.self, forKey: .custom)
    }

    private enum SnakeKeys: String, CodingKey {
        case questionIndex = "question_index"
    }
}

/// Тело ответа, которое уходит на сервер.
public struct ChatQuestionAnswerPayload: Encodable, Sendable {
    public let answers: [ChatQuestionAnswerEntry]
    public let note: String?

    public init(answers: [ChatQuestionAnswerEntry], note: String? = nil) {
        self.answers = answers
        self.note = note
    }
}
