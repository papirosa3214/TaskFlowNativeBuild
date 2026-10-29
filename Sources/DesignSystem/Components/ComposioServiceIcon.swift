import SwiftUI
import UIKit

/// Иконка сервиса Composio — серый знак без подложки, как остальные знаки
/// в настройках (`TFListRow.IconStyle.plain`).
///
/// Логотипы Composio приходят как SVG (`https://logos.composio.dev/api/<slug>`),
/// а iOS SVG не рисует: в списке подключений вместо иконок был generic-значок
/// «link». Поэтому иконки заранее нарисованы в серый (`Tools/composio_icons/`)
/// и лежат в бандле как `ComposioIcons/<slug>.png`. Сервис без иконки (у 53
/// из 1687 логотип ведёт на чужую страницу) показывается общим значком.
public struct ComposioServiceIcon: View {
    let slug: String
    /// Значок, когда логотипа нет.
    var fallback: String = "square.grid.2x2"

    public init(slug: String, fallback: String = "square.grid.2x2") {
        self.slug = slug
        self.fallback = fallback
    }

    public var body: some View {
        Group {
            if let image = ComposioIconStore.image(for: slug) {
                Image(uiImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: TFIconSize.md, height: TFIconSize.md)
                    .foregroundStyle(Color.tfDim)
            } else {
                Image(systemName: fallback)
                    .font(.system(size: TFIconSize.sm))
                    .foregroundStyle(Color.tfDim)
            }
        }
        .frame(width: 40, height: 40)
    }
}

/// Иконки сервисов Composio из бандла. Загрузка ленивая и кэшируется:
/// список каталога — это сотни строк, картинки нужны только видимым.
public enum ComposioIconStore {
    /// Папка с иконками в бандле (`project.yml` → `Resources/ComposioIcons`).
    public static let folderName = "ComposioIcons"

    private static let cache = Cache()

    public static func image(for slug: String) -> UIImage? {
        if let cached = cache.image(for: slug) { return cached }
        guard let image = load(slug: slug) else { return nil }
        cache.set(image, for: slug)
        return image
    }

    private static func load(slug: String) -> UIImage? {
        if let url = Bundle.main.url(forResource: slug, withExtension: "png", subdirectory: folderName) {
            return UIImage(contentsOfFile: url.path)
        }
        // Если папка попала в бандл свёрнутым (без подкаталога) — ищем по имени.
        return UIImage(named: "composio-\(slug)")
    }

    /// Простой кэш: словарь с защитой от гонок (список прокручивается быстро).
    /// Кэш знаков с пределом: каталог «Все интеграции» — это 1600 строк, и
    /// без предела все знаки остались бы в памяти (по 57 КБ каждый).
    /// `NSCache` сам вытесняет старые, когда память понадобится системе.
    private final class Cache {
        private let images = NSCache<NSString, UIImage>()

        init() {
            images.countLimit = 300
        }

        func image(for slug: String) -> UIImage? {
            images.object(forKey: slug as NSString)
        }

        func set(_ image: UIImage, for slug: String) {
            images.setObject(image, forKey: slug as NSString)
        }
    }
}
