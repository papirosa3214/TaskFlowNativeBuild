#!/usr/bin/env python3
"""Host-тест «телефон — чисто окошко» (владелец 29.10.2026). Без симулятора.

Проверяется поведение клиента на двух ответах сервера:

  • лёгкая проекция (`?projection=list`): сервер не присылает подзадачи,
    вместо них — два числа; у роли нет промпта и навыков; у шага в истории
    нет вывода инструмента и аргументов вызова, но сервер говорит, что они
    есть;
  • прежний полный ответ (старый сервер): подзадачи на месте, промпт и
    навыки на месте, тела шага на месте.

Клиент обязан работать с обоими: список рисуется одинаково, и на новом
сервере телефон не разбирает то, что не рисует.

Компилируется и запускается на маке (swiftc), без симулятора.
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]

SOURCES = [
    'Sources/Core/Models/Task.swift',
    'Sources/Core/Models/Subtask.swift',
    'Sources/Core/Models/Label.swift',
    'Sources/Core/Models/Comment.swift',
    'Sources/Core/Models/TaskEvent.swift',
    'Sources/Core/Models/Attachment.swift',
    'Sources/Core/Models/AttemptLadder.swift',
    'Sources/Core/Models/RoleProfile.swift',
    'Sources/Core/Models/RoleChat.swift',
    'Sources/Core/Models/ChatExecutionMode.swift',
    'Sources/Core/Models/ChatRooms.swift',
    'Sources/Core/Models/ChatMessageDeliveryState.swift',
    'Sources/Core/Models/ChatMessageInterruption.swift',
    'Sources/Core/Models/ChatQuestion.swift',
    'Sources/Core/Models/ChatServerBlock.swift',
    'Sources/Core/Models/ChatComposerControls.swift',
    'Sources/Core/Models/ChatQuickReplyPolicy.swift',
    'Sources/Core/Models/TaskCodeChanges.swift',
    'Sources/Core/Common/TaskDay.swift',
    'Sources/Core/Common/CalendarDateMath.swift',
    'Sources/Core/Common/DateFormats.swift',
    'Sources/Core/Common/CodableHelpers.swift',
    'Sources/Core/Common/JSONValue.swift',
    'Sources/Core/Common/AgentTextSanitizer.swift',
    'Sources/Core/Common/LastValueCache.swift',
    'Sources/Core/Common/ParsedValueCache.swift',
    'Sources/Core/Models/AgentComponent.swift',
    'Sources/Core/Models/RuntimeModels.swift',
    'Sources/Features/Notes/NoteDocument.swift',
    'Sources/Features/Chat/ChatRichContent.swift',
]

source = 'import Foundation\n'
for path in SOURCES:
    source += (root / path).read_text() + '\n'

source += r'''
func check(_ ok: Bool, _ name: String) {
    print("\(ok ? "PASS" : "FAIL"): \(name)")
    if !ok { failures += 1 }
}
var failures = 0

// ─── Список задач ────────────────────────────────────────────────────────────
// Лёгкая проекция: подзадач нет, есть два числа (29.10.2026).
let lightTaskJSON = #"{"id":"t1","title":"Задача","status":"active","priority":1,"subtask_total":2,"subtask_done":1}"#
let lightTask = try! JSONDecoder().decode(ApiTask.self, from: Data(lightTaskJSON.utf8))
check(lightTask.subtasks.isEmpty, "лёгкий ответ: подзадач нет")
check(lightTask.listSubtasksTotal == 2, "лёгкий ответ: сколько шагов — из счётчика сервера")
check(lightTask.listSubtasksDone == 1, "лёгкий ответ: сколько сделано — из счётчика сервера")

// Прежний ответ (старый сервер): подзадачи на месте, счётчиков нет.
let fullTaskJSON = #"{"id":"t2","title":"Задача","status":"active","priority":1,"subtasks":[{"id":"s1","task_id":"t2","title":"Шаг","done":true,"position":0},{"id":"s2","task_id":"t2","title":"Шаг","done":false,"position":1},{"id":"s3","task_id":"t2","title":"Шаг","done":false,"position":2}]}"#
let fullTask = try! JSONDecoder().decode(ApiTask.self, from: Data(fullTaskJSON.utf8))
check(fullTask.listSubtasksTotal == 3, "старый сервер: шаги считаются по пришедшим подзадачам")
check(fullTask.listSubtasksDone == 1, "старый сервер: сделано считается по пришедшим подзадачам")

// ─── Каталог ролей ───────────────────────────────────────────────────────────
// Лёгкий ответ: промпта и навыков нет (29.10.2026).
let lightRoleJSON = #"{"role":"role_analyst","title":"Аналитик","status":"ready","status_title":"Готов","runtime_ready":true,"problems":[],"tools":[],"fallbacks":[],"attempt_policy":[],"enabled":true}"#
let lightRole = try! JSONDecoder().decode(RoleProfile.self, from: Data(lightRoleJSON.utf8))
check(lightRole.prompt == nil, "лёгкий ответ роли: промпта нет")
check(lightRole.skills == nil, "лёгкий ответ роли: навыков нет")
check(lightRole.title == "Аналитик" && lightRole.role == "role_analyst", "лёгкий ответ роли: имя и роль на месте")

// Прежний ответ (старый сервер): промпт и навыки на месте.
let fullRoleJSON = #"{"role":"role_analyst","title":"Аналитик","status":"ready","status_title":"Готов","runtime_ready":true,"problems":[],"prompt":"Инструкция роли","skills":[{"skill_name":"разбор"}],"tools":[],"fallbacks":[],"attempt_policy":[],"enabled":true}"#
let fullRole = try! JSONDecoder().decode(RoleProfile.self, from: Data(fullRoleJSON.utf8))
check(fullRole.prompt == "Инструкция роли", "старый сервер: промпт на месте")
check(fullRole.skills?.count == 1, "старый сервер: навыки на месте")

// ─── Шаг хода в истории ──────────────────────────────────────────────────────
// Лёгкий ответ: тел нет, но сервер говорит, что они есть.
let lightStepJSON = #"{"kind":"step","id":"call_1","tool":"read","detail":"файл.md","status":"done","started_at":"2026-10-29T06:12:06.898Z","ended_at":"2026-10-29T06:12:07.907Z","has_output":true,"has_args":true}"#
let lightStep = try! JSONDecoder().decode(RoleChatLiveStep.self, from: Data(lightStepJSON.utf8))
check(lightStep.output == nil && lightStep.args == nil, "лёгкий ответ шага: тел вызова и ответа нет")
check(lightStep.hasOutput && lightStep.hasArgs, "лёгкий ответ шага: сервер говорит, что тела есть")
check(lightStep.tool == "read" && lightStep.detail == "файл.md", "лёгкий ответ шага: строка шага рисуется как прежде")

// Прежний ответ (старый сервер): тела на месте.
let fullStepJSON = #"{"kind":"step","id":"call_2","tool":"read","detail":"файл.md","status":"done","args":"{}","output":"итог"}"#
let fullStep = try! JSONDecoder().decode(RoleChatLiveStep.self, from: Data(fullStepJSON.utf8))
check(fullStep.output == "итог" && fullStep.args == "{}", "старый сервер: тела шага на месте")
check(!fullStep.hasOutput && !fullStep.hasArgs, "старый сервер: признаков догрузки нет")

exit(failures == 0 ? 0 : 1)
'''

developer = Path(subprocess.check_output(['xcode-select', '-p'], text=True).strip())
frameworks = developer / 'Platforms/MacOSX.platform/Developer/Library/Frameworks'
libraries = developer / 'Platforms/MacOSX.platform/Developer/usr/lib'

with tempfile.TemporaryDirectory(prefix='window-payloads-') as tmp:
    path = Path(tmp) / 'main.swift'
    path.write_text(source)
    binary = Path(tmp) / 'tests'
    subprocess.run([
        'swiftc', '-F', str(frameworks), '-I', str(libraries), '-L', str(libraries),
        '-Xlinker', '-rpath', '-Xlinker', str(frameworks), '-Xlinker', '-rpath', '-Xlinker', str(libraries),
        str(path), '-o', str(binary),
    ], check=True)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
