import SwiftUI

// Разделители дней и кнопка «вниз» — общие для ОБЕИХ лент переписки: комнаты
// с ролью и группового чата (`RoleChatRoomScreen`) и чата «Секретарь»
// (`ChatScreen`). Лежат здесь, потому что вид и правила обязаны совпадать:
// плашка дня — тот же рисунок, что метка «Новая сессия» в комнате, кнопка
// одна и та же (системное стекло `voiceCircleSurface`, как у круглых кнопок
// композера).
//
// День считается по календарю УСТРОЙСТВА — намеренно так же, как
// `ChatListTime` в списке чатов рядом: строка списка и плашка внутри чата
// обязаны называть один и тот же день одним и тем же словом. Московское
// время из `RelativeTime` для этого не годится — оно показывает время
// сообщения, а не границу суток.

/// Подпись разделителя дня: «Сегодня» / «Вчера» / «Понедельник» / «1 октября».
enum ChatDayLabel {
    /// Родительный падеж месяца — «1 октября», а не системное «1 окт.».
    private static let monthsGenitive = [
        "января", "февраля", "марта", "апреля", "мая", "июня",
        "июля", "августа", "сентября", "октября", "ноября", "декабря",
    ]

    private static let weekday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "EEEE"
        return formatter
    }()

    /// `created_at` сообщения (`DateFormats.sqliteUTC`) → подпись. `nil` —
    /// даты нет (локальное сообщение в пути, метка сессии без времени).
    static func label(raw: String?, now: Date = .now) -> String? {
        guard let date = DateFormats.sqliteUTC(raw) else { return nil }
        return label(date, now: now)
    }

    static func label(_ date: Date, now: Date = .now) -> String {
        let calendar = Calendar.autoupdatingCurrent
        if calendar.isDateInToday(date) { return "Сегодня" }
        if calendar.isDateInYesterday(date) { return "Вчера" }
        // Ближайшая неделя — словом: увидел «Среда» и сразу видно, где был.
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: now)
        ).day ?? 0
        if days < 7 { return weekday.string(from: date).capitalized }
        return dayAndMonth(date, now: now)
    }

    /// «1 октября» этого года; чужой год — с годом («1 октября 2025»).
    private static func dayAndMonth(_ date: Date, now: Date = .now) -> String {
        let calendar = Calendar.autoupdatingCurrent
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        let month = max(1, min(12, comps.month ?? 1))
        let text = "\(comps.day ?? 1) \(monthsGenitive[month - 1])"
        guard comps.year != calendar.component(.year, from: now) else { return text }
        return "\(text) \(comps.year ?? 0)"
    }

    /// Ключ календарного дня — сравнение «тот же день, что и предыдущее
    /// сообщение». Строкой, чтобы не таскать по ленте `Date` и не зависеть от
    /// точности `startOfDay`.
    static func dayKey(raw: String?) -> String? {
        guard let date = DateFormats.sqliteUTC(raw) else { return nil }
        return dayKey(date)
    }

    static func dayKey(_ date: Date) -> String {
        let comps = Calendar.autoupdatingCurrent.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", comps.year ?? 1970, comps.month ?? 1, comps.day ?? 1)
    }
}

/// Где в ленте начинается новый день: индексы сообщений, перед которыми надо
/// поставить плашку даты. Общий для обеих лент — они отличаются только типом
/// сообщения, а правило группировки одно.
///
/// Сообщение без разбираемой даты (локальное «в пути», метка сессии без
/// `created_at`) нового дня не начинает и текущий не прерывает — иначе плашки
/// размножились бы на ровном месте.
enum ChatDayMarker {
    static func dayStarts<Element>(
        in elements: [Element],
        createdAt: KeyPath<Element, String?>
    ) -> Set<Int> {
        var result: Set<Int> = []
        var previousDay: String?
        for (index, element) in elements.enumerated() {
            guard let day = ChatDayLabel.dayKey(raw: element[keyPath: createdAt]) else { continue }
            guard day != previousDay else { continue }
            result.insert(index)
            previousDay = day
        }
        return result
    }
}

/// Плашка-разделитель: смена дня перед сообщением и закрытие сессии внизу
/// ленты. Ровно тот же рисунок, что метка «Новая сессия» в комнате.
struct ChatFeedDivider: View {
    let title: String
    var identifier: String = "chat.day-divider"

    var body: some View {
        HStack {
            Spacer()
            Text(title)
                .tfText(.caption)
                .foregroundStyle(Color.tfDim)
                .padding(.horizontal, TFSpacing.md)
                .padding(.vertical, 4)
                .background(Color.tfCard)
                .clipShape(Capsule())
            Spacer()
        }
        // Плашка — одна цельная подпись: VoiceOver читает «Сегодня», а
        // XCUITest находит её по идентификатору, а не по координатам.
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

/// Кнопка «вниз» поверх ленты: появляется, когда владелец уехал вверх, и
/// возвращает к последнему сообщению одним нажатием (владелец 03.10.2026:
/// «чтобы я не скролил, а кнопочку нажал»).
struct ChatScrollToBottomButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.down")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.tfText)
                .frame(width: 36, height: 36)
                .voiceCircleSurface()
                // Тап-зона 44 pt при кружке 36 (TFHitTarget.min), как у всех
                // круглых кнопок приложения.
                .frame(width: TFHitTarget.min, height: TFHitTarget.min)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Вниз, к последнему сообщению")
        .accessibilityIdentifier("chat.scroll-to-bottom")
    }
}