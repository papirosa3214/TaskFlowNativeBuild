import SwiftUI

/// Плавное проявление ГОТОВОГО сообщения в ленте (владелец 17.10.2026:
/// «текст появляется очень плавно, не сразу, как будто построчно
/// печатается»).
///
/// Почему нужен отдельный вид: проявление хвоста у идущего ответа уже есть
/// (`RoleTextFade`, `roleReveal`), но оно работает только пока идёт поток
/// текста. Сообщения в ленте приходят готовыми — потока нет, `fade` равен
/// nil, и текст появлялся разом. Здесь тот же механизм, но запускаемый один
/// раз на сообщение, когда оно ложится в ленту.
///
/// Задержка живёт ТОЛЬКО в отрисовке уже полученного текста: сервер отдаёт
/// сообщение целиком, вложения, карточки задач и артефакты появляются сразу
/// и анимации не ждут — иначе просьба «плавно» задела бы создание
/// артефактов. Поэтому оборачиваем только текст ответа роли.
struct RoleMessageReveal<Content: View>: View {
    /// Текст сообщения: по его длине считается темп. Пустой — не анимируем.
    let text: String
    /// Отметка сообщения: переезд ячейки на другое сообщение не должен
    /// переигрывать анимацию.
    let messageID: String
    /// Проявлять ли именно это сообщение. Владелец 17.10.2026 пожаловался,
    /// что лента «скачет вверх, остаётся пустота»: проявление старых
    /// сообщений при прокрутке дёргало автопривязку к низу. Поэтому
    /// анимируется только новое сообщение, и только когда лента внизу.
    var animate: Bool = true
    @ViewBuilder let content: () -> Content

    @State private var fade: RoleTextFade?
    @State private var finished = false

    var body: some View {
        content()
            .roleReveal(fade)
            .onAppear(perform: startIfNeeded)
            .onChange(of: messageID) { _, _ in
                // Другое сообщение в этой же ячейке — своя анимация.
                finished = false
                fade = nil
                startIfNeeded()
            }
    }

    private func startIfNeeded() {
        guard animate, !finished, !text.isEmpty else { return }
        finished = true
        let length = Double(max(text.count, 1))
        let lag = min(RoleMessageRevealTiming.maximumLag,
                      max(RoleMessageRevealTiming.minimumLag, length / 90))
        let rate = min(RoleLiveTextPacer.maxRate, max(RoleLiveTextPacer.minRate, length / lag))
        // Проявление вперёд: буквы готового сообщения печатаются по порядку,
        // а не гаснут одним куском. Идущий ответ так не проявляется — там
        // хвост (см. `RoleTextFade.revealsForward`).
        fade = RoleTextFade(rate: rate, lastRevealAt: .now, isAnimating: true, revealsForward: true)
        // Держим анимацию, пока идёт проявление, потом отпускаем отрисовку:
        // иначе TimelineView крутился бы и на готовом тексте. Считаем по
        // фактическому темпу: при упоре в максимальный темп сообщение печатается
        // дольше, чем `lag`.
        let revealDuration = length / rate
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(revealDuration * 1.15 + RoleTextFade.duration + 0.3))
            guard !Task.isCancelled else { return }
            fade = RoleTextFade(rate: rate, lastRevealAt: .now, isAnimating: false, revealsForward: true)
        }
    }
}

extension View {
    /// Оборачивает только текст ответа роли — вложения и карточки идут рядом
    /// и появляются сразу.
    func roleMessageReveal(text: String, messageID: String, animate: Bool = true) -> some View {
        RoleMessageReveal(text: text, messageID: messageID, animate: animate) { self }
    }
}

/// Темп проявления держим вне обобщённого вида: Swift не разрешает статические
/// хранимые свойства в generic-типах.
private enum RoleMessageRevealTiming {
    /// Долгую речь не растягиваем на десятки секунд: чем длиннее текст, тем
    /// быстрее идёт проявление, но нижняя граница остаётся читаемой.
    static let minimumLag: TimeInterval = 0.9
    static let maximumLag: TimeInterval = 2.6
}
