import XCTest
@testable import TaskFlow

/// Разбор с переиспользованием устойчивой части — для проявления ответа.
///
/// Во время проявления текст растёт на каждом кадре, и раньше он разбирался
/// целиком: замер 24.10.2026 — 110 мкс на ответ в 388 символов, то есть
/// 6.6 мс в секунду только на разбор (и заметно больше на длинном ответе).
/// Теперь устойчивая часть берётся из кэша, а разбирается только последний,
/// растущий блок.
///
/// Главное свойство: результат инкрементального разбора обязан совпадать с
/// полным — иначе во время проявления текст выглядел бы иначе, чем после.
final class MarkdownParseIncrementalTests: XCTestCase {

    /// Случайные идентификаторы внутри блоков и таблиц — для сравнения
    /// содержимого их надо убрать.
    ///
    /// Важно: замена идёт ВСЕГДА. Раньше стояла проверка `contains("UUID")`,
    /// но такой строки в описании блока нет — есть сами UUID, — поэтому
    /// проверка никогда не срабатывала, и таблицы сравнивались по случайным
    /// идентификаторам. Тест падал на тексте с таблицей.
    private func replacingUUIDs(_ text: String) -> String {
        text.replacingOccurrences(
            of: "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}",
            with: "id",
            options: .regularExpression
        )
    }

    /// `NoteBlock` содержит случайный `id` (и id внутри таблиц), поэтому
    /// сравниваем СОДЕРЖИМОЕ, а не сами объекты.
    private func shape(_ blocks: [NoteBlock]) -> [String] {
        blocks.map { block in
            let kind = String(describing: block.kind)
            let text = block.runs.map(\.text).joined(separator: "␟")
            return replacingUUIDs("\(kind)|\(text)|\(block.level)")
        }
    }

    private let corpus: [String] = [
        "",
        "   ",
        "Просто абзац",
        "Просто абзац\n",
        "# Заголовок\n\nАбзац после заголовка",
        "Абзац\n\n- пункт один\n- пункт два",
        "Абзац\n\n1. первый\n2. второй",
        "Абзац\n\n> цитата\n> вторая строка",
        "Абзац\n\n---\n\nПосле разделителя",
        "```swift\nlet x = 1\n```\n\nПосле кода",
        "```swift\nlet x = 1\n\nпустая строка внутри кода\n\nlet y = 2\n```\n\nПосле кода",
        "| колонка |\n| --- |\n| значение |\n\nПосле таблицы",
        "Первый абзац\n\nВторой абзац\n\nТретий абзац",
        "Абзац с **жирным** и `кодом`\n\nДальше *курсив*",
        "   \n\nАбзац после пустой строки с пробелами",
        "Текст\n\n\n\nПосле нескольких пустых строк",
        "Незакрытый **жирный в тексте",
        "Незакрытый ограждение:\n```\nкод без закрытия",
        "Список с подпунктом:\n\n- пункт\n\n  - подпункт",
        "Пункт списка\n\n- первый\n- второй\n\nХвост",
        "Окончание строк CRLF\r\n\r\nАбзац после CRLF",
        "CRLF целиком\r\n\r\n- пункт\r\n\r\nЕщё",
        "Пустая строка в конце\n\n",
        "Три блока\n\nОдин\n\nДва\n\nТри",
    ]

    func testИнкрементальныйРазборСовпадаетСПолным() {
        for text in corpus {
            XCTAssertEqual(
                shape(MarkdownParser.parseIncremental(text)),
                shape(MarkdownParser.parseUncached(text)),
                "Инкрементальный разбор разошёлся с полным на тексте: \(text.prefix(60))"
            )
        }
    }

    /// Главный случай — растущий текст ответа: каждый префикс должен
    /// разбираться так же, как целый текст.
    func testРастущийТекстСовпадаетСПолнымРазбором() {
        let answer = """
        ## Что сделано

        Разбор ответа роли идёт кадрами проявления, и на каждом кадре
        растущий текст разбирается заново.

        - пункт один;
        - пункт два.

        ```swift
        let blocks = MarkdownParser.parse(text)
        ```

        Итог: разбор должен быть дешевле кадра анимации.
        """
        var checked = 0
        for length in stride(from: 1, through: answer.count, by: 3) {
            let prefix = String(answer.prefix(length))
            XCTAssertEqual(
                shape(MarkdownParser.parseIncremental(prefix)),
                shape(MarkdownParser.parseUncached(prefix)),
                "Разбор разошёлся на префиксе длиной \(length)"
            )
            checked += 1
        }
        XCTAssertGreaterThan(checked, 50, "Проверено должно быть много префиксов")
    }

    /// Скорость: инкрементальный разбор растущего текста заметно дешевле
    /// полного — иначе смысла в нём нет.
    func testИнкрементальныйРазборДешевлеПолного() {
        let stable = """
        ## Что сделано

        Разбор ответа роли идёт кадрами проявления, и на каждом кадре
        растущий текст разбирается заново.

        - пункт один;
        - пункт два.
        """
        // Растущий хвост: как в проявлении.
        let iterations = 200
        let tails = ["Хвост растёт", "Хвост растёт и растёт", "Хвост растёт и растёт дальше"]

        let fullStart = DispatchTime.now().uptimeNanoseconds
        for index in 0..<iterations {
            let text = stable + "\n\n" + tails[index % tails.count]
            _ = MarkdownParser.parseUncached(text)
        }
        let full = Double(DispatchTime.now().uptimeNanoseconds - fullStart) / Double(iterations) / 1000

        let incrementalStart = DispatchTime.now().uptimeNanoseconds
        for index in 0..<iterations {
            let text = stable + "\n\n" + tails[index % tails.count]
            _ = MarkdownParser.parseIncremental(text)
        }
        let incremental = Double(DispatchTime.now().uptimeNanoseconds - incrementalStart) / Double(iterations) / 1000

        print(String(format: "РАЗБОР растущего текста: полный %.3f мкс, инкрементальный %.3f мкс", full, incremental))
        XCTAssertLessThan(incremental, full / 2, "Инкрементальный разбор должен быть заметно дешевле полного")
    }

    /// Следующий кадр проявления с тем же текстом не разбирает его заново.
    ///
    /// Состояние проявления публикуется каждые 16 мс (60 Гц), а текст ответа
    /// меняется раз в ~150 мс — значит один и тот же текст приходит десятками
    /// кадров подряд. Кэш живого ответа делает эти кадры почти бесплатными.
    func testПовторныйКадрБерётРазборИзКэша() {
        let text = """
        ## Что сделано

        Разбор ответа роли идёт кадрами проявления.

        - пункт один;
        - пункт два.
        """
        let iterations = 200

        let fullStart = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<iterations { _ = MarkdownParser.parseUncached(text) }
        let full = Double(DispatchTime.now().uptimeNanoseconds - fullStart) / Double(iterations) / 1000

        // Первый кадр прогревает кэш живого текста.
        _ = MarkdownParser.parseIncremental(text)
        let cachedStart = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<iterations { _ = MarkdownParser.parseIncremental(text) }
        let cached = Double(DispatchTime.now().uptimeNanoseconds - cachedStart) / Double(iterations) / 1000

        print(String(format: "КАДР ПРОЯВЛЕНИЯ: разбор с нуля %.3f мкс, из кэша %.3f мкс", full, cached))
        XCTAssertLessThan(cached, full / 2, "Повторный кадр должен брать разбор из кэша")
    }

    /// Разложение ответа на куски кэшируется тем же способом: без кэша текст
    /// раскладывался заново на каждом кадре проявления.
    func testРазложениеОтветаБерётсяИзКэша() {
        let text = "Сводка:\n```tf-json\n{\"version\":1}"
        let cached = ChatRichContent.split(text)
        XCTAssertEqual(cached, ChatRichContent.splitUncached(text))
        XCTAssertEqual(cached, ChatRichContent.split(text))
    }

    /// Готовые куски текста блока кэшируются по id блока: сборка
    /// `AttributedString` стоит ~2 мкс на прогон и была самой дорогой частью
    /// кадра проявления.
    func testКускиТекстаБерутсяИзКэша() {
        let block = NoteBlock(
            kind: .paragraph,
            runs: [RichRun(text: "Привет", bold: true), RichRun(text: " мир")]
        )
        let first = RoleReplyMarkdown.pieces(for: block)
        let second = RoleReplyMarkdown.pieces(for: block)
        XCTAssertEqual(first.count, 2)
        XCTAssertEqual(first.map(\.bold), [true, false])
        XCTAssertEqual(first.map(\.attributed.characters.count), second.map(\.attributed.characters.count))
        // Тот же id — те же куски; другой блок — другие.
        let other = NoteBlock(kind: .paragraph, runs: block.runs)
        XCTAssertNotEqual(other.id, block.id)
    }
}
