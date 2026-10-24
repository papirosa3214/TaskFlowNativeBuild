import XCTest
@testable import TaskFlow

/// Кэш разбора Markdown — LOCK-OPT-PERF-20261022.
///
/// Разбор одного и того же текста повторяется постоянно: `Binding`-геттеры
/// карточки задачи и перерисовка сообщений чата. Кэш отдаёт тот же AST и
/// обязан совпадать со свежим разбором до последнего run'а.
final class MarkdownParseCacheTests: XCTestCase {

    override func setUp() {
        super.setUp()
        MarkdownParseCache.shared.reset()
    }

    private let sample = """
    # Заголовок

    Абзац с **жирным** и *курсивом*, ссылка [документ](https://example.com).

    - пункт списка
    - пункт с задачей

    > цитата

    ```swift
    let x = 1
    ```
    """

    func testПовторныйРазборОтдаётТежеБлоки() {
        let first = MarkdownParser.parse(sample)
        let second = MarkdownParser.parse(sample)
        XCTAssertEqual(
            first.map(\.id), second.map(\.id),
            "Один и тот же текст должен разбираться в один и тот же AST — иначе редактор пересоздаёт строки на каждом проходе"
        )
    }

    func testКэшНеМеняетРазбор() {
        let cached = MarkdownParser.parse(sample)
        let fresh = MarkdownParser.parseUncached(sample)
        XCTAssertEqual(cached.count, fresh.count)
        for (left, right) in zip(cached, fresh) {
            XCTAssertEqual(left.kind, right.kind)
            XCTAssertEqual(left.level, right.level)
            XCTAssertEqual(left.runs, right.runs)
        }
    }

    func testРазныеТекстыДаютРазныеБлоки() {
        let first = MarkdownParser.parse("Первый")
        let second = MarkdownParser.parse("Второй")
        XCTAssertNotEqual(first[0].id, second[0].id)
    }

    func testПравкаНаМестеНеЗадеваетКэш() {
        let cached = MarkdownParser.parse("Абзац")
        var edited = cached
        edited[0].runs[0].text = "Правленый абзац"
        let again = MarkdownParser.parse("Абзац")
        XCTAssertEqual(again[0].runs[0].text, "Абзац", "Кэш не должен отдавать правленый текст")
        XCTAssertEqual(cached[0].runs[0].text, "Абзац")
    }

    /// Живой ответ роли приходит префиксами: пока текст растёт, каждый кадр
    /// — новая строка. В общий кэш такие префиксы попадать не должны: они
    /// вытесняли разборы истории чата (лимит 128 записей) и сообщения
    /// перечитывались при каждой прокрутке.
    func testПотоковыйТекстНеЗабиваетКэш() {
        for length in 1...200 {
            let prefix = String(repeating: "а", count: length)
            _ = MarkdownParser.parse(prefix, cached: false)
        }
        XCTAssertEqual(MarkdownParseCache.shared.count, 0,
                       "Растущие префиксы живого ответа не должны попадать в общий кэш разбора")
    }

    func testГотовыйТекстКэшируется() {
        _ = MarkdownParser.parse("Готовый ответ роли")
        _ = MarkdownParser.parse("Готовый ответ роли")
        XCTAssertEqual(MarkdownParseCache.shared.count, 1,
                       "Готовый текст должен остаться в кэше — он перерисовывается при каждом проходе экрана")
    }
}
