# Порядок и целостность снимка новой сессии (14.11.2026)

Работа: `LOCK-SESSION-SNAPSHOT-ORDER-20261114`. Только новые сессии
(`Sources/Features/Sessions/`). Чаты ролей не тронуты.

## Что было не так

`SessionViewModel.refreshSnapshot()` вызывался из двух независимых мест
(`receive` по `agent_settled` и `recoverAfterReconnect`) и мог идти в двух
копиях одновременно. Две беды:

1. **Обратный порядок.** Запрос снимка A стартовал раньше B, но ответ A
   приходил позже и ставился последним: более старый снимок перезаписывал
   более новый. Порядка ответов сеть не гарантирует.
2. **Потеря событий.** Установка снимка сохраняет `lastCursor` и
   `seenCursors` (`installSnapshot(_:preservingCursor:)`,
   `Sources/Features/Sessions/Engine/SessionViewModel.swift:609`). Если за
   время запроса приходило событие, оно попадало в состояние и в
   `seenCursors`, а затем снимок заменял состояние целиком
   (`state = SessionState(snapshot: snapshot)`). Событие исчезало из
   состояния, а его курсор оставался отмеченным принятым: повторно сервер его
   уже не отдаст — потеря навсегда. Заметнее всего на своём сообщении: оно
   приходит событием `message_end`, а снимок, запрошенный раньше, его не
   содержит.

## Серверный контракт (проверено на .110, `~/Проекты/New-Todoist`, `0aee248b`)

- `GET /api/sessions/:id` (`server/src/routes/owner-sessions.ts:337-345`) →
  `runtime.snapshot(id)` (`server/src/runtime/ownerSessionRuntime.ts:370-388`).
  В ответе: `id`, `cwd`, `sessionFile`, `parentSession`, `model`, `relation`,
  `name`, `leafId`, `isStreaming`, `isIdle`, `entries`, `tree`.
  **Курсора, порядкового номера или отметки потока событий в ответе нет.**
- События: `server/src/runtime/ownerSessionEvents.ts`. Курсор —
  `"<epoch>:<sequence>"` (`:338`, `sequence` растёт на каждый `push`),
  буфер ограничен 512 событиями, `eventsAfter` (`:418-429`) отдаёт всё строго
  после курсора либо `resetRequired`, если курсора в буфере нет (в том числе
  после перезапуска процесса — новый `epoch`).
- В конверте события есть `entryId`, но `normalizePiEvent` его не заполняет
  (единственное место — сигнатура `envelope`, `ownerSessionEvents.ts:62`), то
  есть опознать «это событие уже есть в снимке» по `entryId` нельзя.
- У библиотеки Pi прямо сказано, что `message_end` срабатывает **до**
  сохранения сообщения в транскрипт
  (`pi-coding-agent/dist/core/cache-stats.d.ts:46`), поэтому сверять по
  `entries` тоже нечего.

Вывод: **определить на телефоне, до какого события актуален снимок,
невозможно.** Любая «гарантия» вроде «снимок всегда новее уже применённых
событий» была бы выдумкой.

## Что сделано

Новый тип `SessionSnapshotGate`
(`Packages/NewChatCore/Sources/NewChatCore/SessionSnapshotGate.swift`):
номер запроса и метка окна событий, три вердикта — `install`, `superseded`,
`windowDirty`.

`SessionViewModel`:

- `appliedEventMark` (`:69`) растёт, когда событие открытой сессии опускается
  в состояние (`receive`, `:499`);
- `refreshSnapshot()` (`:555-...)` берёт номер запроса и метку окна, а после
  ответа ставит снимок только при `.install`. Ответ с номером не больше уже
  установленного отбрасывается (`.superseded`); ответ с непустым окном
  отбрасывается (`.windowDirty`) и запрашивается заново — одна повторная
  попытка, дальше снимок не ставится вовсе;
- метка установленного запроса растёт только при установке
  (`snapshotGate.markInstalled`), поэтому порядок установок монотонный.

Отброшенный снимок **ничего не теряет**: состояние остаётся с уже
применёнными событиями и своими курсорами. Цена — записи сессии на экране
могут остаться чуть старее до следующего снимка (`agent_settled`,
переподключение). Каждый отказ пишется в журнал телефона:
`session=<id> snapshot=superseded|window-dirty`.

## Проверки

- RED → GREEN, `swift test --package-path Packages/NewChatCore --filter SessionSnapshotGateTests`
  (XCTest на macOS, сеть и симулятор не нужны): 3 теста —
  `testOlderResponseArrivedLaterIsDropped`, `testSnapshotWithEventsInWindowIsNotInstalled`,
  `testCleanNewestSnapshotInstallsOnce`. RED воспроизведён подменой тела
  `verdict` на прежнее поведение («всегда ставить»): 3 падения из 3. После
  правки 3/3 зелёные.
- `swiftc -parse Sources/Features/Sessions/Engine/SessionViewModel.swift` —
  без ошибок.
- Сторож дизайн-системы `python3 Tools/design-system-guard.py --diff HEAD` —
  чисто.
- Сборка Xcode **не запускалась**: на маке уже 17 часов идёт чужой
  `xcodebuild test-without-building` (UI-раннер `AgentDeviceRunner`), правило
  «одна сборка за раз». Значит, компиляция `SessionViewModel` в проекте этой
  работой не подтверждена — только разбор синтаксиса и типы `NewChatCore` в
  тестах.
- Симулятор, UI-тесты и установка на iPhone не запускались (правило
  25.10.2026).

## Что осталось и требует решения

- **Жёсткая гарантия требует серверной правки.** Нужно, чтобы
  `GET /api/sessions/:id` возвращал курсор, снятый в один момент с чтением
  ветки (например, `cursor: events.currentCursor()` рядом с
  `runtime.snapshot()`), а `message_end` заполнял `entryId`. Тогда клиент
  сможет ставить снимок и досылать ровно то, что после него, без «пустого
  окна» и без лишних запросов. Без этого правка остаётся клиентской и
  консервативной.
- Не тронуто: `refresh()` (несохраняющая установка после голосового
  разговора) и `select`/`open` идут мимо очереди — при их параллельном
  выполнении с `refreshSnapshot` порядок по-прежнему определяет только
  `sessionGeneration`. Это отдельная тема.
- На телефоне поведение не проверялось.
