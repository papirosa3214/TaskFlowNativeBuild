import Foundation
import XCTest
@testable import TaskFlow

/// Порядок ленты чата (карточка 252c400e, этап 5).
///
/// Проверяем правило: сообщения идут в серверной последовательности, живой
/// ход стоит сразу после своего якоря, а не по дате начала хода.
final class ChatTimelineProjectionTests: XCTestCase {

    private func message(_ id: String, text: String = "", own: Bool = false) -> ChatTimelineProjection.MessageRef {
        ChatTimelineProjection.MessageRef(id: id, text: text, isOwn: own)
    }

    /// Старое правило: живой ход вставлялся по дате. Оно ломало порядок —
    /// ход вставал выше более нового сообщения.
    func testLiveTurnStandsRightAfterItsAnchorNotByDate() {
        let items = ChatTimelineProjection.project(
            messages: [message("q1"), message("answer"), message("q2")],
            turns: [ChatTimelineProjection.TurnRef(playbackID: "t1", anchorMessageID: "q2")])
        XCTAssertEqual(items.map(\.id), ["msg:q1", "msg:answer", "msg:q2", "turn:t1"])
    }

    /// Несколько ходов на одном якоре сохраняют порядок между собой.
    func testTwoTurnsOnSameAnchorKeepTheirOrder() {
        let items = ChatTimelineProjection.project(
            messages: [message("q1")],
            turns: [ChatTimelineProjection.TurnRef(playbackID: "t1", anchorMessageID: "q1"),
                    ChatTimelineProjection.TurnRef(playbackID: "t2", anchorMessageID: "q1")])
        XCTAssertEqual(items.map(\.id), ["msg:q1", "turn:t1", "turn:t2"])
    }

    /// Якорь неизвестен (история не загружена) — ход в хвост, а не в середину.
    func testTurnWithoutKnownAnchorGoesToTail() {
        let items = ChatTimelineProjection.project(
            messages: [message("q1"), message("q2")],
            turns: [ChatTimelineProjection.TurnRef(playbackID: "t1", anchorMessageID: "missing")])
        XCTAssertEqual(items.map(\.id), ["msg:q1", "msg:q2", "turn:t1"])
    }

    /// Ход без якоря совсем — тоже в хвост.
    func testTurnWithoutAnchorGoesToTail() {
        let items = ChatTimelineProjection.project(
            messages: [message("q1")],
            turns: [ChatTimelineProjection.TurnRef(playbackID: "t1")])
        XCTAssertEqual(items.map(\.id), ["msg:q1", "turn:t1"])
    }

    /// Порядок сообщений после final и после reconnect — тот же самый:
    /// серверная последовательность не меняется от того, жив ход или нет.
    func testOrderIsSameBeforeAndAfterFinal() {
        let withTurn = ChatTimelineProjection.project(
            messages: [message("q1"), message("answer"), message("q2")],
            turns: [ChatTimelineProjection.TurnRef(playbackID: "t1", anchorMessageID: "q1")])
        let afterFinal = ChatTimelineProjection.project(
            messages: [message("q1"), message("answer"), message("q2")],
            turns: [])
        XCTAssertEqual(withTurn.compactMap(\.messageID), afterFinal.compactMap(\.messageID))
        XCTAssertEqual(afterFinal.map(\.id), ["msg:q1", "msg:answer", "msg:q2"])
    }

    /// Переподключение: тот же снимок истории даёт тот же порядок.
    func testOrderIsStableAcrossReloads() {
        let first = ChatTimelineProjection.project(
            messages: [message("q1"), message("answer"), message("q2")],
            turns: [ChatTimelineProjection.TurnRef(playbackID: "t1", anchorMessageID: "answer")])
        let second = ChatTimelineProjection.project(
            messages: [message("q1"), message("answer"), message("q2")],
            turns: [ChatTimelineProjection.TurnRef(playbackID: "t1", anchorMessageID: "answer")])
        XCTAssertEqual(first, second)
    }

    /// Своё сообщение «в пути», подтверждённое сервером, не задваивается.
    func testConfirmedOwnMessageReplacesPendingWithoutDuplicate() {
        let items = ChatTimelineProjection.project(
            messages: [message("own", text: "Привет", own: true)],
            turns: [],
            pending: [ChatTimelineProjection.PendingRef(id: "p1", text: "Привет")])
        XCTAssertEqual(items.map(\.id), ["msg:own"])
    }

    /// Неподтверждённое своё сообщение остаётся в ленте.
    func testUnconfirmedOwnMessageStaysInFeed() {
        let items = ChatTimelineProjection.project(
            messages: [message("own", text: "Привет", own: true)],
            turns: [],
            pending: [ChatTimelineProjection.PendingRef(id: "p1", text: "Другое")])
        XCTAssertEqual(items.map(\.id), ["msg:own", "pending:p1"])
    }

    /// Порядок не зависит от того, что живых ходов несколько и часть из них
    /// пришла позже по времени, чем их якорь.
    func testTurnDateDoesNotAffectOrder() {
        let items = ChatTimelineProjection.project(
            messages: [message("q1"), message("q2")],
            turns: [ChatTimelineProjection.TurnRef(playbackID: "late", anchorMessageID: "q1"),
                    ChatTimelineProjection.TurnRef(playbackID: "early", anchorMessageID: "q2")])
        XCTAssertEqual(items.map(\.id), ["msg:q1", "turn:late", "msg:q2", "turn:early"])
    }

    /// Ответ, закрытый остановкой, стоит там, где стоял его живой ход: сразу
    /// после своего вопроса. Сервер дописывает такой ответ уже после нового
    /// сообщения владельца — и без правила в ленте два вопроса подряд
    /// (владелец 30.10.2026).
    func testStoppedAnswerStandsRightAfterItsQuestion() {
        let items = ChatTimelineProjection.project(
            messages: [message("q1"),
                       message("q2"),
                       ChatTimelineProjection.MessageRef(id: "a1", anchorMessageID: "q1")],
            turns: [ChatTimelineProjection.TurnRef(playbackID: "t2", anchorMessageID: "q2")])
        XCTAssertEqual(items.map(\.id), ["msg:q1", "msg:a1", "msg:q2", "turn:t2"])
    }

    /// Обычный ответ (без остановки) остаётся в серверной последовательности.
    func testAnswerWithoutStopKeepsServerOrder() {
        let items = ChatTimelineProjection.project(
            messages: [message("q1"), message("a1"), message("q2")], turns: [])
        XCTAssertEqual(items.map(\.id), ["msg:q1", "msg:a1", "msg:q2"])
    }

    /// Два ответа на один вопрос сохраняют порядок между собой.
    func testTwoStoppedAnswersOnSameQuestionKeepOrder() {
        let items = ChatTimelineProjection.project(
            messages: [message("q1"), message("q2"),
                       ChatTimelineProjection.MessageRef(id: "a1", anchorMessageID: "q1"),
                       ChatTimelineProjection.MessageRef(id: "a2", anchorMessageID: "q1")],
            turns: [])
        XCTAssertEqual(items.map(\.id), ["msg:q1", "msg:a1", "msg:a2", "msg:q2"])
    }

    /// Вопроса в загруженной истории нет — сообщение не теряется и не улетает
    /// в хвост, остаётся на своём месте.
    func testAnswerWithUnknownQuestionKeepsItsPlace() {
        let items = ChatTimelineProjection.project(
            messages: [ChatTimelineProjection.MessageRef(id: "a1", anchorMessageID: "gone"),
                       message("q2")],
            turns: [])
        XCTAssertEqual(items.map(\.id), ["msg:a1", "msg:q2"])
    }
}
