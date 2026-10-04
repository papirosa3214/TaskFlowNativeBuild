import XCTest
import SwiftUI
@testable import TaskFlow

final class AppAppearanceTests: XCTestCase {
    func testLegacySelectionMigratesAndNewChoiceWins() {
        let name = "AppAppearanceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(false, forKey: AppAppearance.legacyStorageKey)
        XCTAssertEqual(AppAppearance.migratePreference(in: defaults), .light)
        XCTAssertEqual(defaults.string(forKey: AppAppearance.storageKey), "light")
        defaults.set(AppAppearance.system.rawValue, forKey: AppAppearance.storageKey)
        defaults.set(true, forKey: AppAppearance.legacyStorageKey)
        XCTAssertEqual(AppAppearance.migratePreference(in: defaults), .system)
        XCTAssertNil(AppAppearance.system.colorScheme)
        XCTAssertEqual(AppAppearance.light.colorScheme, .light)
        XCTAssertEqual(AppAppearance.dark.colorScheme, .dark)
    }

    func testNoPreferenceKeepsDarkAppearanceAndUnknownValueIsSafe() {
        let name = "AppAppearanceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(AppAppearance.migratePreference(in: defaults), .dark)
        defaults.set("unsupported", forKey: AppAppearance.storageKey)
        XCTAssertEqual(AppAppearance.migratePreference(in: defaults), .dark)
    }

    func testLightTextAndStatusTokensMeetContrastOnAllBaseSurfaces() {
        let foregrounds: [Color] = [.tfText, .tfSub, .tfDim, .tfRed, .tfOrange,
                                    .tfPink, .tfBlue, .tfPurple, .tfYellow,
                                    .tfCoral, .tfTeal, .tfGreen]
        let backgrounds: [Color] = [.tfBackground, .tfCard, .tfCard2]
        for foreground in foregrounds {
            for background in backgrounds {
                let a = luminance(foreground), b = luminance(background)
                XCTAssertGreaterThanOrEqual((max(a, b) + 0.05) / (min(a, b) + 0.05), 4.5)
            }
        }
    }

    private func luminance(_ color: Color) -> Double {
        let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        func linear(_ value: CGFloat) -> Double {
            let v = Double(value)
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }
}
