import Foundation
import XCTest
@testable import TaskFlow

final class ChatComposerControlsTests: XCTestCase {
    func testSameModelFromTwoProvidersRemainsTwoChoices() throws {
        let options = try JSONDecoder().decode([RoleModelOption].self, from: Data(#"[{"id":"a/shared","title":"Shared","provider":"a","modelID":"shared","contextWindow":1000},{"id":"b/shared","title":"Shared","provider":"b","modelID":"shared","contextWindow":2000}]"#.utf8))
        let groups = RoleModelOption.grouped(options)
        XCTAssertEqual(groups.map(\.provider), ["a", "b"])
        XCTAssertEqual(Set(groups.flatMap(\.models).map(\.id)).count, 2)
        XCTAssertEqual(options[1].contextWindow, 2000)
    }
    func testLegacyModelDoesNotInventProvider() throws {
        let option = try JSONDecoder().decode(RoleModelOption.self, from: Data(#"{"id":"shared","title":"Shared"}"#.utf8))
        XCTAssertEqual(option.providerTitle, "Провайдер не указан")
    }
    func testLegacyBareSelectionMigratesOnlyWhenUnambiguous() throws {
        let options = try JSONDecoder().decode([RoleModelOption].self, from: Data(#"[{"id":"a/shared","title":"Shared","provider":"a","modelID":"shared"},{"id":"b/shared","title":"Shared","provider":"b","modelID":"shared"}]"#.utf8))
        XCTAssertNil(RoleModelOption.resolveSelection("shared", in: options))
        XCTAssertEqual(RoleModelOption.resolveSelection("shared", in: [options[0]]), "a/shared")
        XCTAssertEqual(RoleModelOption.resolveSelection("b/shared", in: options), "b/shared")
    }
    func testContextKeepsUnknownValuesUnknownAndDoesNotReusePostCompactionUsage() throws {
        let context = try decodeContext(#"{"roleID":"s","sessionID":"x","model":"m","provider":"p","tokens":null,"contextWindow":1000,"measuredAt":null,"status":"after_compaction","isEstimate":true}"#)
        XCTAssertNil(context.fraction)
        XCTAssertFalse(context.shouldConsiderReset)
        XCTAssertTrue(context.summary.contains("сжатия"))
    }
    func testMeasuredContextHasRawCountsAndUnclampedOverflowWarning() throws {
        let context = try decodeContext(#"{"roleID":"s","sessionID":"x","model":"m","provider":"p","tokens":1250,"contextWindow":1000,"measuredAt":"2026-10-26T00:00:00Z","status":"measured","isEstimate":false}"#)
        XCTAssertEqual(context.fraction, 1.25)
        XCTAssertTrue(context.shouldConsiderReset)
        XCTAssertTrue(context.summary.contains("1250"))
        XCTAssertTrue(context.summary.contains("1000"))
    }
    func testNoSessionNeverShowsOldMeasurement() throws {
        let context = try decodeContext(#"{"roleID":"s","sessionID":null,"model":null,"provider":null,"tokens":900,"contextWindow":1000,"measuredAt":null,"status":"no_session","isEstimate":false}"#)
        XCTAssertNil(context.fraction)
        XCTAssertFalse(context.shouldConsiderReset)
        XCTAssertEqual(context.summary, "Новая сессия · замера ещё нет")
    }
    func testUnknownFutureStatusIsSafe() throws {
        let context = try decodeContext(#"{"roleID":"s","sessionID":"x","tokens":100,"contextWindow":1000,"status":"future","isEstimate":true}"#)
        XCTAssertNil(context.fraction)
        XCTAssertEqual(context.summary, "Контекст пока недоступен")
    }
    func testSlashSearchOnlyAtStartAndSelectionPreservesArguments() throws {
        let commands = try JSONDecoder().decode([ChatSlashCommand].self, from: Data(#"[{"id":"s","title":"Research","kind":"skill","description":"sources","invocation":"/skill:research "},{"id":"m","title":"web_search","kind":"mcp","description":"search","invocation":"/mcp:web_search "}]"#.utf8))
        XCTAssertEqual(ChatSlashCommand.suggestions(for: "/rese", from: commands).map(\.id), ["s"])
        XCTAssertEqual(ChatSlashCommand.suggestions(for: "/mcp:web", from: commands).map(\.id), ["m"])
        XCTAssertTrue(ChatSlashCommand.suggestions(for: "сравни /rese", from: commands).isEmpty)
        XCTAssertEqual(commands[0].inserting(into: "/rese сравни источники"), "/skill:research сравни источники")
        XCTAssertEqual(commands[0].inserting(into: ""), "/skill:research ")
    }
    func testAssistantResearchAndChatOnlyPolicyDoesNotAffectOtherRoles() {
        XCTAssertEqual(RoleChatWorkMode.available(for: ["secretary"]), [.work, .plan, .goal, .deepResearch])
        XCTAssertEqual(RoleChatWorkMode.available(for: ["builder"]), [.work, .plan, .goal])
        XCTAssertTrue(ChatComposerPolicy.isAssistantOnly(["secretary"]))
        XCTAssertFalse(ChatComposerPolicy.isAssistantOnly(["secretary", "builder"]))
    }
    private func decodeContext(_ text: String) throws -> ChatContextSnapshot {
        try JSONDecoder().decode(ChatContextSnapshot.self, from: Data(text.utf8))
    }
}
