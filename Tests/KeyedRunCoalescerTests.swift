import Foundation
import XCTest
#if canImport(TaskFlow)
@testable import TaskFlow
#endif

/// Склейка одновременных догрузок одного ключа (06.11.2026: на одну секунду
/// ответа роли телефон запрашивал одну и ту же страницу сообщений семь раз).
final class KeyedRunCoalescerTests: XCTestCase {
    func testSecondRequestWhileRunningDoesNotStartAnotherRun() {
        var runs = KeyedRunCoalescer()
        XCTAssertTrue(runs.begin("chat-1"))
        XCTAssertFalse(runs.begin("chat-1"))
        XCTAssertFalse(runs.begin("chat-1"))
    }

    func testRequestsDuringRunGiveExactlyOneRepeat() {
        var runs = KeyedRunCoalescer()
        XCTAssertTrue(runs.begin("chat-1"))
        _ = runs.begin("chat-1")
        _ = runs.begin("chat-1")
        XCTAssertTrue(runs.finish("chat-1"), "пришло новое во время прогона — нужен один повтор")
        XCTAssertFalse(runs.finish("chat-1"), "после повтора новых запросов нет — прогон окончен")
        XCTAssertTrue(runs.begin("chat-1"), "ключ освобождён — следующий запрос запускает прогон")
    }

    func testQuietRunFinishesAtOnce() {
        var runs = KeyedRunCoalescer()
        XCTAssertTrue(runs.begin("chat-1"))
        XCTAssertFalse(runs.finish("chat-1"))
    }

    func testDifferentKeysRunIndependently() {
        var runs = KeyedRunCoalescer()
        XCTAssertTrue(runs.begin("chat-1"))
        XCTAssertTrue(runs.begin("chat-2"))
        XCTAssertFalse(runs.finish("chat-2"))
        XCTAssertFalse(runs.begin("chat-1"))
    }
}
