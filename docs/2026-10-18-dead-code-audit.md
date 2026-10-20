# Аудит мёртвого / избыточного кода — 2026-10-18

Разведочное ревью по поручению владельца «пройдись по коду и посмотри, есть ли что
нагруженное, лишнее или мёртвое». Никаких правок не делал — только замеры.

## Источники

- `graft/.graph/wiring.json` (5 790 нод, 13 623 ребра) — статический граф символов.
  Граф отстаёт на 135 файлов (`graft check STALE`), прицельная проверка через
  `grep -rwn 'name' Sources Tests` без самого файла кандидата.
- `wc -l` по `Sources/**/*.swift` — 71 684 строки в 338 файлах.
- `Sources/Features/Task/TaskFormScreen.swift` — 3 310 строк, самый толстый
  файл; `RoleChatsScreen.swift` — 2 700.

## Метод

1. Символы графа помечены `kind ∈ {struct, class, enum, method, function}`.
2. Из рёбер `relation == 'calls'` собран счётчик входящих вызовов на узел.
3. Если у метода/функции из `Sources/` 0 входящих `calls`-рёбер — кандидат
   на мёртвость.
4. Каждый кандидат проверен через `grep -rwn '<имя>' Sources Tests` без
   его собственного файла: 0 совпадений = «реально мёртвый», ≥1 = «вызывается
   в обход графа (extension-метод enum, перегрузка, динамическая диспетчеризация)».
5. Ложные срабатывания отфильтрованы: UIKit-делегаты, `body/onAppear/init`,
   computed-геттеры, вложенные View — система их вызывает, не код.

## Итог

**647** методов/функций из `Sources/` без входящих call-рёбер.
**197** не подтверждаются `grep`-ом (то есть нет вызова ни в одном другом файле).
**86** высокой уверенности — после фильтра от имён, которые система всё же
вызывает (`body`, override, `init` и т. п.).

Полная классификация сохранена в `/tmp/dead_classified.json` (системные — 64,
внутренние View — 47, «реально мёртвые» — 86). Здесь привожу только вторую
и третью группы.

## Группа A — мёртвые методы в `APIClient+*.swift`

Методы объявлены в расширениях `APIClient`, но ни в одном Swift-файле
приложения или тестов нет их вызова. Это либо отказы сервера, которые уже
решили на фронте, либо будущая фича, забытая в коде.

| Файл | Строка | Что |
| --- | --- | --- |
| `APIClient+AgentDetails.swift` | 18–20 | `agentDetails` |
| 〃 | 25–27 | `mcpServersCatalog` |
| 〃 | 30–32 | `skillsCatalog` |
| 〃 | 108–127 | `updateAgentConnection` |
| 〃 | 131–140 | `updateAgentPrompt` |
| 〃 | 143–152 | `updateAgentPermissions` |
| 〃 | 178–182 | `agentDetailsPathSegment` (приватный хелпер) |
| `APIClient+Chat.swift` | 32–34 | `chatUnread` |
| `APIClient+Knowledge.swift` | 109–119 | `knowledgeDocuments` (без UI) |
| `APIClient+MailIntegration.swift` | 31–35 | `pathPart` (приватный хелпер) |
| `APIClient+RoleChats.swift` | 63–75 | `reactToRoleChatMessage` |
| `APIClient+Runtime.swift` | 46–48 | `runtimeProfile` |
| `APIClient+SystemControl.swift` | 38–42 | `TaskIntakeSettings` (DTO) |
| 〃 | 197–199 | `updateTaskIntakeMode` |

См. также граф-узлы `APIClient+AgentDetails.swift` — топ-1 файл по
количеству «мёртвых» (12 символов).

## Группа B — вложенные типы без потребителей

`enum`-ы и мелкие `struct`-ы, на которые нет ссылок вне их файла. Часть —
это справочники состояний, чьи значения сейчас приходят из бэкенда и
свободно читаются через `String`/`Int`, минуя типизацию.

| Файл | Что |
| --- | --- |
| `Models/RuntimeModels.swift` | `RuntimeState`, `ProviderAuthMethod`, `AgentProfileStatus`, `AgentAttemptStatus`, `AgentRunStatus`, `AuthSessionStatus`, `AuthPromptType` |
| `Models/Task.swift` | `ApiTaskAncestor` (39–43) |
| `Models/User.swift` | `RemainingValue` (60–67) |
| `Models/RoleChat.swift` | `pacingParts` (594–619) |

## Группа C — приватные/локальные хелперы без вызова

Free-floating функции и computed-свойства, которые ни разу не вызываются
даже в своём файле, не считая собственного определения.

| Файл | Что |
| --- | --- |
| `Core/Common/APIError.swift` | `humanized` (50–55) |
| `Core/Common/CodableHelpers.swift` | `decodeIntBoolIfPresent` (18–21) |
| `Core/Stores/TaskStore.swift` | `isMissingRecord` (253–256) |
| `DesignSystem/Navigation/TFPillTabBar.swift` | `symbols` (133–141) |
| `Features/Chat/AgentProfileScreen.swift` | `humanizedTool`, `plural` |
| `Features/Chat/RoleReplyMarkdown.swift` | `charactersAfterSegments`, `numbered`, `readableText` |
| `Features/Chat/VoiceRecordingWaveformView.swift` | `barHeight`, `sculpted` |
| `Features/Chat/SecretaryDraftCard.swift` | `stepsWord`, `tasksWord` |
| `Features/Chat/RoleChatsScreen.swift` | `correctnessMessages`, `turnDuration` |
| `Features/Chat/RoleLiveTurnView.swift` | `isAction`, `highlighted` |
| `Features/Chat/RoleRunJobsScreen.swift` | `reasonTitle`, `timeText` |
| `Features/Chat/ChatViewModel.swift` | `onComposerBlur` |
| `Features/Chat/AgentsViewModel.swift` | `verb` |
| `Coordination/CoordinationAPI.swift` | `fetchSubtaskResolution`, `fetchAttemptResolution`, `fetchCoordinationMetrics` |
| `Directory/NotificationsScreen.swift` | `sectionTitle` |
| `Directory/ProjectTasksScreen.swift` | `refreshRelationshipTasks`, `treeRow` |
| `Directory/Support/DirectoryAPI.swift` | `directoryNotes` |
| `Directory/Support/NotificationTicketCard.swift` | `levelColor` |
| `Directory/Support/ServiceNotificationsClient.swift` | `checkStatus` |
| `Markdown/BlockDocumentEditor.swift` | `isPlainParagraph` |
| `Markdown/MarkdownParser.swift` | `isBoundary` (две перегрузки), `isAlphanumeric` |
| `Markdown/MarkdownText.swift` | `withTraits` |
| `Notes/NoteBlockTextView.swift` | `semanticKey` |
| `Notes/NotesScreen.swift` | `cleanedKnowledgeSnippet` |
| `Notes/NotesViewModel.swift` | `comparator` |
| `Settings/RoleModelsSection.swift` | `guessProvider` |
| `Settings/TemplatesScreen.swift` | `trimmingLeadingEmoji` |
| `Settings/VoiceModelsScreen.swift` | `modelBytes` |
| `Settings/VoiceModelsSupport.swift` | `addEntry` |
| `Task/Detail/CollaborationPlanView.swift` | `taskNumbersColor` |
| `Task/Support/TaskConfirm.swift` | `taskConfirm` |
| `Task/TaskFamilyNavigation.swift` | `allChildren`, `latePullProgress` |
| `Task/TaskFormScreen.swift` | `isInWork`, `agentStateIcon`, `isBlank`, `addSubtaskInline` (×2) |
| `Today/TimelineScreen.swift` | `timelineSort` |
| `Today/TodayComputation.swift` | `partitionOverdueToday` |
| `Upcoming/UpcomingHoursView.swift` | `tfHoursNativeTopScrollEdge` |
| `Upcoming/UpcomingMonthView.swift` | `buildInitialWeeks` |
| `Upcoming/UpcomingScreen.swift` | `todayLayoutIcon` |

Суммарно это ~600 строк мёртвого кода по 86 точкам.

## Группа D — внутренние View, требуют ручной проверки

47 символов в категории «похоже на вложенный тип, вызываемый по имени
(`OuterView.InnerView()`)» — граф их не видит как `calls`. Сюда попали:

- Все настоящие View-структуры: `RoleChatAvatar`, `RoleChatDetailsSheet`,
  `CoordinationScreen`, `ResolutionDetailsSheet`, `KeyboardCornerBackdropView`,
  `TFMonospacedModifier`, `TFSectionDisplayModifier`, `TFGlassSurface`,
  `StructuredOutputEnvelope`, `StructuredOutputBlock`, `AssigneeChip`,
  `PulseModifier`, `GraphNodeLabel`, `TFScreenBackgroundModifier`,
  `LabelEditForm`, `TaskConfirmRequest`, `markReady`, `quotaMenuTitle`,
  `formatDayMonthFull` и др.
- Computed properties на `APIClient`: `publicAvatarURL`, `bodyPreview`,
  `sanitizedHeaders`, `throwIfError` — те, что вряд ли зовутся напрямую.
- `FlowLayout.placeSubviews` — override `CALayoutManager`-протокола.
- `WeakMessageHandler` (вложенный класс, вызывается через `WKUserContentController`).
- `feedItemID` (×2), `readingPreviewTurn` в `RoleChatsScreen` — частные
  ViewModel-методы, могут зваться из замыканий, которые граф не видит.
- `NotificationsScreen.notificationRow` / `summaryRow` — вызываются через
  `LazyVStack`/`ForEach` в этом же файле.

Удалять без чтения файла — нельзя. Каждое место надо открыть и пройтись
глазами: на любом ли месте `foo` или это кусок старого решения.

## Что ещё нагружает, но не мертво

- **3 310-строчный `TaskFormScreen.swift`** — форма карточки, видно, что в нём
  живут и вложенные типы, и ViewModel-методы (`isInWork`, `agentStateIcon`,
  `isBlank`, `addSubtaskInline`, `handleDisappear`, `handleAttachmentImport`).
  По правилам проекта этот файл трогать нельзя без строки `IN_PROGRESS` в
  `AGENT-WORK-SCOPES.md` — но он кандидат на разбиение.
- **2 700-строчный `RoleChatsScreen.swift`** — то же: и View, и формы, и
  ViewModel-методы вперемешку.
- **Сегодня в работе по реестру** — `git status -s` показал 10 незакоммиченных
  файлов M + 4 новых `??` без строки `IN_PROGRESS`. Раздел «Правило границ работы»
  прямо говорит «вне строки — не трогать», так что я их не открывал и не правил.
  Это не мёртвый код, но сигнал, что кто-то работает в обход реестра.

## Где лежит сырьё для будущей работы

- `/tmp/dead.json` — все 647 кандидатов с span.
- `/tmp/dead_strong.json` — 197 после grep-проверки.
- `/tmp/dead_classified.json` — разбивка на «системные» / «внутренние View» /
  «реально мёртвые».

## Что делать дальше

1. Выбрать файл-пилот (например, `RoleReplyMarkdown.swift` — три мёртвых
   функции, тесты есть) и через владельца завести строку в `AGENT-WORK-SCOPES.md`
   с тестом «функция отсутствует». Так блок за блоком.
2. По `APIClient+AgentDetails.swift` отдельно — там 12 мёртвых методов, нужно
   свериться с серверными эндпоинтами (возможно, оставлены под внешнее API).
3. По `RuntimeModels.swift` — узнать у владельца, ожидаются ли эти enum-ы
   в UI или это остатки первого драфта типизации.
