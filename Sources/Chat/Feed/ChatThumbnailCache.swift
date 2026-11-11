import Foundation
import ImageIO
import CoreGraphics
#if canImport(UIKit)
import UIKit
#endif

/// Кэш миниатюр картинок-вложений ленты.
///
/// Раньше ячейка качала оригинал и декодировала его на главном потоке в
/// полный размер, а при пересоздании ячейки всё повторялось — с миганием
/// заглушки. Теперь миниатюра уменьшается через ImageIO в фоне до размера
/// показа × scale и лежит в памяти по id вложения; повторный показ берёт её
/// синхронно.
enum ChatThumbnailCache {
    /// Уменьшает картинку из данных до `maxPixelSize` по длинной стороне.
    /// Декодирует сразу (`ShouldCacheImmediately`), чтобы на главном потоке
    /// при отрисовке не было второго декодирования.
    static func downsample(_ data: Data, maxPixelSize: Int) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard maxPixelSize > 0,
              let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }

    /// Длинная сторона миниатюры в пикселях для рамки показа.
    static func maxPixelSize(width: CGFloat, height: CGFloat, scale: CGFloat) -> Int {
        Int((max(width, height) * max(scale, 1)).rounded(.up))
    }

    /// Ключ кэша: id вложения и размер, чтобы разные рамки не путались.
    static func key(id: String, maxPixelSize: Int) -> NSString {
        "\(id)#\(maxPixelSize)" as NSString
    }

    private final class Box { let image: CGImage; init(_ image: CGImage) { self.image = image } }
    private static let storage: NSCache<NSString, Box> = {
        let cache = NSCache<NSString, Box>()
        cache.countLimit = 200
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()

    static func cached(id: String, maxPixelSize: Int) -> CGImage? {
        storage.object(forKey: key(id: id, maxPixelSize: maxPixelSize))?.image
    }

    static func store(_ image: CGImage, id: String, maxPixelSize: Int) {
        storage.setObject(Box(image), forKey: key(id: id, maxPixelSize: maxPixelSize),
                          cost: image.bytesPerRow * image.height)
    }

    /// Уменьшает в фоне и кладёт в кэш.
    static func thumbnail(from data: Data, id: String, maxPixelSize: Int) async -> CGImage? {
        let image = await Task.detached(priority: .userInitiated) {
            downsample(data, maxPixelSize: maxPixelSize)
        }.value
        if let image { store(image, id: id, maxPixelSize: maxPixelSize) }
        return image
    }

    #if canImport(UIKit)
    static func cachedImage(id: String, maxPixelSize: Int) -> UIImage? {
        cached(id: id, maxPixelSize: maxPixelSize).map { UIImage(cgImage: $0) }
    }
    #endif
}
