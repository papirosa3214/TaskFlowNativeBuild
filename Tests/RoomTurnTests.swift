import Foundation
import XCTest
@testable import TaskFlow

/// Ход роли в строке комнаты (владелец 27.10.2026): формы JSON — как в
/// `/api/chats` (`turn`) и `/api/chats/rooms` (`personal_turn`, `dms[].turn`).
final class RoomTurnTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    func testOutcomesDecode() throws {
        XCTAssertEqual(try decode(RoomTurn.self, #"{"running":true,"outcome":null}"#), RoomTurn(running: true, outcome: nil))
        XCTAssertEqual(try decode(RoomTurn.self, #"{"running":false,"outcome":"answered"}"#).outcome, .answered)
        XCTAssertEqual(try decode(RoomTurn.self, #"{"running":false,"outcome":"failed"}"#).outcome, .failed)
        XCTAssertEqual(try decode(RoomTurn.self, #"{"running":false,"outcome":"limit"}"#).outcome, .limit)
    }

    func testUnknownOutcomeIsNoDot() throws {
        XCTAssertNil(try decode(RoomTurn.self, #"{"running":false,"outcome":"something_new"}"#).outcome)
    }

    func testRoomsSnapshotCarriesTurns() throws {
        let snapshot = try decode(ChatRoomsSnapshot.self, #"""
        {"common":{"chat_id":"common","live":false,"last_message":null},
         "roles":[{"id":"u-secretary","name":"Помощник","working":true,"personal_chat_id":"chat-secretary",
           "personal_turn":{"running":true,"outcome":null},"last_message":null,
           "dms":[{"chat_id":"dm1","peer_id":"role_qa","pair":"a:b","live":false,"last_message":null,
             "turn":{"running":false,"outcome":"limit"}}]}]}
        """#)
        XCTAssertEqual(snapshot.roles[0].personalTurn, RoomTurn(running: true, outcome: nil))
        XCTAssertEqual(snapshot.roles[0].dms[0].turn?.outcome, .limit)
    }

    func testRolePendingOutcomeTakesMostUrgentAcrossRooms() throws {
        let snapshot = try decode(ChatRoomsSnapshot.self, #"""
        {"common":{"chat_id":"common","live":false,"last_message":null},
         "roles":[{"id":"u-secretary","name":"Помощник","working":false,"personal_chat_id":"chat-secretary",
           "personal_turn":{"running":false,"outcome":"answered"},"last_message":null,
           "dms":[{"chat_id":"dm1","peer_id":"role_qa","pair":"a:b","live":false,"last_message":null,"turn":{"running":false,"outcome":"failed"}},
                  {"chat_id":"dm2","peer_id":"role_x","pair":"a:c","live":false,"last_message":null,"turn":{"running":false,"outcome":null}}]},
          {"id":"role_qa","name":"Тестировщик","working":false,"personal_chat_id":"p2",
           "personal_turn":{"running":false,"outcome":null},"last_message":null,"dms":[]}]}
        """#)
        XCTAssertEqual(snapshot.roles[0].pendingOutcome, .failed)
        XCTAssertNil(snapshot.roles[1].pendingOutcome)
    }

    func testOldServerWithoutTurnStillDecodes() throws {
        let snapshot = try decode(ChatRoomsSnapshot.self, #"""
        {"common":{"chat_id":"common","live":false,"last_message":null},
         "roles":[{"id":"u-secretary","name":"Помощник","working":false,"personal_chat_id":null,"last_message":null,"dms":[]}]}
        """#)
        XCTAssertNil(snapshot.roles[0].personalTurn)
    }
}
