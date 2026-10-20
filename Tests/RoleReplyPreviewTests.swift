import XCTest
import Foundation
@testable import TaskFlow

/// Поведение `RoleReplyMarkdown.preview(of:)` — короткой строки, которой
/// результат шага показывается в строке списка. Отдельный файл от
/// `RoleReplyRenderTests`: тот работает по исходникам и собирается на любой
/// версии кода (на нём и держится проверка «до правки было сломано»), а здесь
/// проверяется функция, которой до карточки 19f57bc9 в проекте не было.
final class RoleReplyPreviewTests: XCTestCase {

    /// Превью в строке короткое, но маркированным оно тоже должно быть: строка
    /// идёт в общий рендер целиком, иначе `**жирный**` снова стал бы звёздочками.
    func testPreviewKeepsInlineMarkupOfFirstParagraph() {
        let text = "**Готово.** Проверил таблицу и графики.\nВторая строка того же абзаца."
        XCTAssertEqual(RoleReplyMarkdown.preview(of: text),
                       "**Готово.** Проверил таблицу и графики. Вторая строка того же абзаца.")
    }

    /// Ответ роли почти всегда продолжается служебным блоком — превью в строке
    /// не должно вырастать до всего блока ```widget.
    func testPreviewStopsAtFencedBlock() {
        let text = "Итог шага.\n\n```widget\n{\"type\": \"chart\"}\n```\n\nПосле блока."
        XCTAssertEqual(RoleReplyMarkdown.preview(of: text), "Итог шага.")
    }

    func testPreviewSkipsEmptyLinesBeforeFirstParagraph() {
        XCTAssertEqual(RoleReplyMarkdown.preview(of: "\n\nПервый абзац.\n\nВторой абзац."), "Первый абзац.")
    }

    /// Строки без пустой между собой — один абзац, склеиваются в строку.
    func testPreviewJoinsLinesOfSameParagraph() {
        XCTAssertEqual(RoleReplyMarkdown.preview(of: "Первый абзац.\nВторой абзац."),
                       "Первый абзац. Второй абзац.")
    }

    func testPreviewShortensLongParagraph() {
        let long = String(repeating: "а", count: 300)
        let preview = RoleReplyMarkdown.preview(of: long, limit: 20)
        XCTAssertEqual(preview.count, 21)          // 20 символов + многоточие
        XCTAssertTrue(preview.hasSuffix("\u{2026}"))
    }

    func testPreviewOfEmptyTextIsEmpty() {
        XCTAssertEqual(RoleReplyMarkdown.preview(of: ""), "")
        XCTAssertEqual(RoleReplyMarkdown.preview(of: "   \n\n  "), "")
    }
}
