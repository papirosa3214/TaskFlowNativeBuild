import Foundation

/// Состояние «список действий протух» для окна живого хода и ленты хода.
///
/// События активности во время хода идут пачками — примерно раз в секунду.
/// Если на каждое событие перезапрашивать снимок с сервера, окно
/// перерисовывается постоянно, а прокрутка внутри него уезжает наверх
/// (владелец 25.10.2026: до кнопки «Прервать» было не добраться).
///
/// Поэтому событие только помечает список протухшим, а забирает его
/// отдельный цикл — не чаще раза в `minimumInterval`.
final class LiveActivityRefreshState {
    /// Минимальный интервал между обновлениями списка действий.
    static let minimumInterval: Duration = .seconds(2)

    private(set) var isDirty = false
    private var lastRefreshAt: ContinuousClock.Instant?

    /// Событие активности: содержимое списка, скорее всего, изменилось.
    func markDirty() {
        isDirty = true
    }

    /// Забрать протухшее состояние.
    ///
    /// Возвращает `true`, только если список действий действительно протух и
    /// с прошлого обновления прошло достаточно времени. Иначе — `false`, и
    /// флаг остаётся: следующая проверка его заберёт.
    func takeDirty(now: ContinuousClock.Instant = .now) -> Bool {
        guard isDirty else { return false }
        if let lastRefreshAt, now - lastRefreshAt < Self.minimumInterval { return false }
        isDirty = false
        lastRefreshAt = now
        return true
    }
}
