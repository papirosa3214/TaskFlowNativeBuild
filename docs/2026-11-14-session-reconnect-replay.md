# Восстановление новой сессии после переподключения: снимок + окно событий

Дата: 14.11.2026. Запись реестра: `LOCK-SESSION-RECONNECT-REPLAY-20261114`.
Поручение владельца (14.11.2026): починить только поток новых сессий
(`Sources/Features/Sessions/`), комнату роли не трогать.

## Что было

Сервер `c90c2c18` (`New-Todoist`, «точка снимка не обгоняет запись — стримящийся
ход восстановим») изменил ответ на сброс в `GET /api/sessions/:id/events`:

- при `resetRequired` приходит **снимок** с точкой ленты
  (`eventCursor` = `<epoch>:<seq>`, плюс `eventCursorEpoch`, `eventCursorSeq`);
- `events` — только события окна новее точки снимка (незавершённый ход);
- если окно вытеснено из буфера — `eventsLost: true`, `events: []` и снимок;
- точка снимка откатывается к началу открытого стримящегося окна, поэтому
  голова незавершённого ответа остаётся доигрываемой.

Контракт сервера: `docs/current/owner-session-snapshot-events.md` — снимок
основа, применяются только события с `seq > eventCursorSeq` той же эпохи;
другая эпоха → перечитать снимок; `eventsLost` → рисовать только снимок,
незавершённый ответ придёт целиком на `message_end`.

Клиент на сбросе делал `SessionReducer.apply(payload)`: заменял состояние
снимком и лишь отмечал курсоры событий. В `liveTurn` окно не проигрывалось,
а `liveTurnHasGaps` только откладывал проблему. Итог: после обрыва связи
незавершённый ответ не показывался. На старом сервере (снимок без точки)
проигрывать события нельзя: в ответ попадали и уже вошедшие в записи.

## Что сделано

1. `Packages/NewChatCore/Sources/NewChatCore/SessionModels.swift` — снимок
   получил `eventCursor`, `eventCursorEpoch`, `eventCursorSeq` (все
   необязательные, разбор из JSON), ответ восстановления — `eventsLost`
   (по умолчанию `false`). Старые ответы без этих полей декодируются как
   раньше.
2. `Packages/NewChatCore/Sources/NewChatCore/SessionReconnectReplay.swift` (новый) —
   `SessionEventPoint` (`<epoch>:<seq>`, сравнение только внутри одной эпохи),
   `SessionSnapshot.eventPoint`, `SessionEventEnvelope.eventPoint` и
   `SessionReconnectReplay.events(_:sessionID:)`: при `resetRequired`, без
   `eventsLost` и с точкой снимка — только события той же эпохи с `seq >
   точки`, без повторов курсоров.
3. `Packages/NewChatCore/Sources/NewChatCore/SessionReducer.swift` — на сбросе
   состояние целиком из снимка, `lastCursor` = точка снимка, затем окно
   проигрывается обычным `apply(event)`. Снимок без точки (старый сервер) —
   прежнее поведение: только отметки курсоров, без проигрывания.
4. `Sources/Features/Sessions/Engine/SessionViewModel.swift` —
   `recoverAfterReconnect`: состояние из снимка, `liveTurn` сбрасывается и
   связывается с сессией, затем окно применяется к `liveTurn` в порядке ленты
   (с `updateLiveTurnStopState`). `eventsLost` — честно: только снимок, без
   выдуманных данных; голова ответа доедет на `message_end`. Метка окна
   снимка (`sessionWindow.noteReset()`) сдвигается до применения, чтобы
   параллельный `refreshSnapshot` не лёг поверх снимком постарше.

Поток ролей (`Sources/Features/Roles/`), общий интерфейс и их компоненты не
менялись.

## Проверено

Целевые тесты пакета (macOS, без симулятора):

```
cd Packages/NewChatCore && swift test --filter SessionReducerTests
```

- RED: на исходном коде (`git show HEAD:` версии `SessionModels.swift`,
  `SessionReducer.swift`, без `SessionReconnectReplay.swift`) новые тесты не
  компилируются — API контракта отсутствует;
- GREEN: `Executed 11 tests, with 0 failures` — включая три новых:
  `testReconnectResetReplaysOnlyEventsAfterSnapshotPoint`,
  `testReconnectResetEventsLostKeepsSnapshotAndItsPointOnly`,
  `testReconnectResetSkipsEventsFromAnotherEpoch`, и прежние
  `testReconnectResetConvergesFromSnapshotThenEvents`,
  `testReconnectResetDoesNotReplayMessageAlreadyContainedInSnapshot`
  (совместимость старого ответа).

## Что осталось

- Проверка на живом обрыве связи в приложении (симулятор/iPhone) — только по
  отдельному поручению владельца.
- `docs/реестр-сводка.md` не пересобирался: там несохранённые правки другого
  агента (234 записи), затирать их нельзя.
