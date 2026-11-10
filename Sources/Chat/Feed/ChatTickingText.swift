import SwiftUI
import UIKit

/// Тикающая подпись без перерисовки SwiftUI.
///
/// Владелец 10.11.2026: «время тикает, но не дёргает ленту». `TimelineView`
/// пересобирает поддерево каждый тик, а подпись живёт в широкой ленте — от
/// этого страдала прокрутка. Здесь текст пишется прямо в `UILabel` раз в
/// секунду, состояние SwiftUI не меняется вовсе (как `tickTextContent` в T3).
struct ChatTickingText: UIViewRepresentable {
    /// Текст на момент `date`; вызывается и на каждом тике, и при обновлении вью.
    let format: (Date) -> String
    /// Идёт работа — тикаем; закончилась — пишем один раз.
    let isLive: Bool
    var font: UIFont = .preferredFont(forTextStyle: .caption1)
    var color: UIColor = .secondaryLabel
    var alignment: NSTextAlignment = .left

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 1
        label.adjustsFontForContentSizeCategory = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.text = format(Date())
        context.coordinator.attach(label)
        context.coordinator.start(isLive: isLive)
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        label.font = font
        label.textColor = color
        label.textAlignment = alignment
        context.coordinator.format = format
        let text = format(Date())
        if label.text != text { label.text = text }
        context.coordinator.start(isLive: isLive)
    }

    static func dismantleUIView(_ label: UILabel, coordinator: Coordinator) {
        coordinator.stop()
    }

    func makeCoordinator() -> Coordinator { Coordinator(format: format) }

    final class Coordinator {
        var format: (Date) -> String
        private weak var label: UILabel?
        private var timer: Timer?

        init(format: @escaping (Date) -> String) {
            self.format = format
        }

        func attach(_ label: UILabel) { self.label = label }

        /// Тик — в общем режиме RunLoop, иначе на прокрутке он замирает.
        func start(isLive: Bool) {
            guard isLive else { stop(); return }
            guard timer == nil else { return }
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                guard let self, let label = self.label else { return }
                let text = self.format(Date())
                if label.text != text { label.text = text }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }

        func stop() {
            timer?.invalidate()
            timer = nil
        }
    }
}
