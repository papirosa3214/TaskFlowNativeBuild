import XCTest
import CoreGraphics
import CoreText
@testable import TaskFlow

/// Метка даты и времени заведения в строке задачи — LOCK-TASK-CREATED-STAMP.
///
/// Владелец 12.10.2026 потребовал ровно это: «мне нужна дата и время заведения
/// этой заявки… мне только числа нужны… 12.10.2026, дефис, время 13 двоеточие
/// 10, и всё это в квадратных скобках». Формат здесь и зафиксирован.
final class TaskCreatedStampTests: XCTestCase {
    private func stamp(_ raw: String?, file: StaticString = #filePath, line: UInt = #line) throws -> String {
        try XCTUnwrap(TFTaskCreatedStamp.text(forCreatedAt: raw), "метка не построилась", file: file, line: line)
    }

    /// Базовый случай владельца: `created_at` из SQLite в UTC → МСК-метка.
    /// 10:10 UTC = 13:10 МСК (UTC+3, октябрь 2026).
    func testStampFormatsUtcToMoscow() throws {
        XCTAssertEqual(try stamp("2026-10-12 10:10:00"), "[12.10.2026 - 13:10]")
    }

    /// Граница суток: заведённая в 23:30 МСК заявка пришла как `20:30 UTC`
    /// того же дня. Метка обязана остаться 12-го, а не съехать на 13-е.
    func testStampKeepsMoscowDayAcrossUtcBoundary() throws {
        XCTAssertEqual(try stamp("2026-10-12 20:30:00"), "[12.10.2026 - 23:30]")
    }

    /// Задача, заведённая в полночь МСК, — самый частый случай «поехавшей» даты.
    func testStampCrossesMidnightToMoscow() throws {
        XCTAssertEqual(try stamp("2026-09-30 21:05:00"), "[01.10.2026 - 00:05]")
    }

    /// Метка — только числа и знаки: ни одной буквы, длиннее ожидаемого.
    func testStampHasNoLettersAndFixedShape() throws {
        let text = try stamp("2026-10-12 10:10:00")

        XCTAssertFalse(text.contains { $0.isLetter })
        XCTAssertEqual(text.count, 20)                       // [12.10.2026 - 13:10]
        XCTAssertTrue(text.hasPrefix("["))
        XCTAssertTrue(text.hasSuffix("]"))
        // Ровно те знаки, которых владелец назвал: точка, дефис, двоеточие.
        XCTAssertEqual(text.filter { !$0.isNumber && !"[] .:-".contains($0) }.count, 0)
    }

    /// Нет даты — нет метки. Сервер отдаёт `created_at` всегда, но модель
    /// допускает `nil` (локальный черновик, несохранённая задача), и пустой
    /// вью в строке оставил бы дыру в мета-строке.
    func testStampIsAbsentWithoutDate() {
        XCTAssertNil(TFTaskCreatedStamp.text(forCreatedAt: nil))
        XCTAssertNil(TFTaskCreatedStamp.text(forCreatedAt: ""))
        XCTAssertNil(TFTaskCreatedStamp.text(forCreatedAt: "не дата"))
    }

    /// Дата приходит из БД в формате SQLite UTC; ISO-8601 с `T` и `Z` сервер
    /// не присылает, но `sqliteUTC` их понимает — проверим, что такой вью
    /// не исчезает молча.
    func testStampAcceptsIso8601() throws {
        XCTAssertEqual(try stamp("2026-10-12T10:10:00Z"), "[12.10.2026 - 13:10]")
    }

    /// `ApiTask.createdAt` приходит именно строкой — метка строится из неё
    /// без дополнительного преобразования в каждом экране.
    func testApiTaskCarriesCreatedAtForStamp() throws {
        let data = Data(#"""
        {"id":"t1","title":"Task","priority":1,"status":"active","pinned":0,
         "creator_id":"owner","created_at":"2026-10-12 10:10:00"}
        """#.utf8)

        let task = try JSONDecoder().decode(ApiTask.self, from: data)

        XCTAssertEqual(try stamp(task.createdAt), "[12.10.2026 - 13:10]")
    }

    /// Строка «Сегодня» собрана `accessibilityElement(children: .ignore)` —
    /// всё содержимое заменяется одной подписью. Значит дата заведения
    /// обязана быть В НЕЙ, иначе для VoiceOver метки просто не существует,
    /// хотя глазами она видна. Проверяем словами, а не пиксельными цифрами.
    func testSpokenLabelIsReadableWords() throws {
        let spoken = try XCTUnwrap(TFTaskCreatedStamp.spokenLabel(forCreatedAt: "2026-10-12 10:10:00"))
        XCTAssertTrue(spoken.hasPrefix("Заведена"), "подпись без слова «Заведена»: \(spoken)")
        XCTAssertTrue(spoken.contains("13:10"), "в подписи нет времени 13:10: \(spoken)")
        // Пиксельные цифры в подписи не годятся — читать их должен VoiceOver.
        XCTAssertFalse(spoken.contains("["), "в подписи VoiceOver осталась псевдографика: \(spoken)")
    }

    /// Даты нет — и в подписи строки ничего лишнего не появится.
    func testSpokenLabelAbsentWithoutDate() {
        XCTAssertNil(TFTaskCreatedStamp.spokenLabel(forCreatedAt: nil))
        XCTAssertNil(TFTaskCreatedStamp.spokenLabel(forCreatedAt: ""))
    }

    /// Шрифтовый файл обязан быть в бандле: без него `Font.custom` молча
    /// падает на системный, и метка выглядит «просто системной» — а при
    /// включённой опции разработчика ещё и падает в консоль. Это тест на
    /// наличие ресурса, а не на вид шрифта.
    func testPixelStampFontIsRegisteredInBundle() {
        let url = Bundle.main.url(forResource: "Handjet-Metric", withExtension: "ttf")
        XCTAssertNotNil(url, "Resources/Fonts/Handjet-Metric.ttf не попал в бандл")

        let names = (Bundle.main.infoDictionary?["UIAppFonts"] as? [String]) ?? []
        XCTAssertTrue(
            names.contains { $0.hasPrefix("Handjet-Metric") },
            "UIAppFonts не объявляет шрифт: \(names)"
        )
    }

    /// Точка и двоеточие в пиксельном шрифте не должны съедать ячейку цифры:
    /// в DotGothic16 все три занимали по 500/1000 em, и пустая половина ячейки
    /// после точки читалась как пробел (владелец 12.10.2026: «убери эти
    /// пробелы»). У Handjet точка уже цифры — это и есть проверка на регресс
    /// при следующей замене шрифта.
    func testStampFontHasNoGapsAroundPunctuation() throws {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "Handjet-Metric", withExtension: "ttf"),
            "шрифт метки не найден в бандле"
        )
        let data = try Data(contentsOf: url)
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let cgFont = try XCTUnwrap(CGFont(provider))

        // Ширину меряем через CTLine — тем же путём, каким символ рисуется.
        // `CTFontGetAdvancesForGlyphs` на этом шрифте отдаёт нули (проверено
        // 12.10.2026), а CTLine измеряет фактический набор.
        let ctFont = CTFontCreateWithGraphicsFont(cgFont, 1000, nil, nil)

        func advance(_ character: Character) -> Int {
            let attributed = NSAttributedString(string: String(character), attributes: [
                kCTFontAttributeName as NSAttributedString.Key: ctFont,
            ])
            let line = CTLineCreateWithAttributedString(attributed)
            return Int(CTLineGetTypographicBounds(line, nil, nil, nil))
        }

        let digit = advance("0")
        for character: Character in [".", ":"] {
            let value = advance(character)
            XCTAssertLessThan(
                value, digit,
                "«\(character)» занимает \(value)/1000 em — не у́же цифры (\(digit)), в метке появятся дыры"
            )
        }
    }
}
