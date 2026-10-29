import Foundation

/// Вид панели ввода в чатах (владелец 29.10.2026: «ты можешь вот свою
/// предложить панель ввода, а мою как бы туда в настройки закинуть, чтобы
/// можно было переключать, если что»).
///
/// Три варианта:
/// - `standard` — нынешняя: капсула, поле сверху, ряд действий под ним;
/// - `classic`  — то же, но без «мозгов», папки и колец контекста (как до
///   27.10.2026);
/// - `unified`  — новая: всё в одну строку, поле и чипы в одной капсуле,
///   «+» и отправка снаружи.
public enum ChatComposerStyle: String, CaseIterable, Identifiable, Sendable {
    case standard
    case classic
    case unified

    public var id: String { rawValue }

    /// Ключ в `UserDefaults`: настройка живёт на устройстве, как тема и
    /// размер текста.
    public static let storageKey = "taskflow_chat_composer_style"

    /// Пока владелец не выбрал — нынешняя панель: ничего не меняется молча.
    public static let defaultStyle: ChatComposerStyle = .standard

    public var title: String {
        switch self {
        case .standard: "Текущая"
        case .classic: "Старая"
        case .unified: "Новая"
        }
    }

    /// Пояснение под названием в настройках: чем вариант отличается.
    public var note: String {
        switch self {
        case .standard: "мозг, папка и кольца контекста в ряду под полем"
        case .classic: "до 27.10 — без мозга, папки и колец"
        case .unified: "всё в одну строку: поле и чипы в одной капсуле"
        }
    }

    /// Показывать ли «мозги», папку и кольца контекста.
    public var showsToolChips: Bool { self != .classic }

    /// Одна строка вместо поля над рядом действий.
    public var isSingleRow: Bool { self == .unified }

    /// Разбор сохранённого значения: пустое и неизвестное — текущая панель.
    /// Ставится вместо «упасть на несуществующем варианте»: значение на
    /// устройстве может остаться от прежней сборки.
    public static func resolve(_ raw: String?) -> ChatComposerStyle {
        guard let raw, let style = ChatComposerStyle(rawValue: raw) else { return .defaultStyle }
        return style
    }
}
