# Archive — устаревшие компоненты TaskFlow Native

Сюда перенесены отдельные компоненты, которые больше не используются в
production target, но сохранены как законченные модули (могут пригодиться
позже как образцы архитектуры или как стартовая точка для возврата
функциональности).

## Дата архивирования: 2026-09-11

Источник — разбор мёртвого кода от 11.09.2026. Сам отчёт
(`DEAD-CODE-CLEANUP-REPORT.md`) убран из репозитория 22.09.2026 как
одноразовый: перечень перенесённого целиком повторён ниже, а история правок
лежит в git.

## Структура

| Подпапка | Что внутри | Откуда |
| --- | --- | --- |
| `Keyboard-2026-09-11/` | Своя экранная клавиатура (демо-прототип) | `Sources/Keyboard/` |
| `task-fields-2026-09-11/` | Пять отдельных полей формы задачи (Assignee, Labels, Priority, Project, DueDate) + `FlowLayout` + вырезанные компоненты из `SubtaskFormFieldView`/`AttachmentsFieldView` | `Sources/Features/Task/Fields/` |
| `design-system-2026-09-11/` | Старая шапка экрана (`TFScreenHeader` + `TFHeaderAction`) | `Sources/DesignSystem/Components/` |
| `directory-2026-09-11/` | Старая кнопка «Назад» в Справочнике | `Sources/Features/Directory/Support/` |
| `planner-2026-09-11/` | Старые компоненты чипов проекта (`PlannerProjectChips`, `UpcomingPlannerProjectChips`) | `Sources/Features/Today/`, `Sources/Features/Upcoming/` |
| `planner-2026-11-01/` | Мёртвые файлы планировщика: часовая сетка «Сегодня» (`TodayHoursView`, `TodayHoursLayout`), список «Планирования» (`UpcomingListView`), шторка фильтров (`UpcomingFilterSheet`) | `Sources/Features/Planner/` |
| `task-support-2026-11-01/` | Мёртвый диалог подтверждения задачи (`TaskConfirm`) | `Sources/Features/Tasks/Support/` |
| `ReasonStrip.swift` (в корне архива) | Мёртвая полоса причин и чип исполнителя (`ReasonStrip`, `AssigneeChip`) | `Sources/Features/Coordination/` |

## Дата архивирования: 2026-11-01

Источник — миссия «TaskFlow iOS: единый канон интерфейса и разбивка по смыслу»
(шаг C.1 «Разбивка по смыслу»). Четыре файла планировщика не имели ни одного
вызова: ни в коде, ни в строковых ссылках, ни в тестах. Канон по каждому из них
жив: часовая сетка — `PlannerHoursView`, дневной список — `PlannerListView`,
фильтр — системный `Menu` в `PlannerScreen`.

Файлы перенесены через `git mv`, содержимое не тронуто: история изменений
сохранена, `git log --follow <file>` работает.

### Мёртвый код шага C.4 (2026-11-01)

Тот же день, отдельная волна миссии «Разбивка по смыслу» — шаг C.4 «Заглушки и
мёртвый код». Три файла покинули `Sources/`:

- `TaskConfirm.swift` → `archive/task-support-2026-11-01/`. Диалог подтверждения
  для создания задачи: после того как карточку открыли для уже существующей
  задачи (коммит `056dddf1`), у него не осталось ни одного вызова — ни в коде,
  ни в строковых ссылках, ни в тестах.
- `ReasonStrip.swift` → корень `archive/`. Полоса причин и чип исполнителя в
  координационном экране: 0 вызовов, символы живут только внутри этого файла
  (историческое использование убрано коммитом `cb20e96c`).
- `KnowledgeScreen.swift` — не архивируется, а **удалён**: это был шим-заглушка
  на 9 строк, возвращавший `NotesScreen()`. Замена состоялась в
  `Sources/App/Navigation/RouteDestinationView.swift` (маршрут `AppRoute.knowledge`
  остался и открывает `NotesScreen`).

Живой файл `CoordinationCauseColor.swift` (маппинг `CoordinationTint` → цвет)
переехал не в архив, а в `Sources/DesignSystem/Components/` — это палитра, ей
место в дизайн-системе.

Файлы перенесены через `git mv`, содержимое не тронуто.

## Что НЕ сюда

- Методы сетевого API (`APIClient+Search`, методы `APIClient+Chat`,
  `APIClient+Agents`) — удаляются, не компоненты.
- Заглушки (`ScreenStub`) — удаляются.
- Зарезервированные API (`subtasks`, `claimTask`, `agentRules`, и т.д.) —
  не трогаются.
- `TaskDetailScreen`/`TaskDetailViewModel`/`TaskJournalView` — чистятся
  в `LOCK-120` у Claude Code.

## Как вернуть

Файлы перенесены через `git mv` — история изменений сохранена, можно
посмотреть `git log --follow <file>`.
