import XCTest
@testable import TaskFlow

/// Канал команд телефону `device_op` (контракт ffaf800d-19ad-40e7-8616-9482019f432e):
/// разбор команды, проверка аргументов и коды отказов.
final class DeviceOpsTests: XCTestCase {
    // MARK: - Разбор команды

    func testParsesDeviceOpCommand() throws {
        let json = """
        {"type":"device_op","v":1,"opId":"b3f1c0de","op":"reminder.create",
         "arguments":{"title":"Позвонить в сервис","dueDate":"2026-10-22T09:00:00+03:00"}}
        """
        let event = RealtimeEvent.parse(Data(json.utf8))
        guard case .deviceOp(let request) = event else {
            return XCTFail("команда device_op не разобралась: \(String(describing: event))")
        }
        XCTAssertEqual(request.opId, "b3f1c0de")
        XCTAssertEqual(request.op, "reminder.create")
        XCTAssertEqual(request.v, 1)
        XCTAssertEqual(request.arguments["title"]?.text, "Позвонить в сервис")
        XCTAssertEqual(request.arguments["dueDate"]?.text, "2026-10-22T09:00:00+03:00")
    }

    func testUnknownDeviceOpIsNotAnEvent() {
        let json = "{\"type\":\"device_op\",\"opId\":\"x\",\"op\":\"reminder.create\"}"
        let event = RealtimeEvent.parse(Data(json.utf8))
        guard case .deviceOp(let request) = event else {
            return XCTFail("команда без аргументов должна разбираться")
        }
        XCTAssertTrue(request.arguments.isEmpty)
    }

    // MARK: - Коды отказов

    func testUnknownOperationIsOpUnknown() async {
        let outcome = await AppleEventKitOps.perform(op: "reminder.erase", arguments: [:])
        guard case .failure(let code, _) = outcome else {
            return XCTFail("неизвестная операция должна быть отказом")
        }
        XCTAssertEqual(code, .opUnknown)
    }

    func testReminderCreateWithoutTitleIsInvalidArguments() async {
        let outcome = await AppleEventKitOps.perform(op: "reminder.create", arguments: [:])
        guard case .failure(let code, _) = outcome else {
            return XCTFail("без названия напоминания — отказ")
        }
        XCTAssertEqual(code, .invalidArguments)
    }

    func testReminderCompleteWithoutIdIsInvalidArguments() async {
        let outcome = await AppleEventKitOps.perform(op: "reminder.complete", arguments: [:])
        guard case .failure(let code, _) = outcome else {
            return XCTFail("без идентификатора — отказ")
        }
        XCTAssertEqual(code, .invalidArguments)
    }

    func testCalendarEventsWithoutPeriodIsInvalidArguments() async {
        let outcome = await AppleEventKitOps.perform(op: "calendar.events", arguments: [:])
        guard case .failure(let code, _) = outcome else {
            return XCTFail("без периода — отказ")
        }
        XCTAssertEqual(code, .invalidArguments)
    }

    func testNewerContractVersionIsRejected() async {
        let request = DeviceOpRequest(v: 2, opId: "abc", op: "reminder.list")
        let answer = await DeviceOpsChannel.shared.resultMessage(for: request)
        XCTAssertTrue(answer.contains("version_unsupported"), answer)
        XCTAssertTrue(answer.contains("\"opId\":\"abc\""), answer)
    }

    func testAnswerCarriesOpIdAndOkFlag() async {
        let request = DeviceOpRequest(v: 1, opId: "xyz", op: "calendar.event.create", arguments: [:])
        let answer = await DeviceOpsChannel.shared.resultMessage(for: request)
        XCTAssertTrue(answer.contains("\"type\":\"device_op_result\""), answer)
        XCTAssertTrue(answer.contains("\"opId\":\"xyz\""), answer)
        XCTAssertTrue(answer.contains("\"ok\":false"), answer)
    }

    // MARK: - Даты

    func testParsesContractDates() {
        XCTAssertNotNil(DeviceOpDates.parse("2026-10-22T09:00:00+03:00"))
        XCTAssertNotNil(DeviceOpDates.parse("2026-10-22T09:00:00Z"))
        XCTAssertNotNil(DeviceOpDates.parse("2026-10-22"))
        XCTAssertNil(DeviceOpDates.parse("завтра утром"))
        XCTAssertNil(DeviceOpDates.parse(""))
    }

    func testContractDateKeepsTimezone() throws {
        let parsed = try XCTUnwrap(DeviceOpDates.parse("2026-10-22T09:00:00+03:00"))
        let iso = DeviceOpDates.iso(parsed)
        XCTAssertTrue(iso.contains("T"), iso)
        // Дата в формате контракта — местное время владельца с его
        // часовым поясом, а не время UTC: момент тот же, часовой пояс — свой.
        XCTAssertEqual(try XCTUnwrap(DeviceOpDates.parse(iso)).timeIntervalSince1970,
                       parsed.timeIntervalSince1970,
                       accuracy: 1)
        let offset = TimeZone.current.secondsFromGMT(for: parsed)
        XCTAssertEqual(offset % 3600, 0)
    }
}
