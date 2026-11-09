import SwiftUI
import UIKit

/// Цвета ярлычков типа файла.
///
/// Палитра — из макета владельца `envelope-badges-preview.html` (10.11.2026):
/// у языка и у типа файла свой цвет, в тёмной теме он светлее, подложка —
/// тот же цвет в 16 %. Отдельный файл, чтобы цвета не расползались по вью и
/// менялись в одном месте.
enum ChatBadgePalette {
    static func color(_ tint: ChatLinkPresentation.Tint) -> Color {
        switch tint {
        case .python: return hex(light: 0x3776AB, dark: 0x7FB6E0)
        case .swift: return hex(light: 0xC4571F, dark: 0xF0915C)
        case .typescript: return hex(light: 0x3178C6, dark: 0x79B0F0)
        case .javascript: return hex(light: 0x8A6D1A, dark: 0xE0C05A)
        case .json: return hex(light: 0x6E7681, dark: 0xA8B0BA)
        case .markdown: return hex(light: 0x4A6C8C, dark: 0x93B4D4)
        case .sql: return hex(light: 0xB07A1E, dark: 0xE0AC4A)
        case .bash: return hex(light: 0x4E7A2A, dark: 0x8FC160)
        case .html: return hex(light: 0xB4551F, dark: 0xE89050)
        case .css: return hex(light: 0x6C4AA8, dark: 0xA98BE0)
        case .go: return hex(light: 0x2A7E8C, dark: 0x63BAC8)
        case .other: return hex(light: 0x6E7681, dark: 0xA8B0BA)
        case .pdf: return hex(light: 0x8A4B1E, dark: 0xD08A55)
        case .image: return hex(light: 0x7A5AF8, dark: 0xA992FF)
        case .video: return hex(light: 0xB07A1E, dark: 0xE0AC4A)
        case .web: return hex(light: 0x4E7A2A, dark: 0x8FC160)
        case .docs: return hex(light: 0x2F6FEB, dark: 0x6EA8FF)
        case .note: return hex(light: 0x0A84C8, dark: 0x5BC0F0)
        case .file: return hex(light: 0x6E7681, dark: 0xA8B0BA)
        }
    }

    /// Подложка ярлычка — тот же цвет, но прозрачный.
    static func background(_ tint: ChatLinkPresentation.Tint) -> Color {
        color(tint).opacity(0.16)
    }

    private static func hex(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(tfHex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(tfHex: UInt32) {
        self.init(red: CGFloat((tfHex >> 16) & 0xFF) / 255,
                  green: CGFloat((tfHex >> 8) & 0xFF) / 255,
                  blue: CGFloat(tfHex & 0xFF) / 255,
                  alpha: 1)
    }
}
