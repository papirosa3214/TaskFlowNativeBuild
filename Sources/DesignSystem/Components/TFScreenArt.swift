import SwiftUI

/// Картинка-фон экрана: панель триптиха под содержимым (владелец 15.11.2026 —
/// «фоном сделать, чуть-чуть притемнить, чтобы не бросались в глаза, а поверх
/// обычный текст»; каждая панель — своему экрану).
///
/// Картинка только ФОН: она лежит под списком, не перехватывает нажатия и
/// ничего не рассказывает VoiceOver. Содержимое остаётся плоским — строки и
/// карточки рисуются на картинке, без собственных плашек (решение владельца
/// 15.11.2026: «они должны быть плоскими, не на плашках»).
public enum TFScreenArt: String, CaseIterable {
    /// Левая панель триптиха — «Входящие».
    case inbox = "BackdropInbox"
    /// Средняя панель — «Проекты и задачи».
    case projects = "BackdropProjects"
    /// Правая панель — «Обзор».
    case overview = "BackdropOverview"

    /// Плотность притемнения. Одна цифра на все экраны: 0 — картинка как есть,
    /// 1 — глухой цвет фона. По умолчанию 0.72 — той темноты, которую владелец
    /// выбрал 15.11.2026 («чуть потемнее, пригасить»).
    public static let dim: Double = 0.72
}

/// Слой картинки: заполняет экран, обрезает по краям и гасит затемнением.
public struct TFScreenArtLayer: View {
    private let art: TFScreenArt
    private let dim: Double

    public init(_ art: TFScreenArt, dim: Double = TFScreenArt.dim) {
        self.art = art
        self.dim = dim
    }

    public var body: some View {
        GeometryReader { proxy in
            Image(art.rawValue)
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .overlay(.black.opacity(dim))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview("Фон экрана из триптиха") {
    List {
        Section("Входящие") {
            Text("Согласовать смету на ноябрь")
            Text("Проверить бэкапы .110")
        }
    }
    .tfScreenBackground(art: .inbox)
    .tfNativeHeader("Фон из триптиха")
}
