# Код-ревью TaskFlow: SwiftUI, архитектура, качество кода — 22.10.2026

По трём скиллам: `apple-design` (часть 2 отчёта о производительности —
`docs/2026-10-22-code-review-and-performance.md`), `argent-ios-simulator-setup`
(раздел «Окружение»), `coding-best-practices` (этот документ).

**Объём:** весь `Sources/` — 370 файлов, ~76 тыс. строк. Тесты, `archive/`,
`docs/` в разбор не входили. Правок в приложение по этому документу **не
вносилось** — это перечень решений для владельца; сделаны только две правки в
собственном коде прошлой задачи (перечислены в разделе «Что исправлено сразу»).

---

## ✅ Strengths Found

- **Современный SwiftUI-базовый уровень взят почти целиком.** `NavigationView`
  — 0, `EnvironmentObject` — 0, `PreviewProvider` — 0, `@Published` рядом с
  `@Observable` — 0, `#Preview` — 19.
- **Миграция на `@Observable` доведена**: 45+ классов, `@Bindable` для
  биндинга (`ChatComposer.swift:8`, `QuickAddTaskView.swift:11`,
  `RoleEditorSheet.swift:39`, `VoiceModelsScreen.swift:251`). `@State` с
  `@Observable`-классом вместо `@StateObject` — правильный паттерн
  (`TaskFormScreen.swift:42`, `RoleChatsScreen.swift:750, 825`).
- **Сторы через `@Environment`, а не передачей вниз**: `TaskFormScreen.swift:45-48`
  (`TaskStore`, `ProjectStore`, `LabelStore`, `SessionStore`).
- **Современная работа со скроллом**: `onScrollGeometryChange`
  (`RoleChatsScreen.swift:1529`, `ChatScreen.swift:193`), `onGeometryChange`
  (`RoleChatsScreen.swift:1432`), `LazyVStack` вместо eager-стека (`:1419`).
- **Индексация защищена везде**: `ActivityChart.swift:299-300` (`guard p.count == 3`),
  `ActivityChart.swift:312` (`points.indices.contains(idx)`),
  `AppleEventKitAccess.swift:126`, `BlockDocumentEditor.swift:60`
  (`guard let idx = index(of:)`), `MarkdownParser.swift:206`.
- **Пирамиды вложенных `if let` глубины 3+ нет** — плоские `if let` в
  ViewBuilder либо ранний выход через `guard let`.
- **Управление памятью в `Core` — образцовое**: `[weak self]` в
  `RealtimeClient.swift:79,85,148,222,236`, `SessionStore.swift:31`,
  `DictationEngine.swift:243,336`; наблюдатели снимаются в `deinit`
  (`SessionStore.swift:36-40`); `RealtimeClient` использует `guard let self`
  вместо `self!`.
- **Свои шапки не рисуются** — только системный `navigationTitle` через
  `.tfNativeHeader`; скролл-эффекты — системные.
- **Осознанные решения задокументированы**: `AnyView` как защита от взрыва
  generic-типа (`TaskFormScreen.swift:921-926`), игнорирование скорости в
  `HorizontalPan.settleAnimation` (`HorizontalPan.swift:120-138`).
- **Тестируемость в моделях есть**: `TaskDateText.swift:32,46,77,90` и
  `DirectoryDate.swift:44` принимают `now: Date = Date()`;
  `LinearImportScreen.swift:19` — `init(api: any LinearImportServing = APIClient())`.

---

## ⚠️ Issues Found

### High

**Category: Error Handling / потеря данных**

**[High]: `Sources/Features/Task/Fields/AttachmentsFieldView.swift:76-83`** — неудачная
загрузка вложения теряет файл молча.
```swift
// Current:
for item in pending {
    if let attachment = try? await apiClient.uploadTaskAttachment(...) {
        uploaded.append(attachment)
    }
}
pending.removeAll()          // ← убирает и те, что не загрузились

// Suggested:
for item in pending {
    do {
        uploaded.append(try await apiClient.uploadTaskAttachment(...))
    } catch {
        errorMessage = "Не удалось приложить файл «\(item.fileName)»"
    }
}
pending.removeAll { $0.fileName != ... }   // неудачные остаются в pending
```
// Reason: пользователь прикрепляет файл к только что созданной задаче — сервер
// отвечает ошибкой, файл исчезает без единого сообщения. Соседние методы этого
// же типа (`addPending` :55, `removeUploaded` :64) `errorMessage` ставят — здесь
// забыто. Проверено лично.

**[High]: `Sources/Features/Settings/EscalationStepEditor.swift:66, 78`** — индекс шага,
захваченный при отрисовке, используется для правки массива позже.
```swift
// Current:
Button("Удалить шаг", role: .destructive) { save { $0.steps.remove(at: index!) } }
// …и в «Готово»:
if let index { rule.steps[index] = step }
```
// Reason: `index` — номер на момент открытия шторки. Если правило с че��овека
// изменилось (реалтайм-синхронизация), массив стал короче — `remove(at:)`
/`rule.steps[index]` падают с «index out of range». Проверено лично.

### Medium

**Category: Type Safety**

**[Medium]: `Sources/Core/Models/TaskPreparation.swift:6-8` + `Features/Task/Detail/TaskPreparationView.swift:33,116,157,226,229,233,240,253`** —
серверные статусы хранятся строкой, и вью сравнивает их сырыми литералами.
```swift
// Current (в модели):
public let status: String
public let planStatus: String?
// …при этом в модели УЖЕ есть вычисляемые свойства (TaskPreparation.swift:42-46):
public var isPending: Bool { … }
public var canApprovePlan: Bool { … }
// …а вью всё равно сравнивает строки:
if fresh.status == "needs_clarification" || fresh.status == "structure_review" { … }

// Suggested:
// enum PreparationStatus: String { case needsClarification = "needs_clarification" … }
// и вью работает с моделью, а не со строкой
```
// Reason: новый статус с сервера молча провалится в «ветку по умолчанию» — без
// ошибки и без лога. То же для плана коллаборации:
// `Core/Models/CollaborationPlan.swift:34,40,167,185,242-244` и
`Features/Task/Detail/CollaborationPlanView.swift:167,232,234,473,475,489,537,604,806,820,824,1045`.

**[Medium]: `Sources/Features/Task/TaskFormViewModel.swift:616-622`** — строковый
параметр публичного метода.
```swift
// Current:
func runAgent(mode: String) async -> Bool {
    if mode == "executor" { … }
// Suggested:
func runAgent(mode: AgentRunMode) async -> Bool
```
// Reason: опечатка в строке («exectutor») не ловится компилятором — метод тихо
// перестанет запускать агента.

**Category: Error Handling**

**[Medium]: `Sources/Features/Settings/IntegrationsScreen.swift:258`**, `:62` ·
**`ProviderDetailScreen.swift:135`** · **`AppleEventKitAccess.swift:81-89`** —
молчаливые `try?` на пользовательских действиях.
```swift
// Current:
_ = try? await apiClient.updateGoogleListId(id)   // сервер отклонил → UI молча
// Current:
try? store.save(reminder, commit: true)          // галочка есть, в Напоминаниях нет
```
// Reason: соседние ветки того же экрана ставят `errorMessage` — здесь ошибка
// не видна. `IntegrationsScreen.swift:62`: при ошибке список вебхуков выглядит
// пустым, а не как «не загрузилось».

**[Medium]: `Sources/Features/Task/TaskFamilyNavigation.swift:265-295`** — polling-цикл
в несохранённой `Task`.
```swift
// Current:
Task {
    while candidate.isLoadingTask {
        try? await Task.sleep(for: .milliseconds(30))
        if Task.isCancelled { return }
    }
}
// Suggested:
@State private var loadTask: Task<Void, Never>?
// …запускать с handle и отменять в onDisappear
```
// Reason: handle не сохранён — отменить нечем, `Task.isCancelled` всегда false.
// Если загрузка зависнет, цикл крутится вечно, удерживая модель.

**[Medium]: 10 методов возвращают `Bool` вместо `throws`**
(`TaskFormViewModel.swift:616,640,738,792,856,890,926`, `NoteEditorViewModel.swift:312`,
`LinearImportScreen.swift:56`, `ProviderDetailScreen.swift:60`,
`ComposioIntegrationsScreen.swift:97`). Ошибка не теряется — она в
`saveErrorMessage`, — но контракт метода её не выражает.

**Category: Swift Idioms**

**[Medium]: 14 мест `!` сразу после nil-проверки** — безопасно из-за
short-circuit, но хрупко (правка условия → крэш):
`Today/TimelineScreen.swift:122`, `Today/TodayComputation.swift:200`,
`Upcoming/UpcomingScreen.swift:527`, `Directory/Support/ProjectNotesSection.swift:246`,
`Notes/NoteEditorViewModel.swift:214,266,292`, `Chat/AgentProfileScreen.swift:298`,
`Core/Models/RoleComposio.swift:33`, `Core/Networking/APIClient+Runtime.swift:78`,
`Core/Models/LinearImport.swift:71`, `Core/Networking/ServiceTicketMarkdownParser.swift:99`
(`current! += " " + trimmed` — мутация optional через `!`).

**Category: Performance**

**[Medium]: `Sources/Features/Chat/RoleChatsScreen.swift:1618-1630`** — вложенный
скан словарей внутри `filter` на каждом проходе `body` ленты.
```swift
// Current:
private var visibleMessages: [RoleChatMessage] {
    messages.filter { message in
        !completingTurns.keys.contains { playbackID in
            if let completed = completedMessageIDByTurn[playbackID] { … }
```
// Suggested:
// один раз собрать Set<String> скрытых id и кэшировать по ревизиям messages
```
// Reason: `feedItems` (`:1645`) и `dayDividerTitles` (`:1689`) обходят это
// ещё раз — и всё пересчитывается на каждом проходе `body`, потому что лента
// обёрнута в `GeometryReader` (`:1409`). Комментарий в `:1417` упоминает
// 15.5 CPU-секунд на три свайпа. Это ровно тот же класс проблемы, что уже
// исправлен для «Сегодня» и «Заметок».

**[Medium]: `DateFormatter()` создаётся на каждый вызов в горячих путях** —
`Task/Support/TaskDateText.swift:110-117` (`calendarDateStringMoscow`),
`Chat/AgentWorkTaskRow.swift:113,126`, `Chat/ChatFeedMarks.swift:36,115`,
`Directory/Support/NotificationTicketCard.swift:123`,
`DesignSystem/Components/TFTaskCreatedStamp.swift:54,80`, `Notes/NotesScreen.swift:425`.
Образец рядом: `RoleChatsScreen.swift:598-619` и `DateFormats.swift:11-47` — статические.

**[Medium]: `Sources/Features/Directory/TaskArchiveScreen.swift:13`** —
`taskStore.archivedTasks.sorted { … }` в вычисляемом свойстве, читаемом в `ForEach`:
пересортировка всего архива на каждый проход `body`.

**[Medium]: `AnyView` в заголовках строк ленты** —
`RoleChatsScreen.swift:1471, 2120` (`header: AnyView(ownSenderLine)`) — на каждую
строку 300 сообщений; тип стирается, дифференцирование SwiftUI теряется.
Корневые `AnyView` (`UpcomingScreen.swift:146`, `TaskFormScreen.swift:926`) —
осознанная защита, их не трогать.

**Category: Modern SwiftUI Baseline**

**[Medium]: `UIScreen.main` — deprecated с iOS 16 (мультисцена), 6 мест** —
`CoordinationScreen.swift:135,143,148`, `PlanStepSheets.swift:99`,
`MarkdownKeyboardAccessoryBar.swift:244`, `TaskFormScreen.swift:773`.
Делать: `containerRelativeFrame` для доли экрана, `ViewThatFits` для порогов.

**[Medium]: 4 ручных `PreferenceKey` вместо `onScrollGeometryChange`** —
`TodayHoursView.swift:418` (`HoursGridFrameKey`), `UpcomingHoursView.swift:1141,1191`
(вторая рамка сетки), `UpcomingMonthView.swift:20`, `NoteEditorScreen.swift:387,592`.
Одна и та же задача («живая рамка часовой сетки») решена в двух файлах.

**[Medium]: 38 `GeometryReader` там, где хватит `onGeometryChange`/`visualEffect`** —
горячие: `RoleChatsScreen.swift:1409` (ради одной высоты), `TodayHoursView.swift:210`,
`CompletionHeatmap.swift:181,194,505`, `ActivityChart.swift:373`, `HintOverlay.swift:46`,
`VoiceBarsView.swift:78`.

**[Medium]: `alert(isPresented:)` с отдельным флагом, где есть item** —
`ServiceAccountsScreen.swift:213,225`, `BlockDocumentEditor.swift:515`,
`RoleModelsSection.swift:126`, `PlanStepSheets.swift:290`, `TaskArchiveScreen.swift:54`.
Правильный образец в проекте есть: `CoordinationScreen.swift:89-96`
(`.alert(..., isPresented:, presenting:)`).

**Category: Architecture**

**[Medium]: сеть вызывается прямо из вью** — `TaskFormScreen.swift:2147,2615,2640,2677,2692,2699,2705,3004`,
`RoleChatsScreen.swift:569,3057`, `CollaborationPlanView.swift:82`
(`private let api = APIClient()` — при том что рядом есть `@Observable`-стейт
`CollaborationPlanState.swift:6`). Проверять без UI нельзя.

**[Medium]: два гигантских файла** — `TaskFormScreen.swift` (3423 строки; 60+
`@State`, пять под-структур в том же файле, три булевых флага одного процесса
`:130-132`) и `RoleChatsScreen.swift` (3075 строк; `RoleChatRoomScreen` —
`~1970 строк в одном View`, свой `RealtimeClient` `:784`, голос, загрузка
файлов, планы, переводчик — всё это модель, а не вью).

**[Medium]: `public` по умолчанию** — 271 `public`-тип в 101 файле app-таргета
(`Core/Models/RuntimeModels.swift` — 22, `Core/Models/RoleChat.swift` — 16).
В app-таргете `public` ничего не даёт, но открывает API.

**[Medium]: >100 отдельных `APIClient()`** (`RoleChatsScreen.swift:46`,
`CollaborationPlanView.swift:82`, `ProjectNotesSection.swift:69`,
`KnowledgePickerSheet.swift:16`) — у каждого свой `URLSession`
(`Core/Networking/APIClient.swift:45`).

**Category: Тестируемость**

**[Medium]: `Date()` зашит во вью** — `ActivityChart.swift:203,216,270,273,450,459`,
`AgentRow.swift:106`, `RelativeTime.swift:15,38`, `SystemControlSection.swift:301`:
«сегодня» не подменить в тесте.

**[Medium]: `APIClient` — конкретный класс, а не протокол** —
`TaskFormViewModel.swift:237` (`apiClient: APIClient = APIClient()`), вью-модель
задачи не подменить заглушкой. Образец: `any LinearImportServing`.

**[Low]: случайность в id** — `TemplateStore.swift:39`
(`Int(Date().timeIntervalSince1970 * 1000)` + `Int.random(in:)`): тест по id
невозможен.

**Category: Коллекции**

**[Low]: `ModelMenu.swift:72-75`** — ручной цикл с `contains` по массиву
(O(n²)); `Set` + `map` дают то же за O(n).

---

## 📊 Code Quality Score

**Overall: 7/10**

- Swift Idioms: 8/10 — force unwrap только защищённые, индексация безопасна, пирамид optionals нет; минус за 14 `!` после nil-проверки и строковые статусы.
- Architecture: 6/10 — `@Observable` и `@Environment`-сторы на высоте, но сеть во вью, два файла по 3000+ строк, 100+ `APIClient`, `public` по умолчанию.
- Error Handling: 6/10 — `throws` есть, но `try?` глушит пользовательские ошибки, один случай реальной потери данных.
- Naming: 8/10 — русские описательные имена, `is`/`has` для булевых, MARK-разделы.
- Organization: 7/10 — модули по фичам, дизайн-система вынесена; перегружены два экрана.
- Performance: 7/10 — после правок этой сессии «Сегодня» и «Заметки» считаются на порядки быстрее; в ленте чата остался O(n×m) на кадр.

---

## 📋 Recommendations

1. **High Priority**: починить потерю вложения (`AttachmentsFieldView.swift:76-83`) — неудачные файлы остаются в `pending`, `errorMessage` показывается. Соседние методы уже так делают.
2. **High Priority**: закрыть падение по индексу в `EscalationStepEditor.swift:66,78` — проверять `index < rule.steps.count` перед правкой.
3. **Medium Priority**: вынести `visibleMessages`/`feedItems` из `body` ленты в кэш по ревизиям и убрать `AnyView` из заголовков строк (`RoleChatsScreen.swift:1618-1630, 1471, 2120`) — тот же приём, что применён к «Сегодня» и «Заметкам».
4. **Medium Priority**: статусы из строк — в enum (`TaskPreparation`, `CollaborationPlan`); вью должна работать с моделью, у которой уже есть вычисляемые свойства.
5. **Medium Priority**: убрать `DateFormatter()` из горячих путей (6 файлов) — статические экземпляры, как в `DateFormats.swift`.
6. **Medium Priority**: сеть — во вью-модели; `APIClient` — за протоколом, чтобы задача тестировалась без UI.
7. **Low Priority**: `UIScreen.main` → `containerRelativeFrame`; ручные `PreferenceKey` → `onScrollGeometryChange`; `alert(isPresented:presenting:)`; `public` → `internal` в app-таргете.

## 🔧 Quick Wins

1. `AttachmentsFieldView.flushPending` — не удалять из `pending` то, что не загрузилось, и ставить `errorMessage` (одна правка, снимает потерю файла).
2. `EscalationStepEditor` — `guard index < rule.steps.count` перед `remove(at:)`/`rule.steps[index]`.
3. `TaskDateText.calendarDateStringMoscow` и ещё 5 мест — `private static let` вместо `DateFormatter()` на вызов.
4. `ModelMenu.swift:72-75` — `Set` вместо массива с `contains`.
5. `alert(isPresented:)` → `alert(_:isPresented:presenting:)` в `ServiceAccountsScreen`, `BlockDocumentEditor`, `RoleModelsSection` — флаг исчезает, состояние не рассинхронизируется.

---

## Окружение: `argent-ios-simulator-setup`

- **`.xcodebuildmcp/config.yaml` уже настроен**: `enabledWorkflows: ["simulator",
  "ui-automation", "debugging"]` — элементные инструменты (`snapshot_ui`,
  `tap` по `elementRef`) доступны; переписывать файл не потребовалось.
- **Симулятор один и загружен**: iPhone Air, iOS 27.0,
  `9FF78D89-EE84-4914-AA56-D0A72D1AF43A` — тот же, что и у телефона владельца.
  UDID указывается явно во всех командах.
- **Сборка и запуск** — через `xcodebuild`/`simctl` по `AGENT-CYCLE.md`; для
  приёмки в этой задаче хватило `simctl install` + `simctl launch` +
  `simctl io screenshot` — навигация по экрану не требовалась.
- **Важно для приёмки:** симулятор восстанавливает навигационное состояние
  прошлой сессии поверх отладочного маршрута. Чтобы открыть нужный экран
  честно, нужен запуск с `-ApplePersistenceIgnoreState YES` (иначе, например,
  маршрут `notes` открывал прошлую «Базу знаний»).

---

## Что исправлено сразу (в своём коде, по чеклисту)

Правки в коде предыдущей задачи (`LOCK-OPT-PERF-20261022`) — два замечания
из чеклиста, оба в файлах своей строки реестра:

1. `Sources/Core/Common/DateFormats.swift` — разбор даты больше не копирует
   байты на каждый вызов (`withContiguousStorageIfAvailable`): 0.95 → 0.41 мкс
   на дату. Переименована `twoOrFourDigits` → `fourDigits` (имя не соответствовало
   поведению).
2. `Sources/Features/Notes/NotesViewModel.swift` — убрана мёртвая публичная
   функция `latestNote(inFolderTree:)` (списка внутренних вызовов нет);
   «private by default».

Тесты после правок: 25/25 зелёные, замеры в
`docs/2026-10-22-code-review-and-performance.md`.
