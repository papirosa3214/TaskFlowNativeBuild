import SwiftUI

// Метка даты и времени заведения заявки в строке списка — владелец 12.10.2026:
// «мне нужна дата и время заведения этой заявки… мне только числа нужны… всё
// это в квадратных скобках», шрифт — «чтоб как-то интересно смотрелось».
//
// Формат ровно `[12.10.2026 - 13:10]`: ни слова, ни буквы — только цифры и
// знаки, квадратные скобки обрамляют. Владелец отверг вариант с подписью
// («заведена 12 окт») прямо: «мне не надо вот эту вот всю херню, мне только
// числа нужны».
//
// Шрифт DotGothic16 (OFL, Pixel Maniac / Japanese pixel tradition) — выбран
// владельцем из восьми вариантов, показанных кадрами в строке списка.
// Файл урезан до ASCII+кириллицы (60 КБ вместо 2 МБ), в бандл кладётся
// через `Resources/Fonts` (project.yml), регистрируется `UIAppFonts`
// (Resources/Info.plist).
//
// ⚠️ Время — МОСКОВСКОЕ, не таймзона устройства: `created_at` приходит из
// SQLite в UTC (`DateFormats.sqliteUTC`), и та же трактовка уже принята для
// подписей уведомлений (`DirectoryDate.absolute`). Иначе у задачи, заведённой
// ночью, дата «поплыла» бы на день при смене телефона.
public struct TFTaskCreatedStamp: View {
    private let moment: Date

    /// `nil`/`nil`-строка — сервер не отдал дату, метки нет (nil убирает вью
    /// целиком, а не рисует пустое место).
    public init?(createdAt: String?) {
        guard let moment = DateFormats.sqliteUTC(createdAt) else { return nil }
        self.moment = moment
    }

    public init(moment: Date) {
        self.moment = moment
    }

    /// Текст метки — вынесен наружу ради юнит-теста: проверять разбор даты
    /// через View нельзя.
    public static func text(for date: Date) -> String {
        "[\(formatter.string(from: date))]"
    }

    /// Тот же текст, но от строки `created_at` как её отдаёт сервер.
    /// Единая точка правды для тестов и для вызовов из кода.
    public static func text(forCreatedAt raw: String?) -> String? {
        guard let moment = DateFormats.sqliteUTC(raw) else { return nil }
        return text(for: moment)
    }

    /// МСК-«12.10.2026 - 13:10». Статический форматтер: потокобезопасен и не
    /// пересоздаётся на каждую строку списка (в списке бывает сотня строк).
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "Europe/Moscow")
        formatter.dateFormat = "dd.MM.yyyy - HH:mm"
        return formatter
    }()

    public var body: some View {
        Text(Self.text(for: moment))
            .font(TFFont.pixelStamp)
            .foregroundStyle(Color.tfSub)
            .layoutPriority(-1)
            // Дата не должна доезжать огрызком («[12.10.20…») — обрезанная
            // метка хуже отсутствующей: она читается как баг, а не как время.
            // Остальные элементы мета-строки сжимаются первыми (у них
            // `layoutPriority(-1)` и свой `lineLimit`), дата остаётся целой.
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel(Self.spokenLabel(moment))
    }

    /// Подпись для VoiceOver словами: пиксельные цифры как дату не читаются.
    /// Публичная — ею же дополняется подпись строки там, где строка собрана
    /// в один элемент через `accessibilityElement(children: .ignore)`
    /// (сегодняшний список): там подпись метки иначе просто теряется.
    public static func spokenLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.timeZone = TimeZone(identifier: "Europe/Moscow")
        f.dateFormat = "d MMMM в HH:mm"
        return "Заведена \(f.string(from: date))"
    }

    /// То же от строки `created_at`; `nil` — даты нет.
    public static func spokenLabel(forCreatedAt raw: String?) -> String? {
        guard let moment = DateFormats.sqliteUTC(raw) else { return nil }
        return spokenLabel(moment)
    }
}

public extension TFFont {
    /// Пиксельный шрифт метки даты. Введён вместе с самой меткой
    /// (LOCK-TASK-CREATED-STAMP) — до неё шкала `TFFont` была строго
    /// системной (см. шапку `Typography.swift`: «гарнитура одна системная»).
    /// Это единственное место в приложении с чужой гарнитурой, и оно
    /// намеренное: владелец попросил именно пиксельный шрифт для метки.
    ///
    /// Кегль 11 — как `.caption` (шаг мета-строки), но `@ScaledMetric`
    /// обязателен: `Font.custom(_:size:)` не масштабируется под Dynamic Type,
    /// а строка задачи — текст, а не декорация (WCAG 1.4.4).
    static let pixelStamp = Font.custom("DotGothic16", size: 11, relativeTo: .caption)
}

#Preview("Метка даты заведения") {
    VStack(alignment: .leading, spacing: TFSpacing.md) {
        TFTaskCreatedStamp(createdAt: "2026-10-12 10:10:00")
        TFTaskCreatedStamp(createdAt: "2026-09-03 22:45:00")
        HStack(spacing: TFSpacing.xs) {
            TFPill("31 авг", color: .tfSub, solidBackground: .tfCard)
            TFTaskCreatedStamp(createdAt: "2026-10-12 10:10:00")
        }
    }
    .padding()
    .background(Color.tfBackground)
}
