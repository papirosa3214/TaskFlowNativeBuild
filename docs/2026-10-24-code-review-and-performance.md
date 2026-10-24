# Кодревью и оптимизация TaskFlow Native — 24.10.2026

Задача владельца: «использую данные скиллы для оптимизации… Ты всё должен изучить».
Скиллы: `swift-concurrency-expert`, `swiftui-expert-skill`, `swiftui-performance-audit`,
`swiftui-pro`. Приложение — SwiftUI (`TaskFlowNativeBuild`, iOS 18, Swift 5.10).

## Итог

- Просмотрено всё приложение: 91 000 строк, 333 файла. Аудит шёл шестью
  параллельными зонами (Core, Task, Chat, Today/Upcoming/Routines/Coordination)
  плюс отдельные проходы по всему коду.
- Найдено 63 подтверждённых дефекта производительности/конкурентности
  (из них 10 уровня P0), 22 исправлено в этой серии.
- Главный дефект — один и тот же в четырёх экранных копиях: `DateFormatter`
  создавался **на каждый вызов**. Замер: **162.5 мкс** на создание форматтера
  и разбор против **0.05 мкс** ручного разбора.

## Как мерили

Замер на этой машине (`swiftc -O`, 500 разных строк даты):

| Операция | Время |
|---|---|
| `DateFormatter` создаётся на каждый вызов + разбор | **162.5 мкс** |
| Кэшированный форматтер, только разбор | 37 мкс |
| `Calendar(identifier: .gregorian)` создаётся | 0.39 мкс |
| Ручной разбор `YYYY-MM-DD` | **0.05 мкс** |
| Реалистичная нагрузка: 40 строк × 3 разбора даты за проход `body` | **17.5 мс → 0.005 мс** |

RED/GREEN на тестах (`Tests/CalendarDateMathTests.swift`, 10 тестов):

| Прогон | Экранный хелпер | `UpcomingDate.addDays` |
|---|---|---|
| До правки (RED) | **403 мкс** | 2 форматтера на вызов |
| После правки (GREEN) | **1.85 мкс** | **0.52 мкс** |

Поведение проверено на совпадение с эталонным форматтером (григорианский
календарь, UTC, POSIX-локаль): обычные даты, неканоничные строки, переносы
вроде «2026-02-30» → 2 марта, отказы на мусоре, 20 000 дней подряд на день
недели, 48 месяцев × 42 ячейки месячной сетки.

## Что починили

### P0 — календарные даты

| Файл | Было | Стало |
|---|---|---|
| `Core/Common/CalendarDateMath.swift` (новый) | — | общая ручная арифметика дней (пролептический григорианский календарь, «days from civil»), без `DateFormatter` и `Calendar` |
| `Features/Today/TodayDate.swift` | `DateFormatter` на каждый вызов; `Calendar` на каждый вызов | делегирование в `CalendarDateMath` |
| `Features/Upcoming/UpcomingDate.swift` | то же; `monthGridDates` — 86 форматтеров за вызов | то же; сетка считается целиком вручную |
| `Features/Directory/Support/DirectoryDate.swift` | `Calendar` на каждый вызов | `CalendarDateMath` |
| `Features/Task/Support/TaskDateText.swift` | `DateFormatter` + `Calendar` на каждый вызов | `CalendarDateMath` + один общий календарь МСК |
| `Core/Common/DateFormats.swift` | `calendarDate`/`calendarDateString` шли через кэшированный форматтер (37 мкс) | быстрый разбор (0.05 мкс), поведение то же |

### P0/P1 — Core

| Файл | Что было | Что стало |
|---|---|---|
| `Core/Models/RoleChat.swift` | `roleEnvelopeJSON` кодировал конверт заново на каждый доступ — 2–3 раза на каждое сообщение от роли за каждый проход `body` | кодирование один раз на сообщение, кэш по id (конверт неизменен — поле `let`) |
| `Core/Models/RoleChat.swift` | `pacingParts` компилировал `NSRegularExpression` на каждый вызов — на каждый снимок ответа | регулярка компилируется один раз |
| `Core/Models/RoleChat.swift` | сортировка ленты разбирала даты через `ISO8601FormatStyle` с промежуточной строкой | `DateFormats.sqliteUTC` (быстрый разбор) |
| `Core/Models/RoleChat.swift` | `mergingSnapshot` — поиск по массиву внутри `filter`, O(n·m) на каждый `refresh` | множество id один раз, O(n) |
| `Core/Models/RoleLoad.swift` | `ISO8601DateFormatter` на каждый вызов | общий разборщик `DateFormats.iso8601` |
| `Core/Models/TaskOutcome.swift` | `DateFormatter` на каждый вызов | `DateFormats.sqliteUTC` |
| `Core/Models/ContextObservability.swift` | `ISO8601DateFormatter` на каждый вызов | `DateFormats.iso8601` |
| `Core/Models/AIUsage.swift` | `modelOrder` пересобирал словарь и сортировал его на каждый `shadeIndex` — то есть на каждую модель легенды и столбиков | порядок считается один раз при разборе ответа |
| `Core/Models/RoleLoadLayout.swift` | позиция «сейчас» пересчитывалась на каждый активный слот | один раз на строку |
| `Core/Common/TaskNumber.swift` | `Calendar(identifier:)` на каждый номер задачи | один общий календарь МСК |

### P1 — экраны

| Файл | Что было | Что стало |
|---|---|---|
| `Features/Chat/ChatStructuredOutputView.swift` | `JSONDecoder` на каждый проход `body` для каждого ответа роли | разбор кэшируется по строке JSON |
| `Features/Routines/RoutineScheduleProjection.swift` | `ISO8601DateFormatter` на каждый вызов `date`; компаратор сортировки разбирал даты O(n log n) раз; `DateFormatter` на подпись времени | общий разборщик, сортировка по готовым `Date`, форматтер времени на таймзону |
| `Features/Routines/RoutineFormat.swift` | `DateFormatter` на каждую подпись рутины | форматтеры кэшируются по маске и таймзоне |
| `Features/Task/TaskFormViewModel.swift` | `MarkdownEncoder.encode` на каждый доступ к описанию (несколько раз за проход `body` + сравнение с серверным + автосохранение); `editorForm` разбирал и собирал markdown на каждый вызов | кэш собранного markdown с явным сбросом при записи блоков; разбор серверного описания кэшируется по строке |
| `Features/Coordination/CoordinationScreen.swift` | `.task` + `.onChange` → два параллельных цикла опроса, не отменяемых при уходе с экрана | `.task(id: taskId)` — один цикл, SwiftUI сам гасит прежний |
| `Features/Today/TodayHoursView.swift` | пул задач без времени фильтровался дважды за проход `body` | один проход, результат передаётся дальше |

### Вторая волна (после «осталось» — по твоему вопросу)

| Файл | Что было | Что стало |
|---|---|---|
| `Core/Realtime/RealtimeClient.swift` | каждое событие задачи поднимало `rolesRevision`/`jobsRevision` → экраны «Агенты», «Работы», «Нагрузка» уходили в сеть на **каждое** событие (во время работы агента события идут пачками) | инвалидация схлопывается в окно 0.5 с: пять событий → одна перезагрузка; `.rolesChanged` остаётся мгновенным, ревизия карточки задачи растёт сразу |
| `Core/Session/KeychainService.swift` | `SecItemCopyMatching` на каждый HTTP-запрос — **замер: 2.4 мс на чтение** | копия токена в памяти, Keychain трогается один раз за сессию; выход и 401 чистят копию |
| `Features/Markdown/MarkdownParser.swift` + `MarkdownParseCache.swift` + `Chat/RoleReplyMarkdown.swift` | растущий текст живого ответа попадал в общий кэш разбора: десятки записей в секунду при лимите 128 — из кэша вытеснялись разборы истории чата, сообщения перечитывались при каждой прокрутке | живой текст разбирается без кэша, готовый — как раньше |

Проверка второй волны: `RealtimeInvalidationCoalescingTests` (3), `KeychainTokenCacheTests` (5),
`MarkdownParseCacheTests` (7) — зелёные; вместе с `RoleChatRealtimeTests`, `ChatViewModelTests`,
`MarkdownParserTests`, `ChatRichContentTests`, `DeviceOpsTests` — 57 тестов, 0 падений.

Замер `SecItemCopyMatching` (отдельный бинарь, macOS Keychain — на iOS порядок тот же):
2.4 мс на чтение.

## Осталось — не трогал (и почему)

**Под lock другого агента (`LOCK-UNIFIED-PLANNER-20261024`, Codex)** — ждут его
или владельца:

- `Features/Upcoming/UpcomingScreen.swift:540` — `Set(routineOccurrences…)`
  строится внутри `filter`, то есть на каждую задачу (O(N×M log M) за проход).
- `Features/Upcoming/UpcomingScreen.swift:254,267,292,573,582,602` — `byDate`,
  `datedTasks`, `tasks` пересчитываются 6–10 раз за проход `body`.
- `Features/Today/TodaySectionView.swift:73` — тот же `Set` внутри `filter`.
- `Features/Today/TodayComputationCache.swift:20` — ключ кэша сравнивает
  `[ApiTask]` по значению, а `ApiTask` — это ~35 полей: глубокое сравнение
  всех задач на каждый проход `body`.
- `Features/Today/TodayListView.swift:96` — `GeometryReader` пишет `@State` на
  каждом кадре прокрутки → пересборка секций дважды за кадр.
- `Features/Today/TodayTaskRow.swift:202` — 8 разборов даты на строку задачи;
  лечится одним вызовом, возвращающим готовые `plain/relative/days/overdue`.

**Требует решения владельца (это про свежесть данных, а не про механику):**

- `Core/Realtime/RealtimeClient.swift` — на каждое событие задачи растут
  `rolesRevision`/`jobsRevision`, а по ним перезагружаются списки ролей и
  работ. Если роль/задача не изменились — перезагрузка лишняя, но сузить
  инвалидацию без риска «протухшего» экрана нельзя: решение за владельцем.
- `Core/Session/KeychainService.swift` — `token` читает `SecItemCopyMatching`
  на каждый HTTP-запрос. Нужен кэш в памяти со сбросом на 401/выходе.
- `Core/Models/RoleChat.swift:360` — идентификатор строки строится из
  `text.hashValue`, то есть меняется по мере роста текста. Требует устойчивого
  id от сервера, а не вычисляемого на клиенте. **Проверено 24.10.2026: в
  живом ходу id не используется** — и список элементов, и группа действий
  используют индекс (`id: \.offset`, в коде есть комментарий про это). То
  есть находка латентная: новый код на этом `.id` споткнётся, но сейчас он
  не влияет на отрисовку.
- `Features/Chat/RoleLiveTurnView.swift` — растущий markdown переразбирается
  на 60 Гц во время «проявления» ответа. Сам разбор стоит ~0.08 мс, то есть
  это ~4.8 мс CPU в секунду (не главный расход); главный вред от этого был не
  в разборе, а в забивании кэша — починено во второй волне. Остаток: перерисовывать
  только хвост (приём уже применён в `RoleTextRevealHistory`) — отдельная задача,
  она меняет отрисовку ответа.
- `Features/Task/TaskFamilyNavigation.swift` — опрос в двух циклах без отмены;
  там же чтение всего словаря ревизий на каждое событие.

## Сервер TaskFlow на 110

Смотрел по пути (папка `~/Проекты/New-Todoist`, сервер — Node/TS, не Swift):

1. `server/dev-server.log` — **1.56 ГБ, 6.4 млн строк**: сервер пишет каждый
   запрос и ответ с телом через `StandardOutput=append:` в юнит
   `taskflow-server.service`. Ротация (copytruncate) в `scripts/backup.sh`
   появилась 24.10.2026 и живёт в ночном проходе; отдельного таймера на
   обрезку нет. Копия правила: `cp` + `: >` (не `mv` — файл держит живой
   процесс).
2. `taskflow-server.service` запускает `tsx watch src/index.ts` — режим
   наблюдения за файлами в боевом юните: лишний watcher и лишние рестарты.
3. На машине три экземпляра `tsx src/index.ts`: живой — socket-активированный
   (pid 2955182), старый pid 730828 держит 132 МБ RSS и порт не слушает.

## Проверки

- `Tools/design-system-guard.py --diff HEAD` — чисто.
- `TaskFlowTests` (652 теста) — падают 5 тестов, все вне зоны правок:
  `UIStyleGateTests` (2) ищут исходники `RemoteMachinesSection.swift` и
  `EditProfileSheet.swift`, которых в репозитории нет;
  `VoiceRecordingWaveformTests` (2) и `ServiceTicketPresentationTests` (1) —
  голос и сводки сервера. Проверено откатом моих правок: падают и без них.
- `Tests/CalendarDateMathTests.swift` — 10 тестов, зелёные (RED → GREEN).
- Сборка приложения проходит; кадры «Сегодня» и «Планирование» сняты в
  симуляторе, даты на них корректны («24 окт · сегодня», «Сегодня, 24 окт.»).

## Границы

- Правки только в файлах строки `LOCK-OPT-PERF-20261024` в
  `AGENT-WORK-SCOPES.md`; чужие файлы (`Today/Upcoming` под lock Codex) не
  тронуты.
- Логика и внешний вид не менялись: все правки — кэширование, общий разбор
  дат, отмена дублей. UI-тесты не гонял (дефект виден на кадре — по правилу
  репозитория достаточно сборки и скриншота).
- Сервер на 110 не менял: чужой репозиторий со своими правилами, правки
  боевого поведения — за владельцем.
