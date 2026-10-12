# Форма создания проекта в стиле quick-add

**Lock:** LOCK-PROJECTS-QUICK-ADD-20261012
**Scope:** PROJECTS-QUICK-ADD
**Исполнитель:** Mavis

## Что сделано

`Sources/Features/Directory/ProjectsScreen.swift`:

- Удалена старая inline-форма `ProjectCreateForm` (название + ColorPicker +
  KnowledgeDatasetPicker + Отмена/Создать), которая разворачивалась прямо
  в `LazyVStack` списка проектов.
- Добавлен `private struct ProjectDraft: ObservableObject, Identifiable`
  с локальным состоянием черновика (`name`, `colorHex`, `datasetId`).
- Добавлен `private struct QuickAddProjectView` — компактная шторка создания
  по образцу `QuickAddTaskView`:
  - iOS 26: `safeAreaBar` + `.glassEffect(.regular)` + стеклянная кнопка-стрелка.
  - iOS 18: legacy-капсула с тёплой подсветкой и красной объёмной кнопкой.
  - Капсула иконок содержит **две** иконки: «Цвет» (`paintpalette`,
    пресеты `DirectoryColors.project` через `Menu`) и «База знаний»
    (`book.closed`, `.popover` с `KnowledgeDatasetPicker`).
  - Кнопка-стрелка (`arrow.up`) появляется только при непустом названии.
  - Закрытие — тап по фону (как у задачи), `closePanel()` через `@Environment(\.dismiss)`.
  - Цвет показывается цветным кружком поверх иконки, когда выбран не дефолт.
- В `ProjectsScreen`:
  - `@State showCreate` заменён на `@State projectDraft: ProjectDraft?`.
  - Единая точка входа `openProjectDraft()` для центрального «+»
    (`opensCreateForm = true` в `.task`) и меню «…» → «Добавить проект».
  - `.fullScreenCover(item: $projectDraft)` вешается на корневой body,
    поднимает шторку поверх NavigationStack — тот же подход, что у задачи.
  - `if showCreate { ProjectCreateForm(...) }` внутри LazyVStack удалён.
  - Empty-state и условия подавления переписаны на `projectDraft == nil`.

## Что не сделано

- **Проверка через XCUITest** не выполнена в этой сессии: временный тест
  `UITests/ProjectsQuickAddUITests.swift` написан и не зашёл — таб-бар кастомный
  (`TFTabBar`), `app.tabBars` его не видит; нужен заход через
  `TASKFLOW_DEBUG_ROUTE=projects` либо через MCP `XcodeBuildMCP`. Тест удалён,
  приёмка перенесена на следующий заход.
- **Приёмка на физическом iPhone** — не делалась, устройство на связи,
  требует отдельного захода по `install-iphone.sh` или MCP device workflow.

## Проверка сборкой

```
$ xcodegen generate && xcodebuild ... build 2>&1 | grep -E 'error:|BUILD (SUCCEEDED|FAILED)'
** BUILD SUCCEEDED **
```

Два предупреждения (`BlockDocumentEditor.swift:319`, `SessionStore.swift:25`) —
существующие, к этой правке не относятся.

## Файлы

- Изменён: `Sources/Features/Directory/ProjectsScreen.swift`
- Изменён: `AGENT-WORK-SCOPES.md` (строка LOCK-PROJECTS-QUICK-ADD-20261012)
- Удалён: `UITests/ProjectsQuickAddUITests.swift` (временный, не зашёл)