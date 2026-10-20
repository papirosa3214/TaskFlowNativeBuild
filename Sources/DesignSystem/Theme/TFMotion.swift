import SwiftUI

/// Движение — одна шкала на всё приложение (20.10.2026, по WWDC «Designing
/// Fluid Interfaces»). До неё по коду было ~20 разных кривых и длительностей.
/// Новые анимации берут значение ОТСЮДА; старые переводятся при правке файла.
///
/// - Пружины, а не кривые с длительностью: пружину можно перехватить на
///   полпути, и она продолжит с текущего положения и скорости.
/// - Без отскока по умолчанию. Отскок — только когда жест сам нёс импульс
///   (смахнули, бросили карточку).
/// - «Уменьшить движение» — вместо перемещения короткое затухание.
public enum TFMotion {
    /// Отклик на нажатие, переключатели, мелкие изменения состояния.
    public static let tap: Animation = .spring(duration: 0.2, bounce: 0)
    /// Перестановка, появление и раскрытие блоков — основное движение.
    public static let standard: Animation = .spring(duration: 0.35, bounce: 0)
    /// Шторки, панели, большие поверхности.
    public static let sheet: Animation = .spring(duration: 0.3, bounce: 0.15)
    /// После жеста с импульсом (свайп, бросок) — лёгкий отскок.
    public static let fling: Animation = .spring(duration: 0.4, bounce: 0.2)
    /// Замена при «Уменьшить движение»: затухание без смещения.
    public static let reduced: Animation = .easeInOut(duration: 0.2)

    /// Анимация с учётом «Уменьшить движение».
    public static func animation(_ base: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : base
    }
}
