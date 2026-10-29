import XCTest

/// Логика подключения сервисов Composio: состояние тумблера во время
/// авторизации и разбор ответа сервера со списком аккаунтов.
///
/// Проверки идут через `XCTAssertEqual` со списками: в XCTest для macOS,
/// который собирается `swiftc` без симулятора, форма с одиночными значениями
/// (`XCTAssertEqual(1, 1)`) остаётся макросом C и в Swift не видна.
final class ComposioConnectorTests: XCTestCase {
    // MARK: - Тумблер

    func testPendingStateWinsOverServerState() {
        var toggles = ComposioToggleState()
        toggles.begin("github", isOn: true)
        XCTAssertEqual([toggles.isOn("github", connected: false)], [true])
        XCTAssertEqual([toggles.isOn("linear", connected: false)], [false])
    }

    func testCancelReturnsServerState() {
        var toggles = ComposioToggleState()
        toggles.begin("github", isOn: true)
        toggles.cancel("github")
        XCTAssertEqual([toggles.isOn("github", connected: false)], [false])
        XCTAssertEqual([toggles.isOn("github", connected: true)], [true])
    }

    func testReconcileEndsWaitWhenServerConfirmed() {
        var toggles = ComposioToggleState()
        toggles.begin("github", isOn: true)
        toggles.reconcile(connected: ["github": true])
        XCTAssertEqual([toggles.isOn("github", connected: true)], [true])
        XCTAssertEqual([toggles.pending.isEmpty], [true])
    }

    func testReconcileKeepsWaitWhenServerStateDiffers() {
        var toggles = ComposioToggleState()
        toggles.begin("github", isOn: true)
        toggles.reconcile(connected: ["github": false])
        XCTAssertEqual([toggles.isOn("github", connected: false)], [true])
        XCTAssertEqual([toggles.pending.count], [1])
    }

    func testReconcileIgnoresServiceMissingFromCatalog() {
        var toggles = ComposioToggleState()
        toggles.begin("github", isOn: true)
        toggles.reconcile(connected: ["linear": true])
        XCTAssertEqual([toggles.pending.count], [1])
    }

    // MARK: - Разделы основных интеграций

    private func toolkit(_ slug: String, connected: Bool = false) -> ComposioToolkit {
        ComposioToolkit(slug: slug, name: slug, logo: nil, description: nil, connected: connected, noAuth: false)
    }

    func testConnectedServicesGoFirst() {
        let sections = ComposioPrimaryServices.sections(from: [toolkit("gmail", connected: true), toolkit("notion")])
        XCTAssertEqual([sections.first?.id], ["connected"])
        XCTAssertEqual([sections.first?.toolkits.count], [1])
        XCTAssertEqual([sections.first?.toolkits.first?.slug], ["gmail"])
    }

    func testConnectedServiceIsNotRepeatedInThemeSections() {
        let sections = ComposioPrimaryServices.sections(from: [toolkit("gmail", connected: true)])
        XCTAssertEqual([sections.count], [1])
        XCTAssertEqual([sections.first?.id], ["connected"])
    }

    func testThemeSectionsKeepGroupOrderAndSkipEmpty() {
        let sections = ComposioPrimaryServices.sections(from: [toolkit("notion"), toolkit("gmail"), toolkit("github")])
        XCTAssertEqual([sections.count], [3])
        XCTAssertEqual([sections.first?.id], ["mail"])
        XCTAssertEqual([sections.last?.id], ["code"])
    }

    func testEverySectionExplainsItsPurpose() {
        let sections = ComposioPrimaryServices.sections(from: [toolkit("gmail"), toolkit("github")])
        let empty = sections.filter { $0.note.isEmpty }.count
        XCTAssertEqual([empty], [0])
    }

    // MARK: - Аккаунты сервиса

    func testAccountsAreDecodedFromServerAnswer() throws {
        let data = Data(#"{"items":[{"id":"ca_1","address":"user@example.com","alias":"work","status":"ACTIVE","created_at":"2026-10-01T10:00:00Z"}]}"#.utf8)
        let list = try JSONDecoder().decode(ComposioAccountList.self, from: data)
        XCTAssertEqual([list.items.count], [1])
        XCTAssertEqual([list.items.first?.id ?? ""], ["ca_1"])
        XCTAssertEqual([list.items.first?.address ?? ""], ["user@example.com"])
        XCTAssertEqual([list.items.first?.alias ?? ""], ["work"])
        XCTAssertEqual([list.items.first?.status ?? ""], ["ACTIVE"])
        XCTAssertEqual([list.items.first?.createdAt ?? ""], ["2026-10-01T10:00:00Z"])
    }

    func testAccountWithoutAddressIsDecoded() throws {
        let data = Data(#"{"items":[{"id":"ca_2","address":null,"alias":null,"status":"INACTIVE"}]}"#.utf8)
        let list = try JSONDecoder().decode(ComposioAccountList.self, from: data)
        XCTAssertEqual([list.items.first?.address == nil], [true])
        XCTAssertEqual([list.items.first?.alias == nil], [true])
        XCTAssertEqual([list.items.first?.createdAt == nil], [true])
    }
}
