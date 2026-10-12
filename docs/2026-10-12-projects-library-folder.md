# Новый проект сразу получает папку в TaskFlow Library

**Lock:** LOCK-PROJECTS-LIBRARY-FOLDER-20261012
**Scope:** PROJECTS-LIBRARY-FOLDER
**Исполнитель:** Mavis

## Проблема

iOS-клиент при создании проекта **не передавал** `with_docs=true` в `POST /projects`,
поэтому сервер не создавал папку под `Library/Projects` (`server/src/routes/projects.ts:192-218`).
Каждый новый проект оставался без `notesFolderId`, секция «Документация» на экране
проекта была пустая, заметки ролей и задач сыпались в общий корень дневника, мимо
TaskFlow Library.

## Что сделано

Изменены **2 вызова** `projectStore.create(...)` — добавлен параметр `withDocs: true`:

1. `Sources/Features/Directory/ProjectsScreen.swift:776` —
   `QuickAddProjectView.save()` (создание проекта через шторку `+`)
2. `Sources/Features/Notes/NoteExtractedTasksSheet.swift:149` —
   создание нового проекта при извлечении задач из заметки

`ProjectStore.create(...)` параметр `withDocs` уже принимал и пробрасывал в
`apiClient.createProject(...)` (`Sources/Core/Stores/ProjectStore.swift:34-51`) —
правка не требовалась.

`IntegrationsScreen.swift` (`Apple Напоминания`) **не тронут** — там создание
проекта-обёртки без папки.

## Серверная сторона (не менялась)

`server/src/routes/projects.ts:188-225` (08.10.2026) уже умеет:
- если `with_docs=true` — ищет папку `Library/Projects` под корнем `is_kb_root=1`
- создаёт новую папку с именем проекта внутри `Library/Projects`
- линкует её с проектом через `UPDATE projects SET notes_folder_id = ...`
- fallback в top-level, если `Library/Projects` ещё нет

На `.110` проверено: `Library` (`is_kb_root=1`) и подпапка `Projects` (id 187)
уже инициализированы (`sqlite3 ~/Проекты/New-Todoist/server/taskflow.db ...`).

## Проверка сборкой

```
$ xcodegen generate && xcodebuild ... build 2>&1 | grep -E 'error:|BUILD (SUCCEEDED|FAILED)'
** BUILD SUCCEEDED **
```

## Не сделано

- **UI-приёмка через XCUITest** — не делал, та же история, что у LOCK-PROJECTS-QUICK-ADD-20261012:
  таб-бар кастомный `TFTabBar` и `TASKFLOW_DEBUG_ROUTE` не открывает экран «Проекты» сразу.
  Проверка поведения через UI требует отдельного захода с MCP `XcodeBuildMCP` или debug-route.
- **Проверка через `GET /api/projects/:id`** — теоретически сработает: после создания
  проекта через шторку поле `notesFolderId` должно стать ненулевым, а путь к этой папке
  через `journalFolders`/`journalFolderPath` должен начинаться с «TaskFlow Library / Projects».
- **На физический iPhone не ставилось** — устройство на связи (`unavailable` по прежним
  записям), `install-iphone.sh` нужно запускать отдельно.

## Файлы

- Изменён: `Sources/Features/Directory/ProjectsScreen.swift` (один параметр в одном месте)
- Изменён: `Sources/Features/Notes/NoteExtractedTasksSheet.swift` (один параметр в одном месте)
- Изменён: `AGENT-WORK-SCOPES.md` (строка LOCK-PROJECTS-LIBRARY-FOLDER-20261012)
- Создан: `docs/2026-10-12-projects-library-folder.md`