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
    @ViewBuilder let content: () -> Content

    @State private var fade: RoleTextFade?
    @State private var finished = false

    /// Долгую речь не растягиваем на десятки секунд: чем длиннее текст, тем
    /// быстрее идёт проявление, но нижняя граница остаётся читаемой.
    private static let minimumLag: TimeInterval = 0.9
    private static let maximumLag: TimeInterval = 2.6

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
        guard !finished, !text.isEmpty else { return }
        finished = true
        let length = Double(max(text.count, 1))
        let lag = min(Self.maximumLag, max(Self.minimumLag, length / 90))
        let rate = min(RoleLiveTextPacer.maxRate, max(RoleLiveTextPacer.minRate, length / lag))
        fade = RoleTextFade(rate: rate, lastRevealAt: .now, isAnimating: true)
        // Держим анимацию, пока идёт проявление, потом отпускаем отрисовку:
        // иначе TimelineView крутился бы и на готовом тексте.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(lag + RoleTextFade.duration + 0.2))
            guard !Task.isCancelled else { return }
            fade = RoleTextFade(rate: rate, lastRevealAt: .now, isAnimating: false)
        }
    }
}

extension View {
    /// Оборачивает только текст ответа роли — вложения и карточки идут рядом
    /// и появляются сразу.
    func roleMessageReveal(text: String, messageID: String) -> some View {
        RoleMessageReveal(text: text, messageID: messageID) { self }
    }
}
