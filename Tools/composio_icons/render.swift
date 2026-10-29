// Растеризация логотипов Composio: SVG → монохромный серый PNG.
//
// Зачем: Composio отдаёт логотипы сервисов как SVG (https://logos.composio.dev/api/<slug>),
// а iOS (ImageIO) SVG не рисует — в списке подключений вместо иконок был
// generic-значок «link». Скрипт готовит иконки заранее: серый силуэт сервиса
// на прозрачном фоне, PNG в папку Resources/ComposioIcons.
//
// Правила оформления (владелец 29.10.2026): иконки в стиле приложения —
// серо-серенькие, один цвет на фоне. Поэтому цвет логотипа не переносится:
// картинка рисуется как есть, а в пикселе светлота становится прозрачностью
// (белый фон — дырка, тёмная подложка — плотный серый, светлый знак внутри
// тёмной подложки виден как более светлое пятно). Так структура знака
// («N» у Notion, кошка у GitHub) не сливается в серый квадрат.
//
// Запуск: swift Tools/composio_icons/render.swift <каталог SVG> <каталог PNG> [список слагов]

import AppKit
import Foundation
import WebKit

/// Серый, в который переводится знак (тот же, что `Color.tfDim` в приложении).
let iconGray: UInt8 = 148

func html(for svg: String) -> String {
    """
    <!DOCTYPE html><html><head><meta charset="utf-8"><style>
    html,body{margin:0;padding:0;background:transparent;overflow:hidden}
    /* Некоторые логотипы перекрашиваются по теме (prefers-color-scheme) —
       берём светлую ветку, иначе белый знак на тёмном фоне стал бы пустым. */
    html{color-scheme:light}
    #wrap{width:60px;height:60px}
    svg{width:60px;height:60px;display:block}
    svg image{filter:grayscale(1)}
    </style></head><body><div id="wrap">\(svg)</div></body></html>
    """
}

@MainActor
final class IconRenderer {
    let webView: WKWebView
    private var continuation: CheckedContinuation<NSImage?, Never>?

    init() {
        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = true
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 60, height: 60), configuration: config)
        // Прозрачный фон: иконка должна лечь на плитку приложения, а не на белое поле.
        view.underPageBackgroundColor = .clear
        view.setValue(false, forKey: "drawsBackground")
        webView = view
    }

    func render(svg: String) async -> NSImage? {
        await withCheckedContinuation { (continuation: CheckedContinuation<NSImage?, Never>) in
            self.continuation = continuation
            webView.loadHTMLString(html(for: svg), baseURL: nil)
        }
    }

    func snapshot() async -> NSImage? {
        await withCheckedContinuation { continuation in
            webView.takeSnapshot(with: nil) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}

@MainActor
final class NavigationDelegate: NSObject, WKNavigationDelegate {
    private let renderer: IconRenderer

    init(renderer: IconRenderer) { self.renderer = renderer }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            // Кадр после загрузки: анимации и ленивые картинки могли не успеть.
            try? await Task.sleep(nanoseconds: 60_000_000)
            let image = await renderer.snapshot()
            await renderer.finish(image)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in await renderer.finish(nil) }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in await renderer.finish(nil) }
    }
}

extension IconRenderer {
    func finish(_ image: NSImage?) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: image)
    }
}

/// Пиксель → серый силуэт: светлота становится прозрачностью.
/// Белый фон исчезает, тёмная подложка остаётся плотной, светлый знак внутри
/// неё виден как более светлое пятно. Результат — один серый цвет и форма.
func silhouette(from cgImage: CGImage) -> CGImage? {
    let width = cgImage.width, height = cgImage.height
    let bytesPerRow = width * 4
    var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
    guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    // Светлота пикселя → прозрачность: белый фон исчезает, тёмная подложка
    // остаётся плотной, светлый знак внутри неё виден как более светлое пятно.
    var alphas = [UInt8](repeating: 0, count: width * height)
    var lightnesses = [Double](repeating: 0, count: width * height)
    var maxAlpha: UInt8 = 0
    var darkest = 1.0
    for pixel in 0..<(width * height) {
        let index = pixel * 4
        let alpha = pixels[index + 3]
        guard alpha > 0 else { continue }
        let r = Double(pixels[index]) * 255 / Double(alpha)
        let g = Double(pixels[index + 1]) * 255 / Double(alpha)
        let b = Double(pixels[index + 2]) * 255 / Double(alpha)
        let lightness = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255
        lightnesses[pixel] = lightness
        darkest = min(darkest, lightness)
        let value = UInt8(round(Double(alpha) * pow(1 - min(1, max(0, lightness)), 1.25)))
        alphas[pixel] = value
        maxAlpha = max(maxAlpha, value)
    }
    // Знак, нарисованный белым (без своей подложки), иначе вышел бы пустым:
    // у него светлота — это и есть форма.
    let inverted = darkest > 0.85
    if inverted {
        for pixel in 0..<(width * height) {
            let alpha = pixels[pixel * 4 + 3]
            guard alpha > 0 else { continue }
            let value = UInt8(round(Double(alpha) * pow(min(1, max(0, lightnesses[pixel])), 1.25)))
            alphas[pixel] = value
            maxAlpha = max(maxAlpha, value)
        }
    }
    // У каждого знака своя светлота (оранжевая плитка, белая коробка), и без
    // нормализации одни иконки были бы бледными, другие — плотными. Приводим
    // каждую к одному весу: дырки (прозрачность 0) остаются дырками.
    let scale = maxAlpha > 0 ? 255.0 / Double(maxAlpha) : 1
    for pixel in 0..<(width * height) {
        let index = pixel * 4
        // Пишем все пиксели, включая прозрачные: иначе белые буквы внутри
        // знака остались бы белыми и непрозрачными.
        let newAlpha = min(255.0, Double(alphas[pixel]) * scale)
        let value = UInt8(round(Double(iconGray) * newAlpha / 255))
        pixels[index] = value
        pixels[index + 1] = value
        pixels[index + 2] = value
        pixels[index + 3] = UInt8(round(newAlpha))
    }
    guard let rgba = context.makeImage() else { return nil }
    // Пустой знак (не отрисовался) — картинки нет, в приложении будет общий значок.
    if maxAlpha == 0 { return nil }
    // Серый + альфа: цвет в приложении перекрашивается шаблоном, важна
    // только прозрачность (структура знака).
    guard let gray = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                               bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(),
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    gray.setFillColor(gray: 1, alpha: 0)
    gray.fill(CGRect(x: 0, y: 0, width: width, height: height))
    gray.draw(rgba, in: CGRect(x: 0, y: 0, width: width, height: height))
    return gray.makeImage()
}

func writePNG(_ image: NSImage, to path: String) -> Bool {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return false }
    // Пустая картинка (знак не отрисовался) — файл не пишем: в приложении
    // для такого сервиса показывается общий значок.
    guard let gray = silhouette(from: cgImage) else { return false }
    let rep = NSBitmapImageRep(cgImage: gray)
    guard let png = rep.representation(using: .png, properties: [:]) else { return false }
    do {
        try png.write(to: URL(fileURLWithPath: path))
        return true
    } catch {
        return false
    }
}

/// Не-SVG (у 54 сервисов Composio по ссылке лежит чужая HTML-страница) —
/// такой файл рисуется браузером как страница, поэтому пропускаем его.
func isSVG(_ text: String) -> Bool {
    let head = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return head.hasPrefix("<svg") || (head.hasPrefix("<?xml") && text.contains("<svg"))
}

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write("нужно: render.swift <каталог SVG> <каталог PNG> [файл со слагами]\n".data(using: .utf8)!)
    exit(2)
}
let svgDir = arguments[1]
let pngDir = arguments[2]
let slugFile = arguments.count > 3 ? arguments[3] : nil

let slugs: [String]
if let slugFile {
    slugs = try String(contentsOfFile: slugFile, encoding: .utf8)
        .split(separator: "\n")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
} else {
    slugs = (try? FileManager.default.contentsOfDirectory(atPath: svgDir))?
        .filter { $0.hasSuffix(".svg") }
        .map { String($0.dropLast(4)) }
        .sorted() ?? []
}

try? FileManager.default.createDirectory(atPath: pngDir, withIntermediateDirectories: true)

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

Task { @MainActor in
    let renderer = IconRenderer()
    let delegate = NavigationDelegate(renderer: renderer)
    renderer.webView.navigationDelegate = delegate

    var done = 0
    var failed = 0
    for slug in slugs {
        let svgPath = (svgDir as NSString).appendingPathComponent("\(slug).svg")
        guard let data = FileManager.default.contents(atPath: svgPath),
              let svg = String(data: data, encoding: .utf8), isSVG(svg) else {
            failed += 1
            continue
        }
        guard let image = await renderer.render(svg: svg) else {
            failed += 1
            continue
        }
        let pngPath = (pngDir as NSString).appendingPathComponent("\(slug).png")
        if writePNG(image, to: pngPath) {
            done += 1
        } else {
            failed += 1
        }
        if done % 100 == 0 { print("готово \(done), пропущено \(failed)", terminator: "\n") }
    }
    print("итого: \(done) иконок, пропущено \(failed)", terminator: "\n")
    // Пропущенные — сервисы, у которых по ссылке Composio лежит не SVG, а чужая
    // страница: для них в приложении показывается общий значок.
    exit(done > 0 ? 0 : 1)
}

app.run()
