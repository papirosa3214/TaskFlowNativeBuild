import SwiftUI
import UIKit

/// Иконка внутри строки текста — с метрикой буквы, а не «как встанет».
///
/// Владелец 10.11.2026: «иконки почему-то неровно чуть-чуть отражаются, сделай
/// чтобы на одной линии». Инлайн-картинка в `Text` прижимается низом к базовой
/// линии, поэтому ассет 64×64 вставал то выше, то ниже соседних букв. Здесь
/// картинка собирается под кегль: высота канвы — `ascent + descent`, сама
/// иконка размером с заглавную букву и низом ровно на базовой линии. Тогда все
/// иконки в абзаце стоят одинаково.
enum ChatInlineIcon {
    /// Геометрия картинки. Чистая функция — проверяется тестом на хосте.
    /// - Returns: размер канвы и прямоугольник, куда рисовать саму иконку.
    static func layout(pointSize: CGFloat, ascent: CGFloat, descent: CGFloat) -> (canvas: CGSize, icon: CGRect) {
        let side = max(1, (pointSize * 0.86).rounded())
        let height = max(side, (ascent + descent).rounded(.up))
        let icon = CGRect(x: 0, y: height - side, width: side, height: side)
        return (CGSize(width: side, height: height), icon)
    }

    /// Готовая картинка под кегль и цвет текста.
    static func image(_ icon: ChatLinkPresentation.Icon, pointSize: CGFloat, color: UIColor) -> UIImage {
        let font = UIFont.systemFont(ofSize: pointSize)
        let (canvas, rect) = layout(pointSize: pointSize, ascent: font.ascender, descent: -font.descender)
        let key = "\(identifier(icon))|\(Int(pointSize.rounded() * 10))|\(colorKey(color))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let renderer = UIGraphicsImageRenderer(size: canvas)
        let image = renderer.image { context in
            switch icon {
            case .asset(let name):
                if let asset = UIImage(named: name) {
                    asset.draw(in: rect)
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
