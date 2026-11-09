# Voice conversation delegation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Голосовой помощник открывает ветку своей работы и зовёт чужую роль через `taskflow_call_role`, не зависая на звонке, и после паузы озвучивает решение.

**Architecture:** Живой Gemini/LiveKit не меняем. Новый инструмент `taskflow_chat_open_branch` сразу создаёт ветку, карточку и чатовый ход секретаря. Чужая роль — существующий `taskflow_call_role`. Пока звонок жив, выжимка не будит текстовый ход, а попадает в `BackgroundRunner`. Воркер опрашивает статус работы и говорит после `wait_for_idle`.

**Tech Stack:** Node/TypeScript TaskFlow server on .110, Python livekit-agents worker, существующие `chatCoordination` / `enqueueMessageDelivery` / `BackgroundRunner`. iOS в первом проходе не трогаем.

**Spec:** [`docs/superpowers/specs/2026-11-03-voice-conversation-delegation-design.md`](../specs/2026-11-03-voice-conversation-delegation-design.md)

## Global Constraints

- Канон iOS: `/Users/max/Проекты/TaskFlowNativeBuild`. Сервер: `~/Проекты/New-Todoist` на .110, только ветка и PR.
- Проверки — логика без симулятора; UI-тесты и установка на iPhone только по отдельному поручению.
- **Тесты только целевые файлы этой правки.** Не гонять полный `vitest`, не гонять весь Python worker suite. Прогон: `npx vitest run <этот файл> --maxWorkers=4` через `bash -lc`. Перед любым прогоном на .110 — `uptime`; нагрузка выше ~10 — не запускать.
- Не добавлять в `VOICE_TOOLS_GUIDE` и шаблоны слов «шуршит», «пробить» и прочих цитат владельца.
- Не менять Gemini Live, Pipecat, `taskflow_chat_send` как голосовой путь чужой роли.
- `QUICK_ANSWER_SECONDS = 3` не использовать как способ открыть ветку: инструмент обязан вернуть принятость сам.
- Коммитить только свои файлы; сервер — ветка → PR в `papirosa3214/New-Todoist`; iOS — только если задача 4 реально меняет Swift.

## Review Focus

- Звонок жив, субагент ответил: карточка обновляется, голос получит выжимку, **текстовый ход помощника не стартует** — тест в задаче 2.
- Звонок уже сброшен, субагент ответил: текстовый ход помощника будится как сейчас — тест в задаче 2.
- Обычное ответвление долгим нажатием по-прежнему пишет «Ветка … — готово» — тест в задаче 1.
- Повтор терминального статуса не кладёт второй доклад в очередь — тест в задаче 3.
- Пустой live-текст пробивки не подменяется заготовленной фразой — тест в задаче 1 (`spoken_text === ""`).

## File structure

Сервер (работа в git worktree `.110`, не в общей копии на грязном `main`):

- Create: `server/src/lib/voiceCallRegistry.ts` — память живых звонков `chatId → callId`.
- Create: `server/src/runtime/secretaryVoiceBranch.ts` — `openSecretaryVoiceBranch`, `readVoiceJob`.
- Create: `server/test/secretaryVoiceBranch.test.ts` — все серверные проверки этой работы (один файл).
- Modify: `server/src/runtime/roleToolCatalog.ts` — инструмент в каталог секретаря и в `CORE_OPERATIONS`.
- Modify: `server/src/lib/roleToolScope.ts` — право `secretary`.
- Modify: `server/src/lib/secretaryVoiceTools.ts` — `VOICE_TOOLS_GUIDE`.
- Modify: `server/src/runtime/secretaryVoiceBridge.ts` — регистрация звонка, `GET /secretary/voice-job`.
- Modify: `server/src/runtime/roleSubagentCall.ts` — не будить текстовый ход, если чат на звонке.
- Modify: `server/src/routes/chats.ts` — `mirrorBranchResult` пропускает голосовую ветку.
- Modify: `server/agents/secretary-voice/worker.py` — регистрация звонка, watch job → `BackgroundRunner`.
- Modify: `server/agents/secretary-voice/test_background.py` — один тест watch.

iOS не в списке, пока живая карточка не соврёт. Тогда точечно `RoleChatCoordination` / подпись, без нового экрана.

---

### Task 1: Ветка своей работы

**Files:**
- Create: `server/src/lib/voiceCallRegistry.ts`
- Create: `server/src/runtime/secretaryVoiceBranch.ts`
- Create: `server/test/secretaryVoiceBranch.test.ts`
- Modify: `server/src/runtime/roleToolCatalog.ts` (`CORE_OPERATIONS` + сборка операций секретаря)
- Modify: `server/src/lib/roleToolScope.ts` (`taskflow_chat_open_branch: ["secretary"]`)
- Modify: `server/src/routes/chats.ts` (`mirrorBranchResult`)

**Interfaces:**
- Consumes: `POST /chats/:id/branch` logic (те же участники, `branch_of_*`); `ensureSubagentCoordinationCard`; `enqueueMessageDelivery`; `chat_session_preferences` родителя.
- Produces:
  - `registerVoiceCall(chatId: string, callId: string): void`
  - `clearVoiceCall(chatId: string): void`
  - `activeVoiceCallId(chatId: string): string | null`
  - `openSecretaryVoiceBranch(input: { parentChatId: string; brief: string; ownerId: string; model?: string }): { accepted: true; branchId: string; questionId: string; title: string }`
  - `readVoiceJob(questionId: string): { terminal: boolean; status: string; spoken_text: string }`
  - Tool `taskflow_chat_open_branch` with `{ brief: string, model?: string }`, execute не ждёт хода.

- [ ] **Step 1: Write the failing tests** in `server/test/secretaryVoiceBranch.test.ts` (один describe, без живых моделей):

```ts
it("openSecretaryVoiceBranch возвращает accepted до конца хода и кладёт бриф в ветку", async () => {
  // stub enqueueMessageDelivery: запоминает вызов, промис хода не резолвит
  const result = openSecretaryVoiceBranch({ parentChatId, brief: "Собери план на четверг", ownerId });
  expect(result.accepted).toBe(true);
  expect(result.branchId).toBeTruthy();
  const copied = /* первое сообщение ветки */;
  expect(copied.text).toContain("Собери план на четверг");
  expect(enqueueCalled).toBe(true);
});

it("в родителе карточка с child_chat_id, без дайджеста Ветка — готово", () => {
  openSecretaryVoiceBranch({ parentChatId, brief: "Собери план на четверг", ownerId });
  const card = /* system message с steps.coordination в parentChatId */;
  expect(card.coordination.child_chat_id).toBe(result.branchId);
  expect(card.coordination.recipient_id).toBe("u-secretary");
  expect(/* messages in parent whose text starts with "Ветка" и содержит "готово" */).toHaveLength(0);
});

it("обычная ветка POST /chats/:id/branch по-прежнему зеркалит итог", () => {
  // существующий HTTP branch без openSecretaryVoiceBranch
  // после ответа роли в ветке: в родителе есть текст «Ветка … — готово»
});

it("readVoiceJob отдаёт пустой spoken_text пока live пуст, без подставной фразы", () => {
  const job = readVoiceJob(questionId);
  expect(job.terminal).toBe(false);
  expect(job.spoken_text).toBe("");
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash -lc 'cd ~/Проекты/New-Todoist/server && npx vitest run test/secretaryVoiceBranch.test.ts --maxWorkers=4'`
Expected: FAIL — `openSecretaryVoiceBranch` is not defined.

- [ ] **Step 3: Implement**

`voiceCallRegistry.ts`: модульный Map, без БД (убийство процесса — вне спецификации).

`openSecretaryVoiceBranch`: сохранить бриф сообщением владельца в родителе → тот же insert, что `POST /:id/branch` → `ensureSubagentCoordinationCard({ chatId: parent, requesterId: secretary, recipientId: secretary, question: brief, roomChatId: branchId, originMessageId })` → скопировать `chat_session_preferences` родителя в ветку (если `model` задан — только снимок этого хода, таблицу родителя не UPDATE) → `enqueueMessageDelivery` на копию брифа в ветке, **не** `await startChatRun`. Пометить ветку так, чтобы `mirrorBranchResult` её пропускал: `chats` с `branch_of_chat_id` и карточкой `recipient_id = u-secretary` + `child_chat_id = эта ветка`. Миграцию не плодить.

Tool: как `createRoleSubagentCallTool`, имя `"taskflow_chat_open_branch"`, description без предписанных фраз: открыть ветку текущего чата с брифом и запустить там этого же помощника, сразу вернуть accepted. В ядро каталога и scope секретаря.

`readVoiceJob`: прочитать coordination по `question_id`; `spoken_text` = live/answer как есть, `""` если пусто.

- [ ] **Step 4: Run the same vitest command**

Expected: PASS, только этот файл.

- [ ] **Step 5: Commit** on the server branch

```bash
git commit -m "$(cat <<'EOF'
feat(voice): open secretary work as a chat branch

EOF
)"
```

---

### Task 2: Выжимка `taskflow_call_role` во время звонка

**Files:**
- Modify: `server/src/runtime/roleSubagentCall.ts` (доставка выжимки ~строка 431 `enqueueMessageDelivery` / `recoverAgentDelivery`)
- Modify: `server/src/runtime/secretaryVoiceBridge.ts` (регистрация звонка)
- Modify: `server/test/secretaryVoiceBranch.test.ts` (два теста в тот же файл)

**Interfaces:**
- Consumes: `registerVoiceCall` / `activeVoiceCallId` из задачи 1; существующий `taskflow_call_role` (фон, карточка, лимиты).
- Produces: если `activeVoiceCallId(chatId)` не null — карточка обновляется как сейчас, `recoverAgentDelivery` **не** вызывается. Иначе поведение 1-в-1 как сейчас. Immediate return `taskflow_call_role` дополнить `question_id` (если его ещё нет), чтобы воркер мог watch.

- [ ] **Step 1: Write the failing tests** in the same `secretaryVoiceBranch.test.ts`:

```ts
it("живой звонок: выжимка call_role не будит текстовый ход", async () => {
  registerVoiceCall(parentChatId, "call-1");
  // завершить субагентский ход тем же путём, что roleSubagentCall.test.ts
  expect(recoverAgentDeliveryCalled).toBe(false);
  expect(card.coordination.terminal).toBe(true);
});

it("звонка нет: выжимка по-прежнему будит текстовый ход", async () => {
  clearVoiceCall(parentChatId);
  // тот же финиш субагента
  expect(recoverAgentDeliveryCalled).toBe(true);
});
```

Не копировать весь `roleSubagentCall.test.ts`. Поднять только финиш выжимки (мок runner), как в существующем файле.

- [ ] **Step 2: Run** `npx vitest run test/secretaryVoiceBranch.test.ts --maxWorkers=4`

Expected: FAIL on `recoverAgentDeliveryCalled`.

- [ ] **Step 3: Implement**

В `secretaryVoiceBridge.ts`: POST `/secretary/tool` с `call_id` зовёт `registerVoiceCall(chatId, callId)`; `/secretary/tools-close` зовёт `clearVoiceCall`. GET `/secretary/voice-job?question_id=` → `readVoiceJob`.

В доставке выжимки `roleSubagentCall.ts`: `if (activeVoiceCallId(chatId)) { /* карточку обновить, recoverAgentDelivery не звать */ } else { /* как сейчас */ }`.

- [ ] **Step 4: Same vitest file PASS**

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
fix(voice): do not wake secretary text turn during a live call

EOF
)"
```

---

### Task 3: Воркер смотрит работу и инструкция звонка

**Files:**
- Modify: `server/agents/secretary-voice/worker.py`
- Modify: `server/agents/secretary-voice/test_background.py`
- Modify: `server/src/lib/secretaryVoiceTools.ts` (`VOICE_TOOLS_GUIDE`)

**Interfaces:**
- Consumes: `GET /secretary/voice-job`, `BackgroundRunner.pending` / `_deliver`; tool results with `question_id` from tasks 1–2.
- Produces: `BackgroundRunner.watch_job(self, label: str, question_id: str) -> None` — не блокирует tool return; по `terminal` кладёт `(label, spoken_text)` в `pending` один раз. Повтор `terminal` не дублирует. Пустой `spoken_text` тоже кладёт как есть.

- [ ] **Step 1: Write the failing test** in `test_background.py` (не новый файл, не весь worker suite):

```python
@pytest.mark.asyncio
async def test_watch_job_enqueues_once_when_terminal():
    runner = BackgroundRunner()
    runner.session = FakeIdleSession()
    reads = iter([
        {"terminal": False, "status": "queued", "spoken_text": ""},
        {"terminal": True, "status": "answered", "spoken_text": "План: встреча в 12."},
        {"terminal": True, "status": "answered", "spoken_text": "План: встреча в 12."},
    ])
    runner.fetch_job = lambda _id: next(reads)
    runner.watch_job("ветка", "q1")
    await asyncio.sleep(0)  # дать watch-циклу дойти до terminal
    assert runner.pending == [("ветка", "План: встреча в 12.")]
```

Подменить poll так, чтобы не ходить в сеть. Не звать `test_worker.py`.

- [ ] **Step 2: Run** `python3 -m pytest test_background.py::test_watch_job_enqueues_once_when_terminal -q` in `server/agents/secretary-voice`

Expected: FAIL — `watch_job` is not defined.

- [ ] **Step 3: Implement**

После `shared_tools_via_api` invoke: если JSON результата содержит `question_id`, `runner.watch_job(spec["name"], question_id)` и вернуть короткий accepted-текст модели (существующий `BACKGROUND_ACK` годится для медленных HTTP; для ветки/call_role accepted приходит из tool result — не ждать 3 с).

Старт сессии: POST tool-контекст уже шлёт `call_id`; убедиться, что он стабилен на время звонка.

`VOICE_TOOLS_GUIDE` дописать смыслом спецификации (своя работа → ветка с брифом; чужая → `taskflow_call_role`; не объявлять успех до accepted; ход читать живым текстом; итог по существу). Характер не трогать.

- [ ] **Step 4: Same pytest line PASS.** Плюс повтор `npx vitest run test/secretaryVoiceBranch.test.ts --maxWorkers=4` — регрессия задач 1–2.

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(voice): speak delegated results after a pause

EOF
)"
```

- [ ] **Step 6: Server PR** from the worktree branch to `papirosa3214/New-Todoist`. Не перезапускать `taskflow-secretary-voice.service`, пока есть живые комнаты.

---

### Task 4: iOS только если карточка врёт

**Files:** none until proven. Candidates: `Sources/Core/Models/RoleChat.swift` (`RoleChatCoordination`), `Sources/Features/Roles/RoleChatsScreen.swift` / `SubagentRail.swift` — только подпись получателя «помощник», без нового экрана.

**Interfaces:**
- Consumes: серверная карточка задачи 1 (`recipient_id = u-secretary`, `child_chat_id` = ветка).
- Produces: ничего, если текущий клиент уже рисует карточку и рельс.

- [ ] **Step 1:** На живом JSON карточки (после задачи 1) проверить декод `RoleChatCoordination`. Если поля на месте и рельс строится — **остановиться, iOS-диффа нет**.

- [ ] **Step 2:** Если `recipient_name` врёт чужую роль — правка подписи, без нового UI. Тест: один хостовый `Tools/test_*.py` на разбор, без симулятора.

- [ ] **Step 3:** Если был дифф — ветка и PR iOS. Иначе шаг пустой.

---

## Self-review

- Своя ветка + бриф + карточка без дайджеста → Task 1.
- `taskflow_call_role`, без лички, без текстового хода на живом звонке → Task 2.
- Пауза / очередь докладов / один раз / пустой live-текст → Task 3 + Review Focus.
- Инструкция звонка → Task 3.
- iOS нулевой по умолчанию → Task 4.
- Полный vitest, Python worker suite, XCUITest, симулятор в план не входят.
