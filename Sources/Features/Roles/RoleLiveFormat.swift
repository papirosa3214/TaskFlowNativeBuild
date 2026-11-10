import Foundation

/// Длительность и число шагов словами — общие для живого хода и истории.
///
/// Вынесено из `RoleLiveTurnView` (10.11.2026), чтобы подпись работы
/// проверялась тестом на хосте: экран тянет UIKit и SwiftUI.
enum RoleLiveFormat {
    /// «1 шаг / 3 шага / 7 шагов».
    static func steps(_ count: Int) -> String {
        let mod100 = count % 100
        let word: String
        if mod100 >= 11 && mod100 <= 14 {
            word = "шагов"
        } else {
            switch count % 10 {
            case 1: word = "шаг"
            case 2, 3, 4: word = "шага"
            default: word = "шагов"
            }
        }
        return "\(count) \(word)"
    }

    /// «42 с», «3 мин 5 с», «12 мин».
    static func duration(seconds: Int) -> String {
        let s = max(0, seconds)
        if s < 60 { return "\(s) с" }
        let minutes = s / 60
        let rest = s % 60
        return rest == 0 ? "\(minutes) мин" : "\(minutes) мин \(rest) с"
    }
}
