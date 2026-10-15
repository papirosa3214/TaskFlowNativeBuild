import SwiftUI

extension View {
    /// Точка привязки подсказки. Рамка — в координатах окна (`.global`),
    /// потому что оверлей подсказок живёт в отдельном окне поверх листов и
    /// шапок. Нажатие на элемент засчитывает шаг, сам элемент работает как
    /// обычно (жест одновременный, не перехватывает нажатие).
    func hintAnchor(_ id: String) -> some View {
        modifier(HintAnchorModifier(id: id))
    }
}

private struct HintAnchorModifier: ViewModifier {
    let id: String

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                HintCenter.shared.report(anchor: id, frame: frame)
            }
            .onDisappear { HintCenter.shared.remove(anchor: id) }
            .simultaneousGesture(TapGesture().onEnded { HintCenter.shared.tapped(anchor: id) })
    }
}
