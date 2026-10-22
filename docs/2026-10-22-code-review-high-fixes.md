# Два High-находжения кодревью — исправлено

22.10.2026 · реестр: `LOCK-ATTACHMENT-FLUSH-20261022`, `LOCK-ESCALATION-STEP-INDEX-20261022`
Источник: `docs/2026-10-22-code-quality-review.md` (раздел «⚠️ Issues Found → High»).

## Результат

Оба High-находжения закрыты, логика приложения не менялась — починены только
обработка ошибки загрузки вложения и адресация шага в окне правки напоминания.

| Находка | Файл | Что было | Что стало |
| --- | --- | --- | --- |
| High №1 — потеря вложения | `Sources/Features/Task/Fields/AttachmentsFieldView.swift` | ошибка загрузки глушилась через `try?`, `pending.removeAll()` убирал файл в любом случае | неудачный файл остаётся в `pending`, пользователь получает `errorMessage` — как в `add` и `removeUploaded` |
| High №2 — падение по индексу | `Sources/Features/Settings/EscalationStepEditor.swift` | номер шага, захваченный при отрисовке, шёл в `remove(at:)` и `rule.steps[index]` | шаг ищется по значению (`EscalationStepDraft.currentIndex(in:)`), выход за границу больше невозможен |

## Что сделано

### High №1 — `AttachmentsFieldView.flushPending(taskId:)`

```swift
// было
for item in pending {
    if let attachment = try? await apiClient.uploadTaskAttachment(...) {
        uploaded.append(attachment)
    }
}
pending.removeAll()

// стало
var failed: [PendingAttachment] = []
for item in pending {
    do {
        let attachment = try await apiClient.uploadTaskAttachment(...)
        uploaded.append(attachment)
    } catch {
        failed.append(item)
    }
}
if failed.isEmpty {
    pending.removeAll()
} else {
    pending = failed
    errorMessage = "Не удалось приложить файл"
}
```

Часть файлов может уйти на сервер, часть — нет: удалённые из `pending` только
те, что действительно загрузились.

### High №2 — `EscalationStepEditor`

Логика правки и удаления шага вынесена из View в `EscalationStepDraft`
(тот же файл) — её теперь можно проверить юнит-тестом:

```swift
func currentIndex(in rule: EscalationRule) -> Int? {
    guard let index else { return nil }              // новый шаг — искать нечего
    if rule.steps.indices.contains(index), rule.steps[index] == step {
        return index                                 // шаг стоит на своём месте
    }
    if let moved = rule.steps.firstIndex(of: step) {
        return moved                                  // шаг переехал (сортировка по часам)
    }
    if rule.steps.indices.contains(index) {
        return index                                  // содержимое шага изменилось — правим тот же номер
    }
    return nil                                        // шага больше нет — править нечего
}
```

Шаг в правиле узнаётся по значению (`afterHours` + `priorityMax` + `channels`),
а не по номеру: два шага с одинаковым числом часов в правиле невозможны
(сервер различает шаги по часам, проверка `hoursTaken`). Поэтому правка и
удаление попадают именно в тот шаг, который открыли, — даже если правило
перечитали с сервера или шаги пересортировались.

Если шага в правиле больше нет, правка не применяется (шага нет — менять
нечего) и новый шаг по-прежнему просто добавляется.

## Проверки

RED — на прежнем коде (логика в `EscalationStepDraft` вынесена без изменения
поведения, дальше — исправление):

```
Test Case '-[TaskFlowTests.TaskAttachmentsFlushTests testНеудачнаяЗагрузкаОставляетФайлВPending]' failed
Test Case '-[TaskFlowTests.TaskAttachmentsFlushTests testЧастичнаяЗагрузкаОставляетТолькоНеудачныйФайл]' failed
    XCTAssertEqual failed: ("0") is not equal to ("1")     ← файл пропал из pending
    XCTAssertNotNil failed                                   ← errorMessage не задан

Test Case '-[TaskFlowTests.EscalationStepIndexTests testПравкаПопадаетВТотЖеШаг]' failed
    XCTAssertEqual failed: ("EscalationStep(afterHours: 30, …)") is not equal to ("EscalationStep(afterHours: 1, …)") - чужой шаг не тронут
Test Case '-[TaskFlowTests.EscalationStepIndexTests testУдалениеНеБьётПоСоседнемуШагу]' failed
    XCTAssertEqual failed: ("EscalationStep(afterHours: 24, …)") is not equal to ("EscalationStep(afterHours: 1, …)") - чужой шаг не тронут
Fatal error: Index out of range                                ← падение на выходе за границу
Restarting after unexpected exit, crash, or test timeout
```

GREEN — после исправления:

```
Executed 4 tests, with 0 failures   EscalationStepIndexTests
Executed 3 tests, with 0 failures   TaskAttachmentsFlushTests
Executed 7 tests, with 0 failures
```

Сторож дизайн-системы — чисто. Сборка iOS Simulator — BUILD SUCCEEDED.

## Ограничения

- «Удалить шаг» на единственном шаге по-прежнему не проходит: сервер не
  принимает правило без шагов (`EscalationSettingsViewModel.update`) — это
  прежнее поведение, его не трогали.
- Visual-приёмка на телефоне за владельцем.

## Материалы

- `Sources/Features/Task/Fields/AttachmentsFieldView.swift`
- `Sources/Features/Settings/EscalationStepEditor.swift`
- `Tests/TaskAttachmentsFlushTests.swift` (новый, 3 теста)
- `Tests/EscalationStepIndexTests.swift` (новый, 4 теста)
- `docs/2026-10-22-code-quality-review.md` — исходный список находок
