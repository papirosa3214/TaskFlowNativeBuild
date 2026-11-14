import SwiftUI

/// Фон экрана приложения — `tfBackground`.
///
/// 16.10.2026, владелец (кадр с телефона): «Параметры сервера» и
/// «Диагностика» показали чёрное поле вместо фона приложения. Оба экрана
/// строятся на сыром `List`, а тот рисует собственный системный фон
/// (`systemGroupedBackground`), а не фон приложения: на тёмной теме это
/// заметно более чёрное поле, чем `tfBackground` (#171717).
///
/// Модификатор обязателен для ЛЮБОГО списка/формы в приложении:
/// `List { … }.tfScreenBackground()`. Он делает три вещи разом, иначе
/// каждая забытая даёт свой симптом:
///
/// 1. гасит системный фон списка (`scrollContentBackground(.hidden)`),
/// 2. кладёт под содержимое `Color.tfBackground` на всю площадь экрана,
/// 3. оставляет фон под `refreshable`, поэтому оттягивание вниз показывает
///    тот же тон, а не системный серый.
///
/// В шторке (`tfSheet`) фон приложения не кладётся: виден системный цвет шторки.
public struct TFScreenBackgroundModifier: ViewModifier {
    /// Цвет подложки. По умолчанию фон приложения; отличается только у
    /// экранов с намеренно иной подложкой (снимок в `LiveWindowRecheck`).
    private let color: Color
    /// Картинка-фон поверх подложки (владелец 15.11.2026). `nil` — ровный цвет.
    private let art: TFScreenArt?
    @Environment(\.tfInSheet) private var inSheet

    public init(color: Color = .tfBackground, art: TFScreenArt? = nil) {
        self.color = color
        self.art = art
    }

    public func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background {
                if inSheet && color == .tfBackground {
                    Color.clear
                } else if let art {
                    ZStack {
                        color
                        TFScreenArtLayer(art)
                    }
                } else {
                    color
                }
            }
    }
}

public extension View {
    /// Фон приложения под списком/формой. См. `TFScreenBackgroundModifier`.
    /// `art:` — картинка-фон экрана (владелец 15.11.2026).
    func tfScreenBackground(_ color: Color = .tfBackground, art: TFScreenArt? = nil) -> some View {
        modifier(TFScreenBackgroundModifier(color: color, art: art))
    }
}

#Preview("Фон экрана") {
    List {
        Section("Секция") {
            Text("Строка списка")
            Text("Ещё строка")
        }
    }
    .tfScreenBackground()
    .tfNativeHeader("Проверка фона")
}