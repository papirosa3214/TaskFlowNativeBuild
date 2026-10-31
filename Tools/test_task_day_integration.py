#!/usr/bin/env python3
"""Host regression of the production picker conversion, without SwiftUI/Simulator.

Compile unchanged Foundation helpers and the actual view-model conversion methods.
Before integration the picker passes its Date straight through; require that exact
old binding before using the identity adapter for the RED run.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def declaration(text, marker):
    start = text.index(marker)
    opening = text.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]


vm = (ROOT / 'Sources/Features/Tasks/TaskFormViewModel.swift').read_text()
methods = [declaration(vm, 'nonisolated static func dueDateString(')]
integrated = 'nonisolated static func dueDateFromPicker(' in vm
if integrated:
    methods += [declaration(vm, 'nonisolated static func ' + name + '(')
                for name in ['dueDateFromPicker', 'pickerDateForDisplay']]
else:
    quick = (ROOT / 'Sources/Features/Tasks/QuickAddTaskView.swift').read_text()
    assert 'Binding(get: { viewModel.dueDate ?? Date() }, set: { viewModel.dueDate = $0 })' in quick
    methods += ['static func dueDateFromPicker(_ value: Date, deviceTimeZone: TimeZone) -> Date { value }',
                'static func pickerDateForDisplay(_ value: Date, deviceTimeZone: TimeZone) -> Date { value }']

program = '''import Foundation
enum APIClient {
''' + declaration((ROOT / 'Sources/Core/Networking/APIClient+Tasks.swift').read_text(),
                  'struct NewTaskRequest:') + '''
}
enum TaskFormViewModel {
''' + '\n'.join(methods) + '''
}
var failures = 0
var checks = 0
func check(_ condition: Bool, _ message: String) {
    checks += 1
    if !condition { failures += 1; print("FAIL: " + message) }
}
for name in ["Europe/Moscow", "Europe/Berlin", "Asia/Dubai", "Asia/Kolkata", "Asia/Tokyo", "Australia/Perth", "Pacific/Auckland", "America/New_York", "America/Los_Angeles"] {
    let zone = TimeZone(identifier: name)!
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    let picked = calendar.date(from: DateComponents(year: 2026, month: 10, day: 23))!
    let stored = TaskFormViewModel.dueDateFromPicker(picked, deviceTimeZone: zone)
    check(TaskFormViewModel.dueDateString(stored) == "2026-10-23", name + ": selected day survives save")
    let shown = TaskFormViewModel.pickerDateForDisplay(stored, deviceTimeZone: zone)
    let parts = calendar.dateComponents([.year, .month, .day], from: shown)
    check(parts.year == 2026 && parts.month == 10 && parts.day == 23, name + ": picker displays selected day")
    let savedAgain = TaskFormViewModel.dueDateString(TaskFormViewModel.dueDateFromPicker(shown, deviceTimeZone: zone))
    check(savedAgain == "2026-10-23", name + ": round trip")
}
'''
if integrated:
    program += '''
let repeated = APIClient.NewTaskRequest(title: "Repeat", runRepeat: "weekly", repeatUntil: "2026-12-31")
let repeatedJSON = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(repeated)) as! [String: Any]
check(repeatedJSON["run_repeat"] as? String == "weekly", "create request includes repeat")
check(repeatedJSON["repeat_until"] as? String == "2026-12-31", "create request includes repeat limit")
let simple = APIClient.NewTaskRequest(title: "Simple")
let simpleJSON = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(simple)) as! [String: Any]
check(simpleJSON["run_repeat"] == nil, "omit absent repeat")
check(simpleJSON["repeat_until"] == nil, "omit absent repeat limit")
check(TaskDay.date(from: "2026-02-30") == nil, "reject impossible date")
check(TaskDay.date(from: "2026-02-28") != nil, "accept valid date")
for name in ["Europe/Berlin", "America/New_York", "Asia/Tokyo"] {
    let zone = TimeZone(identifier: name)!
    let loaded = TaskDay.date(from: "2026-10-23")!
    let shown = TaskFormViewModel.pickerDateForDisplay(loaded, deviceTimeZone: zone)
    let saved = TaskFormViewModel.dueDateString(TaskFormViewModel.dueDateFromPicker(shown, deviceTimeZone: zone))
    check(saved == "2026-10-23", name + ": server round trip")
}
'''
program += '''
print("Task day integration: \\(checks - failures)/\\(checks) passed")
exit(failures == 0 ? 0 : 1)
'''
sources = ['Sources/Core/Common/CalendarDateMath.swift', 'Sources/Core/Common/DateFormats.swift',
           'Sources/Features/Tasks/Support/TaskDateText.swift']
if integrated:
    sources.append('Sources/Core/Common/TaskDay.swift')
with tempfile.TemporaryDirectory(prefix='task-day-integration-') as folder:
    main = Path(folder) / 'main.swift'
    main.write_text(program)
    binary = Path(folder) / 'tests'
    subprocess.run(['swiftc', *[str(ROOT / x) for x in sources], str(main), '-o', str(binary)], check=True)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
