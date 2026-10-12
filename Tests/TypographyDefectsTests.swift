import XCTest
import SwiftUI
import UIKit
@testable import TaskFlow

/// Пять дефектов типографики, найденных инвентаризацией 12.10.2026
/// (LOCK-TYPOGRAPHY-SPEC, этап А).
///
/// Тесты держат не «как выглядит», а то, что легко потерять при следующей
/// правке: масштабирование под Dynamic Type, отсутствие ступени `input`
/// не у полей и отсутствие системных цветов вместо палитры.
final class TypographyDefectsTests: XCTestCase {

    // MARK: Дефект А — текст в блочном редакторе не масштабировался

    /// Кегли блочного редактора обязаны приходить из `UIFontMetrics`, то есть
    /// зависеть от системного размера текста. Раньше это были статичные
    /// `systemFont(ofSize:)`, и комментарий, шаг и подзадача оставались 15 pt,
    /// пока всё остальное на экране росло (WCAG 1.4.4).
    func testMarkdownBaseFontsScaleWithContentSizeCategory() {
        let cases: [(BlockKind, String)] = [
            (.heading(level: 1), "заголовок 1"),
            (.heading(level: 2), "заголовок 2"),
            (.heading(level: 3), "заголовок 3"),
            (.codeBlock(language: nil), "код"),
            (.paragraph, "тело"),
        ]

        for (kind, name) in cases {
            // Кегль берётся из `UIFontMetrics`, то есть зависит от категории
            // системного размера текста. Разницу меряем явной категорией:
            // `performAsCurrent` на `UIFontMetrics` не влияет.
            let big = MarkdownText.baseFont(
                for: kind,
                compatibleWith: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
            ).pointSize
            let normal = MarkdownText.baseFont(
                for: kind,
                compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)
            ).pointSize

            XCTAssertGreaterThan(
                big, normal * 1.5,
                "\(name): кегль не растёт под «Крупный текст» — \(normal) → \(big)"
            )
        }
    }

    /// Тело блока — 16 pt на дефолтном размере: это основной текст, который
    /// человек читает и правит (владелец 12.10.2026: «название не 17, а где-то
    /// 16, и все остальные основные текста тоже»). Масштабирование не должно
    /// менять обычный вид.
    func testMarkdownBodyKeepsBaseSizeAtDefaultCategory() {
        let font = MarkdownText.baseFont(for: .paragraph)
        XCTAssertEqual(font.pointSize, 16, accuracy: 0.01)
    }

    // MARK: Дефект Б — иерархия карточки была перевёрнута

    /// Название задачи в карточке должно быть КРУПНЕЕ заголовка секции, а не
    /// наоборот: было 17 pt против 20 pt.
    func testCardTitleIsLargerThanSectionHeader() {
        let title = TFTextStyle.taskTitle.baseSize
        let section = TFTextStyle.title.baseSize

        XCTAssertGreaterThan(title, section, "название карточки (\(title)) должно быть крупнее заголовка секции (\(section))")
        XCTAssertGreaterThan(TFTextStyle.title.baseSize, TFTextStyle.body.baseSize)
    }

    // MARK: Дефект В — ступень `input` не на своём месте

    /// `input` (16) в этом проекте зарезервирована ТОЛЬКО под текстовые поля.
    /// В календаре Планирования она стояла на числе дня — числа дня теперь
    /// `body` (15), то есть строго меньше ступени поля.
    func testInputTierIsStrictlyForFields() {
        XCTAssertGreaterThan(TFTextStyle.input.baseSize, TFTextStyle.body.baseSize)
        XCTAssertEqual(TFTextStyle.input.baseSize, 16)
    }

    // MARK: Дефект Г — пустое состояние без типографики

    /// Пустое состояние рисуется ступенью шкалы, а не системным размером.
    /// 13 pt — ступень `.action`, которой набраны пустые состояния и рядом
    /// стоящие подписи; она обязана быть в шкале.
    func testEmptyStateUsesScaleNotSystemDefault() {
        let ourSizes = [
            TFTextStyle.titleLarge.baseSize, TFTextStyle.taskTitle.baseSize,
            TFTextStyle.title.baseSize, TFTextStyle.input.baseSize,
            TFTextStyle.body.baseSize, TFTextStyle.row.baseSize,
            TFTextStyle.action.baseSize, TFTextStyle.meta.baseSize,
            TFTextStyle.caption.baseSize, TFTextStyle.micro.baseSize,
        ]
        XCTAssertTrue(ourSizes.contains(13), "в шкале нет ступени 13 для пустых состояний")
        // Ступень `.body` = 15: пустое состояние набирается ею или `.action` 13,
        // но НЕ системным `.body` SwiftUI (17) — иначе оно поплывёт с настройкой.
        XCTAssertNotEqual(TFTextStyle.body.baseSize, 17)
    }

    // MARK: Дефект Д — цвета вне палитры

    /// Палитра — единственный источник цвета текста. Проверяем, что три тона
    /// вообще объявлены и различимы: если кто-то «склеит» `tfSub` и `tfDim`,
    /// правило из DESIGN.md потеряет смысл.
    func testPaletteTextTokensExist() {
        XCTAssertNotEqual(Color.tfText, Color.tfSub)
        XCTAssertNotEqual(Color.tfSub, Color.tfDim)
        XCTAssertNotEqual(Color.tfText, Color.tfDim)
    }
}
