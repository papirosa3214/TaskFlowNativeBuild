import XCTest
@testable import TaskFlow

/// Сколько стоит разбор markdown-ответа роли. Проявление идёт кадрами
/// (60 Гц), и на каждом кадре растущий текст разбирается заново — если
/// разбор дорогой, это заметная работа на главном потоке.
final class MarkdownParsePerfTests: XCTestCase {

    /// Ответ роли средней длины: абзацы, список, заголовок, код.
    private static let answer: String = """
    ## Что сделано

    Разбор ответа роли идёт кадрами проявления, и на каждом кадре растущий \
    текст разбирается заново. Чем длиннее ответ, тем дороже кадр.

    - пункт один: описания того, что было сделано;
    - пункт два: подробности про измерения;
    - пункт три: что осталось на потом.

    ```swift
    let blocks = MarkdownParser.parse(text)
    ```

    Итог: разбор должен быть дешевле, чем кадр анимации (16 мс).
    """

    func testСтоимостьРазбораОтвета() {
        let text = Self.answer
        let iterations = 200

        // Разбор без кэша — как в кадре проявления.
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<iterations { _ = MarkdownParser.parseUncached(text) }
        let perParse = Double(DispatchTime.now().uptimeNanoseconds - start) / Double(iterations) / 1000

        // Тот же объём с кэшем: при неизменном тексте разбор не повторяется.
        _ = MarkdownParser.parse(text, cached: true)
        let cachedStart = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<iterations { _ = MarkdownParser.parse(text, cached: true) }
        let perCached = Double(DispatchTime.now().uptimeNanoseconds - cachedStart) / Double(iterations) / 1000

        // Сколько таких разборов уходит на секунду проявления (60 кадров).
        let perSecond = perParse * 60

        print(String(format: "РАЗБОР ответа (%d символов): без кэша %.3f мкс, из кэша %.3f мкс, на 60 кадрах %.3f мс/с",
                     text.count, perParse, perCached, perSecond / 1000))
    }

    /// Кадр проявления целиком: разложение ответа на куски плюс разбор
    /// markdown. Именно это тело ответа пересобирает 60 раз в секунду — на
    /// каждый кадр публикации состояния проявления.
    func testСтоимостьКадраПроявления() {
        let text = Self.answer
        let iterations = 200

        let uncachedStart = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<iterations {
            _ = ChatRichContent.splitUncached(text, isStreaming: true)
            _ = MarkdownParser.parseUncached(text)
        }
        let uncached = Double(DispatchTime.now().uptimeNanoseconds - uncachedStart) / Double(iterations) / 1000

        // Прогрев кэшей живого текста.
        _ = ChatRichContent.split(text, isStreaming: true)
        _ = MarkdownParser.parseIncremental(text)
        let cachedStart = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<iterations {
            _ = ChatRichContent.split(text, isStreaming: true)
            _ = MarkdownParser.parseIncremental(text)
        }
        let cached = Double(DispatchTime.now().uptimeNanoseconds - cachedStart) / Double(iterations) / 1000

        print(String(format: "КАДР ПРОЯВЛЕНИЯ (%d символов): без кэша %.3f мкс, из кэша %.3f мкс, на 60 кадрах %.3f мс/с",
                     text.count, uncached, cached, uncached * 60 / 1000))
        XCTAssertLessThan(cached, uncached / 2, "Кадр проявления должен брать разбор из кэша")
    }
}
