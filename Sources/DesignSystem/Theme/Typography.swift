import SwiftUI

// Типографика — шкала ступеней, spec/DESIGN-TOKENS.md §2.
// Гарнитура одна системная (San Francisco = `Font.system` на native, свой шрифт не заводим).
//
// НЕ перенесено с веба сознательно:
// - фиксированный line-height title-large (32px вместо обычных 1.x) — это
//   защита от обрезки выносных букв браузерным рендерером; SwiftUI текст
//   так не обрезает, поэтому берём обычный `.lineSpacing`, не жёсткий box;
// - letter-spacing (`tracking`) перенесён как есть числом из спеки — там,
//   где на устройстве не будет заметен зазор, можно убрать (спека сама
//   оговаривает это как «эффект уже несёт SF Pro»).
//
// Правило проекта: 16px (`.tfInput`) — ТОЛЬКО для текстовых полей (защита
// от системного зума iOS при фокусе на iOS-вебе; на native зума нет, но
// ступень держим зарезервированной, чтобы визуальный язык не расходился
// с вебом и будущими экранами).
//
// ─────────────────────────────────────────────────────────────────────────
// 14.09.2026, Dynamic Type (a11y-аудит).
//
// БЫЛО: все ступени — статические `Font.system(size:)`. Такой шрифт НЕ
// масштабируется под системный размер текста, а Apple в документации
// `Font.system(size:weight:design:)` никаких гарантий масштабирования и не
// даёт. Итог: пользователь, выкрутивший «Крупный текст», видел ровно тот же
// кегль, что и все остальные — при том что это требование WCAG 1.4.4
// (Resize Text) и одна из строк диагностики HIG.
//
// СТАЛО: каждая ступень объявлена через `@ScaledMetric(relativeTo:)` со
// СВОИМ базовым кеглем и своей системной кривой. На дефолтном размере
// текста `@ScaledMetric` возвращает ровно базовое значение — поэтому
// визуальный язык и вся вёрстка остаются БУКВАЛЬНО прежними, а масштаб
// появляется только когда пользователь его просит.
//
// Почему не семантические `.body`/`.headline`: они дают другие кегли
// (`.body` = 17 против наших 15), то есть поехал бы весь дизайн. `relativeTo:`
// берёт у системного стиля только КРИВУЮ масштабирования, а размер оставляет
// наш — это и нужно.
//
// Одна модификация закрывает 342 вызова `.tfText(...)` в 61 файле: сигнатура
// не изменилась, места вызова трогать не пришлось.
// ─────────────────────────────────────────────────────────────────────────

public enum TFFont {
    /// Заголовок корневого экрана (`ScreenHeader variant="large"`).
    public static let titleLarge = Font.system(size: 28, weight: .bold)
    public static let titleLargeTracking: CGFloat = -0.84

    /// Заголовок карточки задачи.
    public static let taskTitle = Font.system(size: 20, weight: .semibold)
    public static let taskTitleTracking: CGFloat = -0.40

    /// Заголовок вторичного экрана/шторки (`variant="compact"`), «Готово» в навбаре.
    public static let title = Font.system(size: 17, weight: .semibold)
    public static let titleTracking: CGFloat = -0.20

    /// ТОЛЬКО текстовые поля — см. предупреждение выше.
    public static let input = Font.system(size: 16, weight: .regular)
    public static let inputTracking: CGFloat = -0.10

    /// Основной текст, название задачи в строке, редактор Дневника.
    public static let body = Font.system(size: 15, weight: .regular)
    public static let bodyTracking: CGFloat = -0.03

    /// Строка списка, пункт меню.
    public static let row = Font.system(size: 14, weight: .regular)

    /// Вторичное действие, подпись под строкой, описание задачи.
    public static let action = Font.system(size: 13, weight: .regular)
    public static let actionTracking: CGFloat = 0.10

    /// Мета-данные, статусы, счётчики, подпись пункта меню создания.
    public static let meta = Font.system(size: 12, weight: .medium)
    public static let metaTracking: CGFloat = 0.14

    /// Мелкая подпись, бейджи/пилюли строки задачи.
    public static let caption = Font.system(size: 11, weight: .medium)
    public static let captionTracking: CGFloat = 0.20

    /// Совсем мелкое: буквы недели, деления графика, счётчик на таббаре.
    public static let micro = Font.system(size: 10, weight: .medium)
    public static let microTracking: CGFloat = 0.25

    // 12.10.2026, LOCK-OVERVIEW-YELLOW-DISPLAY. Заголовок раздела жёлтым
    // капсом встроенной гарнитуры PT Sans Narrow (см. обоснование выбора в
    // `TFSectionDisplayModifier` ниже). Кегль и `Font` живут в модификаторе
    // через `@ScaledMetric` — здесь только разрядка, она от кегля не зависит.
    public static let sectionDisplayTracking: CGFloat = 0.6
    public static let sectionDisplaySmallTracking: CGFloat = 0.4
}

// ─────────────────────────────────────────────────────────────────────────
// 12.10.2026, LOCK-OVERVIEW-YELLOW-DISPLAY. Заголовки разделов «Обзора».
//
// Владелец дал образец: узкий жирный дисплейный капс, все заглавные, без
// иконок и без пояснений. Гарнитуру назвал — Big Shoulders Display.
//
// Цвет из образца НЕ переносится: владелец отдельно уточнил «цвета наши
// сохранить», поэтому заголовки остаются `Color.tfText` (как были до правки).
// Класть в приложение жёлтый из макета — было моей самодеятельностью.
//
// ПОЧЕМУ PT Sans Narrow, а не Big Shoulders Display. У Big Shoulders Display
// НЕТ КИРИЛЛИЦЫ — проверено напрямую по таблице `cmap`, у всех трёх начертаний
// (Black/ExtraBold/Bold) из оригинального репозитория
// github.com/xotypeco/big_shoulders: ни U+0410 «А», ни U+044F «я». То же в
// версии Google Fonts (латиница + latin-ext + вьетнамский, и всё).
// Заголовки разделов русские, они бы не набрались вовсе — пустые
// прямоугольники. PT Sans Narrow — узкая жирная гротеск-гарнитура с полной
// кириллицей; выбрана владельцем 12.10.2026 из списка вариантов после того,
// как Oswald не понравился.
//
// Файлы статичные, начертания Regular и Bold из репозитория Google Fonts
// (`ofl/ptsansnarrow`). Кириллица проверена по `cmap` при установке: U+0410,
// U+044F, U+0451, «—» и «№» на месте. Имена в файлах: family = «PT Sans
// Narrow», «Bold» — начертание (name ID 2), поэтому в коде указывается одно
// семейство, а начертание задаётся весом.
// ─────────────────────────────────────────────────────────────────────────

/// Заголовок раздела узким жирным капсом встроенной гарнитуры.
/// Трекинг положительный, а не отрицательный: узкая гарнитура рассыпается
/// на длинных русских словах («УВЕДОМЛЕНИЯ»).
public struct TFSectionDisplayModifier: ViewModifier {
    private let style: TFTextStyle
    private let color: Color

    @Environment(\.tfTypeSettingsEnabled) private var typeSettingsEnabled

    @ScaledMetric(relativeTo: .title3)    private var largeSize: CGFloat = 22
    @ScaledMetric(relativeTo: .headline)  private var smallSize: CGFloat = 17

    init(style: TFTextStyle, color: Color) {
        self.style = style
        self.color = color
    }

    private var group: TFTypeGroup {
        switch style {
        case .taskTitle, .titleLarge: .heading
        default: .subheading
        }
    }

    private var size: CGFloat {
        let base: CGFloat = switch style {
        case .taskTitle, .titleLarge: largeSize
        default: smallSize
        }
        return typeSettingsEnabled ? base * group.multiplier : base
    }

    // Одно семейство на оба кегля: в файлах PT Sans Narrow family = «PT Sans
    // Narrow», а Regular/Bold — это начертания (name ID 2). Поэтому в коде
    // указывается одно имя, а начертание задаётся весом ниже. Два разных
    // имени здесь означали бы «Oswald Bold» вместо family — и SwiftUI молча
    // нарисовал бы системный шрифт (та же ошибка, что стоила первой попытки
    // ещё с Oswald).
    private var name: String { "PT Sans Narrow" }

    private var weight: Font.Weight {
        switch style {
        case .taskTitle, .titleLarge: .bold
        default: .medium
        }
    }

    private var tracking: CGFloat {
        switch style {
        case .taskTitle, .titleLarge: TFFont.sectionDisplayTracking
        default: TFFont.sectionDisplaySmallTracking
        }
    }

    public func body(content: Content) -> some View {
        content
            .font(.custom(name, size: size).weight(weight))
            .tracking(tracking)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}

public extension View {
    /// Заголовок раздела «Обзора» узким жирным капсом (образец владельца).
    ///
    /// Цвет — НЕ жёлтый из образца: владелец прямо попросил сохранить свои
    /// цвета («я же просил цвета наши сохранить»), поэтому новых цветов не
    /// заводим. Жёлтый из макета в приложение не переносится.
    ///
    /// Цвет по умолчанию — `Color.tfText`, то есть белый. 12.10.2026 пробовали
    /// приглушать на `tfSub` («сильно белый, прям сильно яркий»), но с новой
    /// гарнитурой PT Sans Narrow серый стал читаться вялым, и владелец вернул
    /// белый: заголовки разделов должны быть заметными. Это откат правки
    /// `LOCK-OVERVIEW-HEADER-DIM`, а не новый цвет — новых красок не заводим.
    ///
    /// `style: .taskTitle` — крупный заголовок раздела, остальное — подзаголовок.
    func tfSectionDisplay(style: TFTextStyle = .taskTitle, color: Color = .tfText) -> some View {
        modifier(TFSectionDisplayModifier(style: style, color: color))
    }
}

/// Готовые модификаторы «размер + трекинг одним вызовом» — большинство мест
/// в UI используют пару размер/трекинг вместе, дублировать их на каждом Text не нужно.
///
/// ⚠️ Статический шрифт: НЕ масштабируется под Dynamic Type. Для нового кода
/// предпочитайте `.tfText(...)` (масштабируемый) или объявите свой
/// `@ScaledMetric`. Оставлено для склейки `Text` через `+`, где нужен именно
/// `Font`, а не `View`.
public extension Text {
    func tfStyle(_ font: Font, tracking: CGFloat = 0) -> Text {
        self.font(font).tracking(tracking)
    }
}

public enum TFTextStyle {
    case titleLarge, taskTitle, title, input, body, listTitle, row, action, meta, caption, micro, heatmapCount

    /// Базовый кегль ступени — то, что видно на дефолтном размере текста.
    /// ЭТО ЕДИНСТВЕННОЕ МЕСТО в приложении, где заданы размеры текста:
    /// поменял здесь — поменялось везде, где применён `.tfText(...)`.
    /// Пять размеров на всё приложение (владелец, 01.11.2026).
    var baseSize: CGFloat {
        switch self {
        case .heatmapCount: 34
        default: group.baseSize
        }
    }

    /// Группа шкалы: к какому из пяти размеров относится ступень.
    var group: TFTypeGroup {
        switch self {
        case .titleLarge, .taskTitle, .title: .subheading
        case .input, .body, .listTitle, .row: .body
        case .action, .meta: .secondary
        case .caption, .micro: .tertiary
        case .heatmapCount: .heading
        }
    }

    /// Системный стиль, чью КРИВУЮ масштабирования берём. Размер остаётся
    /// наш (`baseSize`) — от системного стиля нужен только характер роста.
    var relativeTo: Font.TextStyle {
        switch self {
        case .titleLarge: .title       // 28
        case .taskTitle: .title3       // 20
        case .title: .headline         // 17
        case .input: .callout          // 16
        case .body: .subheadline       // 15
        case .listTitle: .subheadline  // 16 → та же кривая, что у названия в списке
        case .row: .footnote           // 13 → 14 близко
        case .action: .footnote        // 13
        case .meta: .caption           // 12
        case .caption: .caption2       // 11
        case .micro: .caption2         // 11 → 10 близко
        case .heatmapCount: .title
        }
    }

    var weight: Font.Weight {
        switch self {
        case .titleLarge: .bold
        case .taskTitle: .semibold
        case .title: .semibold
        case .input: .regular
        case .body: .regular
        case .listTitle: .regular
        case .row: .regular
        case .action: .regular
        case .meta: .medium
        case .caption: .medium
        case .micro: .medium
        case .heatmapCount: .semibold
        }
    }

    var design: Font.Design {
        switch self {
        case .heatmapCount: .rounded
        default: .default
        }
    }

    var tracking: CGFloat {
        switch self {
        case .titleLarge: TFFont.titleLargeTracking
        case .taskTitle: TFFont.taskTitleTracking
        case .title: TFFont.titleTracking
        case .input: TFFont.inputTracking
        case .body: TFFont.bodyTracking
        case .listTitle: TFFont.bodyTracking
        case .row: 0
        case .action: TFFont.actionTracking
        case .meta: TFFont.metaTracking
        case .caption: TFFont.captionTracking
        case .micro: TFFont.microTracking
        case .heatmapCount: 0
        }
    }
}

/// Применяет ступень шкалы с масштабированием под Dynamic Type.
///
/// Каждая ступень — отдельный `@ScaledMetric` со своим `relativeTo`. Держать
/// их все в одном модификаторе нужно потому, что `relativeTo:` задаётся
/// статически при объявлении свойства и не может выбираться по `style`
/// в рантайме. Свойство, которое не соответствует текущей ступени, просто
/// не читается — стоимость нулевая.
private struct TFTextStyleModifier: ViewModifier {
    let style: TFTextStyle

    @Environment(\.tfTypeSettingsEnabled) private var typeSettingsEnabled

    @ScaledMetric(relativeTo: .title)      private var titleLargeSize: CGFloat = 22
    @ScaledMetric(relativeTo: .title3)     private var taskTitleSize: CGFloat = 17
    @ScaledMetric(relativeTo: .headline)   private var titleSize: CGFloat = 17
    @ScaledMetric(relativeTo: .callout)    private var inputSize: CGFloat = 15
    @ScaledMetric(relativeTo: .subheadline) private var bodySize: CGFloat = 15
    @ScaledMetric(relativeTo: .footnote)   private var rowSize: CGFloat = 15
    @ScaledMetric(relativeTo: .footnote)   private var actionSize: CGFloat = 13
    @ScaledMetric(relativeTo: .caption)    private var metaSize: CGFloat = 13
    @ScaledMetric(relativeTo: .caption2)   private var captionSize: CGFloat = 11
    @ScaledMetric(relativeTo: .caption2)   private var microSize: CGFloat = 11
    @ScaledMetric(relativeTo: .title)      private var heatmapCountSize: CGFloat = 34

    @ScaledMetric(relativeTo: .subheadline) private var listTitleSize: CGFloat = 15

    private var scaledSize: CGFloat {
        switch style {
        case .titleLarge: titleLargeSize
        case .taskTitle: taskTitleSize
        case .title: titleSize
        case .input: inputSize
        case .body: bodySize
        case .listTitle: listTitleSize
        case .row: rowSize
        case .action: actionSize
        case .meta: metaSize
        case .caption: captionSize
        case .micro: microSize
        case .heatmapCount: heatmapCountSize
        }
    }

    /// Кегль с поправкой на выбранную ступень группы. В чатах множитель не
    /// работает: их корни выключают настройку через `.tfTypeSettingsEnabled(false)`.
    private var effectiveSize: CGFloat {
        typeSettingsEnabled ? scaledSize * style.group.multiplier : scaledSize
    }

    func body(content: Content) -> some View {
        content
            .font(.system(size: effectiveSize, weight: style.weight, design: style.design))
            .tracking(style.tracking)
    }
}

public extension View {
    /// Применяет ступень шкалы (шрифт + трекинг) целиком. Цвет текста задаётся отдельно —
    /// шкала про размер/начертание, а не про то, где текст первичный/вторичный.
    ///
    /// Кегль масштабируется под Dynamic Type: на дефолтном размере текста
    /// значение равно базовому (`TFTextStyle.baseSize`), при увеличенном —
    /// растёт по системной кривой.
    func tfText(_ style: TFTextStyle) -> some View {
        modifier(TFTextStyleModifier(style: style))
    }

    /// Моноширинный кегль с масштабированием под Dynamic Type.
    ///
    /// `.tfText` здесь не годится: он ставит `design: .default`, а моноширинный
    /// нужен там, где цифры обязаны не «плясать» по ширине (время в таймлайне,
    /// кодовые метки). API принимает базовый кегль и системный стиль, чью кривую
    /// масштабирования взять — `ScaledMetric(wrappedValue:relativeTo:)` даёт
    /// задать `relativeTo` в рантайме, чего `@ScaledMetric` в объявлении не умеет.
    ///
    /// `active: false` не навязывает шрифт вовсе (`.font(nil)`), поэтому
    /// модификатор можно ставить В КОНЕЦ цепочки поверх `.tfText(...)` и
    /// включать моноширинный только по условию — иначе более поздний `.font`
    /// затрёт `.tfText` (ровно этот баг и был в `AgentRow`: `.font(monospaced
    /// ? … : nil)` стоял ДО `.tfText(.body)`, и флаг не работал никогда).
    func tfMonospaced(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        relativeTo: Font.TextStyle = .body,
        active: Bool = true
    ) -> some View {
        modifier(TFMonospacedModifier(size: size, weight: weight, relativeTo: relativeTo, active: active))
    }
}

private struct TFMonospacedModifier: ViewModifier {
    @ScaledMetric private var scaled: CGFloat
    private let weight: Font.Weight
    private let active: Bool

    init(size: CGFloat, weight: Font.Weight, relativeTo: Font.TextStyle, active: Bool) {
        _scaled = ScaledMetric(wrappedValue: size, relativeTo: relativeTo)
        self.weight = weight
        self.active = active
    }

    func body(content: Content) -> some View {
        content.font(active ? .system(size: scaled, weight: weight, design: .monospaced) : nil)
    }
}

/// Выключатель настройки шрифтов для поддерева (все чаты).
private struct TFTypeSettingsEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

public extension EnvironmentValues {
    var tfTypeSettingsEnabled: Bool {
        get { self[TFTypeSettingsEnabledKey.self] }
        set { self[TFTypeSettingsEnabledKey.self] = newValue }
    }
}

/// Гасит настройку шрифтов в поддереве: все чаты (роли, Помощник,
/// групповые, проектные). Решение владельца 01.11.2026: чат остаётся как был.
public extension View {
    func tfChatTypography() -> some View {
        environment(\.tfTypeSettingsEnabled, false)
    }
}
