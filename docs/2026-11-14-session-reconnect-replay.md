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

## Ревью `7c7b5da0`: событие, пришедшее во время ответа на сброс

Замечание владельца (14.11.2026): `recoverAfterReconnect` ждёт ответа HTTP,
а сокет за это время может принести новые события. Они ложатся в `state` и в
`liveTurn` через `receive`, а затем ветка `resetRequired` заменяет состояние
снимком и делает `liveTurn.reset()` — событие, пришедшее после того, как
сервер собрал снимок, пропадает из обоих мест (в ответе его уже нет).

### Что исправлено (только новые сессии, роли не тронуты)

1. `SessionViewModel.receive` — пока ответ на сброс в пути
   (`isReconnectFetchInFlight`), события открытой сессии складываются в
   `reconnectBuffer` (потолок 512 — как буфер ленты сервера). Очередь читается
   и очищается в `recoverAfterReconnect`.
2. `SessionReconnectReplay.events(_:sessionID:carried:)` — к окну ответа
   добавляются пришедшие во время запроса события по тому же правилу (та же
   эпоха, `seq` новее точки снимка), без повторов и с сортировкой по `seq`:
   порядок ленты, а не порядок источников.
3. `SessionReducer.apply(_:replay:to:)` — принимает готовое окно; курсор после
   сброса считается `SessionReconnectReplay.cursor(point:applied:previous:)`
   **после** проигрывания и не откатывается назад.
4. `eventsLost` и курсор. Точка снимка намеренно отстаёт от конца ленты
   (откат к началу окна стримящегося ответа), поэтому после сброса прежний
   курсор клиента новее неё. Если ставить курсор на точку, следующий догон
   снова просит вытесненный кусок, сервер опять отвечает сбросом — и каждый
   обрыв повторно стирает живой ход. Теперь курсор = максимум из точки
   снимка, проигранных событий и прежнего курсора той же эпохи. При
   `eventsLost` и той же эпохе живой ход **не стирается**: уже показанный
   текст сервер прислал сам, голову окна восстановить нечем, полный текст
   доедет на `message_end` (`liveTurnHasGaps = true` — по концу хода текст
   берётся из снимка). Другая эпоха — другой ход: он сбрасывается.

Гарантия ограничена контрактом сервера: при `eventsLost` середина окна не
восстанавливается ни клиентом, ни сервером, её не будет до `message_end`.

### Проверено для этой правки

```
cd Packages/NewChatCore && swift test --filter SessionReducerTests
```

- RED (дефект воспроизведён на новой редакции: в `events` отброшен `carried`,
  в `cursor` нет учёта прежнего курсора): 2 новых теста, 5 проверок падают;
- GREEN: `Executed 13 tests, with 0 failures`; новые —
  `testReconnectResetAppliesEventArrivedWhileResponseInFlight` (событие из
  очереди доезжает, повторы не двоятся, курсор на последнем проигранном) и
  `testReconnectResetEventsLostKeepsCursorBeforeReset` (курсор не
  откатывается; чужая эпоха курсор не тянет);
- `swiftc -parse` изменённого `SessionViewModel.swift` — чисто; сторож
  дизайн-системы `--diff HEAD` — чисто;
- сборка Xcode не запускалась: в этот момент шёл чужой `xcodebuild
  test-without-building` (UI-раннер на симуляторе), правило «одна сборка за
  раз»; симулятор, UI-тесты и установка не запускались.

## Ревью владельца `51bc45a4`: очередь при `eventsLost`, курсор за дыру

> Часть выводов первого круга отменена вторым кругом (ниже): «при
> `eventsLost` курсор остаётся на точке снимка» и «`reconnectFetchSessionID`».

Замечания владельца (14.11.2026):

1. `SessionReconnectReplay.events` под `guard !payload.eventsLost` возвращал
   `[]` и для `carried`, хотя очередь содержит сокетные события **после**
   начала HTTP-запроса: сервер их в ответ уже не положил, а в `entries`
   снимка их быть не может (они новее его точки).
2. `SessionReducer` после сброса сдвигал `lastCursor` на прежний курсор вперёд,
   не воспроизводя эти события: `agent_settled`/`message_end` из очереди
   терялись окончательно, а догон их пропускал, потому что курсор уже ушёл за
   них.
3. `reconnectBuffer` ограничен 512 и молча делал `removeFirst`: считать, что
   окно не длиннее серверного буфера, неверно при долгом запросе. Сдвигать
   курсор за потерянные данные без восстановления нельзя.
4. Плюс одновременные `recoverAfterReconnect` и смена сессии во время запроса.

### Что исправлено (только новые сессии, роли не тронуты)

- `SessionReconnectReplay.events`: запрет `eventsLost` снят — проигрываются
  все события новее точки снимка той же эпохи из ответа **и** из `carried`
  (дедуп по курсору, порядок по `seq`). `eventsLost` — факт о вытесненной
  голове окна, а не о том, что событие уже в снимке.
- `SessionReconnectReplay.cursor(..., complete:)`: при неполном окне
  (`eventsLost` или вытесненная очередь) курсор остаётся на точке снимка —
  за дыру он не идёт. При полном окне поведение прежнее (не откатывается).
- `SessionReconnectReplay.resumeCursor(lastCursor:recovering:)`: пока известна
  дыра, догон просит от неё, хотя живые события уже увели `lastCursor` вперёд;
  курсор другой эпохи к дыре не относится.
- `SessionReducer.apply(_:replay:replayComplete:to:)`: полнота окна передаётся
  явно и складывается с `eventsLost`; от неё зависит курсор.
- `SessionViewModel`:
  - `reconnectFetchSessionID` вместо булева флага: очередь принадлежит сессии
    своего догона, второй одновременный догон той же сессии пропускается
    (`recover skipped in-flight`), а чужой вызов не забирает очередь и не снимает
    флаг;
  - `reconnectBufferTruncated` вместо молчаливого `removeFirst`: упёрлись в
    512 — окно неполное, курсор не двигается, в журнал пишется `truncated=true`;
  - `recoveryCursor` — известная дыра; на сбросе ставится точка снимка, при
    успешном догоне снимается, при смене сессии очищается вместе с очередью;
  - `keepsLiveTurn` считается от неполноты окна (`!replayComplete`), поэтому
    вытеснение очереди не стирает уже показанный текст; полный текст по-прежнему
    доезжает на `message_end`;
  - при смене сессии (`installSnapshot`, другой `id`) очередь, флаг усечения,
    владелец очереди и дыра сбрасываются.

Гарантия та же и ограничена контрактом сервера: середину вытесненного окна
клиент не восстанавливает, он её честно помнит (`recoveryCursor`, журнал) и
просит заново на следующем догоне, а не перешагивает.

### Проверено

```
cd Packages/NewChatCore && swift test --filter SessionReducerTests
```

- RED на коде до правки: 3 теста, 8 проверок упали
  (`testReconnectResetEventsLostStillReplaysEventsNewerThanPoint`,
  `testReconnectResetEventsLostKeepsCarriedSocketEvents`,
  `testReconnectResetEventsLostDoesNotAdvanceCursorPastGap`);
- GREEN после правки: `Executed 15 tests, with 0 failures`; добавлен
  `testResumeCursorKeepsKnownGap`;
- `swiftc -parse Sources/Features/Sessions/Engine/SessionViewModel.swift` — чисто;
  сторож дизайн-системы `--diff HEAD` — чисто;
- сборка Xcode, симулятор, UI-тесты и установка не запускались (по поручению).

## Второй круг ревью (14.11.2026): двойной проигрыш, владение очередью, вечная дыра

Замечания владельца к разнице первого круга:

1. `keepsLiveTurn` сохранял текущий `liveTurn`, но потом применял **всё**
   окно, включая `carried`, которое `receive` уже применил: шаги и куски текста
   задваивались. Состояние при этом пересоздаётся снимком — ему нужно окно
   целиком.
2. Владение очередью по одному `sessionID`: при A→B→A поздний ответ старого
   запроса A считал очередь нового A своей и забирал её до проверки поколения
   сессии; его `catch` так же снимал чужой флаг.
3. `eventsLost` — сервер физически вытеснил данные. Постоянный
   `recoveryCursor` на вытесненной точке давал сброс на каждом переподключении:
   восстановление надо считать законченным (с финальным ответом), а не
   выдавать дыру восстановленной.

### Что исправлено (только новые сессии)

- `SessionReconnectReplay.liveEvents(_:sessionID:carried:keepingCurrent:)`:
  сохранённый ход получает только события ответа (`keepingCurrent: true` →
  `carried` не повторяется), пересозданный — окно целиком. Состояние всегда
  получает полное окно через `SessionReducer`.
- `SessionViewModel`: владение очередью — `ReconnectFetch(sessionID, token)`,
  `token` из монотонного `reconnectFetchSeq`; сравнение по `Equatable`
  (`reconnectFetch == fetch`), поэтому поздний ответ и его `catch` чужой флаг
  не снимают и чужую очередь не забирают.
- `recoveryCursor` ставится только на дыру, закрываемую повтором
  (`!carriedComplete && !payload.eventsLost`); `SessionReducer` больше не
  учитывает `eventsLost` в полноте окна — курсор идёт по последнему
  проигранному событию, к вытесненной точке не возвращается. В журнал пишется
  `recover gap-evicted not-recovered` — потерянное не выдаётся за
  восстановленное.
- Живой ход при `eventsLost` по-прежнему не стирается (`keepsLiveTurn`):
  показанный текст сервер прислал сам, полный текст доедет на `message_end`.

### Проверено

```
cd Packages/NewChatCore && swift test --filter SessionReducerTests
```

- RED на прежнем поведении: 4 теста, 4 проверки упали
  (`…EventsLostDoesNotReturnCursorToEvictedPoint`,
  `…EventsLostStillReplaysEventsNewerThanPoint`,
  `…EventsLostKeepsCarriedSocketEvents`,
  `…LiveEventsKeptTurnExcludesCarriedAlreadyApplied`);
- GREEN после правки: `Executed 17 tests, with 0 failures`; добавлены
  `testReconnectResetRecoverableWindowKeepsPointCursor` и
  `testLiveEventsKeptTurnExcludesCarriedAlreadyApplied`;
- `swiftc -parse` по `Sources` (цель iOS 17, arm64) — чисто;
  сторож дизайн-системы `--diff HEAD` — чисто;
- сборка Xcode, симулятор, UI-тесты, установка не запускались (по поручению).

## Что осталось

- Проверка на живом обрыве связи в приложении (симулятор/iPhone) — только по
  отдельному поручению владельца.
- `docs/реестр-сводка.md` не пересобирался: там несохранённые правки другого
  агента (234 записи), затирать их нельзя.
