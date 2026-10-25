import XCTest
@testable import TaskFlow

@MainActor
final class RealtimeConnectionAcceptanceTests: XCTestCase {
    func testUnauthorizedFrameDoesNotConfirmConnection() {
        let client = RealtimeClient()
        client.confirmConnection(for: .serverError(message: "unauthorized"))
        XCTAssertFalse(client.isConnected, "Отказ сервера не является успешным подключением")
    }

    func testOrdinaryEventDoesNotReplaceHandshake() {
        let client = RealtimeClient()
        client.confirmConnection(for: .ping)
        XCTAssertFalse(client.isConnected)
    }

    func testConnectedHandshakeConfirmsConnection() {
        let client = RealtimeClient()
        client.confirmConnection(for: .connected)
        XCTAssertTrue(client.isConnected)
    }
}
