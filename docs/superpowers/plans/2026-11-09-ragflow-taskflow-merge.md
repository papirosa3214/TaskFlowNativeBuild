# Слияние RAGFlow и TaskFlow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Раздел «База знаний» в iOS становится единственной дверью к RAGFlow: датасеты с разделами и доступами ролям, документы с загрузкой и разбором, окно «Спросить базу», заметки индексируются сразу при сохранении.

**Architecture:** Ключ RAGFlow остаётся на сервере TaskFlow; iOS говорит только с `/api/knowledge/*`. Реестр в SQLite держит то, чего в RAGFlow нет (включён/исключён, раздел, доступ ролям), RAGFlow остаётся источником правды о существовании и размерах датасетов. Индексация заметок — очередь-задания в процессе сервера поверх существующего `knowledgeSync.ts`; суточный прогон остаётся страховкой.

**Tech Stack:** Node 22 + Fastify 5 + better-sqlite3 + vitest (`app.inject()`, одноразовая база из `server/test/setup.ts`); iOS — SwiftUI, `Sources/Core/Networking/APIClient+*.swift`.

**Spec:** `docs/2026-11-09-baza-znaniy-ragflow-design.md` (разделы 9 и 14 — обязательны к прочтению вместе с планом).

## Global Constraints

- Сервер: репозиторий на `.110`, `~/Проекты/New-Todoist`. Доставка — прямой коммит в `main` и push, без PR и CI.
- iOS: `/Users/max/Проекты/TaskFlowNativeBuild`, прямой push `main`, зеркало `github main`.
- Тесты только точечные, явными файлами, `npx vitest run <файл> --maxWorkers=4`; полный прогон запрещён (кладёт `.110`).
- Правка логики — RED → GREEN: тест падает до правки и проходит после. Декоративные правки SwiftUI тестами не обвешиваем.
- Симулятор, UI-тесты и установка на iPhone — только по отдельному прямому поручению владельца.
- Миграции только добавляются в конец `server/src/migrations.ts`, существующие не правятся.
- `taskflow_kb_search` (FTS по `user_notes`) не меняет поведения: роли получают RAGFlow отдельным инструментом.
- Тексты и комментарии в коде — русские, в стиле файлов, куда они ложатся.
- Лимит файла загрузки — 15 МБ; типы `.md/.txt/.pdf/.docx/.html`; способ разбора наследуется от датасета.

## Review Focus

- Заметка, только что сохранённая, не должна пропадать из выдачи на время переразбора → тест порядка «залить новую копию, потом удалить старую» (Task 4).
- Перенос заметки в другой проект/удаление не должны оставлять `taskflow-<id>.md` в старом датасете → тест `dataset_id` из прошлой заливки (Task 4).
- Незалогиненный/не-владелец не должен управлять датасетами и доступами → 403 в Task 2.
- Исключённый датасет не должен попадать ни в чипсы, ни в поиск, ни в вопрос → тест выборки (Task 3).
- Роль без выдачи не должна видеть чужие датасеты через `taskflow_rag_search` → тест (Task 7).

---

### Task 1: Реестр датасетов и разделы (сервер)

**Files:**
- Create: `server/src/lib/knowledgeRegistry.ts`
- Modify: `server/src/migrations.ts` (новая миграция в конце, id `222_knowledge_registry`)
- Test: `server/test/knowledgeRegistry.test.ts`

**Interfaces:**
- Produces:
  - `MEMORY_DATASET_ID = "aad90ec0901f11f1be69a9ef96f0a9d6"`
  - `ensureDatasetRows(ids: string[]): void`
  - `enabledDatasetIds(): string[]`
  - `listSections(): Array<{ id: number; title: string; position: number; dataset_count: number }>`
  - `createSection(title: string): { id: number; title: string; position: number }`
  - `updateSection(id: number, patch: { title?: string; position?: number }): boolean`
  - `deleteSection(id: number): boolean`
  - `patchDataset(datasetId: string, patch: { enabled?: boolean; section_id?: number | null; title?: string | null }): void`
  - `datasetRegistryRow(datasetId: string): { dataset_id: string; enabled: 0 | 1; section_id: number | null; title: string | null } | undefined`
  - `setDatasetRoles(datasetId: string, roleKeys: string[]): void`
  - `datasetRoles(datasetId: string): Array<{ key: string; title: string }>`
  - `roleDatasetIds(roleKey: string): string[]` — включённые и выданные роли

- [ ] **Step 1: Тест — «Память — заметки» исключена, новые датасеты включены**

```ts
it("исключает память и включает остальные при первом чтении", () => {
  ensureDatasetRows([MEMORY_DATASET_ID, "ds-project"]);
  expect(datasetRegistryRow(MEMORY_DATASET_ID)?.enabled).toBe(0);
  expect(datasetRegistryRow("ds-project")?.enabled).toBe(1);
  expect(enabledDatasetIds()).toEqual(["ds-project"]);
});
```

- [ ] **Step 2: Прогнать — падает**

Run: `cd ~/Проекты/New-Todoist/server && npx vitest run test/knowledgeRegistry.test.ts --maxWorkers=4`
Expected: FAIL — `Cannot find module '../src/lib/knowledgeRegistry.js'`

- [ ] **Step 3: Миграция + модуль**

Миграция `222_knowledge_registry`: три таблицы из спека §14.1 (`knowledge_dataset_sections`, `knowledge_datasets`, `knowledge_dataset_roles`), затем `INSERT` строки памяти с `enabled = 0`. В `knowledgeRegistry.ts` `ensureDatasetRows` делает `INSERT OR IGNORE` для каждого id, `enabled` по умолчанию 1 (строка памяти уже вставлена отдельно). `deleteSection` обнуляет `section_id` у своих датасетов. `setDatasetRoles` — транзакция: delete + insert, ключи сверяются с `roles(key)`.

- [ ] **Step 4: Добавить остальные тесты (разделы, роли, включение/исключение)**

Названия: `создаёт раздел в конец и переставляет`, `удаление раздела оставляет датасеты без раздела`, `выдача ролей заменяется целым набором`, `roleDatasetIds пересекает выданное с включённым`.

- [ ] **Step 5: Прогнать — зелено**

Run: `npx vitest run test/knowledgeRegistry.test.ts --maxWorkers=4`
Expected: PASS, 5 tests

- [ ] **Step 6: Коммит**

```bash
git add server/src/lib/knowledgeRegistry.ts server/src/migrations.ts server/test/knowledgeRegistry.test.ts
git commit -m "feat(knowledge): реестр датасетов, разделы и доступы ролям"
```

---

### Task 2: Ручки управления датасетами и разделами (сервер)

**Files:**
- Modify: `server/src/routes/knowledge.ts` (новые ручки рядом с существующими)
- Test: `server/test/knowledgeAdmin.test.ts`

**Interfaces:**
- Consumes: `knowledgeRegistry` из Task 1, `isOwner` из `server/src/access.ts`
- Produces: ручки спека §14.2. `GET /api/knowledge/datasets` получает поля `enabled`, `section`, `roles` и параметр `?include_disabled=1`.

- [ ] **Step 1: Тест — исключённые не отдаются, `include_disabled=1` возвращает**

```ts
it("не отдаёт исключённый датасет без флага", async () => {
  const res = await app.inject({ method: "GET", url: "/api/knowledge/datasets", headers: auth() });
  const ids = res.json().datasets.map((d: any) => d.id);
  expect(ids).not.toContain(MEMORY_DATASET_ID);
  const all = await app.inject({ method: "GET", url: "/api/knowledge/datasets?include_disabled=1", headers: auth() });
  expect(all.json().datasets.map((d: any) => d.id)).toContain(MEMORY_DATASET_ID);
});
```

RAGFlow в тестах не поднят: `GET /api/knowledge/datasets` на недоступный RAGFlow отвечает своей ошибкой. Поэтому список датасетов в тесте подменяется — модуль запросов к RAGFlow вынести в `server/src/lib/ragflowClient.ts` функцией `listDatasets(): Promise<RagflowDataset[]>`, и тест мокает её (`vi.mock("../src/lib/ragflowClient.js")`).

- [ ] **Step 2: Прогнать — падает**

Run: `npx vitest run test/knowledgeAdmin.test.ts --maxWorkers=4`
Expected: FAIL — нет `?include_disabled`, нет `enabled` в ответе

- [ ] **Step 3: Реализация**

Вынести текущие вызовы RAGFlow из `knowledge.ts` в `ragflowClient.ts` (`listDatasets`, `listDocuments`, `uploadDocument`, `deleteDocuments`, `documentStatus`, `retrieval`, `documentText`) без изменения поведения — существующие ручки обязаны отвечать как раньше. Затем добавить ручки §14.2 с `isOwner` и `ensureDatasetRows` перед сборкой ответа.

- [ ] **Step 4: Тест — управление только владельцу**

`it("не-владелец получает 403 на PATCH датасета и на разделы")` — пользователь без `role = 'owner'`: `PATCH /api/knowledge/datasets/x` → 403, `POST /api/knowledge/sections` → 403.

- [ ] **Step 5: Прогнать — зелено**

Run: `npx vitest run test/knowledgeAdmin.test.ts --maxWorkers=4`
Expected: PASS

- [ ] **Step 6: Коммит**

```bash
git commit -am "feat(knowledge): ручки реестра датасетов, разделов и доступов"
```

---

### Task 3: Область поиска — только включённые, роли — только выданные

**Files:**
- Modify: `server/src/routes/knowledge.ts` (`GET /api/knowledge/search`, `allDatasetIds`)
- Test: `server/test/knowledgeScope.test.ts`

**Interfaces:**
- Consumes: `enabledDatasetIds`, `roleDatasetIds` (Task 1)
- Produces: `resolveScopeDatasetIds(requested: string[], roleKey: string | null): string[]` в `server/src/lib/knowledgeScope.ts` — пересечение запрошенных с разрешёнными, пустой результат → 403 с текстом «датасет не включён в TaskFlow».

- [ ] **Step 1: Тест выборки**

```ts
it("не пускает исключённый датасет в поиск", () => {
  ensureDatasetRows(["ds-on", "ds-off"]);
  patchDataset("ds-off", { enabled: false });
  expect(resolveScopeDatasetIds(["ds-on", "ds-off"], null)).toEqual(["ds-on"]);
  expect(() => resolveScopeDatasetIds(["ds-off"], null)).toThrow(/не включён/);
});
it("роль видит только выданное", () => {
  setDatasetRoles("ds-on", ["researcher"]);
  expect(resolveScopeDatasetIds(["ds-on"], "builder")).toEqual([]);
  expect(resolveScopeDatasetIds(["ds-on"], "researcher")).toEqual(["ds-on"]);
});
```

- [ ] **Step 2: Прогнать — падает** (нет модуля)
- [ ] **Step 3: Реализация** — модуль + подключение в существующем поиске, где `dataset_id` теперь обязателен (400 без него; список `allDatasetIds()` остаётся для обратной совместимости одного датасета).
- [ ] **Step 4: Прогнать — зелено**

Run: `npx vitest run test/knowledgeScope.test.ts --maxWorkers=4`

- [ ] **Step 5: Коммит** `git commit -am "feat(knowledge): поиск только по включённым датасетам, роль — по выданным"`

---

### Task 4: Очередь индексации заметок (сервер)

**Files:**
- Create: `server/src/lib/knowledgeIndexQueue.ts`
- Modify: `server/src/migrations.ts` (миграция `223_knowledge_index_jobs`), `server/src/routes/notes.ts` (`POST /api/notes`, `PATCH /api/notes/:id`, `DELETE /api/notes/:id`), `server/src/index.ts` (запуск воркера)
- Test: `server/test/knowledgeIndexQueue.test.ts`

**Interfaces:**
- Consumes: `noteDocument`, `contentSha`, `uploadDocs`, `deleteDocs`, `rememberUploaded` из `server/src/lib/knowledgeSync.ts`
- Produces:
  - `enqueueNoteIndex(noteId: string, action?: "upsert" | "delete"): void`
  - `noteIndexState(noteId: string): "queued" | "running" | "done" | "error" | null`
  - `noteIndexStates(ids: string[]): Map<string, "queued" | "running" | "done" | "error">`
  - `runIndexQueueOnce(): Promise<void>` — один тик
  - `startIndexQueue()` / `stopIndexQueue()`

- [ ] **Step 1: Тест — дебаунс и хэш-скип**

```ts
it("не заливает повторно неизменённую заметку", async () => {
  enqueueNoteIndex("note-1");
  db.prepare("UPDATE knowledge_index_jobs SET queued_at = datetime('now','-20 seconds') WHERE note_id = ?").run("note-1");
  await runIndexQueueOnce();  // первая заливка — uploadDocs вызван один раз
  expect(uploads.length).toBe(1);
  enqueueNoteIndex("note-1");
  db.prepare("UPDATE knowledge_index_jobs SET queued_at = datetime('now','-20 seconds') WHERE note_id = ?").run("note-1");
  await runIndexQueueOnce();  // содержимое то же — второй заливки нет
  expect(uploads.length).toBe(1);
});
```

- [ ] **Step 2: Прогнать — падает**
- [ ] **Step 3: Миграция и модуль**

Таблица `knowledge_index_jobs`: `note_id PK`, `action` (`upsert`/`delete`), `dataset_id`, `content_hash`, `queued_at`, `attempts`, `status`, `error`, `ragflow_doc_id`. `runIndexQueueOnce` берёт одно задание с `queued_at <= datetime('now','-10 seconds')` и `status IN ('queued','running')` где `attempts < 3`, выставляет `running`, дальше: `delete` → `deleteDocs` из своего датасета; `upsert` → собрать `noteDocument`, сравнить хэш с `content_hash` (совпал — `done` без обращений к RAGFlow), иначе залить новую копию, запомнить её id, удалить прежний `ragflow_doc_id`, запустить разбор, записать `content_hash`, `done`. Прежний `dataset_id` брать из `rememberUploaded()`/состояния синка; если он отличается — удалять копию и там.
- [ ] **Step 4: Хуки в `notes.ts`** — `POST`/`PATCH` ставят `enqueueNoteIndex(id)`, `DELETE` — `enqueueNoteIndex(id, "delete")`. Тест: `PATCH /api/notes/:id` создаёт строку `queued`.
- [ ] **Step 5: Прогнать — зелено**

Run: `npx vitest run test/knowledgeIndexQueue.test.ts --maxWorkers=4`

- [ ] **Step 6: Коммит** `git commit -am "feat(knowledge): очередь индексации заметок при сохранении"`

---

### Task 5: Состояние индексации в списке заметок

**Files:**
- Modify: `server/src/routes/notes.ts` (`GET /api/notes`)
- Test: `server/test/knowledgeIndexQueue.test.ts` (тот же файл, новый блок)

**Interfaces:**
- Consumes: `noteIndexStates` (Task 4)
- Produces: поле `index_state` в каждом элементе `notes` (отсутствует, если строки задания нет).

- [ ] **Step 1: Тест**

```ts
it("отдаёт index_state только там, где есть задание", async () => {
  const res = await app.inject({ method: "GET", url: "/api/notes", headers: auth() });
  const withJob = res.json().notes.find((n: any) => n.id === "note-with-job");
  const without = res.json().notes.find((n: any) => n.id === "note-old");
  expect(withJob.index_state).toBe("queued");
  expect("index_state" in without).toBe(false);
});
```

- [ ] **Step 2: Прогнать — падает**, Step 3 реализовать, Step 4 прогнать — зелено (`--maxWorkers=4`), Step 5 коммит `feat(knowledge): состояние индексации в списке заметок`.

---

### Task 6: Документы датасета — загрузка, статус, удаление, переразбор

**Files:**
- Create: `server/src/lib/knowledgeDocs.ts`
- Modify: `server/src/migrations.ts` (миграция `224_knowledge_uploads`), `server/src/routes/knowledge.ts`
- Test: `server/test/knowledgeDocs.test.ts`

**Interfaces:**
- Consumes: `ragflowClient` из Task 2, `datasetRegistryRow` из Task 1
- Produces:
  - `ALLOWED_UPLOAD_EXT = [".md", ".txt", ".pdf", ".docx", ".html"]`
  - `assertUploadable(datasetId: string, name: string, size: number): void` — бросает `UploadRejected` с готовым текстом (не свой датасет / не включён / тип / размер)
  - `isOwnedDocument(datasetId: string, name: string): boolean` — `taskflow-*.md` либо строка в `knowledge_uploads`
  - ручки `POST /api/knowledge/datasets/:id/documents` (сырые байты, `?name=`), `GET /api/knowledge/documents/:ragflowId/status`, `DELETE /api/knowledge/documents/:ragflowId`, `POST /api/knowledge/datasets/:id/reparse`

- [ ] **Step 1: Тест правил загрузки**

```ts
it("отказывает в чужом датасете и в чужом типе", () => {
  expect(() => assertUploadable("ds-foreign", "a.pdf", 1000)).toThrow(/только в свои датасеты/);
  expect(() => assertUploadable("ds-on", "a.exe", 1000)).toThrow(/\.md/);
  expect(() => assertUploadable("ds-on", "a.pdf", 16 * 1024 * 1024)).toThrow(/15 МБ/);
  expect(() => assertUploadable("ds-on", "a.pdf", 1000)).not.toThrow();
});
```

- [ ] **Step 2: Прогнать — падает**
- [ ] **Step 3: Реализация** — таблица `knowledge_uploads` (`ragflow_doc_id PK`, `dataset_id`, `name`, `uploaded_by`, `uploaded_at`); загрузка пишет строку после успешного ответа RAGFlow и сразу зовёт разбор; `DELETE` проверяет `isOwnedDocument`, чужое — 403 с текстом.
- [ ] **Step 4: Тест удаления чужого** — `DELETE /api/knowledge/documents/foreign-id` → 403.
- [ ] **Step 5: Прогнать — зелено**, Step 6 коммит `feat(knowledge): загрузка документов в свои датасеты с разбором`.

---

### Task 7: Окно «Спросить базу» (сервер)

**Files:**
- Create: `server/src/lib/knowledgeAsk.ts`
- Modify: `server/src/routes/knowledge.ts`
- Test: `server/test/knowledgeAsk.test.ts`

**Interfaces:**
- Consumes: `resolveScopeDatasetIds` (Task 3), `callUnifiedAi` из `server/src/lib/aiClient.ts`, `ragflowClient.retrieval`
- Produces:
  - `buildAskPrompt(question: string, chunks: AskChunk[]): Array<{ role: "system" | "user"; content: string }>` — лимит 8 кусков и 12 000 символов
  - `POST /api/knowledge/ask` → `{ answer: string | null, model: string | null, chunks: Array<{text, document_name, title, project, doc_id, dataset_id, dataset_name, score}> }`

- [ ] **Step 1: Тест промпта**

```ts
it("режет куски по лимиту и нумерует их", () => {
  const msgs = buildAskPrompt("что нового?", Array.from({ length: 12 }, (_, i) => chunk("т" + i)));
  const user = msgs[msgs.length - 1].content;
  expect(user).toContain("[1]");
  expect(user).toContain("[8]");
  expect(user).not.toContain("[9]");
  expect(user.length).toBeLessThanOrEqual(12_000 + 2_000);
});
it("без модели отдаёт куски с answer: null", async () => { /* aiClient бросает — ответ 200, answer: null */ });
```

- [ ] **Step 2: Прогнать — падает**
- [ ] **Step 3: Реализация** — retrieval по разрешённым датасетам (одна модель векторов → один вызов), сборка промпта, `callUnifiedAi`, при ошибке модели — `answer: null` и `model: null`, статус 200.
- [ ] **Step 4: Прогнать — зелено**, Step 5 коммит `feat(knowledge): вопрос к базе с ответом модели и источниками`.

---

### Task 8: Роли — `taskflow_rag_search` по выданным датасетам

**Files:**
- Modify: `server/src/runtime/inProcessRun.ts` (рядом с `taskflow_kb_search`), `server/src/runtime/roleToolCatalog.ts:376`
- Test: `server/test/roleProjectKnowledge.test.ts` (дополнить) или новый `server/test/roleRagSearch.test.ts`

**Interfaces:**
- Consumes: `roleDatasetIds` (Task 1), `ragflowClient.retrieval`
- Produces: инструмент `taskflow_rag_search(query, top_k?)` → `{ запрос, куски: [{ документ, датасет, текст, score }] }`; без выдачи — `{ запрос, куски: [], примечание: "доступ ни к одному датасету не выдан" }`. В каталоге — операция `rag_search` в группе `taskflow_knowledge`.

- [ ] **Step 1: Тест** — роль `builder` без выдачи получает пустой список и не делает вызов retrieval (мок считает обращения: 0).
- [ ] **Step 2: Прогнать — падает**
- [ ] **Step 3: Реализация** — инструмент и строка каталога; `taskflow_kb_search` не трогается.
- [ ] **Step 4: Прогнать — зелено**, Step 5 коммит `feat(roles): поиск по выданным роли датасетам базы знаний`.

---

### Task 9: Сторож очереди индексации

**Files:**
- Modify: `server/src/lib/kbSearchWatcher.ts`
- Test: `server/test/kbSearchWatcher.test.ts` (создать, если нет)

- [ ] **Step 1: Тест** — «задание в queued старше 10 минут → сигнал», «всё done → тишина».
- [ ] **Step 2: прогнать — падает**, Step 3 реализовать вторую пробу рядом с существующей, Step 4 прогнать — зелено, Step 5 коммит `feat(knowledge): сторож застревания очереди индексации`.

---

### Task 10: iOS — сеть и модели

**Files:**
- Modify: `Sources/Core/Networking/APIClient+Knowledge.swift`
- Create: `Sources/Core/Networking/APIClient+KnowledgeAdmin.swift`
- Test: `Tests/KnowledgeApiDecodingTests.swift`

**Interfaces:**
- Consumes: JSON из Task 2, 3, 6, 7, 5
- Produces: `ApiKnowledgeDataset` (+ `enabled`, `section: ApiKnowledgeSection?`, `roles: [ApiKnowledgeRole]`), `ApiKnowledgeSection`, `ApiKnowledgeRole`, `ApiAskAnswer` (`answer`, `model`, `chunks`), методы `knowledgeSections()`, `createSection(_:)`, `patchDataset(id:enabled:sectionId:title:)`, `setDatasetRoles(id:roleKeys:)`, `uploadDocument(datasetId:name:bytes:)`, `documentStatus(id:datasetId:)`, `deleteDocument(id:datasetId:)`, `reparseDataset(id:)`, `askKnowledge(question:datasetIds:)`, `noteIndexStates` в `notes`-модели (`indexState: String?`).

- [ ] **Step 1: Тест декодирования** — образец JSON датасета с `section`/`roles`/`enabled` и ответ `ask` с `answer: null` декодируются без ошибок.
- [ ] **Step 2: Прогнать — падает**, Step 3 реализовать, Step 4 прогнать — зелено (`xcodebuild test` только по прямому поручению; иначе — точечная статическая проверка и diff), Step 5 коммит `feat(ios): модели и ручки управления базой знаний`.

---

### Task 11: iOS — экран «База знаний» и экран датасета

**Files:**
- Modify: `Sources/Features/Knowledge/NotesScreen.swift` (становится списком датасетов по разделам + вход «Заметки TaskFlow» + вход «Спросить базу»), `Sources/App/Navigation/RouteDestinationView.swift` (новый маршрут датасета)
- Create: `Sources/Features/Knowledge/KnowledgeDatasetsScreen.swift`, `Sources/Features/Knowledge/KnowledgeDatasetScreen.swift`, `Sources/Features/Knowledge/KnowledgeDatasetViewModel.swift`

**Interfaces:**
- Consumes: Task 10, `TFFont`/дизайн-система проекта
- Produces: секции по разделам, «+ Раздел», меню строки (включить/исключить, переименовать, в раздел, доступ ролям), экран датасета с документами, поиском внутри датасета, загрузкой и блоком «Доступ ролям».

- [ ] **Step 1: Экран списка** — состояние загрузки/ошибки как в нынешнем `NotesScreen`, без новых компонентов дизайн-системы.
- [ ] **Step 2: Экран датасета** — загрузка через document picker с UTI из Global Constraints, строка с прогрессом разбора (опрос 2 с, до 5 минут), кнопка «+» только у своих.
- [ ] **Step 3: Diff-проверка** — `git diff`, сверить с дизайн-доком §9.1, 9.3, 14.3; сборка только по прямому поручению.
- [ ] **Step 4: Коммит** `feat(ios): экран базы знаний по разделам и экран датасета`.

---

### Task 12: iOS — окно «Спросить базу» и состояние индексации в дневнике

**Files:**
- Create: `Sources/Features/Knowledge/KnowledgeAskScreen.swift`
- Modify: `Sources/Features/Knowledge/NotesScreen.swift` (точки состояния в строках дневника), `Sources/Features/Knowledge/NoteEditorViewModel.swift` (после сохранения — не ждать синка, состояние придёт из списка)

- [ ] **Step 1: Окно вопроса** — чипсы только включённых датасетов, поле вопроса, ответ + куски с документом и датасетом, при `answer == nil` — «ответить не смог, вот что нашёл».
- [ ] **Step 2: Дневник** — четыре состояния из `index_state`, без метки при её отсутствии.
- [ ] **Step 3: Diff-проверка**, Step 4 коммит `feat(ios): окно вопроса к базе и состояние индексации заметок`.

---

## Выкладка (после Task 9, до iOS)

- [ ] Сервер: `npx tsc --noEmit` (штатная сборка), перезапуск сервиса, `GET /api/knowledge/datasets` и `GET /api/health` на `.110` — ответ 200.
- [ ] Живая проверка: загрузить `.md` в датасет по умолчанию, дождаться `DONE`, спросить `POST /api/knowledge/ask` по нему и убедиться, что кусок из этого файла в выдаче.
- [ ] iOS: прямой push `main` + зеркало `github main`; установка на iPhone — по отдельному поручению.
