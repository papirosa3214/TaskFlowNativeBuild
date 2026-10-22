import XCTest
@testable import TaskFlow

/// Загрузка вложений после создания задачи (`flushPending`).
///
/// High №1 кодревью 22.10.2026: неудачная загрузка глушилась через `try?`,
/// а `pending.removeAll()` убирал файл из списка молча — пользователь терял
/// файл и не узнавал об этом. Тесты ниже держат правило: неудачный файл
/// остаётся в `pending`, а пользователь получает `errorMessage`.
@MainActor
final class TaskAttachmentsFlushTests: XCTestCase {

    override func tearDown() {
        AttachmentFlushURLProtocol.handler = nil
        AttachmentFlushURLProtocol.calls = 0
        super.tearDown()
    }

    /// Неудачная загрузка: файл остаётся в `pending`, ошибка показана.
    /// На прежнем коде файл пропадал — тест падал.
    func testНеудачнаяЗагрузкаОставляетФайлВPending() async throws {
        AttachmentFlushURLProtocol.handler = { _ in throw URLError(.networkConnectionLost) }
        let controller = TaskAttachmentsController(apiClient: makeClient(), taskId: nil)
        await controller.add(url: try makeTempFile(name: "note.txt"))

        await controller.flushPending(taskId: "task-1")

        XCTAssertEqual(controller.pending.count, 1, "неудачный файл не должен пропадать")
        XCTAssertEqual(controller.pending.first?.fileName, "note.txt")
        XCTAssertNotNil(controller.errorMessage, "пользователь должен узнать о неудаче")
        XCTAssertTrue(controller.uploaded.isEmpty)
    }

    /// Успешная загрузка: файл ушёл на сервер, `pending` пуст, ошибки нет.
    func testУспешнаяЗагрузкаУбираетФайлИзPending() async throws {
        AttachmentFlushURLProtocol.handler = { _ in
            (200, Data(#"{"attachment":{"id":"att-1","task_id":"task-1","file_name":"note.txt","mime":"text/plain","size":5}}"#.utf8))
        }
        let controller = TaskAttachmentsController(apiClient: makeClient(), taskId: nil)
        await controller.add(url: try makeTempFile(name: "note.txt"))

        await controller.flushPending(taskId: "task-1")

        XCTAssertTrue(controller.pending.isEmpty)
        XCTAssertEqual(controller.uploaded.count, 1)
        XCTAssertEqual(controller.uploaded.first?.id, "att-1")
        XCTAssertNil(controller.errorMessage)
    }

    /// Два файла, второй не загрузился: загруженный уходит на сервер,
    /// неудачный остаётся в `pending` — файл не пропадает по дороге.
    func testЧастичнаяЗагрузкаОставляетТолькоНеудачныйФайл() async throws {
        AttachmentFlushURLProtocol.handler = { request in
            let name = request.url?.query?.split(separator: "name=").last.map(String.init) ?? ""
            if name.contains("second") {
                throw URLError(.networkConnectionLost)
            }
            return (200, Data(#"{"attachment":{"id":"att-1","task_id":"task-1","file_name":"first.txt","mime":"text/plain","size":5}}"#.utf8))
        }
        let controller = TaskAttachmentsController(apiClient: makeClient(), taskId: nil)
        await controller.add(url: try makeTempFile(name: "first.txt"))
        await controller.add(url: try makeTempFile(name: "second.txt"))
        XCTAssertEqual(controller.pending.count, 2)

        await controller.flushPending(taskId: "task-1")

        XCTAssertEqual(controller.uploaded.count, 1)
        XCTAssertEqual(controller.uploaded.first?.fileName, "first.txt")
        XCTAssertEqual(controller.pending.count, 1)
        XCTAssertEqual(controller.pending.first?.fileName, "second.txt")
        XCTAssertNotNil(controller.errorMessage)
    }

    // MARK: - Обвязка

    private func makeClient() -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AttachmentFlushURLProtocol.self]
        return APIClient(session: URLSession(configuration: config))
    }

    private func makeTempFile(name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try Data("данные".utf8).write(to: url)
        return url
    }
}

/// Ответ сервера на загрузку — по одному на запрос, номер считается отдельно.
private final class AttachmentFlushURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data))?
    nonisolated(unsafe) static var calls = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let handler = try XCTUnwrap(Self.handler)
            Self.calls += 1
            let (status, data) = try handler(request)
            let response = try XCTUnwrap(HTTPURLResponse(
                url: XCTUnwrap(request.url),
                statusCode: status,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
