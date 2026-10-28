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

    static let storageKey = "taskflow_text_tone"
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
        guard let raw = UserDefaults.standard.string(forKey: storageKey),
              let tone = TFTextTone(rawValue: raw) else { return .pure }
        return tone
    }
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
