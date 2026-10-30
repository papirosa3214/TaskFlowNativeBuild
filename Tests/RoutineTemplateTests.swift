#if ROUTINE_TEMPLATE_HOST_TEST
import Foundation

struct RoleProfile { let role: String; let title: String }
struct APIError: Error { var errorDescription: String? { "Request failed" } }
enum Method { case patch }
final class APIClient {
    var body: Data?; var path: String?; var creates = 0
    var response: ApiScheduleResponse!
    func roles() async throws -> [RoleProfile] { [] }
    func schedulePreview(ruleKind: String, ruleExpr: String?, timeLocal: String, timezone: String) async throws -> ApiSchedulePreview {
        .init(nextRunAt: nil, timezone: timezone, ruleLabel: nil)
    }
    func request<T: Decodable>(_ method: Method, _ path: String, body: ApiScheduleCreateRequest) async throws -> T {
        self.path = path; self.body = try JSONEncoder().encode(body)
        return response as! T
    }
    func createSchedule(_ body: ApiScheduleCreateRequest) async throws -> ApiScheduleResponse {
        creates += 1; self.body = try JSONEncoder().encode(body); return response
    }
}
@main struct RoutineTemplateTests {
    @MainActor static func main() async {
        var failures = 0
        func check(_ ok: Bool, _ name: String) {
            if !ok { failures += 1; print("FAIL: \(name)") }
        }
        let json = #"{"schedule":{"id":"r1","title":"Дайджест","task_payload":{"title":"Новости","plan_profile":"research","labels":["news"]},"rule_kind":"daily","time_local":"09:00","timezone":"Europe/Moscow","status":"active","catch_up":false,"overlap_policy":"skip","created_at":"2026-10-26","updated_at":"2026-10-26"}}"#
        let response = try! JSONDecoder().decode(ApiScheduleResponse.self, from: Data(json.utf8))
        let api = APIClient(); api.response = response
        let model = RoutineFormViewModel(api: api, schedule: response.schedule)
        let saved = await model.create()
        let body = try! JSONSerialization.jsonObject(with: api.body!) as! [String: Any]
        let payload = body["task_payload"] as! [String: Any]
        check(saved && api.path == "/schedules/r1", "editing uses PATCH")
        check(payload["plan_profile"] as? String == "research", "editing retains chosen template")
        check(payload["labels"] as? [String] == ["news"], "hidden payload retained")
        let freshAPI = APIClient(); freshAPI.response = response
        let fresh = RoutineFormViewModel(api: freshAPI); fresh.title = "Новая"
        _ = await fresh.create()
        let newPayload = (try! JSONSerialization.jsonObject(with: freshAPI.body!) as! [String: Any])["task_payload"] as! [String: Any]
        check(freshAPI.creates == 1, "new automatic routine can save")
        check(newPayload["assignee_id"] is NSNull, "automatic never substitutes fixed role")
        check(newPayload["plan_profile"] is NSNull, "automatic sends explicit null template")
        // Explicit choice, replacement, and clearing must all use the real form path.
        model.selectPlanTemplate("single_executor")
        check(model.assigneeRoleKey == nil && model.planProfile == "single_executor", "template clears legacy role")
        _ = await model.create()
        var edited = (try! JSONSerialization.jsonObject(with: api.body!) as! [String: Any])["task_payload"] as! [String: Any]
        check(edited["plan_profile"] as? String == "single_executor" && edited["assignee_id"] is NSNull, "replacement saved as one plan")
        model.selectPlanTemplate(nil)
        _ = await model.create()
        edited = (try! JSONSerialization.jsonObject(with: api.body!) as! [String: Any])["task_payload"] as! [String: Any]
        check(edited["plan_profile"] is NSNull && edited["assignee_id"] is NSNull, "automatic clears both fields for PATCH merge")
        model.assigneeRoleKey = "researcher"
        model.selectPlanTemplate(nil)
        check(model.assigneeRoleKey == nil, "automatic also clears legacy role")
        fresh.selectPlanTemplate("research")
        _ = await fresh.create()
        let chosen = (try! JSONSerialization.jsonObject(with: freshAPI.body!) as! [String: Any])["task_payload"] as! [String: Any]
        check(chosen["plan_profile"] as? String == "research" && chosen["assignee_id"] is NSNull, "new routine saves selected template")
        print("Routine template: \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }
}
#endif
