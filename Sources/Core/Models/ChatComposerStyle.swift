import Foundation

/// Вид панели ввода в чатах (владелец 29.10.2026: «свою панель ввода
/// предложить, а мою родную — оставить, чтобы можно было переключать, если
/// что», по образцу переключателя нижней панели).
///
/// Два варианта:
/// - `standard` — родная панель: капсула, поле сверху, ряд действий под ним;
/// - `unified`  — новая: всё в одну строку, поле и чипы в одной капсуле,
///   кнопка действий слева, отправка справа.
public enum ChatComposerStyle: String, CaseIterable, Identifiable, Sendable {
    case standard
    case unified

    public var id: String { rawValue }

    /// Ключ в `UserDefaults`: настройка живёт на устройстве, как тема и
    /// размер текста.
    public static let storageKey = "taskflow_chat_composer_style"

    /// Пока владелец не выбрал — родная панель: ничего не меняется молча.
    public static let defaultStyle: ChatComposerStyle = .standard

    public var title: String {
        switch self {
        case .standard: "Родная"
        case .unified: "Новая"
        }
    }

    /// Пояснение под названием в настройках: чем вариант отличается.
    public var note: String {
        switch self {
        case .standard: "как сейчас: поле в капсуле, ряд действий под ним"
        case .unified: "по макету: поле и чипы в одной капсуле, всё в одну строку"
        }
    }

    /// Одна строка вместо поля над рядом действий.
    public var isSingleRow: Bool { self == .unified }

    /// Разбор сохранённого значения: пустое и неизвестное — родная панель.
    /// Ставится вместо «упасть на несуществующем варианте»: значение на
    /// устройстве может остаться от прежней сборки.
    public static func resolve(_ raw: String?) -> ChatComposerStyle {
        guard let raw, let style = ChatComposerStyle(rawValue: raw) else { return .defaultStyle }
        return style
    }
}
