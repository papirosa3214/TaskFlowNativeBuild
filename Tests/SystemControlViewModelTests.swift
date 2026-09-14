import Foundation
import XCTest
@testable import TaskFlow

/// Карточка управления системой на «Обзоре»: включение и режим постановки.
/// Проверяется главное — что интерфейс не врёт владельцу: отказ сервера
/// возвращает подтверждённое значение, а непрочитанное состояние не
/// выдаётся за «выключено»/«ручной».
@MainActor
final class SystemControlViewModelTests: XCTestCase {
    override func tearDown() {
        SystemControlURLProtocol.handler = nil
        super.tearDown()
    }

    private func makeViewModel() -> SystemControlViewModel {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SystemControlURLProtocol.self]
        return SystemControlViewModel(api: APIClient(session: URLSession(configuration: configuration)))
    }

    func testLoadReadsRunningStateAndMode() async {
        SystemControlURLProtocol.handler = { request in
            if request.url?.path.hasSuffix("/agent-service") == true {
                return (200, Data(#"{"active":true,"enabled":true}"#.utf8))
            }
            return (200, Data(#"{"mode":"automatic"}"#.utf8))
        }
        let viewModel = makeViewModel()
        await viewModel.load()

        XCTAssertTrue(viewModel.isSystemOn)
        XCTAssertTrue(viewModel.isSystemStateKnown)
        XCTAssertEqual(viewModel.mode, .automatic)
        XCTAssertTrue(viewModel.isModeKnown)
    }

    /// Юнит включён, но не работает — владельцу это «выключено»: задачу
    /// такая система не возьмёт, и показывать её работающей нельзя.
    func testEnabledButNotActiveCountsAsOff() async {
        SystemControlURLProtocol.handler = { request in
            if request.url?.path.hasSuffix("/agent-service") == true {
                return (200, Data(#"{"active":false,"enabled":true}"#.utf8))
            }
            return (200, Data(#"{"mode":"manual"}"#.utf8))
        }
        let viewModel = makeViewModel()
        await viewModel.load()

        XCTAssertFalse(viewModel.isSystemOn)
        XCTAssertTrue(viewModel.isSystemStateKnown)
    }

    /// Сервер молчит — состояние остаётся НЕИЗВЕСТНЫМ, а не «выключено».
    /// На этом флаге экран показывает «Нет связи» и гасит тумблер.
    func testUnreachableServerLeavesStateUnknown() async {
        SystemControlURLProtocol.handler = { _ in (500, Data(#"{"error":"down"}"#.utf8)) }
        let viewModel = makeViewModel()
        await viewModel.load()

        XCTAssertFalse(viewModel.isSystemStateKnown)
        XCTAssertFalse(viewModel.isModeKnown)
    }

    func testModeToggleSurvivesRoundTrip() async {
        SystemControlURLProtocol.handler = { request in
            if request.url?.path.hasSuffix("/agent-service") == true {
                return (200, Data(#"{"active":true,"enabled":true}"#.utf8))
            }
            if request.httpMethod == "PATCH" {
                return (200, Data(#"{"mode":"automatic"}"#.utf8))
            }
            return (200, Data(#"{"mode":"manual"}"#.utf8))
        }
        let viewModel = makeViewModel()
        await viewModel.load()
        await viewModel.setMode(.automatic)

        XCTAssertEqual(viewModel.mode, .automatic)
        XCTAssertNil(viewModel.errorMessage)
    }

    /// Отказ сервера обязан вернуть ровно подтверждённое значение —
    /// иначе оптимистичный показ превращается в тихое враньё.
    func testRejectedModeChangeRestoresConfirmedValue() async {
        SystemControlURLProtocol.handler = { request in
            if request.url?.path.hasSuffix("/agent-service") == true {
                return (200, Data(#"{"active":true,"enabled":true}"#.utf8))
            }
            if request.httpMethod == "PATCH" {
                return (400, Data(#"{"error":"нераспознанный режим"}"#.utf8))
            }
            return (200, Data(#"{"mode":"manual"}"#.utf8))
        }
        let viewModel = makeViewModel()
        await viewModel.load()
        await viewModel.setMode(.automatic)

        XCTAssertEqual(viewModel.mode, .manual)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testRejectedSystemToggleRestoresConfirmedValue() async {
        SystemControlURLProtocol.handler = { request in
            if request.httpMethod == "POST" {
                return (500, Data(#"{"error":"systemd"}"#.utf8))
            }
            if request.url?.path.hasSuffix("/agent-service") == true {
                return (200, Data(#"{"active":true,"enabled":true}"#.utf8))
            }
            return (200, Data(#"{"mode":"manual"}"#.utf8))
        }
        let viewModel = makeViewModel()
        await viewModel.load()
        await viewModel.setSystemOn(false)

        XCTAssertTrue(viewModel.isSystemOn)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    /// Пока состояние не прочитано, переключать нечего: запрос на сервер
    /// не уходит вовсе.
    func testToggleIsIgnoredWhileStateUnknown() async {
        var requestCount = 0
        SystemControlURLProtocol.handler = { _ in
            requestCount += 1
            return (500, Data(#"{"error":"down"}"#.utf8))
        }
        let viewModel = makeViewModel()
        await viewModel.load()
        let afterLoad = requestCount

        await viewModel.setSystemOn(true)
        await viewModel.setMode(.automatic)

        XCTAssertEqual(requestCount, afterLoad)
    }
}

private final class SystemControlURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (status, data) = handler(request)
        let response = HTTPURLResponse(
            url: url, statusCode: status, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
