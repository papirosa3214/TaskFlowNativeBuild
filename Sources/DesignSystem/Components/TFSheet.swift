import SwiftUI

/// Шторка снизу вверх с оригинальным цветом системы (владелец 05.11.2026:
/// «это мы её докрашиваем в чёрный. Надо, чтобы был оригинальный цвет»).
///
/// Всё, что выезжает снизу, подаётся через `tfSheet`, а не голый `.sheet`.
/// Содержимое узнаёт, что лежит в шторке, и фон приложения под ним не
/// кладётся: `tfScreenBackground()` и `TFScreenFill` становятся прозрачными,
/// а на экранах вне шторки остаётся `tfBackground`.
public extension EnvironmentValues {
    @Entry var tfInSheet = false
}

public extension View {
    func tfSheet<Content: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        sheet(isPresented: isPresented, onDismiss: onDismiss) {
            content().environment(\.tfInSheet, true)
        }
    }

    func tfSheet<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        sheet(item: item, onDismiss: onDismiss) { value in
            content(value).environment(\.tfInSheet, true)
        }
    }
}

/// Заливка фоном приложения во весь экран; в шторке прозрачна.
public struct TFScreenFill: View {
    @Environment(\.tfInSheet) private var inSheet

    public init() {}

    public var body: some View {
        (inSheet ? Color.clear : Color.tfBackground).ignoresSafeArea()
    }
}
