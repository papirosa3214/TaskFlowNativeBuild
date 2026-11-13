import SwiftUI

/// Строка хода как у Claude Code (владелец 12.11.2026: «идёт анимация и
/// какое-нибудь прикольное слово… как Claude Code делает»): слева кубик из
/// видео владельца — грань показывает, чем занят агент, — справа словечко с
/// многоточием, раз в несколько секунд сменяется другим.
struct TFActivityStatus: View {
    let phase: TFActivityPhase
    /// С чего начать перебор: у каждого хода своё первое слово.
    var seed: Int = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: TFSpacing.sm) {
            TFActivityCube(phase: phase, size: 18)
            TimelineView(.periodic(from: .now, by: Self.wordPeriod)) { context in
                let word = Self.word(at: context.date, seed: seed)
                Text(word + "…")
                    .tfText(.meta)
                    .foregroundStyle(Color.tfSub)
                    .contentTransition(.opacity)
                    .animation(reduceMotion ? nil : TFMotion.standard, value: word)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(phase.label)
    }

    static let wordPeriod: TimeInterval = 3.5

    /// Словечки хода — по-русски, в духе Claude Code.
    static let words = [
        "Кумекаю", "Колдую", "Шуршу", "Мозгую", "Соображаю", "Прикидываю",
        "Ворожу", "Шаманю", "Стряпаю", "Мастерю", "Докапываюсь", "Раскладываю",
        "Перебираю", "Разгадываю", "Плету", "Взвешиваю", "Варю мысль", "Чешу репу",
        "Распутываю", "Сверяю", "Подкручиваю", "Нащупываю",
    ]

    static func word(at date: Date, seed: Int) -> String {
        let tick = Int(date.timeIntervalSinceReferenceDate / wordPeriod)
        let index = ((tick + seed) % words.count + words.count) % words.count
        return words[index]
    }
}
