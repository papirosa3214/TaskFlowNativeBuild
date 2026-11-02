import Foundation
import SwiftUI

/// Маппинг `CoordinationTint` → реальные цвета SwiftUI. Этот файл — единственное место, где tint
/// превращается в цвет: чтобы при правке палитры не пришлось трогать логику графа и тесты.
extension CoordinationTint {
    /// Цвет узла/чипа для светлой темы. Контраст с `tfCard`/`tfCard2` ≥ 4.5:1,
    /// для `stalled_manual_review`/`step_stalled` — AAA 7:1.
    var light: Color {
        switch self {
        case .neutralBlue: return Color(red: 0.27, green: 0.49, blue: 0.85)
        case .dimGray: return Color(white: 0.45)
        case .dottedGray: return Color(white: 0.55)
        case .amber: return Color(red: 0.85, green: 0.62, blue: 0.10)
        case .pink: return Color(red: 0.83, green: 0.30, blue: 0.45)
        // «Идёт работа» (active_run) — синий, а не красный (02.11.2026): молния
        // красным читалась как тревога, хотя это обычное состояние.
        case .accentPulse: return Color(red: 0.27, green: 0.49, blue: 0.85)
        case .softBlue: return Color(red: 0.40, green: 0.65, blue: 0.92)
        case .softCyan: return Color(red: 0.45, green: 0.70, blue: 0.78)
        case .darkRedCritical: return Color(red: 0.62, green: 0.10, blue: 0.10)  // AAA 7:1
        case .violet: return Color(red: 0.45, green: 0.28, blue: 0.72)
        case .darkOrange: return Color(red: 0.82, green: 0.42, blue: 0.10)
        case .violetOutline: return Color(red: 0.55, green: 0.36, blue: 0.82)
        case .softGreen: return Color(red: 0.30, green: 0.62, blue: 0.36)
        case .unknownGray: return Color(white: 0.62)
        }
    }

    var colorDark: Color {
        switch self {
        case .neutralBlue: return Color(red: 0.55, green: 0.74, blue: 1.00)
        case .dimGray: return Color(white: 0.70)
        case .dottedGray: return Color(white: 0.78)
        case .amber: return Color(red: 1.00, green: 0.78, blue: 0.30)
        case .pink: return Color(red: 1.00, green: 0.55, blue: 0.66)
        case .accentPulse: return Color(red: 0.45, green: 0.72, blue: 1.00)
        case .softBlue: return Color(red: 0.62, green: 0.82, blue: 1.00)
        case .softCyan: return Color(red: 0.65, green: 0.85, blue: 0.90)
        case .darkRedCritical: return Color(red: 0.95, green: 0.30, blue: 0.30)  // AAA на тёмном
        case .violet: return Color(red: 0.78, green: 0.60, blue: 0.95)
        case .darkOrange: return Color(red: 1.00, green: 0.62, blue: 0.30)
        case .violetOutline: return Color(red: 0.85, green: 0.66, blue: 1.00)
        case .softGreen: return Color(red: 0.55, green: 0.85, blue: 0.62)
        case .unknownGray: return Color(white: 0.85)
        }
    }

    /// Цвет с учётом текущей цветовой схемы.
    @Environment(\.colorScheme) static var colorSchemeRef: ColorScheme
    func color(for scheme: ColorScheme) -> Color {
        scheme == .dark ? colorDark : light
    }

    /// Имя SF Symbol для чипа и узла. `nil` = без иконки.
    var symbol: String? {
        switch self {
        case .neutralBlue: return "circle"
        case .dimGray: return "link"
        case .dottedGray: return "clock"
        case .amber: return "questionmark.circle"
        case .pink: return "key"
        case .accentPulse: return "arrow.triangle.2.circlepath"
        case .softBlue: return "tray.full"
        case .softCyan: return "arrow.clockwise"
        case .darkRedCritical: return "exclamationmark.triangle"
        case .violet: return "eye"
        case .darkOrange: return "arrow.clockwise"
        case .violetOutline: return "checkmark.seal"
        case .softGreen: return "checkmark.circle"
        case .unknownGray: return "questionmark"
        }
    }
}