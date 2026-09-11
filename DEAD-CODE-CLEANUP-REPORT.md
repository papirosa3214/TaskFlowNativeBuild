# Отчёт по мёртвому коду

Дата проверки: 2026-09-11  
Репозиторий: `TaskFlowNativeBuild`

## Результат

В репозитории есть построенная карта `graft/`, но она частично устарела: в
`graft/manifest.json` ещё числятся удалённые `TaskDetailScreen.swift` и
`TaskDetailViewModel.swift`, а digest не совпадает с текущими исходниками.
Поэтому список ниже сверялся не только с карточками graft, но и с фактическими
ссылками через текущий исходный код.

Автоматическая чистка исходников в этой задаче не выполнена: подтверждённые
мёртвые кандидаты находятся за пределами выданных активных скопов
(`LOCK-044`, `LOCK-046`, `LOCK-088`, `LOCK-109`). Отчёт можно передать
агенту, который владеет соответствующими файлами.

## Приоритет P0 — удалить после снятия/передачи скопов

### 1. Старые сетевые методы поиска

Файл: `Sources/Core/Networking/APIClient+Search.swift`

- `APIClient.search(_:)` — определён, вызовов в текущем коде нет.
- Текущий экран использует `directorySearch` из
  `Sources/Features/Directory/Support/DirectoryAPI.swift`.

Действие: удалить файл целиком.

### 2. Старый chat API

Файл: `Sources/Core/Networking/APIClient+Chat.swift`

Удалить только методы без callers:

- `chatMessages`
- `sendChatMessage`
- `sendChatTyping`
- `markChatRead`

Оставить `chatParticipants` и `chatStats`: они используются текущим
`ChatViewModel`.

Причина отдельной осторожности: актуальные методы находятся в
`Sources/Features/Chat/ChatAPI.swift`; старые методы используют устаревшие
маршруты и контракты и опасны как случайная точка входа.

### 3. Старые методы invite/rename агента

Файл: `Sources/Core/Networking/APIClient+Agents.swift`

Удалить:

- `InviteAgentResponse`
- `inviteAgent`
- `renameAgent`

Оставить `agents()` и `deleteAgent()`. Текущий код использует
`inviteAgentFixed` и `renameAgentFixed` из
`Sources/Features/Chat/AgentsAPI.swift`.

### 4. Старые task field views

Файлы без текущих callers — удалить целиком:

- `Sources/Features/Task/Fields/AssigneeFieldView.swift`
- `Sources/Features/Task/Fields/LabelsFieldView.swift`
- `Sources/Features/Task/Fields/PriorityFieldView.swift`
- `Sources/Features/Task/Fields/ProjectFieldView.swift`
- `Sources/Features/Task/Fields/DueDateFieldView.swift`

В `LabelsFieldView.swift` вместе с view уйдёт неиспользуемый `FlowLayout`.

### 5. Мёртвые части файлов с живым кодом

`Sources/Features/Task/Fields/SubtaskFormFieldView.swift`:

- удалить `SubtaskDraftListView`;
- удалить `SubtaskEditListView`;
- оставить `SubtaskDraft` и `AddSubtaskRow` — они используются текущей
  формой задачи.

`Sources/Features/Task/Fields/AttachmentsFieldView.swift`:

- удалить только `AttachmentsFieldView`;
- оставить `PendingAttachment` и `TaskAttachmentsController` — они нужны
  `TaskFormViewModel`.

## Приоритет P1 — удалить отдельным проходом

### Полностью изолированный keyboard demo

Каталог: `Sources/Keyboard/`

Все десять файлов образуют одну цепочку, начинающуюся с
`TFKeyboardDemoScreen`. Экран не подключён к навигации; остальные типы
используются только этим demo:

- `TFKeyboardDemoScreen.swift`
- `TFKeyboardTextField.swift`
- `TFKeyboardTextEditor.swift`
- `TFKeyboardInputView.swift`
- `TFKeyboardView.swift`
- `TFKeyboardKeyView.swift`
- `TFKeyboardLayout.swift`
- `TFKeyboardMetrics.swift`
- `TFKeyboardPalette.swift`
- `TFKeyboardHaptics.swift`

Действие: удалить каталог целиком, если keyboard demo больше не нужен.
Если это намеренный debug/demo-прототип, вынести его из production target в
отдельный demo target вместо удаления.

## Приоритет P1 — мёртвые UI-компоненты

Удалить после проверки, что их не создаёт динамический код:

- `UpcomingPlannerProjectChips` из
  `Sources/Features/Upcoming/UpcomingFilterSheet.swift` — файл сам помечает
  компонент как больше не рендерящийся;
- `PlannerProjectChips` из
  `Sources/Features/Today/PlannerProjectChips.swift` — callers нет;
- `Sources/App/Navigation/ScreenStub.swift` — runtime callers нет;
- `Sources/DesignSystem/Components/TFScreenHeader.swift` — используется
  только stub и собственными preview;
- `TFHeaderAction` из того же файла — нужен только этому мёртвому header;
- `Sources/Features/Directory/Support/DirectoryBackButton.swift` — callers
  нет.

Не удалять по этому отчёту:

- `Sources/DesignSystem/Components/TFHeaderBackdrop.swift` — используется
  `UpcomingListView`;
- `Sources/DesignSystem/Components/TFNativeHeader.swift` — используется
  живыми экранами.

## Приоритет P2 — зарезервированные API, не удалять автоматически

Эти методы сейчас не имеют callers, но комментарии и контекст указывают на
будущий/агентский протокол. Сначала нужно решение владельца:

- `APIClient+Subtasks.swift`: `subtasks`, `setSubtaskWork`, `comments`;
- `APIClient+Tasks.swift`: `claimTask`, `heartbeatTask`, `agentRules`;
- `APIClient+Auth.swift`: `register`, `issueApiToken`;
- `APIClient.swift`: `publicAvatarURL`.

## Остатки внутри живых экранов

После снятия соответствующих lock’ов удалить неиспользуемые private members:

`Sources/Features/Upcoming/UpcomingScreen.swift`:

- `selectedDate`;
- `rescheduleOpen`;
- `openDaySheetBinding`;
- `emptyFilterBanner`;
- `belowContentView`;
- `deleteTask`.

`Sources/Features/Directory/SearchScreen.swift`:

- private `searchBar` — экран уже использует `.searchable`, а property не
  читается.

`TaskJournalView.swift` целиком не удалять: текущий файл содержит живые
`TaskJournalEntry`, `AgentOwnerActionKind` и `TaskJournalView.eventText`.

## Инструкция агенту на выполнение

1. Перед правкой убедиться, что каждый изменяемый файл добавлен в строку
   `IN_PROGRESS` в `AGENT-WORK-SCOPES.md`.
2. Удалять только перечисленные символы/файлы; не удалять живые куски из
   `SubtaskFormFieldView.swift` и `AttachmentsFieldView.swift`.
3. После каждого блока проверить callers:

   ```bash
   rg -n "APIClient\.search|chatMessages|sendChatMessage|sendChatTyping|markChatRead|inviteAgent|renameAgent|AttachmentsFieldView|SubtaskDraftListView|SubtaskEditListView|PlannerProjectChips|UpcomingPlannerProjectChips|ScreenStub|TFScreenHeader|DirectoryBackButton" Sources
   ```

4. Запустить проектные проверки по принятому централизованному workflow и
   убедиться, что target собирается.
5. После удаления пересобрать/обновить graft: текущая карта уже содержит
   устаревшие карточки и не должна считаться финальной истиной.
6. Проверить `git diff` и `git status`; не затрагивать файлы вне выданного
   scope.

## Критерий готовности

В production target не остаётся кода из P0/P1 без callers, старые API-контракты
не доступны как случайный путь вызова, живые модели/контроллеры сохранены, а
обновлённый graft не содержит карточек удалённых файлов.
