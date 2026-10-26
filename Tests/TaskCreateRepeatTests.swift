import Foundation
import XCTest
@testable import TaskFlow

/// Повтор карточки при СОЗДАНИИ с телефона раньше молча терялся: в теле
/// создания не было полей `run_repeat`/`repeat_until`, хотя правка их шла.
final class TaskCreateRepeatTests: XCTestCase {

    func testCreateRequestCarriesRepeatRule() throws {
        let request = APIClient.NewTaskRequest(
            title: "Полив цветов",
            runRepeat: "weekly",
            repeatUntil: "2026-12-31"
        )
        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["run_repeat"] as? String, "weekly")
        XCTAssertEqual(json["repeat_until"] as? String, "2026-12-31")
    }

    /// Без повтора лишние ключи в теле создания не отправляются — сервер
    /// ждёт именно такой набор полей.
    func testCreateRequestOmitsRepeatWhenNotSet() throws {
        let request = APIClient.NewTaskRequest(title: "Без повтора")
        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(json["run_repeat"])
        XCTAssertNil(json["repeat_until"])
    }
}
