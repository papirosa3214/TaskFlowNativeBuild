import SwiftUI
import UIKit

/// Иконка внутри строки текста — с метрикой буквы, а не «как встанет».
///
/// Владелец 10.11.2026: «иконки почему-то неровно чуть-чуть отражаются, сделай
/// чтобы на одной линии». Инлайн-картинка в `Text` прижимается низом к базовой
/// линии, поэтому ассет 64×64 вставал то выше, то ниже соседних букв.
///
/// Владелец 11.11.2026: «чипы у ссылок соразмерны тексту, не увеличивая высоту
/// строки». Картинка стоит низом на базовой линии и всей высотой уходит вверх,
/// поэтому канва не может быть выше подъёма шрифта (`ascender`): раньше она
/// равнялась `ascender + descent` и каждая строка со ссылкой становилась выше
/// соседних. Сама иконка — по заглавной букве (`capHeight`), а не 86% кегля.
/// Тогда все иконки в абзаце стоят одинаково, а строка не растёт.
enum ChatInlineIcon {
    /// Геометрия иконки. Чистая функция — проверяется тестом на хосте.
    struct Layout {
        let canvas: CGSize
        let icon: CGRect
        /// Сдвиг вниз от базовой линии (`Text.baselineOffset`), отрицательный.
        let baselineOffset: CGFloat
    }

    /// Владелец 11.11.2026: «ярлычки микроскопические» и «стоят выше». Иконка —
    /// почти в кегль (а не с заглавную букву) и опущена так, что её центр на
    /// середине заглавной буквы. Строку не раздвигает: верх не выше подъёма
    /// шрифта, низ не ниже спуска.
    static func layout(pointSize: CGFloat, ascent: CGFloat, descent: CGFloat, capHeight: CGFloat) -> Layout {
        let cap = capHeight > 0 ? capHeight : pointSize * 0.7
        let fit = max(1, min(pointSize * 0.92, ascent + descent))
        var side = fit.rounded()
        var offset = cap / 2 - side / 2
        // Не выходить за спуск и подъём шрифта.
        if offset < -descent { offset = -descent }
        if side + offset > ascent { side = max(1, (ascent - offset).rounded(.down)) }
        let canvas = CGSize(width: side, height: side)
        return Layout(canvas: canvas, icon: CGRect(origin: .zero, size: canvas), baselineOffset: offset)
    }

    /// Готовая картинка под кегль и цвет текста.
    static func layout(pointSize: CGFloat) -> Layout {
        let font = UIFont.systemFont(ofSize: pointSize)
        return layout(pointSize: pointSize, ascent: font.ascender, descent: -font.descender,
                      capHeight: font.capHeight)
    }

    static func image(_ icon: ChatLinkPresentation.Icon, pointSize: CGFloat, color: UIColor) -> UIImage {
        let geometry = layout(pointSize: pointSize)
        let canvas = geometry.canvas, rect = geometry.icon
        let key = "\(identifier(icon))|\(Int(pointSize.rounded() * 10))|\(colorKey(color))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let renderer = UIGraphicsImageRenderer(size: canvas)
        let image = renderer.image { context in
            switch icon {
            case .asset(let name):
                if let asset = UIImage(named: name) {
                    drawAsset(asset, named: name, in: rect)
                } else {
                    drawSymbol("doc.text", in: rect, color: color)
                }
            case .symbol(let name):
                drawSymbol(name, in: rect, color: color)
            }
            _ = context
        }
        cache.setObject(image, forKey: key)
        return image
    }

    private static let cache = NSCache<NSString, UIImage>()

    /// Ассет рисуется по видимой части, без прозрачных полей: у файлов набора
    /// pierre поле вокруг значка, и он выходил мельче буквы и висел над базовой
    /// линией (владелец 11.11.2026: «мизерные и стоят выше»). Видимая часть
    /// вписывается в прямоугольник буквы и садится низом на базовую линию.
    private static func drawAsset(_ asset: UIImage, named name: String, in rect: CGRect) {
        let size = asset.size
        let bounds = opaqueBounds(of: asset, named: name)
            ?? CGRect(origin: .zero, size: CGSize(width: 1, height: 1))
        guard bounds.width > 0, bounds.height > 0, size.width > 0, size.height > 0 else {
            asset.draw(in: rect); return
        }
        let visible = CGSize(width: bounds.width * size.width, height: bounds.height * size.height)
        let scale = min(rect.width / visible.width, rect.height / visible.height)
        let full = CGSize(width: size.width * scale, height: size.height * scale)
        let drawnVisible = CGSize(width: visible.width * scale, height: visible.height * scale)
        let visibleOrigin = CGPoint(x: rect.minX + (rect.width - drawnVisible.width) / 2,
                                    y: rect.maxY - drawnVisible.height)
        let origin = CGPoint(x: visibleOrigin.x - bounds.minX * full.width,
                             y: visibleOrigin.y - bounds.minY * full.height)
        asset.draw(in: CGRect(origin: origin, size: full))
    }

    private static var opaqueCache: [String: CGRect] = [:]

    /// Видимая часть картинки в долях (0…1) от её размера.
    static func opaqueBounds(of image: UIImage, named name: String) -> CGRect? {
        if let cached = opaqueCache[name] { return cached }
        guard let cg = image.cgImage else { return nil }
        let width = cg.width, height = cg.height
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(data: &pixels, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else { return nil }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[y * width + x] > 8 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        let result = CGRect(x: CGFloat(minX) / CGFloat(width), y: CGFloat(minY) / CGFloat(height),
                            width: CGFloat(maxX - minX + 1) / CGFloat(width),
                            height: CGFloat(maxY - minY + 1) / CGFloat(height))
        opaqueCache[name] = result
        return result
    }

    private static func identifier(_ icon: ChatLinkPresentation.Icon) -> String {
        switch icon {
        case .asset(let name): return "asset:" + name
        case .symbol(let name): return "symbol:" + name
        }
    }

    private static func colorKey(_ color: UIColor) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%.2f%.2f%.2f%.2f", r, g, b, a)
    }

    private static func drawSymbol(_ name: String, in rect: CGRect, color: UIColor) {
        let config = UIImage.SymbolConfiguration(pointSize: rect.height * 0.92, weight: .medium)
        guard let symbol = UIImage(systemName: name, withConfiguration: config)?
            .withTintColor(color, renderingMode: .alwaysOriginal) else { return }
        let size = symbol.size
        let scale = min(rect.width / max(size.width, 1), rect.height / max(size.height, 1))
        let drawSize = CGSize(width: size.width * scale, height: size.height * scale)
        let origin = CGPoint(x: rect.midX - drawSize.width / 2, y: rect.maxY - drawSize.height)
        symbol.draw(in: CGRect(origin: origin, size: drawSize))
    }
}
