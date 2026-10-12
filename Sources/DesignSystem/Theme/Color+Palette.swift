import SwiftUI

// Палитра TaskFlow: тёмная ветка из spec/DESIGN-TOKENS.md §1, светлая — с проверкой контраста.
//
// Поверхности и смысловые акценты адаптируются к выбранной теме.
// Светлые акценты темнее для читаемых подписей на белых/серых поверхностях.
// Выбор задаётся AppAppearance на уровне сцены; системные компоненты
// получают ту же тему без собственных подложек и имитаций.
public extension Color {

    /// Строит динамический цвет: разные hex для тёмной/светлой темы, как в web `:root[data-theme]`.
    private static func dynamic(dark: String, light: String) -> Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }

    // MARK: Поверхность (переключается темой)

    /// Фон экрана, самый нижний слой глубины.
    static let tfBackground = dynamic(dark: "#171717", light: "#f4f4f5")
    /// Поверхность: карточки, шапка, шторка, поле, панель таббара.
    static let tfCard = dynamic(dark: "#242424", light: "#ffffff")
    /// Элемент внутри карточки: подложка тумблера, выпадающее меню, чип.
    static let tfCard2 = dynamic(dark: "#2b2b2b", light: "#ececee")
    /// Основной текст, активная иконка таббара.
    static let tfText = dynamic(dark: "#ffffff", light: "#171717")
    /// Вторичный текст (подписи, второй уровень важности).
    static let tfSub = dynamic(dark: "#a6a6a6", light: "#424242")
    /// Приглушённые подписи и неактивные иконки; текст остаётся читаемым.
    static let tfDim = dynamic(dark: "#949494", light: "#4e4e4e")

    /// Единственная граница/разделитель — полупрозрачная белая (тёмная) / чёрная (светлая), не сплошной цвет.
    static let tfStroke = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.09)
            : UIColor.black.withAlphaComponent(0.09)
    })

    /// Системный вторичный/третичный тон в тёмной теме; читаемая подпись в светлой.
    static let tfReadableSecondary = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor.secondaryLabel.resolvedColor(with: trait)
            : UIColor(Color.tfSub).resolvedColor(with: trait)
    })
    static let tfReadableTertiary = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor.tertiaryLabel.resolvedColor(with: trait)
            : UIColor(Color.tfDim).resolvedColor(with: trait)
    })
    /// Маленькие предупреждения: сохраняем прежнюю прозрачность только в тёмной теме.
    static let tfWarningText = Color(uiColor: UIColor { trait in
        UIColor(Color.tfOrange).resolvedColor(with: trait)
            .withAlphaComponent(trait.userInterfaceStyle == .dark ? 0.8 : 1)
    })
    static let tfPickerArrow = Color(uiColor: UIColor { trait in
        UIColor(Color.tfDim).resolvedColor(with: trait)
            .withAlphaComponent(trait.userInterfaceStyle == .dark ? 0.35 : 1)
    })
    /// Вне текущего периода календаря: приглушаем только в тёмной теме.
    static func tfMutedText(darkOpacity: Double) -> Color {
        Color(uiColor: UIColor { trait in
            UIColor(Color.tfDim).resolvedColor(with: trait)
                .withAlphaComponent(trait.userInterfaceStyle == .dark ? darkOpacity : 1)
        })
    }

    /// Пользовательские цвета проектов/меток: сохраняем оттенок, затемняем только текст в светлой теме.
    /// Цвет API и заливки/аватары остаются исходными; целевой контраст текста ≥7:1 на tfCard2.
    static func tfReadableText(_ color: Color) -> Color {
        Color(uiColor: UIColor { trait in
            let resolved = UIColor(color).resolvedColor(with: trait)
            guard trait.userInterfaceStyle != .dark else { return resolved }
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, alpha: CGFloat = 0
            guard resolved.getRed(&r, green: &g, blue: &b, alpha: &alpha) else { return UIColor(Color.tfText).resolvedColor(with: trait) }
            func luminance(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> Double {
                func linear(_ v: CGFloat) -> Double {
                    let x = Double(v)
                    return x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
                }
                return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
            }
            var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0
            UIColor(Color.tfCard2).resolvedColor(with: trait).getRed(&br, green: &bg, blue: &bb, alpha: nil)
            let maximum = (luminance(br, bg, bb) + 0.05) / 7 - 0.05
            var low: CGFloat = 0, high: CGFloat = 1
            if luminance(r, g, b) > maximum {
                for _ in 0..<16 {
                    let middle = (low + high) / 2
                    if luminance(r * middle, g * middle, b * middle) <= maximum { low = middle }
                    else { high = middle }
                }
            } else { low = 1 }
            return UIColor(red: r * low, green: g * low, blue: b * low, alpha: 1)
        })
    }

    // MARK: Акценты (тот же смысл и тон, адаптивная контрастность)

    /// Единственный акцент приложения — активная вкладка/пункт, «сегодня», просрочка, удаление.
    /// Как заливку под белый текст НЕ использовать — контраст 4.08:1, ниже нормы 4.5. См. `tfRedSolid`.
        static let tfRed = dynamic(dark: "#e44332", light: "#c53426")
    /// Заливка ИМЕННО под белый текст 15px/600 (`Button variant="primary"`) — контраст 4.67:1.
    static let tfRedSolid = Color(hex: "#d63a28")
    /// Приоритет P2, предупреждения.
    static let tfOrange = dynamic(dark: "#ff9a14", light: "#945200")
    /// Прикладной цвет меток/категорий.
    static let tfPink = dynamic(dark: "#ff7a8a", light: "#b32a55")
    /// Приоритет P3, статус «на проверке».
    static let tfBlue = dynamic(dark: "#4a9fd8", light: "#246da3")
    /// Прикладной цвет меток/категорий.
    static let tfPurple = dynamic(dark: "#a78bfa", light: "#7353b6")
    /// Прикладной цвет; маркер-выделитель в заметках.
    static let tfYellow = dynamic(dark: "#f7d038", light: "#7b6500")
    /// Ошибки, «агент пропал» — тревожное состояние, не путать с `tfRed`-акцентом.
    static let tfCoral = dynamic(dark: "#ff6b6b", light: "#bc3342")
    /// Статус «в работе» (агент), единый зелёный/бирюзовый акцент состояния.
    static let tfTeal = dynamic(dark: "#35b8a3", light: "#147466")
    /// Тот же смысловой ряд, что teal — темнее и насыщеннее.
    static let tfGreen = dynamic(dark: "#15937e", light: "#14745f")

    /// 30.09.2026, владелец: промежуточный тон (#1D1D1D) между `tfBackground`
    /// и `tfCard` давал видимую полосу там, где фон списка внутри шторки не
    /// докрашивает до края (например, в зазоре `.listSectionSpacing` между
    /// секциями карточки задачи) — сквозь эту прореху проступал именно этот,
    /// более светлый оттенок шторки. Уравнен с `tfBackground`: шторка и
    /// список внутри неё теперь один и тот же цвет, и утечка фона нигде не
    /// видна, даже там, где сама прореха в вёрстке не найдена и не закрыта.
    /// Было отдельным hex (#1D1D1D) — до этого его же 02.09.2026 консолидировали
    /// из трёх разных мест (`RootShellView`, `TodayScreen`, `TaskDetailScreen`).
    static let tfSheetBackground = tfBackground

    /// Ink-цвет чипа сетки часов (Today/Upcoming) — тёмный текст поверх
    /// цветной плашки, был заведён отдельно в двух местах под разными
    /// именами (`todayChipInk`, `UpcomingHoursView`) с одним и тем же hex.
    static let tfHourChipInk = Color(hex: "#141414")

    // MARK: Служебные — вне токенов темы, не переключаются намеренно (системные/брендовые)

    /// Свайп-действие строки задачи «Изменить» — буквальный iOS-цвет жеста.
    static let tfSwipeEdit = Color(hex: "#007AFF")
    /// Свайп-действие строки задачи «Удалить» — буквальный iOS-цвет жеста.
    static let tfSwipeDelete = Color(hex: "#FF3B30")
}

/// Приоритеты: прежние оттенки в тёмной теме, читаемые акценты в светлой.
public enum TaskPriority: Int, CaseIterable, Sendable {
    case urgent = 1   // P1 «Срочный»
    case high = 2     // P2 «Высокий»
    case medium = 3   // P3 «Средний»
    case low = 4      // P4 «Низкий»

    public var color: Color {
        switch self {
        case .urgent: .tfRed
        case .high: .tfOrange
        case .medium: .tfBlue
        case .low: .tfSub
        }
    }

    public var label: String {
        switch self {
        case .urgent: "Срочный"
        case .high: "Высокий"
        case .medium: "Средний"
        case .low: "Низкий"
        }
    }
}

/// 02.09.2026, аудит DESIGN.md: заглушка «нет цвета» — проект/метка/аватар,
/// которым сервер не прислал свой цвет. Строкой (не `Color`), потому что
/// большинство мест парсят её ВМЕСТЕ с реальным цветом через один и тот же
/// `Color(hex: someOptionalString ?? TFHexDefault.unassigned)` — было
/// захардкожено `"#A6A6A6"` по отдельности штук 25 раз в разных экранах.
public enum TFHexDefault {
    public static let unassigned = "#A6A6A6"
}

// MARK: - Hex → UIColor/Color

extension UIColor {
    /// Парсер `#RRGGBB` — единственный способ завести цвет в проекте (спека: hex-литералы только тут, не в разметке экранов).
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: s).scanHexInt64(&rgb)
        if s.count < 6 { s = String(repeating: "0", count: 6 - s.count) + s }
        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >> 8) & 0xFF) / 255
        let b = Double(rgb & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}

public extension Color {
    /// Тот же парсер для мест, где нужен именно `Color`, а не `UIColor` (акценты без dark/light-варианта).
    init(hex: String) {
        self.init(uiColor: UIColor(hex: hex))
    }

    /// Обратный путь `Color → "#RRGGBB"` — просьба владельца 03.09.2026:
    /// «RGB-шкала, чтобы сам выбирал оттенки» у меток — нативный `ColorPicker`
    /// отдаёт `Color`, а модель хранит цвет hex-строкой, нужен мост обратно.
    func toHex() -> String {
        let resolved = resolve(in: EnvironmentValues())
        let r = Int((resolved.red * 255).rounded())
        let g = Int((resolved.green * 255).rounded())
        let b = Int((resolved.blue * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
