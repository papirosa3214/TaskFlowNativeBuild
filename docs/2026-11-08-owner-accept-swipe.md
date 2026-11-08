# Свайп «Принять» — полномочия владельца не ограничены (08.11.2026)

## Что было

В общем списке «Задачи» свайп влево (trailing) давал «Принять» не на каждой
строке. Правило выбора действия — `ProjectTaskSwipeAction.action(for:isOwner:currentUserID:)`
в `Sources/DesignSystem/Components/DirectoryTaskRow.swift`:

```swift
guard isOwner else { return nil }
guard task.status == .active else { return nil }
if let me = currentUserID, task.assigneeId == me { return .complete }
if !task.readyForPickup { return nil }   // ← вот здесь терялась кнопка
return .complete
```

То есть кнопка была только у задач «на мне» или с поднятым внутренним флагом
готовности (`ready_for_pickup`). Сданная на приёмку задача — двойная галочка
критика (`agentState == .review`, `criticApproved == true`), исполнитель-роль,
флаг опущен — оставалась **без свайпа вообще**: только «В архив». Закрыть её
можно было лишь из карточки, через меню «Работа».

Владелец 08.11.2026: «у меня задача полностью готовая, двойная галочка стоит,
но я не могу принять задачу и увести её в выполненную»; «все эти правила и
ограничители выстраиваются, чтобы работал процесс для агентов и ролей… но у
меня полномочия не ограничены: я могу создать задачу и сразу её отправить в
выполненный, и вообще-то никого ебать не должно».

## Что стало

```swift
guard isOwner else { return nil }
guard task.status == .active else { return nil }
return .complete
```

Флаг готовности и исполнитель остаются внутренними регуляторами ролей и
сервера (кто и когда берёт задачу, что не стартует без утверждённого плана) и
больше не участвуют в выборе действия владельца. Параметр `currentUserID`
сохранён в сигнатуре ради существующих вызовов, но на выбор не влияет.

Что не менялось: `status == .completed` и архивные по-прежнему без кнопки;
экран «Архив» и «Активность» передают `.restore` явно, их не задело.
Сам свайп остался тем же действием `performSwipe` → `case .complete`: если
задача в `review` — сначала `approveCurrentTaskVersion` + сброс `agent_state`,
затем `PATCH status = completed`.

## Где пункт «Принять и закрыть задачу / Вернуть на доработку»

Не в «…», а в карточке задачи: иконка «Работа» (две фигурки, правый верхний
угол) — `Sources/Features/Tasks/TaskCardContent.swift:2340-2350`, пункты
появляются при `isOwner && viewModel.agentState != nil` (`:2411`):
`review` → «Принять и закрыть задачу» + «Вернуть на доработку», `inProgress` →
«Вернуть на доработку» + «Принять и закрыть», `blocked` → «Ответить и вернуть
в работу» + «Принять и закрыть», `todo` → только «Принять и закрыть».
У черновика (`agent_state == nil`) пунктов нет — это не поломка, а выбор
действий по состоянию.

## Проверка

- `Tools/test_task_swipe_actions.py`: RED — 2 падения
  (`testUnconfirmedTaskGetsCompleteSwipeForOwner`,
  `testReviewTaskGetsCompleteSwipeWithoutReadyFlag`), GREEN — 5/5.
- `swiftc -parse Sources/DesignSystem/Components/DirectoryTaskRow.swift` — чисто.
- `git diff --check` — чисто.
- Сторож дизайн-системы: по изменённому файлу ошибок нет (44 ошибки в
  логе — давние, в других файлах, к этой правке не относятся).
- Симулятор, UI-тесты и iPhone не запускались. Визуальную приёмку делает
  владелец.
