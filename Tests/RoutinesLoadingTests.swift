#if ROUTINES_HOST_TEST
import Foundation

// Boundary doubles; production RoutinesViewModel and Schedule.swift are compiled unchanged.
struct RoleProfile { let role: String; let title: String }
enum JSONValue { case string(String) }
struct APIError: Error { var errorDescription: String? { "Ошибка" } }
enum RoutineFormat {
    static func runNotice(status: String, detail: String?) -> String { status }
}
@MainActor final class APIClient {
    nonisolated init() {}
    var roleRequests = 0
    var scheduleRequests = 0
    var failSchedules = false
    var failRoles = false
    var releaseRoles: CheckedContinuation<Void, Never>?
    let sample = try! JSONDecoder().decode(ApiSchedule.self, from: Data(#"{"id":"one","title":"Routine","task_payload":{"title":"Task","assignee_id":"builder"},"rule_kind":"daily","time_local":"09:00","timezone":"Europe/Moscow","status":"active","catch_up":false,"overlap_policy":"skip","created_at":"","updated_at":""}"#.utf8))
    func roles() async throws -> [RoleProfile] {
        roleRequests += 1
        await withCheckedContinuation { releaseRoles = $0 }
        if failRoles { throw APIError() }
        return [RoleProfile(role: "builder", title: "Разработчик")]
    }
    func schedules() async throws -> [ApiSchedule] {
        scheduleRequests += 1
        if failSchedules { throw APIError() }
        return [sample]
    }
    func patchSchedule(id: String, fields: [String: JSONValue]) async throws -> ApiSchedule { sample }
    func runScheduleNow(id: String) async throws -> ApiScheduleRunNowResponse { .init(ok: true, schedule: sample, run: nil) }
    func deleteSchedule(id: String) async throws {}
}

@main struct RoutinesLoadingTests {
    @MainActor static func main() async {
        var failures = 0
        func check(_ condition: Bool, _ message: String) {
            if !condition { failures += 1; print("FAIL: \(message)") }
        }
        for failedSchedules in [false, true] {
            let api = APIClient()
            api.failSchedules = failedSchedules
            api.failRoles = failedSchedules
            let model = RoutinesViewModel(api: api)
            let loading = Task { await model.load() }
            // Gate on a real suspension, no timing assumptions or sleep.
            while api.releaseRoles == nil { await Task.yield() }
            check(api.scheduleRequests == 1, "schedules requested before role catalogue completes")
            check(!model.isLoading, "loading indicator ends independently of roles")
            if failedSchedules {
                check(model.errorMessage != nil, "schedule error visible before roles complete")
            } else {
                check(model.schedules.map(\.id) == ["one"], "routines visible before roles complete")
                check(model.roleTitle(for: "builder") == "builder", "fallback key while roles pending")
            }
            api.releaseRoles?.resume()
            await loading.value
            check(!model.isLoading, "loading ends")
            if !failedSchedules {
                check(model.roleTitle(for: "builder") == "Разработчик", "role title updates afterwards")
                await model.load()
                check(api.roleRequests == 1 && api.scheduleRequests == 2, "refresh retains role catalogue and fetches schedules")
            } else {
                check(model.errorMessage != nil, "role failure does not hide schedule error")
            }
        }
        print("Routines loading: \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }
}
#endif
