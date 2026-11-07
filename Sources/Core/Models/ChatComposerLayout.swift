import Foundation

/// Вид панели ввода в покое (владелец 29.10.2026: «два состояния этого
/// панели… когда я сворачиваю опять клавиатуру, он опять в маленький не
/// превращается»).
public enum ChatComposerLayout: String, Equatable, Sendable {
    /// Однострочная: круглая кнопка слева, капсула с полем, круглый микрофон
    /// справа.
    case compact
    /// Привычная панель целиком: поле сверху, ряд действий под ним.
    case full
}

/// Событие, после которого решается, ставить ли каретку в поле.
public enum ChatComposerFocusEvent: String, Equatable, Sendable {
    /// Нажат микрофон — началась диктовка.
    case microphonePressed
    /// Расшифровка вставлена в черновик.
    case transcriptionInserted
    /// Вставлено упоминание «@Имя».
    case mentionInserted
}

/// Правила панели ввода, вынесенные из вью — их можно проверить на хосте.
public enum ChatComposerLayoutPolicy {
    /// Какая панель показывается.
    ///
    /// Родная панель всегда полная. Новая — однострочная, пока ввода нет:
    /// как только в черновике есть текст, панель разворачивается в полную;
    /// когда текст убрали и клавиатуру свернули, сжимается обратно.
    ///
    /// `isFocused` — поле ввода в фокусе: панель разворачивается по касанию.
    /// Поле ввода при этом **не подменяется** — оно одно на оба вида, поэтому
    /// динамика окна безопасна для каретки (владелец 30.10.2026).
    public static func layout(style: ChatComposerStyle, isFocused: Bool,
                              hasText: Bool) -> ChatComposerLayout {
        switch style {
        case .standard: return .full
        case .unified: return (isFocused || hasText) ? .full : .compact
        }
    }

    /// Ставить ли каретку в поле.
    ///
    /// Микрофон каретку не ставит: на неё реагирует клавиатура, а при
    /// диктовке она владельцу не нужна (29.10.2026). После расшифровки —
    /// тоже: текст уже в поле, а править его можно по тапу. Упоминание
    /// вставляется по тапу на «@» — там каретка нужна.
    public static func focusesField(_ event: ChatComposerFocusEvent) -> Bool {
        switch event {
        case .microphonePressed, .transcriptionInserted: return false
        case .mentionInserted: return true
        }
    }
}

/// Содержимое окна сессии: вложения и режимы работы — блоками, а не строками
/// списка (владелец 29.10.2026: «не обязательно все списком этим делать…
/// можно же сделать именно карточки, такие же самые… фото, файл, камера в
/// самом начале сделано прикольно»).
public enum ChatSessionAttachment: String, CaseIterable, Identifiable, Sendable {
    case photo
    case file
    case camera

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .photo: "Фото"
        case .file: "Файл"
        case .camera: "Камера"
        }
    }

    public var symbol: String {
        switch self {
        case .photo: "photo.on.rectangle"
        case .file: "doc"
        case .camera: "camera"
        }
    }
}

/// Режимы работы в окне сессии.
public enum ChatSessionWorkModePolicy {
    /// Режимы окна сессии (владелец 07.11.2026): исследование скрыто.
    public static let allModes: [RoleChatWorkMode] = [.work, .plan, .goal]

    public static func visibleSelection(_ mode: RoleChatWorkMode) -> RoleChatWorkMode {
        allModes.contains(mode) ? mode : .work
    }

    /// Глубокое исследование сервер принимает только в чате с Исследователем
    /// или с Помощником владельца (`routes/chats.ts`).
    public static func allowsResearch(roles: [String]) -> Bool {
        roles.contains("researcher") || roles.contains("secretary")
    }
}
