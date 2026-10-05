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

    func testLightNeutralTextHasStrongContrastOnAllBaseSurfaces() {
        for foreground in [Color.tfText, .tfSub, .tfDim] {
            for background in [Color.tfBackground, .tfCard, .tfCard2] {
                let a = luminance(foreground), b = luminance(background)
                XCTAssertGreaterThanOrEqual((max(a, b) + 0.05) / (min(a, b) + 0.05), 7.0)
            }
        }
    }

    func testDarkNeutralTextKeepsExistingPalette() {
        for (color, expected) in [(Color.tfText, 255.0), (.tfSub, 166.0), (.tfDim, 148.0)] {
            let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
            for value in [r, g, b] { XCTAssertEqual(Double(value), expected / 255, accuracy: 0.001) }
        }
    }

    func testRemainingLightLabelsAreOpaqueAndReadable() {
        let labels: [Color] = [.tfReadableSecondary, .tfReadableTertiary, .tfPickerArrow,
                               .tfMutedText(darkOpacity: 0.5), .tfMutedText(darkOpacity: 0.6),
                               .tfMutedText(darkOpacity: 0.8)]
        for foreground in labels {
            var alpha: CGFloat = 0
            UIColor(foreground).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
                .getRed(nil, green: nil, blue: nil, alpha: &alpha)
            XCTAssertEqual(alpha, 1)
            for background in [Color.tfBackground, .tfCard, .tfCard2] {
                let a = luminance(foreground), b = luminance(background)
                XCTAssertGreaterThanOrEqual((max(a, b) + 0.05) / (min(a, b) + 0.05), 7)
            }
        }
        for foreground in TaskPriority.allCases.map(\.color) + [.tfWarningText] {
            var alpha: CGFloat = 0
            UIColor(foreground).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
                .getRed(nil, green: nil, blue: nil, alpha: &alpha)
            XCTAssertEqual(alpha, 1)
            for background in [Color.tfBackground, .tfCard, .tfCard2] {
                let a = luminance(foreground), b = luminance(background)
                XCTAssertGreaterThanOrEqual((max(a, b) + 0.05) / (min(a, b) + 0.05), 4.5)
            }
        }
    }

    func testDarkPriorityAndMutedAppearanceIsPreserved() {
        let traits = UITraitCollection(userInterfaceStyle: .dark)
        for (priority, hex) in zip(TaskPriority.allCases, ["#E44332", "#FF9A14", "#4A9FD8", "#A6A6A6"]) {
            XCTAssertEqual(UIColor(priority.color).resolvedColor(with: traits), UIColor(hex: hex))
        }
        XCTAssertEqual(UIColor(Color.tfReadableSecondary).resolvedColor(with: traits), UIColor.secondaryLabel.resolvedColor(with: traits))
        XCTAssertEqual(UIColor(Color.tfReadableTertiary).resolvedColor(with: traits), UIColor.tertiaryLabel.resolvedColor(with: traits))
        for (color, expected) in [(Color.tfWarningText, 0.8), (.tfPickerArrow, 0.35), (.tfMutedText(darkOpacity: 0.5), 0.5)] {
            var alpha: CGFloat = 0
            UIColor(color).resolvedColor(with: traits).getRed(nil, green: nil, blue: nil, alpha: &alpha)
            XCTAssertEqual(Double(alpha), expected, accuracy: 0.001)
        }
    }

    func testCustomProjectAndLabelTextAdaptsWithoutChangingDarkColor() {
        let traits = UITraitCollection(userInterfaceStyle: .dark)
        for hex in ["#A6A6A6", "#FF9A14", "#F7D038", "#35B8A3", "#FF7A8A", "#FFFFFF", "#000000"] {
            let original = Color(hex: hex)
            let readable = Color.tfReadableText(original)
            XCTAssertEqual(UIColor(readable).resolvedColor(with: traits), UIColor(original).resolvedColor(with: traits))
            for background in [Color.tfBackground, .tfCard, .tfCard2] {
                let a = luminance(readable), b = luminance(background)
                XCTAssertGreaterThanOrEqual((max(a, b) + 0.05) / (min(a, b) + 0.05), 7)
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
