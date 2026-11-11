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
    /// Темп: медленный — только для обычного текста; отчёты, таблицы и
    /// виджеты — прежний быстрый (владелец 06.11.2026: «замедление нужно
    /// только для текста, не для вывода инструментов»).
    var pace: RoleMessageRevealPace = .prose
    @ViewBuilder let content: () -> Content

    @State private var fade: RoleTextFade?
    @State private var finished = false

    var body: some View {
        content()
            .roleReveal(fade)
            .onAppear(perform: startIfNeeded)
            .onDisappear(perform: snapIfStillAnimating)
            .onChange(of: messageID) { _, _ in
                // Другое сообщение в этой же ячейке — своя анимация.
                finished = false
                fade = nil
                startIfNeeded()
            }
            .onChange(of: animate) { _, shouldAnimate in
                // История при открытии сначала без проявления; новое
                // сообщение потом включает animate — без этого старт не
                // сработает (ячейка уже на экране).
                if shouldAnimate { startIfNeeded() }
            }
    }

    private func startIfNeeded() {
        // Уже проигрывали: если Task отменили на полдороге (ячейка ушла с
        // экрана), `finished` остаётся true, а fade — с isAnimating. Без сброса
        // вторая половина фразы так и висит прозрачной (владелец 03.11.2026).
        if finished {
            fade = RoleMessageRevealLifecycle.resolvedFade(
                finished: true, current: fade, preferAnimate: animate && !text.isEmpty
            )
            return
        }
        guard animate, !text.isEmpty else { return }
        finished = true
        let length = Double(max(text.count, 1))
        let timing = pace.timing
        let lag = min(timing.maximumLag, max(timing.minimumLag, length / timing.charsPerSecond))
        let rate = min(RoleLiveTextPacer.maxRate, max(timing.minimumRate, length / lag))
        // Проявление вперёд: буквы готового сообщения печатаются по порядку,
        // а не гаснут одним куском. Идущий ответ так не проявляется — там
        // хвост (см. `RoleTextFade.revealsForward`).
        fade = RoleTextFade(rate: rate, lastRevealAt: .now, isAnimating: true, revealsForward: true)
        // Держим анимацию, пока идёт проявление, потом снимаем textRenderer:
        // иначе TimelineView крутился бы и на готовом тексте. Снимаем fade
        // целиком (nil) — так текст гарантированно полный, без «половины фразы».
        let revealDuration = length / rate
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(revealDuration * 1.15 + RoleTextFade.duration + 0.3))
            fade = RoleMessageRevealLifecycle.fadeAfterRevealCompleted()
        }
    }

    private func snapIfStillAnimating() {
        fade = RoleMessageRevealLifecycle.fadeAfterInterrupt(current: fade)
    }
}

/// Правила завершения проявления — без SwiftUI, чтобы ловить «половину фразы»
/// unit-тестом на хосте.
enum RoleMessageRevealLifecycle {
    /// Конец таймера: убираем renderer, текст рисуется целиком.
    static func fadeAfterRevealCompleted() -> RoleTextFade? { nil }

    /// Ячейка ушла / Task отменён, пока буквы ещё проявлялись — не оставлять
    /// полупрозрачный хвост.
    static func fadeAfterInterrupt(current: RoleTextFade?) -> RoleTextFade? {
        guard let current, current.isAnimating else { return current }
        return nil
    }

    /// Повторный onAppear после `finished`: если fade всё ещё анимирует —
    /// снять; иначе не трогать (уже полный текст или nil).
    static func resolvedFade(finished: Bool, current: RoleTextFade?, preferAnimate: Bool) -> RoleTextFade? {
        guard finished else { return current }
        if current?.isAnimating == true { return nil }
        return current
    }
}

extension View {
    /// Оборачивает только текст ответа роли — вложения и карточки идут рядом
    /// и появляются сразу.
    func roleMessageReveal(text: String, messageID: String, animate: Bool = true,
                           pace: RoleMessageRevealPace = .prose) -> some View {
        RoleMessageReveal(text: text, messageID: messageID, animate: animate, pace: pace) { self }
    }
}

/// Темп проявления готового сообщения.
enum RoleMessageRevealPace {
    /// Обычный текст ответа — медленно и плавно.
    case prose
    /// Отчёт, таблица, виджет, вывод инструментов — прежний быстрый темп.
    case structured

    /// Есть ли в тексте таблица или блок ``` (код, виджет) — тогда темп быстрый.
    static func of(markdown text: String) -> RoleMessageRevealPace {
        text.contains("```") || text.contains("\n|") || text.hasPrefix("|") ? .structured : .prose
    }

    var timing: RoleMessageRevealTiming {
        switch self {
        // Владелец 06.11.2026: «плавность прям усилить» — проза примерно в
        // 1,7 раза медленнее прежнего. Свой нижний предел 30 знаков/с: общий
        // `RoleLiveTextPacer.minRate` (60) оставил бы короткую фразу быстрой.
        case .prose:
            return RoleMessageRevealTiming(minimumLag: 1.6, maximumLag: 4.5, charsPerSecond: 50, minimumRate: 30)
        // Прежний темп (до 06.11.2026) — для всего, что не проза.
        case .structured:
            return RoleMessageRevealTiming(minimumLag: 0.9, maximumLag: 2.6, charsPerSecond: 90,
                                           minimumRate: RoleLiveTextPacer.minRate)
        }
    }
}

/// Границы темпа: долгий текст не растягиваем на десятки секунд — чем длиннее,
/// тем быстрее идёт проявление, но нижняя граница остаётся читаемой.
struct RoleMessageRevealTiming {
    let minimumLag: TimeInterval
    let maximumLag: TimeInterval
    /// Базовый темп: сколько знаков в секунду, пока не упёрлись в границы.
    let charsPerSecond: Double
    let minimumRate: Double
}
