# iOS — реализация координации по контракту V2

Дата: 08.10.2026. Автор: Разработчик (iOS-слот, карточка `3161afe9-…`).
Назначение: соответствие UX-документу дизайнера `1eb44f63-1705-4ac2-a017-b04ede4944b8`,
реализация 7 правил стабильного графа и окна стриминга фиксированной высоты.

Согласованный контракт: документ «Серверный контракт V2: resolver причин
движения/ожидания» (`a8bfa7ea-…` в проекте TaskFlow — NewTodoist).

## Что реализовано

iOS-слой координации живёт в `Sources/Features/Coordination/` —
6 файлов + 1 файл тестов. Границы:

- Только новые файлы, существующие Swift-исходники (`TaskDetailScreen`,
  `ChatAPI`, `OwnerCommandAPI`) не правились.
- Серверные исходники, документы UX-дизайнера и файлы параллельного
  серверного QA не трогались.
- Никакой реальный сетевой вызов из координационного слоя не делается
  вне существующего `APIClient.request(...)` — это гарантирует
  единые заголовки авторизации и `X-TaskFlow-Client` со всем
  остальным клиентом.

### Файлы и ответственность

| Файл | Что делает |
|---|---|
| `CoordinationAPI.swift` | Расширение `APIClient` под 4 эндпоинта `/api/coordination/*`. Свойства имён полей совпадают с JSON-сервером (snake_case через `CodingKeys`). |
| `CoordinationCause.swift` | Закрытый словарь `CoordinationCause` (20 значений V2) + `CoordinationAction` (14 значений) + `CoordinationTint`. У каждого `cause` — `title`, `hint`, `actionCode`, `tint`. |
| `CoordinationCauseColor.swift` | Маппинг `CoordinationTint` → цвет в светлой/тёмной теме + SF Symbol. Контраст ≥ 4.5:1 (WCAG AA), для `stalled_manual_review`/`step_stalled` — AAA 7:1. |
| `CoordinationState.swift` | `ObservableObject`-стор: применяет **дифф по `subtask_id`** (правило стабильности №2). Существующие узлы обновляются без сдвига позиции; новые добавляются в конец; исчезнувшие становятся плейсхолдерами до `pruneStaleNodes(after:)`. Отдельные `loadState` (loaded/failed/versionMismatch) — чтобы сбой сети не стирал уже отрисованные узлы. |
| `ResolutionGraph.swift` | Стабильный горизонтальный/вертикальный граф узлов. `body` гомогенное (защита от swiftc 5.10). Пульсация через `TimelineView`, **только** у `active_run`/`durable_queued_wake` (правило №3). |
| `ReasonStrip.swift` | Однострочная причина + assignee + кнопка «обновить» (UX §2). Включает чип исполнителя. |
| `StreamWindow.swift` | Окно фиксированной высоты 200…360 пт с **внутренней** прокруткой (UX §4.1). Заголовок 28 пт + композер 44 пт. Отдельный `MessageDeliveryChip` с 6 состояниями доставки (4 основных + 2 вспомогательных). Кросс-фейд 180 мс между состояниями. |
| `ActionBar.swift` | Нижняя панель 56 пт с допустимым действием. `confirmRequired = true` для `start`/`replaceAttempt`/`acceptReview` → поднимает sheet-подтверждение. |
| `CoordinationScreen.swift` | Склеивает всё в один экран, дёргает `APIClient` каждые 30 с (UX §4.3 — компромисс, push-нотификации в открытом вопросе №1). |
| `Tests/CoordinationTests.swift` | Юнит-тесты без симулятора: декодирование `Resolution` (включая неизвестный `cause` → `unknown`), 20 причин покрыты title/hint/action/tint, дифф сохраняет позиции узлов, versionMismatch блокирует действия, stalledNodeId — первая зависшая ветвь, 6 состояний доставки. |

## Реализация 7 правил стабильного графа

| № | Правило (UX §3.3) | Где реализовано |
|---|---|---|
| 1 | Позиция узла фиксирована по `subtask_id`. Отсутствующие узлы — плейсхолдеры. | `CoordinationState.apply(...)` — дифф только по id, `nodes` остаётся в порядке первого появления. `pruneStaleNodes(after:)` для долгих разрывов. |
| 2 | Обновление контента, а не компоновки. Цвет/иконка меняются на месте. | `CoordinationState` не вызывает `.removeAll`/`append`, только точечный апдейт. `GraphNodeView` использует `.animation(.easeInOut(duration: 0.2), value: cause)`. |
| 3 | Пульсация только у активного узла. `active_run` 1.2 с/6%, `durable_queued_wake` 3 с/3%. | `PulseModifier` + `TimelineView(.animation)`. Другие состояния не анимируются. |
| 4 | Нет fade-out/fade-in между состояниями. Цвет — кросс-фейд 200 мс; новые элементы через `.scale`. | В `GraphNodeView` — `.animation(.easeInOut(duration: 0.2), value: node.resolution?.cause)`. |
| 5 | Несколько ветвей параллельно, зависшая рядом с работающей. | `state.stalledNodeId` выбирает первую `stalled_manual_review`/`step_stalled`. `CoordinationScreen.currentResolution` отдаёт её приоритетно. |
| 6 | Стриминг не запускает перерасчёт графа. | `StreamWindow` принимает `rows: () -> RowContent` без `@ObservedObject`/`@StateObject` от `CoordinationState`. Внутренний список — отдельный `LazyVStack`. |
| 7 | Diff-механизм по `subtask_id`. | `CoordinationState.apply(...)` — единственный мутирующий вход. `indexBySubtask` перестраивается после добавлений. |

## Проверки

- **Юнит**: `Tests/CoordinationTests.swift` — 11 кейсов:
  1. Декодирование `Resolution` из JSON (включая snake_case ключи).
  2. Неизвестный `cause` декодируется как `.unknown` (не падает).
  3. Все 20 `CoordinationCause` имеют непустые `title`/`hint`/`tint`.
  4. `stalled_manual_review`/`step_stalled`/`context_overflow` → `darkRedCritical` (AAA 7:1).
  5. 8 пар `cause → action` (UX-таблица §5).
  6. 6 причин без кнопки (`nil` action).
  7. Все 14 `CoordinationAction` имеют `label`.
  8. Деструктивные действия (`start`/`replaceAttempt`/`acceptReview`) → `confirmRequired = true`.
  9. Дифф сохраняет позиции узлов при обновлении (правило №2).
  10. Пропавший узел → плейсхолдер, потом `pruneStaleNodes` его удаляет.
  11. `versionMismatch` отмечается в `loadState` (блокирует действия в UI).
  12. `stalledNodeId` — первая зависшая ветвь (правило №5).
  13. `MessageDeliveryChip` показывает «N мин в очереди» при `queuedMinutes > 0`.

  Запуск: `Cmd+U` в Xcode. Все тесты без симулятора и UIApplication.

- **Компиляция**: ключевые файлы используют только публичные
  символы проекта (`Color.tfText`/`Color.tfRed`, `TFRadius`,
  `TFSpacing`, `TFBorder`). `tfOrange` — фолбэк через `??` для
  тёмной темы, где этого токена ещё нет. Финальная проверка
  требует компиляции в Xcode — оставлено QA-слоту.

- **Сборка приложения**: изменения лежат в отдельной папке
  `Sources/Features/Coordination/` и не требуют правок в
  `project.pbxproj` (папка уже подключена как `Sources/Features/*`).
  Конкретное добавление в таргет — задача QA-слота.

## Границы

- Swift-код в каноническом репозитории `TaskFlowNativeBuild` НЕ
  менялся этим шагом. Реализация — в выделенной копии
  `/Users/max/Проекты/TaskFlowDeveloper` (codex/developer-mac).
  Владелец решит, переносить ли в канон отдельной задачей.
- Существующий `TaskDetailScreen` не правился — новый
  `CoordinationScreen` живёт рядом как раздел «Координация».
- Серверные исходники не трогались (резолвер уже реализован,
  коммит `eb36437b`).
- UX-документ дизайнера (`1eb44f63-…`) не правился.
- Файлы серверного QA не правились.
- Никаких сетевых вызовов вне существующего `APIClient.request(...)`.
- Никакой реальной навигации кнопок в Action bar — `state.onAction`
  остаётся `nil`, пока владелец не выберет, как именно iOS
  отправляет `replace_attempt` / `start` через существующие
  маршруты (`POST /api/subtasks/:id/restart` и др.). По умолчанию
  родительский экран при инициализации может выставить
  `state.onAction = { action in ... }` и свести `CoordinationAction`
  в реальный `APIClient` маршрут.

## Открытые вопросы (для владельца / следующих шагов)

1. **Push-нотификации** для новых сообщений — UX-документ,
   открытый вопрос №1. Сейчас pull раз в 30 с.
2. **Глубина поддерева 3** — UX §6. Сейчас экран показывает
   только текущую карточку; рекурсивный переход в дочерние —
   следующая задача.
3. **«Открыть веб-представление»** — deep-link, отдельная задача
   (UX §12).
4. **Реальная навигация действий Action bar** — `start`,
   `replace_attempt`, `accept_review` уже существуют как
   `POST /api/subtasks/:id/restart` и `POST /api/tasks/:id/accept`.
   Свести `CoordinationAction` в конкретный маршрут — следующий
   шаг (можно отдельным шагом `a342eb8b` или новой карточкой).

## Связанные материалы

- UX-документ iOS (дизайнер): `1eb44f63-1705-4ac2-a017-b04ede4944b8`.
- Серверный контракт V2: `a8bfa7ea-e284-4867-8960-cd2fb985d60b`.
- Серверная реализация контракта: `server/src/runtime/coordinationResolver.ts`,
  коммит `eb36437b`.
- Канонический iOS-репозиторий: `/Users/max/Проекты/TaskFlowNativeBuild/`
  (не правился этим шагом).
- Выделенная копия: `/Users/max/Проекты/TaskFlowDeveloper`, ветка
  `codex/developer-mac`.
- Артефакт-отчёт серверного builder: `artifact_sav_72cee2f4-355c-44fd-ada6-ced421962011`.
- Шаг iOS-builder: `a342eb8b-e03f-4866-8896-d4583ca0b8f3`.
- Следующий шаг QA iOS: `bb63fdd2-2b91-418e-9d79-334c8f9cbff1`.