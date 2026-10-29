import Foundation
import SwiftUI

// Общий смысловой слой виджетов: словарь «тон → цвет + иконка» из визуального
// языка §1.4 (`docs/2026-10-14-widget-visual-language.md`), плотности заливок
// §1.6 и детерминированный текст-запасной для блоков, которые клиент рисовать
// не умеет (галерея §8.3).
//
// Один и тот же смысл всегда одного цвета и одной иконки, во всех виджетах:
// «просрочено» — это красный `calendarSmall` и в списке, и в лестнице, и в
// сетке. Цвет при этом НЕ единственный носитель смысла (§1.4 п.1) — рядом
// всегда иконка или подпись.

/// Смысловой тон элемента виджета. Значение приходит из блока строкой
/// (`tone` у элемента доски/списка, `state` у звена/ступени/точки).
enum WidgetTone: String {
    case over, block, inprog, review, done, free, noasg, future

    /// Неизвестное значение не роняет блок: рисуется нейтральный тон, а не
    /// заглушка (галерея §8.4 — «неизвестный `tone` → `dim`, без цвета»).
    init(_ raw: String?) {
        let key = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self = WidgetTone(rawValue: key) ?? .future
    }

    var color: Color {
        switch self {
        case .over: return Color.tfRed
        case .block: return Color.tfOrange
        case .inprog: return Color.tfTeal
        case .review: return Color.tfBlue
        case .done: return Color.tfGreen
        case .free: return Color.tfSub
        case .noasg: return Color.tfPurple
        case .future: return Color.tfDim
        }
    }

    /// Имя значка.
    ///
    /// ВНИМАНИЕ, найдено на симуляторе: словарь иконок визуального языка и
    /// галереи — это имена LUCIDE (`calendarSmall`, `check`, `activity`), а
    /// клиент рисует SF Symbols. `check`, `check.circle`, `activity`,
    /// `calendarSmall` в SF Symbols НЕ существуют: SwiftUI рисует для них пустое
    /// место — значок молча пропадает, а кружок остаётся. Поэтому имена здесь
    /// переведены на настоящие SF Symbols (проверено списком символов SDK), и по
    /// той же причине поле `icon` из блока не рисуется как есть.
    var icon: String {
        switch self {
        case .over: return "calendar.badge.clock"
        case .block: return "lock"
        case .inprog: return "bolt.horizontal"
        case .review: return "eye"
        case .done: return "checkmark"
        case .free: return "circle"
        case .noasg: return "person"
        case .future: return "clock"
        }
    }

    /// Подпись для VoiceOver: строка должна читаться одной фразой, а не
    /// «кружок, график, Просрочено» (галерея §7.1).
    var label: String {
        switch self {
        case .over: return "просрочено"
        case .block: return "заблокировано"
        case .inprog: return "в работе"
        case .review: return "на проверке"
        case .done: return "готово"
        case .free: return "назначено"
        case .noasg: return "без исполнителя"
        case .future: return "будущее"
        }
    }
}

/// Плотности заливок и треков. Различаются темой и пересчитываются на лету —
/// визуальный язык требует, чтобы смена темы не пересоздавала сообщение и не
/// меняла высоту блока (галерея §8.2).
struct WidgetInk {
    let isDark: Bool

    init(_ scheme: ColorScheme) { isDark = scheme == .dark }

    /// Заливка прикладным цветом: 18 % в тёмной теме, 25 % в светлой. На белом
    /// 15 % прикладного цвета не читается — порог начинается с 25 % (§1.6).
    func fill(_ tone: WidgetTone) -> Color {
        tone.color.opacity(isDark ? 0.18 : 0.25)
    }

    /// Трек полосы: «пустая» часть шкалы.
    var track: Color { isDark ? Color.tfPaper.opacity(0.06) : Color.black.opacity(0.12) }

    /// Пять ступеней шкалы плотности (тепловая карта, сетка дней). Здесь цвет —
    /// единственный носитель количества, поэтому категориальная палитра не
    /// используется: один тон на весь блок (§Т5).
    func density(_ step: Int, base: Color) -> Color {
        let steps: [Double] = isDark ? [0.06, 0.10, 0.20, 0.35, 0.55]
                                    : [0.12, 0.25, 0.40, 0.60, 0.85]
        let index = min(max(step, 0), steps.count - 1)
        guard index > 0 else { return track }
        return base.opacity(steps[index])
    }
}

/// Значок состояния: круг с иконкой смысла (в галерее — `StateMark`).
/// Диаметр 21, как у кружка статуса подзадачи в остальном приложении.
///
/// Иконка — цветом текста, а не цветом тона: на заливке своего же цвета значок
/// не читается ни в одной теме (визуальный язык §1.7 — тот же вывод, что и для
/// текста). Смысл несёт заливка, значок только подтверждает.
struct WidgetStateMark: View {
    let tone: WidgetTone
    let ink: WidgetInk
    var glyph: CGFloat = TFIconSize.xs
    var diameter: CGFloat = 21

    var body: some View {
        // ZStack, а не круг с накладкой: накладка отдаёт значку размер
        // основания, и часть глифов (`check`, `activity`) не рисовалась вовсе,
        // хотя круглый `circle` выживал. Здесь размер значка задаёт сам значок.
        ZStack {
            Circle().fill(ink.fill(tone))
            Image(systemName: tone.icon)
                .font(.system(size: glyph, weight: .semibold))
                .foregroundStyle(Color.tfText)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}

/// Горизонтальная полоса: трек + заливка. Высота 4 — строка списка, 8 — шкала
/// прогресса (галерея К3/К4/Т8).
struct WidgetBar: View {
    let fraction: Double
    let fill: Color
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.tfCard2)
                Capsule()
                    .fill(fill)
                    .frame(width: max(0, min(1, fraction)) * geo.size.width)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Заголовок блока: название и необязательная подпись справа.
struct WidgetTitle: View {
    let title: String?
    let note: String?

    var body: some View {
        if title != nil || note != nil {
            HStack(alignment: .firstTextBaseline, spacing: TFSpacing.sm) {
                if let title {
                    Text(title)
                        .tfText(.title)
                        .foregroundStyle(Color.tfText)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                if let note {
                    Text(note)
                        .tfText(.caption)
                        .foregroundStyle(Color.tfDim)
                        .lineLimit(1)
                }
            }
        }
    }
}

/// Пустое состояние (§5.3 языка): иконка и одна фраза. Блок без данных — это
/// «Данных пока нет», а не «виджет не разобран».
struct WidgetEmptyNote: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "tray")
            .tfText(.caption)
            .foregroundStyle(Color.tfDim)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Загрузка

/// Скелетон блока на время, пока ответ роли дописывается (визуальный язык §5.2).
/// Спиннер внутри виджета запрещён, мигания и градиента нет, геометрия та же,
/// что у `WidgetCard`, — иначе блок прыгает в момент появления данных.
/// Подпись не рисуем: она и была причиной, по которой состояние выглядело как
/// «виджет готовится», а не как «данные едут».
struct WidgetSkeletonCard: View {
    private let rows: [(ratio: CGFloat, height: CGFloat)] = [
        (0.45, 12), (1.0, 10), (1.0, 10), (0.6, 10),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.md) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                bar(ratio: row.ratio, height: row.height)
            }
        }
        .padding(TFSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tfCard, in: RoundedRectangle(cornerRadius: TFRadius.xl))
        .overlay(RoundedRectangle(cornerRadius: TFRadius.xl).strokeBorder(Color.tfStroke, lineWidth: TFBorder.width))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Виджет готовится")
    }

    /// Полоса на всю ширину блока, короткая — по `ratio` от левого края.
    private func bar(ratio: CGFloat, height: CGFloat) -> some View {
        Capsule()
            .fill(Color.tfCard2)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .scaleEffect(x: ratio, y: 1, anchor: .leading)
    }
}

// MARK: - Формат

enum WidgetFormat {
    /// Целое с разрядами через пробел: 29490 → «29 490». Цены и суммы в
    /// виджетах сравнения читаются именно так.
    static func integer(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        let digits = String(abs(rounded))
        var grouped = ""
        for (index, character) in digits.reversed().enumerated() {
            if index > 0 && index % 3 == 0 { grouped.append(" ") }
            grouped.append(character)
        }
        return (rounded < 0 ? "−" : "") + String(grouped.reversed())
    }

    static func percent(_ fraction: Double) -> String {
        "\(Int((min(1, max(0, fraction)) * 100).rounded()))%"
    }

    /// Значение в допустимом диапазоне. Вне диапазона показываем границу и
    /// прочерк под ней (галерея §8.4) — молча обрезать число нельзя.
    static func clamped(_ value: Double, _ low: Double, _ high: Double) -> Double {
        min(high, max(low, value))
    }

    // MARK: Даты

    private static let isoDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let dayMonth: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "dd.MM"
        return formatter
    }()

    private static let monthName: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "LLLL yyyy"
        return formatter
    }()

    /// `ГГГГ-ММ-ДД` → дата. Неразбираемая дата — `nil`, тогда на её месте
    /// рисуется прочерк (§8.4), а не сегодняшнее число.
    static func date(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        return isoDate.date(from: raw.trimmingCharacters(in: .whitespaces))
    }

    /// «2026-10-17» → «17.10». Неразбралось — прочерк.
    static func shortDate(_ raw: String?) -> String {
        guard let date = date(raw) else { return "—" }
        return dayMonth.string(from: date)
    }

    /// «2026-10» → «Октябрь 2026». Неразбралось — прочерк.
    static func month(_ raw: String?) -> String {
        guard let raw else { return "—" }
        let key = raw.trimmingCharacters(in: .whitespaces)
        guard let head = isoDate.date(from: key + "-01") else { return "—" }
        let name = monthName.string(from: head)
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    /// Сколько дней между двумя датами `ГГГГ-ММ-ДД` (может быть отрицательным).
    static func days(from: String?, to: String?) -> Int? {
        guard let from = date(from), let to = date(to) else { return nil }
        return Calendar(identifier: .iso8601).dateComponents([.day], from: from, to: to).day
    }

    /// Дни месяца «ГГГГ-ММ»: сколько всего и сколько пустых клеток перед первым
    /// числом. `firstWeekday` — с какой строки в блоке начинается неделя
    /// (1 — понедельник, как в ISO); по умолчанию тоже понедельник.
    static func monthShape(_ raw: String?, firstWeekday: Double = 1) -> (days: Int, leadingBlanks: Int)? {
        guard let raw else { return nil }
        let key = raw.trimmingCharacters(in: .whitespaces)
        let calendar = Calendar(identifier: .iso8601)
        guard let first = isoDate.date(from: key + "-01"),
              let range = calendar.range(of: .day, in: .month, for: first)
        else { return nil }
        // Calendar.iso8601 отдаёт 1 = понедельник; колонка сетки считается от
        // той строки, которую назвал блок.
        let isoWeekday = calendar.component(.weekday, from: first)
        let start = WidgetFormat.clamped(firstWeekday, 1, 7).rounded()
        let column = (Double(isoWeekday) - start + 7).truncatingRemainder(dividingBy: 7)
        return (range.count, Int(column))
    }
}

// MARK: - Запасной текст

/// Текстовый запасной вариант (галерея §8.3–8.4). Клиент, который тип не рисует,
/// всё равно должен показать смысл блока: раньше неизвестный тип давал
/// «Виджет не разобран», и это выглядело поломкой на стороне владельца.
/// Текст собирается из тех же полей детерминированно — руками в рецептах его
/// писать нельзя.
enum WidgetFallback {
    static func text(for type: String, data: WidgetData) -> String? {
        switch type {
        case "status_board": return statusBoard(data)
        case "bars_list": return barsList(data)
        case "chain": return chain(data)
        case "ladder": return ladder(data)
        case "timeline": return timeline(data)
        case "calendar_grid": return calendarGrid(data)
        case "heatmap": return heatmap(data)
        case "compare": return compare(data)
        case "table": return table(data)
        default: return generic(data)
        }
    }

    // MARK: Восемь новых типов

    private static func statusBoard(_ data: WidgetData) -> String? {
        let groups = data.array("groups")
        guard !groups.isEmpty else { return nil }
        let parts = groups.prefix(8).map { "\($0.string("label") ?? "—") \(WidgetFormat.integer($0.number("value") ?? 0))" }
        let head = data.string("title")
        let tail = data.string("note") ?? ""
        return ([head].compactMap { $0 } + [parts.joined(separator: ", ")] + [tail])
            .filter { !$0.isEmpty }
            .joined(separator: " — ")
    }

    private static func barsList(_ data: WidgetData) -> String? {
        let items = data.array("items")
        guard !items.isEmpty else { return nil }
        let parts = items.prefix(8).map { item -> String in
            let value = WidgetFormat.integer(item.number("value") ?? 0)
            guard let maxValue = item.number("max"), maxValue > 0 else {
                return "\(item.string("label") ?? "—"): \(value)"
            }
            return "\(item.string("label") ?? "—"): \(value) из \(WidgetFormat.integer(maxValue))"
        }
        return ([data.string("title")] + [parts.joined(separator: "; ")]).compactMap { $0 }.joined(separator: " — ")
    }

    private static func chain(_ data: WidgetData) -> String? {
        let links = data.array("links")
        guard !links.isEmpty else { return nil }
        let parts = links.prefix(8).map { "\($0.string("label") ?? "—") (\(WidgetTone($0.string("state")).label))" }
        let summary = data.string("summary") ?? summary(done: links.filter { WidgetTone($0.string("state")) == .done }.count, of: links.count)
        return ([data.string("title")] + [parts.joined(separator: ", "), summary]).compactMap { $0 }.joined(separator: ": ")
    }

    private static func ladder(_ data: WidgetData) -> String? {
        let steps = data.array("steps")
        guard !steps.isEmpty else { return nil }
        let overall = data.number("overall").map { "готовность \(WidgetFormat.percent($0 / 100))" }
        let parts = steps.prefix(8).map { "\($0.string("label") ?? "—") \(WidgetFormat.integer($0.number("value") ?? 0))" }
        return ([data.string("title")] + [overall, parts.joined(separator: ", ")]).compactMap { $0 }.joined(separator: ": ")
    }

    private static func timeline(_ data: WidgetData) -> String? {
        let items = data.array("items")
        guard !items.isEmpty else { return nil }
        let parts = items.prefix(8).map { item -> String in
            let meta = item.string("meta").map { " (\($0))" } ?? ""
            return "\(WidgetFormat.shortDate(item.string("date"))) \(item.string("label") ?? "—")\(meta)"
        }
        return ([data.string("title")] + [parts.joined(separator: "; ")]).compactMap { $0 }.joined(separator: " — ")
    }

    private static func calendarGrid(_ data: WidgetData) -> String? {
        let cells = data.array("cells")
        guard let month = data.string("month") else { return nil }
        let total = cells.reduce(0) { $0 + ($1.number("count") ?? 0) }
        let busy = cells.filter { ($0.number("count") ?? 0) > 0 }.count
        return "\(WidgetFormat.month(month)): дней с событиями \(busy), всего \(WidgetFormat.integer(total))"
    }

    private static func heatmap(_ data: WidgetData) -> String? {
        let cells = data.array("cells")
        let weeks = data.number("weeks").map { WidgetFormat.integer($0) } ?? "—"
        let total = cells.reduce(0) { $0 + ($1.number("value") ?? 0) }
        let peak = cells.compactMap { $0.number("value") }.max() ?? data.number("max") ?? 0
        let unit = data.string("unit").map { " \($0)" } ?? ""
        return "Активность за \(weeks) недель: всего \(WidgetFormat.integer(total))\(unit), пик \(WidgetFormat.integer(peak)) за день"
    }

    private static func compare(_ data: WidgetData) -> String? {
        guard let left = data.object("left"), let right = data.object("right") else { return nil }
        let unit = data.string("unit").map { " \($0)" } ?? ""
        let head = [data.string("subject"), data.string("title")].compactMap { $0 }.first
        let sides = [left, right].map { "\($0.string("label") ?? "—") \(WidgetFormat.integer($0.number("value") ?? 0))\(unit)" }
        return ([head] + [sides.joined(separator: ", "), data.string("verdict")]).compactMap { $0 }.joined(separator: ". ")
    }

    /// Тип не в реестре: собираем хоть что-то понятное из типовых полей, чтобы
    /// блок не выглядел поломкой. Если данных нет — честный прочерк.
    /// Таблица: колонки и число строк. Общий `generic` ищет поля вида
    /// «label/value», которых у таблицы нет, — сводка была пустой, и клиент,
    /// который таблицу не рисует, показывал только сырой JSON.
    private static func table(_ data: WidgetData) -> String? {
        WidgetTableParser.summary(data.raw)
    }

    private static func generic(_ data: WidgetData) -> String? {
        if let title = data.string("title"), let text = data.string("text"), title.isEmpty == false {
            return "\(title): \(text)"
        }
        let items = data.array("items").prefix(8).map { item -> String in
            let label = item.string("label") ?? item.string("text") ?? item.string("name") ?? "—"
            let value = item.string("value") ?? item.number("value").map(WidgetFormat.integer)
            return [label, value].compactMap { $0 }.joined(separator: ": ")
        }
        let rows = data.array("rows").prefix(8).map { row in
            [row.string("label"), row.string("value")].compactMap { $0 }.joined(separator: ": ")
        }
        let parts = Array(items) + Array(rows)
        guard !parts.isEmpty else { return nil }
        return ([data.string("title")] + [parts.joined(separator: "; ")]).compactMap { $0 }.joined(separator: " — ")
    }

    private static func summary(done: Int, of total: Int) -> String {
        "\(done) из \(total) готово"
    }
}
// MARK: - Вид запасного варианта

/// Тип, который клиент не рисует. Раньше здесь была заглушка «Виджет не
/// разобран» — по сути молчаливая поломка на стороне владельца: блок выглядел
/// сломанным, хотя сервер отдал правильные данные (галерея §8.3–8.4).
///
/// Теперь сначала идёт текст, собранный из тех же полей, а под ним — исходный
/// блок, чтобы ничего не потерялось. И то и другое — на случай, когда блок
/// пришёл с битыми данными и собрать из него нечего.
struct WidgetTextFallback: View {
    let json: String
    let note: String

    var body: some View {
        WidgetCard(title: nil) {
            Label(note, systemImage: "text.alignleft")
                .tfText(.caption)
                .foregroundStyle(Color.tfSub)
            if let text = summary {
                Text(text)
                    .tfText(.row)
                    .foregroundStyle(Color.tfText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(json)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color.tfDim)
            }
            .accessibilityLabel("Исходный блок виджета")
        }
    }

    private var summary: String? {
        guard let data = WidgetData.parse(json) else { return nil }
        return WidgetFallback.text(for: data.string("type") ?? "", data: data)
    }
}
