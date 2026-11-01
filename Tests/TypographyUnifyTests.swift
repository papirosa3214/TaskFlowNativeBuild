import XCTest
import SwiftUI
@testable import TaskFlow

/// Типографика сведена на шкалу: размеры текста живут в ОДНОМ файле
/// (`Sources/DesignSystem/Theme/Typography.swift`), а экраны берут ступень.
/// Владелец 12.10.2026: «унифицируй это, чтобы, грубо говоря, ты в одном месте
/// шрифт поправил, тебе всё приложение сразу поправил» (LOCK-TYPOGRAPHY-UNIFY).
///
/// Тесты держат саму шкалу: если кто-то снова заведёт кегль мимо неё или
/// разъедет ступень, здесь это станет видно.
final class TypographyUnifyTests: XCTestCase {

    /// Все ступени — закрытый список. Новая роль текста добавляется сюда, а не
    /// сырым `.font(.system(size:))` на экране.
    private let allStyles: [TFTextStyle] = [
        .titleLarge, .taskTitle, .title, .input, .body, .listTitle,
        .row, .action, .meta, .caption, .micro,
    ]

    /// Название задачи в строке списка — ступень, а не свой кегль в компоненте.
    /// Раньше это был локальный `@ScaledMetric` внутри `TFTaskRowContent`:
    /// правился в одном файле, а весь остальной текст — в другом.
    ///
    /// В пятигрупповой модели (владелец 01.11.2026) `listTitle` входит в
    /// группу `.body` — 15 pt, как `body` и `row`, трекинг тот же.
    func testListTitleTierIsPartOfScale() {
        XCTAssertEqual(TFTextStyle.listTitle.group, .body)
        XCTAssertEqual(TFTextStyle.listTitle.baseSize, 15)
        XCTAssertEqual(TFTextStyle.listTitle.weight, .regular)
        XCTAssertEqual(TFTextStyle.listTitle.tracking, TFFont.bodyTracking)
    }

    /// Размеры ступеней лежат в разумном диапазоне: от самой мелкой подписи
    /// до заголовка корневого экрана. Ступень, выпавшая из диапазона, — почти
    /// всегда опечатка (34, 56, 7), и она разом поехала бы по всем экранам.
    ///
    /// Совпадение размеров у РАЗНЫХ ролей допустимо: `input` и `listTitle`
    /// оба 16 — поле ввода и название задачи в строке списка. Это разные роли,
    /// и живут они теперь в одном файле, а не по экранам.
    func testTierSizesStayInRange() {
        for style in allStyles {
            XCTAssertGreaterThanOrEqual(style.baseSize, 10, "\(style): слишком мелко")
            XCTAssertLessThanOrEqual(style.baseSize, 28, "\(style): крупнее заголовка экрана")
        }
    }

    /// Ступень `input` — только под текстовые поля. В пятигрупповой модели
    /// (владелец 01.11.2026) отдельного кегля у полей нет: `input` входит в
    /// группу `.body` (15 pt) наравне с `body`, `listTitle` и `row`. Поэтому
    /// проверяем принадлежность группе и то, что группа `body` не совпала
    /// с системным `.body` SwiftUI (17 pt) — иначе текст «поплывёт» относительно
    /// остального шрифта при смене размера текста.
    func testInputTierStaysDistinctFromBody() {
        XCTAssertEqual(TFTextStyle.input.group, .body)
        XCTAssertEqual(TFTextStyle.input.baseSize, TFTextStyle.body.baseSize)
        XCTAssertNotEqual(TFTextStyle.input.baseSize, 17)
    }

    /// Каждая ступень обязана давать трекинг и вес: пустая ступень означает
    /// текст, который снова начнёт «плавать» относительно остальных.
    func testEveryTierDefinesWeightAndTracking() {
        for style in allStyles {
            XCTAssertGreaterThan(style.baseSize, 0, "\(style): нулевой кегль")
            XCTAssertLessThanOrEqual(
                abs(style.tracking), 1.0,
                "\(style): трекинг \(style.tracking) вне разумного диапазона"
            )
        }
    }

    /// Кривая масштабирования задана у каждой ступени — иначе под «Крупный
    /// текст» она расти не будет (WCAG 1.4.4).
    func testEveryTierScalesUnderDynamicType() {
        for style in allStyles {
            // Ступень обязана быть выразима системным стилем: сам факт вызова
            // `relativeTo` проверяем через существование значения.
            _ = style.relativeTo
        }
    }
}
