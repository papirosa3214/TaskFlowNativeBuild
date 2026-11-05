import SwiftUI

/// Один сохранённый выбор для всего приложения, включая модальные экраны.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    static let storageKey = "taskflow_appearance"
    static let legacyStorageKey = "taskflow_settings_dark_theme"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Как в системе"
        case .light: "Светлая"
        case .dark: "Тёмная"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// Сохраняет старый выбор тумблера; без выбора остаётся привычная тёмная тема.
    @discardableResult
    static func migratePreference(in defaults: UserDefaults = .standard) -> AppAppearance {
        if let raw = defaults.string(forKey: storageKey) {
            return AppAppearance(rawValue: raw) ?? .dark
        }
        let legacy = defaults.object(forKey: legacyStorageKey) as? Bool
        let appearance: AppAppearance = legacy == false ? .light : .dark
        defaults.set(appearance.rawValue, forKey: storageKey)
        return appearance
    }
}


/// Тон основного текста (просьба владельца 28.10.2026: «Настройки → Внешний вид»).
/// Выбор действует в тёмной теме: на светлом фоне тёплый оттенок читается как грязь.
/// Отдельные места вёрстки (кнопка с белым текстом, аватар, бейдж) берут тон же —
/// они живут на цветной плашке и от темы не зависят.
enum TFTextTone: String, CaseIterable, Identifiable {
    case pure, paper, cream, ash

    static let storageKey = TypographyPreferences.toneKey(for: .app)
    static let chatStorageKey = TypographyPreferences.toneKey(for: .chat)
    var id: String { rawValue }

    var title: String {
        switch self {
        case .pure: "Чистый белый"
        case .paper: "Тёплая бумага"
        case .cream: "Крем"
        case .ash: "Пепел"
        }
    }

    /// Значение тона в тёмной теме. `pure` — прежнее поведение приложения.
    var hex: String {
        switch self {
        case .pure: "#ffffff"
        case .paper: "#f6f0e4"
        case .cream: "#f4e7cf"
        case .ash: "#e8e5df"
        }
    }

    var color: Color { Color(hex: hex) }

    /// Сохранённый выбор; по умолчанию — чистый белый, то есть как было до настройки.
    static var saved: TFTextTone {
        saved(for: .app)
    }

    static func saved(for context: TypographyContext) -> TFTextTone {
        guard let raw = UserDefaults.standard.string(forKey: TypographyPreferences.toneKey(for: context)),
              let tone = TFTextTone(rawValue: raw) else { return .pure }
        return tone
    }
}


/// Гарнитура приложения (владелец, 01.11.2026): 11 шрифтов с кириллицей,
/// все под открытой лицензией OFL. Файлы — в `Resources/Fonts`,
/// регистрация — `UIAppFonts` в `project.yml`.
enum TFTypeFace: String, CaseIterable, Identifiable {
    case system, golos, onest, nunito, comfortaa, unbounded
    case lora, playfair, cormorant, caveat, marck, mono

    static let storageKey = TypographyPreferences.faceKey(for: .app)
    static let chatStorageKey = TypographyPreferences.faceKey(for: .chat)
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Системная"
        case .golos: "Golos Text"
        case .onest: "Onest"
        case .nunito: "Nunito"
        case .comfortaa: "Comfortaa"
        case .unbounded: "Unbounded"
        case .lora: "Lora"
        case .playfair: "Playfair Display"
        case .cormorant: "Cormorant Garamond"
        case .caveat: "Caveat"
        case .marck: "Marck Script"
        case .mono: "JetBrains Mono"
        }
    }

    var subtitle: String {
        switch self {
        case .system: "San Francisco, как сейчас"
        case .golos: "аккуратный гротеск"
        case .onest: "мягкий нейтральный"
        case .nunito: "округлый, дружелюбный"
        case .comfortaa: "геометричный округлый"
        case .unbounded: "широкий дисплейный"
        case .lora: "книжный serif"
        case .playfair: "элегантный serif"
        case .cormorant: "тонкий книжный"
        case .caveat: "рукописный"
        case .marck: "каллиграфический"
        case .mono: "моноширинный"
        }
    }

    /// CSS family для HTML-артефактов в ленте чата.
    var cssFamily: String {
        switch self {
        case .system: "-apple-system"
        case .golos: "'Golos Text'"
        case .onest: "'Onest'"
        case .nunito: "'Nunito'"
        case .comfortaa: "'Comfortaa'"
        case .unbounded: "'Unbounded'"
        case .lora: "'Lora'"
        case .playfair: "'Playfair Display'"
        case .cormorant: "'Cormorant Garamond'"
        case .caveat: "'Caveat'"
        case .marck: "'Marck Script'"
        case .mono: "'JetBrains Mono'"
        }
    }

    /// PostScript-имена: (обычное, жирное). У `system` — nil.
    var names: (regular: String, bold: String)? {
        switch self {
        case .system: nil
        case .golos: ("GolosText-Regular", "GolosText-Bold")
        case .onest: ("Onest-Regular", "Onest-Bold")
        case .nunito: ("Nunito-Regular", "Nunito-Bold")
        case .comfortaa: ("Comfortaa-Regular", "Comfortaa-Bold")
        case .unbounded: ("Unbounded-Regular", "Unbounded-Bold")
        case .lora: ("Lora-Regular", "Lora-Bold")
        case .playfair: ("PlayfairDisplay-Regular", "PlayfairDisplay-Bold")
        case .cormorant: ("CormorantGaramond-Regular", "CormorantGaramond-Bold")
        case .caveat: ("Caveat-Regular", "Caveat-Bold")
        case .marck: ("MarckScript-Regular", "MarckScript-Regular")
        case .mono: ("JetBrainsMono-Regular", "JetBrainsMono-Bold")
        }
    }

    static var saved: TFTypeFace {
        saved(for: .app)
    }

    static func saved(for context: TypographyContext) -> TFTypeFace {
        guard let raw = UserDefaults.standard.string(forKey: TypographyPreferences.faceKey(for: context)),
              let face = TFTypeFace(rawValue: raw) else { return .system }
        return face
    }

    /// Сохранить гарнитуру и перерисовать приложение.
    ///
    /// Счётчик `taskflow_type_revision` держит корень `TaskFlowApp` в
    /// `@AppStorage` и кладёт в `.id(...)` — без его роста дерево экранов не
    /// пересоздаётся и выбранная гарнитура не видна (владелец 01.11.2026:
    /// «шрифты вроде меняются, но большинство не меняет ничего»).
    static func save(_ face: TFTypeFace) {
        save(face, for: .app)
    }

    static func save(_ face: TFTypeFace, for context: TypographyContext) {
        UserDefaults.standard.set(face.rawValue, forKey: TypographyPreferences.faceKey(for: context))
        let next = UserDefaults.standard.integer(forKey: TFTypeScale.revisionKey) + 1
        UserDefaults.standard.set(next, forKey: TFTypeScale.revisionKey)
    }

    /// Шрифт нужного кегля. Жирность сводится к двум файлам: semibold и bold берут Bold.
    func font(size: CGFloat, weight: Font.Weight, design: Font.Design = .default) -> Font {
        guard let names else { return .system(size: size, weight: weight, design: design) }
        let isBold = weight == .bold || weight == .semibold || weight == .heavy || weight == .black
        return .custom(isBold ? names.bold : names.regular, size: size)
    }

    /// То же, но с выключателем: в чатах гарнитура остаётся системной.
    static func active(size: CGFloat, weight: Font.Weight, design: Font.Design = .default, enabled: Bool) -> Font {
        let face = enabled ? TFTypeFace.saved : TFTypeFace.system
        return face.font(size: size, weight: weight, design: design)
    }
}

/// Пять групп типографики (владелец, 01.11.2026): всё приложение выровнено
/// по пяти размерам, у каждой группы свой регулятор в «Внешний вид».
/// Группа — вес текста в том месте, где он стоит, а не тип элемента.
/// Все чаты (роли, Помощник, групповые, проектные) исключены: их корни
/// ставят `.tfTypeSettingsEnabled(false)`.
enum TFTypeGroup: String, CaseIterable, Identifiable {
    case heading, subheading, body, secondary, tertiary

    var id: String { rawValue }
    var storageKey: String { "taskflow_type_\(rawValue)" }

    /// Единственные пять размеров текста в приложении.
    var baseSize: CGFloat {
        switch self {
        case .heading: 22
        case .subheading: 17
        case .body: 15
        case .secondary: 13
        case .tertiary: 11
        }
    }

    var title: String {
        switch self {
        case .heading: "Заголовок"
        case .subheading: "Подзаголовок"
        case .body: "Основной текст"
        case .secondary: "Второстепенный текст"
        case .tertiary: "Мелкий текст"
        }
    }

    var subtitle: String {
        switch self {
        case .heading: "Шапка экрана"
        case .subheading: "Разделы и заголовки карточек"
        case .body: "Названия задач, основной текст"
        case .secondary: "Описание, срок, статус"
        case .tertiary: "Бейджи, счётчики, дни недели"
        }
    }

    /// Множитель выбранной ступени этой группы.
    var multiplier: CGFloat { TFTypeScale.saved(for: self).multiplier }

    static func saved(_ group: TFTypeGroup) -> TFTypeScale { TFTypeScale.saved(for: group) }
}

/// Ступень регулятора группы: множитель к базовому кеглю группы.
enum TFTypeScale: String, CaseIterable, Identifiable {
    case small, compact, standard, large, xlarge

    var id: String { rawValue }

    var multiplier: CGFloat {
        switch self {
        case .small: 0.85
        case .compact: 0.92
        case .standard: 1
        case .large: 1.08
        case .xlarge: 1.17
        }
    }

    var title: String {
        switch self {
        case .small: "Мельче"
        case .compact: "Чуть мельче"
        case .standard: "Обычный"
        case .large: "Чуть крупнее"
        case .xlarge: "Крупнее"
        }
    }

    static func saved(for group: TFTypeGroup) -> TFTypeScale {
        guard let raw = UserDefaults.standard.string(forKey: group.storageKey),
              let scale = TFTypeScale(rawValue: raw) else { return .standard }
        return scale
    }

    /// Ключ-счётчик правок шрифтов: корень приложения держит его в
    /// `@AppStorage`, чтобы при смене ступени дерево пересоздалось.
    static let revisionKey = "taskflow_type_revision"

    static func save(_ scale: TFTypeScale, for group: TFTypeGroup) {
        UserDefaults.standard.set(scale.rawValue, forKey: group.storageKey)
        bumpRevision()
    }

    static func saved(forChat group: TFChatTypeGroup) -> TFTypeScale {
        guard let raw = UserDefaults.standard.string(forKey: group.storageKey),
              let scale = TFTypeScale(rawValue: raw) else { return .standard }
        return scale
    }

    static func save(_ scale: TFTypeScale, forChat group: TFChatTypeGroup) {
        UserDefaults.standard.set(scale.rawValue, forKey: group.storageKey)
        bumpRevision()
    }

    private static func bumpRevision() {
        let next = UserDefaults.standard.integer(forKey: revisionKey) + 1
        UserDefaults.standard.set(next, forKey: revisionKey)
    }
}

/// Шкала шрифта чата — по фактической схеме ленты (владелец 03.11.2026).
/// Пятигрупповая шкала приложения чат не читает (`.tfChatTypography()`);
/// здесь свои ступени: основной, жирное, заголовок, код, размышления, мелкий.
enum TFChatTypeGroup: String, CaseIterable, Identifiable {
    case body, emphasis, heading, mono, thinking, meta

    var id: String { rawValue }
    var storageKey: String { "taskflow_chat_type_\(rawValue)" }

    /// Базовые кегли — как сейчас в ленте до регулятора.
    var baseSize: CGFloat {
        switch self {
        case .body: 15          // обычный текст ответа (`TFFont.body`)
        case .emphasis: 15      // **жирное** — тот же кегль, вес bold
        case .heading: 17       // `#` / `##` → headline / title3 ступень
        case .mono: 16          // блоки кода и `inline` (callout monospaced)
        case .thinking: 11      // размышления курсивом (caption + italic)
        case .meta: 12          // подписи шагов, токены, длительности
        }
    }

    var title: String {
        switch self {
        case .body: "Основной"
        case .emphasis: "Жирное"
        case .heading: "Заголовок"
        case .mono: "Код"
        case .thinking: "Размышления"
        case .meta: "Мелкий"
        }
    }

    var subtitle: String {
        switch self {
        case .body: "Текст ответа роли"
        case .emphasis: "Выделение **…** в ответе"
        case .heading: "Заголовки # в ответе"
        case .mono: "Блоки кода и моноширинный"
        case .thinking: "Курсив мыслей роли"
        case .meta: "Подписи, шаги, токены"
        }
    }

    var size: CGFloat { baseSize * TFTypeScale.saved(forChat: self).multiplier }
}

/// Размер текста приложения поверх системного Dynamic Type: одна настройка на всё
/// приложение, потому что все кегли идут через `.tfText(...)` и `ScaledMetric`.
enum TFTextScale: String, CaseIterable, Identifiable {
    case compact, standard, large, xlarge

    static let storageKey = "taskflow_text_scale"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: "Компактный"
        case .standard: "Обычный"
        case .large: "Крупный"
        case .xlarge: "Очень крупный"
        }
    }

    var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .compact: .small
        case .standard: .large
        case .large: .xLarge
        case .xlarge: .xxLarge
        }
    }

    static var saved: TFTextScale {
        guard let raw = UserDefaults.standard.string(forKey: storageKey),
              let scale = TFTextScale(rawValue: raw) else { return .standard }
        return scale
    }
}
