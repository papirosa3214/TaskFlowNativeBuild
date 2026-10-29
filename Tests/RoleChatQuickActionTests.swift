import Foundation
import XCTest
@testable import TaskFlow

/// Правки быстрых действий владельцем (LOCK-CHAT-QUICK-ACTIONS-20261029).
final class RoleChatQuickActionTests: XCTestCase {
    private var starter: RoleChatStarter {
        RoleChatStarters.starter(for: "researcher")
    }

    func testWithoutOverridesCommandsStayStock() {
        let commands = RoleChatQuickActions.effectiveCommands(for: starter, overrides: [:])
        XCTAssertEqual(commands.map(\.title), starter.commands.map(\.title))
        XCTAssertEqual(commands.map(\.prompt), starter.commands.map(\.prompt))
    }

    func testCustomNameReplacesTitle() {
        let overrides: RoleChatQuickActionOverrides = [
            0: RoleChatQuickActionOverride(name: "Собери спецификацию", prompt: nil)
        ]
        let commands = RoleChatQuickActions.effectiveCommands(for: starter, overrides: overrides)
        XCTAssertEqual(commands[0].title, "Собери спецификацию")
        // Промпт остался штатным — правка его не трогала.
        XCTAssertEqual(commands[0].prompt, starter.commands[0].prompt)
    }

    func testCustomPromptReplacesPrompt() {
        let overrides: RoleChatQuickActionOverrides = [
            1: RoleChatQuickActionOverride(name: nil, prompt: "Разбери мой код и найди узкие места")
        ]
        let commands = RoleChatQuickActions.effectiveCommands(for: starter, overrides: overrides)
        XCTAssertEqual(commands[1].prompt, "Разбери мой код и найди узкие места")
        XCTAssertEqual(commands[1].title, starter.commands[1].title)
    }

    func testBlankFieldsMeanStockValue() {
        let overrides: RoleChatQuickActionOverrides = [
            0: RoleChatQuickActionOverride(name: "   ", prompt: "\n")
        ]
        let commands = RoleChatQuickActions.effectiveCommands(for: starter, overrides: overrides)
        XCTAssertEqual(commands[0].title, starter.commands[0].title)
        XCTAssertEqual(commands[0].prompt, starter.commands[0].prompt)
    }

    func testEmptyOverrideMeansNothingToSave() {
        XCTAssertTrue(RoleChatQuickActionOverride().isEmpty)
        XCTAssertTrue(RoleChatQuickActionOverride(name: " ", prompt: "").isEmpty)
        XCTAssertFalse(RoleChatQuickActionOverride(name: "Имя").isEmpty)
        XCTAssertFalse(RoleChatQuickActionOverride(prompt: "Промпт").isEmpty)
    }

    func testEditorShowsCurrentValues() {
        let overrides: RoleChatQuickActionOverrides = [
            0: RoleChatQuickActionOverride(name: "Собери спецификацию", prompt: "Собери спецификацию по моему коду")
        ]
        let shown = RoleChatQuickActions.override(for: 0, in: starter, overrides: overrides)
        XCTAssertEqual(shown.name, "Собери спецификацию")
        XCTAssertEqual(shown.prompt, "Собери спецификацию по моему коду")
    }

    func testEditorOfUntouchedCardShowsStockValues() {
        let shown = RoleChatQuickActions.override(for: 0, in: starter, overrides: [:])
        XCTAssertEqual(shown.name, starter.commands[0].title)
        XCTAssertEqual(shown.prompt, starter.commands[0].prompt)
    }

    func testStorageKeyDependsOnRole() {
        XCTAssertNotEqual(RoleChatQuickActions.storageKey(roleKey: "researcher"),
                          RoleChatQuickActions.storageKey(roleKey: "builder"))
        XCTAssertTrue(RoleChatQuickActions.storageKey(roleKey: "researcher").contains("researcher"))
    }
}
