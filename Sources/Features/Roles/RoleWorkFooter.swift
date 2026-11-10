import Foundation

/// Подпись работы роли — тем же словом и порядком у живого хода и в истории.
///
/// Владелец 10.11.2026: «как в T3 — работа свёрнута полосой, время тикает, но
/// не дёргает ленту». Считать текст отдельной функцией нужно ещё и потому, что
/// тикающую подпись рисует отдельная вьюха (`ChatTickingText`) и её текст
/// проверяется тестом на хосте, а не глазами на телефоне.
enum RoleWorkFooter {
    /// «Работает · 1 мин 20 с · 5 шагов» — что показать под ходом.
    /// - Parameters:
    ///   - state: слово состояния («Работает», «Остановлено», «Ответ получен»).
    ///   - startedAt: когда ход начался; nil — время не показываем.
    ///   - steps: сколько шагов уже сделано.
    ///   - now: текущий момент (у законченного хода — время завершения).
    static func text(state: String, startedAt: Date?, steps: Int, now: Date) -> String {
        var parts = [state]
        if let startedAt {
            let seconds = Int(max(0, now.timeIntervalSince(startedAt)))
            parts.append(RoleLiveFormat.duration(seconds: seconds))
        }
        if steps > 0 {
            parts.append(RoleLiveFormat.steps(steps))
        }
        return parts.joined(separator: " · ")
    }

    /// «7 шагов · думал 1 мин» — что написать на полосе работы.
    static func summary(stepCount: Int, thinkingSeconds: Int) -> String {
        var parts: [String] = []
        if stepCount > 0 { parts.append(RoleLiveFormat.steps(stepCount)) }
        if thinkingSeconds >= 1 {
            parts.append("думал " + RoleLiveFormat.duration(seconds: thinkingSeconds))
        }
        return parts.joined(separator: " · ")
    }

    /// Показывать ли свёрнутую работу у готового сообщения: должны быть шаги
    /// или размышления, и не режим выбора.
    static func shouldShowWork(hasDetails: Bool, isSelecting: Bool) -> Bool {
        hasDetails && !isSelecting
    }
}
