#!/usr/bin/env python3
"""Behavioral host tests of the real routine editor and hint engine. No Simulator."""
from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parents[1]
source = 'import Foundation\nimport XCTest\n'
for path in ['Sources/Core/Common/CalendarDateMath.swift', 'Sources/Core/Common/DateFormats.swift', 'Sources/Core/Models/Schedule.swift', 'Sources/Features/Routines/RoutineFormat.swift']:
    source += (root / path).read_text() + '\n'
source += r'''
struct RoleProfile { let role: String; let title: String }
enum TaskPriority: Int { case urgent = 1, high, medium, low }
struct APIError: Error { var errorDescription: String? { "Request failed" } }
enum Method { case patch }
final class APIClient {
    var body: Data?; var path: String?; var creates = 0; var fails = false
    var response: ApiScheduleResponse!
    func roles() async throws -> [RoleProfile] { [] }
    func schedulePreview(ruleKind: String, ruleExpr: String?, timeLocal: String, timezone: String) async throws -> ApiSchedulePreview {
        ApiSchedulePreview(nextRunAt: nil, timezone: timezone, ruleLabel: nil)
    }
    func request<T: Decodable>(_ method: Method, _ path: String, body: ApiScheduleCreateRequest) async throws -> T {
        self.path = path; self.body = try JSONEncoder().encode(body)
        if fails { throw APIError() }
        return response as! T
    }
    func createSchedule(_ body: ApiScheduleCreateRequest) async throws -> ApiScheduleResponse {
        creates += 1; self.body = try JSONEncoder().encode(body); return response
    }
}
'''
source += (root / 'Sources/Features/Routines/RoutineFormViewModel.swift').read_text() + '\n'
for name in ['HintModels', 'HintScenarios', 'HintCenter']:
    source += (root / ('Sources/DesignSystem/Hints/' + name + '.swift')).read_text() + '\n'
source += (root / 'Tests/RoutineEditingTests.swift').read_text().replace('@testable import TaskFlow', '').replace('    func test', '    @objc func test')
source += '\nlet suite = RoutineEditingTests.defaultTestSuite\nsuite.run()\nlet unitPassed = suite.testRun!.hasSucceeded\n'
source += r'''
Task { @MainActor in
    var failures = unitPassed ? 0 : 1
    func check(_ ok: Bool, _ name: String) {
        print("\(ok ? "PASS" : "FAIL"): \(name)")
        if !ok { failures += 1 }
    }
    let json = #"{"schedule":{"id":"routine-1","title":"Дайджест","task_payload":{"title":"Новости","description":"Полное задание\nВторая строка","assignee_id":"researcher","project_id":"p1","priority":2,"duration_min":45,"labels":["news"],"requires_reviewer_review":true,"needs_research":true},"rule_kind":"weekly_days","rule_expr":"1,3,5","time_local":"10:30","timezone":"Europe/Moscow","status":"paused","catch_up":false,"overlap_policy":"skip","created_at":"2026-10-26","updated_at":"2026-10-26"}}"#
    let response = try! JSONDecoder().decode(ApiScheduleResponse.self, from: Data(json.utf8))
    let api = APIClient(); api.response = response
    let editor = RoutineFormViewModel(api: api, schedule: response.schedule)
    check(editor.instructions == "Полное задание\nВторая строка", "full existing instructions are loaded")
    check(editor.ruleExpr == "1,3,5" && editor.timeLocal == "10:30", "existing schedule is loaded")
    editor.instructions = "Новое задание"
    let saved = await editor.create()
    check(saved && api.path == "/schedules/routine-1" && api.creates == 0, "edit PATCHes the same routine, never POSTs a new one")
    let body = try! JSONSerialization.jsonObject(with: api.body!) as! [String: Any]
    let payload = body["task_payload"] as! [String: Any]
    check(payload["description"] as? String == "Новое задание", "edited instructions are sent")
    check(payload["labels"] as? [String] == ["news"] && payload["requires_reviewer_review"] as? Bool == true && payload["needs_research"] as? Bool == true, "editing preserves hidden template settings")
    check(body["status"] == nil && body["current_task_id"] == nil, "editing does not resume paused routine or replace existing task")
    editor.instructions = ""; editor.assigneeRoleKey = nil; editor.projectId = nil; editor.durationMin = nil
    _ = await editor.create()
    let cleared = (try! JSONSerialization.jsonObject(with: api.body!) as! [String: Any])["task_payload"] as! [String: Any]
    check(["description", "assignee_id", "project_id", "duration_min"].allSatisfy { cleared[$0] is NSNull }, "clearing optional fields sends explicit null for server merge")
    let freshAPI = APIClient(); freshAPI.response = response
    let fresh = RoutineFormViewModel(api: freshAPI); fresh.title = "Новая рутина"
    let created = await fresh.create()
    check(created && freshAPI.creates == 1 && freshAPI.path == nil, "new routine still uses POST")
    api.fails = true
    let failed = await editor.create()
    check(!failed && editor.errorMessage != nil && !editor.isSaving, "save failure stays actionable")
    if let scenario = HintScenarios.all.first(where: { $0.id == "routine-editing" }) {
        let defaults = UserDefaults(suiteName: "routine-hint-" + UUID().uuidString)!
        let center = HintCenter(defaults: defaults, scenarios: [scenario])
        center.start(scenario.id)
        check(center.currentStep?.anchor == "routine.instructions", "hint starts at task instructions")
        center.next()
        check(center.currentStep?.anchor == "routine.history", "hint explains separate run history")
        center.next()
        check(center.completed.contains(scenario.id), "hint completes")
    } else { check(false, "routine editing hint exists") }
    exit(failures == 0 ? 0 : 1)
}
dispatchMain()
'''
developer = Path(subprocess.check_output(['xcode-select', '-p'], text=True).strip())
frameworks = developer / 'Platforms/MacOSX.platform/Developer/Library/Frameworks'
libraries = developer / 'Platforms/MacOSX.platform/Developer/usr/lib'
with tempfile.TemporaryDirectory(prefix='routine-editing-') as tmp:
    path = Path(tmp) / 'main.swift'; path.write_text(source)
    binary = Path(tmp) / 'tests'
    subprocess.run(['swiftc', '-F', str(frameworks), '-I', str(libraries), '-L', str(libraries), '-Xlinker', '-rpath', '-Xlinker', str(frameworks), '-Xlinker', '-rpath', '-Xlinker', str(libraries), str(path), '-o', str(binary)], check=True)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
