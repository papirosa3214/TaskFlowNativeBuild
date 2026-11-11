import SwiftUI
import UIKit

/// Свайп от левого края возвращает назад и в чатах (владелец 08.11.2026:
/// «если перехожу в комнату — свайп назад, как во всём приложении»).
///
/// Системный жест живёт в `UINavigationController`, а чат рисует свою шапку и
/// держит собственные панорамы у правой кромки — после пуша жест иногда
/// оказывается выключенным. Здесь он включается обратно и снимается чужой
/// делегат, который мог его глушить; на экране без стека ничего не делает.
struct SwipeBackEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.enable()
    }

    final class Controller: UIViewController {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            enable()
        }

        func enable() {
            guard let stack = navigationController, stack.viewControllers.count > 1 else { return }
            stack.interactivePopGestureRecognizer?.isEnabled = true
            stack.interactivePopGestureRecognizer?.delegate = nil
        }
    }
}

extension View {
    /// Вернуть системный свайп назад на этом экране.
    func swipeBackEnabled() -> some View {
        background(SwipeBackEnabler().frame(width: 0, height: 0).allowsHitTesting(false))
    }
}
