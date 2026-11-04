import Foundation
import XCTest
@testable import TaskFlow

/// Каталог описаний моделей и порядок показа (LOCK-CHAT-MODEL-PICKER-20261029).
final class ChatModelCatalogTests: XCTestCase {
    private func option(_ id: String, _ title: String) -> RoleModelOption {
        RoleModelOption(id: id, title: title, provider: "anthropic", modelID: id, contextWindow: nil)
    }

    func testFreeVariantsHaveAnExplicitFreeMarker() {
        XCTAssertTrue(ChatModelCatalog.isFree("opencode/beam-free"))
        XCTAssertTrue(ChatModelCatalog.isFree("opencode/glm-5.3-flash-free"))
        XCTAssertTrue(ChatModelCatalog.isFree("openrouter/vendor/model:free"))
        XCTAssertFalse(ChatModelCatalog.isFree("opencode/beam"))
        XCTAssertFalse(ChatModelCatalog.isFree("openai/free-text-model"))
        XCTAssertFalse(ChatModelCatalog.isFree("ollama/local-free"))
    }

    func testFavoritesComeFirstThenAlphabetical() {
        let models = [
            option("anthropic/claude-sonnet-5", "Sonnet 5"),
            option("anthropic/claude-haiku-5-5", "Haiku 5.5"),
            option("anthropic/claude-opus-5", "Opus 5")
        ]
        let ordered = ChatModelCatalog.ordered(models, favorites: ["anthropic/claude-opus-5"])
        XCTAssertEqual(ordered.map(\.id), ["anthropic/claude-opus-5", "anthropic/claude-haiku-5-5", "anthropic/claude-sonnet-5"])
    }

    func testWithoutFavoritesOrderIsAlphabetical() {
        let models = [
            option("anthropic/claude-sonnet-5", "Sonnet 5"),
            option("anthropic/claude-haiku-5-5", "Haiku 5.5")
        ]
        let ordered = ChatModelCatalog.ordered(models, favorites: [])
        XCTAssertEqual(ordered.map(\.id), ["anthropic/claude-haiku-5-5", "anthropic/claude-sonnet-5"])
    }

    func testKnownModelHasOwnDescription() {
        let profile = ChatModelCatalog.profile(for: "anthropic/claude-opus-5")
        XCTAssertEqual(profile.kind, .advanced)
        XCTAssertFalse(profile.summary.isEmpty)
    }

    func testFamilyDescribesOtherVersionsOfSameModel() {
        // Версии той же модели характер не меняют — описание по семейству.
        let known = ChatModelCatalog.profile(for: "anthropic/claude-opus-5")
        let sibling = ChatModelCatalog.profile(for: "anthropic/claude-opus-4-8")
        XCTAssertEqual(known.kind, sibling.kind)
    }

    func testCodingModelsAreMarkedSpecialized() {
        XCTAssertEqual(ChatModelCatalog.profile(for: "openai-codex/gpt-5.3-codex-spark").kind, .specialized)
        XCTAssertEqual(ChatModelCatalog.profile(for: "kimi-coding/k3").kind, .specialized)
    }

    func testCheapAndFastModelsAreLightweight() {
        XCTAssertEqual(ChatModelCatalog.profile(for: "anthropic/claude-haiku-5-5").kind, .lightweight)
        XCTAssertEqual(ChatModelCatalog.profile(for: "openai-codex/gpt-6-luna").kind, .lightweight)
    }

    /// Столбики в списке моделей: дешёвые — 1, дорогие — 4 (владелец 03.11.2026).
    func testCostLevelFollowsKind() {
        XCTAssertEqual(ChatModelCatalog.profile(for: "anthropic/claude-haiku-5-5").costLevel, 1)
        XCTAssertEqual(ChatModelCatalog.profile(for: "openai-codex/gpt-5.3-codex-spark").costLevel, 2)
        XCTAssertEqual(ChatModelCatalog.profile(for: "anthropic/claude-sonnet-5").costLevel, 3)
        XCTAssertEqual(ChatModelCatalog.profile(for: "anthropic/claude-opus-5").costLevel, 4)
        XCTAssertEqual(
            ChatModelCatalog.profile(for: "anthropic/claude-haiku-5-5").costAccessibilityLabel,
            "Стоимость: низкая")
        XCTAssertEqual(
            ChatModelCatalog.profile(for: "anthropic/claude-opus-5").costAccessibilityLabel,
            "Стоимость: высокая")
    }

    func testUnknownModelWithoutFamilyHasNoProfile() {
        XCTAssertFalse(ChatModelCatalog.hasProfile(for: "some-provider/some-model-42"))
    }

    func testEveryKnownModelHasNonEmptySummary() {
        for id in ["anthropic/claude-opus-5", "anthropic/claude-sonnet-5-5", "anthropic/claude-haiku-4-5",
                   "anthropic/claude-fable-5-1", "openai-codex/gpt-6-astra", "openai-codex/gpt-6-luna",
                   "minimax/MiniMax-M3", "kimi-coding/k3"] {
            let profile = ChatModelCatalog.profile(for: id)
            XCTAssertFalse(profile.summary.isEmpty, "у модели \(id) пустое описание")
        }
    }
}
