import Foundation

/// Вид панели ввода в покое (владелец 29.10.2026: «два состояния панели»).
public enum ChatComposerLayout: String, Equatable, Sendable {
    /// Однострочная: круглое меню действий, капсула с полем и значками и
    /// круглый микрофон вместо неактивной отправки.
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
    /// Панель в покое: однострочная, пока пользователь не начал ввод.
    /// Дальше — привычная панель целиком, и обратно она не сжимается:
    /// сжатие отняло бы каретку посреди набора.
    public static func layout(style: ChatComposerStyle, hasExpanded: Bool) -> ChatComposerLayout {
        switch style {
        case .standard: return .full
        case .unified: return hasExpanded ? .full : .compact
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
