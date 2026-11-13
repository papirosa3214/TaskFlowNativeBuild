import CoreGraphics

/// Куда довести ленту чатов после отпускания пальца (владелец 13.11.2026:
/// «должна быть упругость… аватарки отбивали поле поиска… а то сопротивление
/// вообще нету и оно улетает всё резко»).
///
/// Ряд ролей и липкая полоска проектов не уезжают от одного флика: пока
/// палец не протянул ряд за `expandedReturnFraction`, лента возвращается в
/// раскрытое состояние, и ряд отбивается обратно к поиску. Задвигает его
/// только осознанная протяжка пальцем — дальше обычное прежнее поведение по
/// ближайшему краю.
///
/// Чистая логика без SwiftUI: считается и проверяется отдельно
/// (`python3 Tools/test_chats_scroll.py`).
struct ChatStoriesScrollPolicy {
    /// Высота раскрытого ряда ролей.
    var rowHeight: CGFloat
    /// Высота поля поиска: оно тоже доводится — либо видно целиком, либо
    /// сжато в ноль (как в Telegram, владелец 12.11.2026).
    var searchHeight: CGFloat
    /// Короткий список (добран пустым местом): дальше схлопнутого поиска он не
    /// уезжает — строки не прячутся под полоску проектов (владелец 12.11.2026).
    /// `nil` — список длинный, прокручивается как обычно.
    var limit: CGFloat? = nil
    /// Какая доля ряда должна уйти за верх, чтобы отпущенная лента его
    /// задвинула. Меньше — ряд отбивается назад.
    var expandedReturnFraction: CGFloat = 0.7

    /// Куда встанет лента, если её отпустить на смещении `y`.
    /// - Parameter wasExpanded: в момент отпускания ряд был виден больше чем
    ///   наполовину, то есть его ещё не задвинули пальцем.
    func target(offset y: CGFloat, wasExpanded: Bool) -> CGFloat {
        if let limit, y > limit { return limit }
        if y <= 0 { return 0 }
        guard rowHeight > 0 else { return y }
        if y < rowHeight {
            // Флик не прячет ряд: его задвигает только палец, прошедший порог.
            if wasExpanded, y < rowHeight * expandedReturnFraction { return 0 }
            return y < rowHeight / 2 ? 0 : rowHeight
        }
        if y < rowHeight + searchHeight {
            return y < rowHeight + searchHeight / 2 ? rowHeight : rowHeight + searchHeight
        }
        return y
    }
}
