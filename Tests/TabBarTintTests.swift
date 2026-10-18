import XCTest
import SwiftUI
@testable import TaskFlow

/// Акцент панели не должен наследоваться содержимым вкладок.
///
/// Случай 18.10.2026: `.tint(Color.tfRed)` на `TabView` красит панель, но тинт —
/// значение окружения, поэтому его наследовали пункты тулбара внутри разделов:
/// «…» в шапке «Проектов» стала красной, а системная стрелка «назад» осталась
/// светлой (владелец: «почему туда не заливается, а туда заливается»).
/// Снять `.tint` нельзя — без него система на перерисовке панели возвращает
/// свой синий. Поэтому вкладка снимает тинт у содержимого: `.tint(nil)`.
///
/// Проверка смотрит на **кадр** панели и шапки, а не на `tintColor` юikit-вью:
/// 18.10.2026 выяснилось, что `UITabBar.tintColor`, `UINavigationBar.tintColor` и
/// `UIView.tintColor` внутри вкладки показывают акцент и после правки, когда
/// нарисованная кнопка уже системная. Врут — считать надо нарисованное.
@MainActor
final class TabBarTintTests: XCTestCase {
    private func isAccentRed(_ pixel: (UInt8, UInt8, UInt8)) -> Bool {
        let (r, g, b) = (CGFloat(pixel.0), CGFloat(pixel.1), CGFloat(pixel.2))
        return r > 120 && g < 110 && b < 100
    }

    private func sectionContent() -> some View {
        NavigationStack {
            Text("Раздел")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Пункт") {}
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                    }
                }
        }
    }

    /// Кадр окна с панелью и шапкой раздела.
    private func windowShot(selectedIndex: Int) throws -> UIImage {
        let host = UIHostingController(rootView: TFPillTabBar(
            items: [TFTabItem(icon: "TabIconHome", accessibilityLabel: "Обзор"),
                    TFTabItem(icon: "TabIconChat", accessibilityLabel: "Чат")],
            selectedIndex: .constant(selectedIndex), isCreateMenuOpen: false,
            onSelect: { _ in }, onCreateTap: {}) { _ in
                self.sectionContent()
            })
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKey = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        window.isHidden = true
        window.rootViewController = nil
        previousKey?.makeKeyAndVisible()
        return image
    }

    /// Сколько пикселей акцента в области кнопки «…» (правый верхний угол).
    private func accentPixels(topTrailingOf image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return -1 }
        let width = cgImage.width, height = cgImage.height
        let box = CGRect(x: Int(Double(width) * 0.7), y: 0,
                         width: width - Int(Double(width) * 0.7), height: Int(Double(height) * 0.15))
        let bytesPerRow = width * 4
        var data = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let context = CGContext(data: &data, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return -1 }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        var count = 0
        for y in Int(box.minY)..<Int(box.maxY) {
            for x in Int(box.minX)..<Int(box.maxX) {
                let offset = y * bytesPerRow + x * 4
                if isAccentRed((data[offset], data[offset + 1], data[offset + 2])) { count += 1 }
            }
        }
        return count
    }

    func testSectionToolbarIsNotPaintedWithTabBarAccent() throws {
        let image = try windowShot(selectedIndex: 1)
        let accentPixels = accentPixels(topTrailingOf: image)
        XCTAssertGreaterThanOrEqual(accentPixels, 0, "кадр окна не отрисовался")
        XCTAssertLessThanOrEqual(accentPixels, 5,
                                 "шапка раздела покрасилась акцентом панели: \(accentPixels) пикселей акцента в области «…»")
    }
}
