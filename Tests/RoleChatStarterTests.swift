import Foundation
import XCTest
@testable import TaskFlow

/// Стартовый экран чата с ролью: приветствие и четыре быстрые команды
/// (LOCK-CHAT-ROLE-START-20261029).
final class RoleChatStarterTests: XCTestCase {
    func testEveryKnownRoleHasFourCommands() {
        XCTAssertEqual(RoleChatStarters.all.count, 11)
        for (key, starter) in RoleChatStarters.all {
            XCTAssertEqual(starter.commands.count, RoleChatStarters.commandCount,
                           "роль \(key): команд должно быть \(RoleChatStarters.commandCount)")
        }
    }

    func testCommandsAreFilledAndDistinct() {
        for (key, starter) in RoleChatStarters.all {
            XCTAssertFalse(starter.greeting.isEmpty, "роль \(key): без приветствия")
            for command in starter.commands {
                XCTAssertFalse(command.title.isEmpty, "роль \(key): пустое название команды")
                XCTAssertFalse(command.hint.isEmpty, "роль \(key): пустая подсказка у «\(command.title)»")
                XCTAssertFalse(command.prompt.isEmpty, "роль \(key): пустой текст команды «\(command.title)»")
                XCTAssertFalse(command.icon.isEmpty, "роль \(key): нет значка у «\(command.title)»")
            }
            XCTAssertEqual(Set(starter.commands.map(\.title)).count, starter.commands.count,
                           "роль \(key): названия команд повторяются")
        }
    }

    func testKnownRoleResolvesToItsOwnStarter() {
        XCTAssertEqual(RoleChatStarters.starter(for: "researcher").roleKey, "researcher")
        XCTAssertEqual(RoleChatStarters.starter(for: "secretary").roleKey, "secretary")
        XCTAssertEqual(RoleChatStarters.starter(for: "claude_code").roleKey, "claude_code")
    }

    func testUnknownRoleFallsBackToGenericStarter() {
        XCTAssertEqual(RoleChatStarters.starter(for: "nope").roleKey, "")
        XCTAssertEqual(RoleChatStarters.starter(for: nil).roleKey, "")
        XCTAssertEqual(RoleChatStarters.starter(for: "").roleKey, "")
        XCTAssertEqual(RoleChatStarters.starter(for: nil).commands.count, RoleChatStarters.commandCount)
    }
}
