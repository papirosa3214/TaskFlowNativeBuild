import UIKit
import UniformTypeIdentifiers

/// Копирование в буфер обмена для того, что не должно покидать устройство.
///
/// Обычный `UIPasteboard.general.string` уезжает по Handoff и Universal
/// Clipboard — то есть секрет, скопированный на телефоне, оказывается в буфере
/// макета и в облаке Apple. Для паролей, токенов и кодов устройства буфер
/// помечается `localOnly`: значение остаётся на этом устройстве.
///
/// Для обычного текста (сообщение, название задачи) правило не нужно —
/// там `UIPasteboard.general.string` как был.
enum SafePasteboard {
    /// Положить секрет в буфер, не выпуская его с устройства.
    ///
    /// `expireDate` — чтобы значение не лежало в буфере бессрочно: спустя
    /// две минуты система его сама выбросит.
    static func copySecret(_ value: String) {
        UIPasteboard.general.setItems(
            [[UTType.utf8PlainText.identifier: value]],
            options: [
                .localOnly: true,
                .expireDate: Date().addingTimeInterval(120),
            ]
        )
    }
}
