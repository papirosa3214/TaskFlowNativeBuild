import Foundation
import XCTest
#if canImport(TaskFlow)
@testable import TaskFlow
#endif

final class ChatSlashCommandCardTests: XCTestCase {
    /// Новый сервер: карточка из title/summary/icon.
    @objc func testCardFields() throws {
        let json = #"[{"id":"merge-to-main","title":"Влить в main","kind":"skill","description":"Длинное описание.","invocation":"/skill:merge-to-main ","summary":"коммит и слияние","icon":"arrow.triangle.merge"}]"#
        let command = try XCTUnwrap(JSONDecoder().decode([ChatSlashCommand].self, from: Data(json.utf8)).first)
        XCTAssertEqual(command.cardSummary, "коммит и слияние")
        XCTAssertEqual(command.cardIcon, "arrow.triangle.merge")
    }

    /// Старый сервер без карточки: подпись — первая фраза описания, значок по виду.
    @objc func testOldServerFallback() throws {
        let json = #"[{"id":"s","title":"Research","kind":"skill","description":"Ищет источники. Применяй, когда…","invocation":"/skill:research "},{"id":"m","title":"web_search","kind":"mcp","description":"search","invocation":"/mcp:web_search "}]"#
        let commands = try JSONDecoder().decode([ChatSlashCommand].self, from: Data(json.utf8))
        XCTAssertEqual(commands[0].cardSummary, "Ищет источники")
        XCTAssertEqual(commands[0].cardIcon, "sparkles")
        XCTAssertEqual(commands[1].cardIcon, "wrench.and.screwdriver")
    }
}
