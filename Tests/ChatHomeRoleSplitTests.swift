import XCTest

/// Список чатов делит роли на внутренних и внешних.
///
/// Владелец 10.11.2026: посередине подпись «Внешние агенты» и отделить их
/// от внутренних ролей. Внутренний — у кого вшит портрет. Внешний — роль
/// без портрета (Claude Code, Codex, Гермес). Секретарь и человек — не внешние.
final class ChatHomeRoleSplitTests: XCTestCase {
    @objc func testClaudeCodeIsExternal() {
        XCTAssertTrue(RoleAvatarAsset.isExternalChatRole(roleKey: "claude_code", userID: "role_claude_code"))
    }

    @objc func testHermesWithoutKeyIsExternal() {
        XCTAssertTrue(RoleAvatarAsset.isExternalChatRole(roleKey: nil, userID: "role_hermes"))
    }

    @objc func testKnownExternalKeysStayExternal() {
        for key in ["codex", "gemini", "opencode"] {
            XCTAssertTrue(RoleAvatarAsset.isExternalChatRole(roleKey: key, userID: "role_\(key)"))
        }
    }

    @objc func testResearcherStaysInternal() {
        XCTAssertFalse(RoleAvatarAsset.isExternalChatRole(roleKey: "researcher", userID: "role_researcher"))
    }

    @objc func testOrchestratorAliasStaysInternal() {
        XCTAssertFalse(RoleAvatarAsset.isExternalChatRole(roleKey: "orchestrator", userID: "role_orchestrator"))
    }

    @objc func testSecretaryStaysInternal() {
        XCTAssertFalse(RoleAvatarAsset.isExternalChatRole(roleKey: "secretary", userID: "u-secretary"))
        XCTAssertFalse(RoleAvatarAsset.isExternalChatRole(roleKey: nil, userID: "u-secretary"))
    }

    @objc func testPersonIsNotExternal() {
        XCTAssertFalse(RoleAvatarAsset.isExternalChatRole(roleKey: nil, userID: "u-maksim"))
    }
}
