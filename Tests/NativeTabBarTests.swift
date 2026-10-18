import XCTest
import SwiftUI
@testable import TaskFlow

@MainActor
final class NativeTabBarTests: XCTestCase {
    func testNavigationUsesSystemUITabBarInsteadOfPaintedCapsules() async throws {
        let host = UIHostingController(rootView: TFPillTabBar(
            items: [TFTabItem(icon: "TabIconHome", accessibilityLabel: "Обзор"),
                    TFTabItem(icon: "TabIconChat", accessibilityLabel: "Чат")],
            selectedIndex: .constant(0), isCreateMenuOpen: false,
            onSelect: { _ in }, onCreateTap: {}))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKey = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousKey?.makeKeyAndVisible()
        }
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        let native = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.findTabBar(in: host.view) != nil
        }, object: nil)
        let result = await XCTWaiter.fulfillment(of: [native], timeout: 2)
        XCTAssertEqual(result, .completed, "Панель обязана содержать настоящий UITabBar Apple")
        let bar = try XCTUnwrap(findTabBar(in: host.view))
        XCTAssertEqual(bar.items?.count, 3)
        XCTAssertEqual(bar.items?.last?.title, "Создать")
    }

    func testCreateActionKeepsCurrentTabAndNavigationUsesExistingHandler() {
        var selections: [Int] = []
        var creates = 0
        let bar = TFPillTabBar(
            items: [TFTabItem(icon: "TabIconHome", accessibilityLabel: "Обзор"),
                    TFTabItem(icon: "TabIconChat", accessibilityLabel: "Чат")],
            selectedIndex: .constant(0), isCreateMenuOpen: false,
            onSelect: { selections.append($0) }, onCreateTap: { creates += 1 })
        bar.selectionBinding.wrappedValue = 2
        XCTAssertEqual(creates, 1)
        XCTAssertTrue(selections.isEmpty)
        XCTAssertEqual(bar.selectionBinding.wrappedValue, 0)
        bar.selectionBinding.wrappedValue = 1
        XCTAssertEqual(selections, [1])
        bar.selectionBinding.wrappedValue = -1
        bar.selectionBinding.wrappedValue = nil
        XCTAssertEqual(selections, [1])
        XCTAssertEqual(creates, 1)
    }

    private func findTabBar(in view: UIView) -> UITabBar? {
        if let bar = view as? UITabBar { return bar }
        return view.subviews.lazy.compactMap { self.findTabBar(in: $0) }.first
    }
}
