import XCTest
@testable import TaskFlow

/// Отметки checklist-виджета на клиенте (карточка 21842242): ключи — как их
/// понимает сервер, состояние приходит с сервера, отказ не остаётся незамеченным.
final class ChatChecklistSyncTests: XCTestCase {
    private func widget(_ json: String) -> WidgetData {
        WidgetData.parse(json) ?? WidgetData(raw: [:])
    }

    // MARK: - Ключи

    func testItemKeyPrefersExplicitKeyThenIdThenIndex() {
        let items = widget(#"{"items":[{"key":"pay","id":"x"},{"id":"call"},{"text":"почта"}]}"#).array("items")
        XCTAssertEqual(ChecklistKey.item(items[0], index: 0), "pay")
        XCTAssertEqual(ChecklistKey.item(items[1], index: 1), "call")
        XCTAssertEqual(ChecklistKey.item(items[2], index: 2), "2")
    }

    func testWidgetKeyPrefersBlockIdThenPosition() {
        XCTAssertEqual(ChecklistKey.widget(widget(#"{"type":"checklist","id":"week"}"#), position: "3"), "week")
        XCTAssertEqual(ChecklistKey.widget(widget(#"{"type":"checklist"}"#), position: "3"), "3")
        XCTAssertEqual(ChecklistKey.widget(widget(#"{"type":"checklist"}"#), position: nil), "0")
    }

    // MARK: - Состояние из сообщения

    func testMessageDecodesChecklistState() throws {
        let json = #"{"id":"m1","text":"```widget","is_session_marker":false,"checklist_state":[{"widget_key":"0","item_key":"pay","done":true}]}"#
        let message = try JSONDecoder().decode(RoleChatMessage.self, from: Data(json.utf8))
        XCTAssertEqual(message.checklistState?.count, 1)
        XCTAssertEqual(message.checklistState?.first?.itemKey, "pay")
        XCTAssertEqual(message.checklistState?.first?.done, true)
    }

    func testMessageWithoutStateDecodesAsEmpty() throws {
        let message = try JSONDecoder().decode(RoleChatMessage.self, from: Data(#"{"id":"m1","text":"привет","is_session_marker":false}"#.utf8))
        XCTAssertNil(message.checklistState)
    }

    // MARK: - Что рисуется

    @MainActor
    func testSavedStateWinsOverBlockValue() {
        let sync = ChecklistMessageSync(seed: [], send: { _ in [] })
        XCTAssertFalse(sync.done(widgetKey: "0", itemKey: "pay", inBlock: false))
        sync.apply([ChecklistItemState(widgetKey: "0", itemKey: "pay", done: true)])
        XCTAssertTrue(sync.done(widgetKey: "0", itemKey: "pay", inBlock: false))
    }

    @MainActor
    func testSameItemKeyInTwoWidgetsIsSeparate() {
        let sync = ChecklistMessageSync(seed: [], send: { _ in [] })
        sync.apply([ChecklistItemState(widgetKey: "0", itemKey: "pay", done: true)])
        XCTAssertTrue(sync.done(widgetKey: "0", itemKey: "pay", inBlock: false))
        XCTAssertFalse(sync.done(widgetKey: "1", itemKey: "pay", inBlock: false))
    }

    // MARK: - Отправка

    @MainActor
    func testToggleSendsKeysAndAdoptsServerState() async {
        let recorder = SendRecorder(result: [
            ChecklistItemState(widgetKey: "0", itemKey: "pay", done: true),
            ChecklistItemState(widgetKey: "0", itemKey: "call", done: true),
        ])
        let sync = ChecklistMessageSync(seed: [], send: { item in
            recorder.record(item)
            return try recorder.result
        })
        await sync.toggle(widgetKey: "0", itemKey: "pay", to: true)
        XCTAssertEqual(recorder.sent, [ChecklistItemState(widgetKey: "0", itemKey: "pay", done: true)])
        XCTAssertTrue(sync.done(widgetKey: "0", itemKey: "pay", inBlock: false))
        // Ответ принёс состояние всего сообщения — соседний пункт тоже виден.
        XCTAssertTrue(sync.done(widgetKey: "0", itemKey: "call", inBlock: false))
        XCTAssertNil(sync.failure)
    }

    @MainActor
    func testUncheckIsAlsoSent() async {
        let recorder = SendRecorder(result: [])
        let sync = ChecklistMessageSync(seed: [ChecklistItemState(widgetKey: "0", itemKey: "pay", done: true)],
                                       send: { item in
                                           recorder.record(item)
                                           return try recorder.result
                                       })
        await sync.toggle(widgetKey: "0", itemKey: "pay", to: false)
        XCTAssertEqual(recorder.sent.first?.done, false)
        XCTAssertFalse(sync.done(widgetKey: "0", itemKey: "pay", inBlock: false))
    }

    @MainActor
    func testRejectionRollsBackAndExplains() async {
        let sync = ChecklistMessageSync(seed: [], send: { _ in
            throw APIError.server(status: 400, message: "В сообщении нет checklist-виджета «9»")
        })
        await sync.toggle(widgetKey: "0", itemKey: "pay", to: true)
        XCTAssertFalse(sync.done(widgetKey: "0", itemKey: "pay", inBlock: false))
        XCTAssertEqual(sync.failure, "Виджет в сообщении переписан — отметка не сохранена")
    }

    @MainActor
    func testMissingChatIsNotSilentSuccess() async {
        let sync = ChecklistMessageSync(seed: [], send: { _ in
            throw APIError.notFound(message: "Чат не найден")
        })
        await sync.toggle(widgetKey: "0", itemKey: "pay", to: true)
        XCTAssertEqual(sync.failure, "Сообщение или чат не найдены — отметка не сохранена")
    }
}

/// Заглушка отправки: помнит, что ушло, и отдаёт заготовленный ответ.
private final class SendRecorder: @unchecked Sendable {
    private(set) var sent: [ChecklistItemState] = []
    let result: [ChecklistItemState]

    init(result: [ChecklistItemState]) { self.result = result }

    func record(_ item: ChecklistItemState) { sent.append(item) }
}
