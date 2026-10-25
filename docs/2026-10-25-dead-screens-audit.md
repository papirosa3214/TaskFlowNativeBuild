# Аудит мёртвых экранов iOS-клиента — 2026-10-25

Карточка `f6637ef6-1a1c-447e-828b-6ecfe31ff42c`, шаг `5c2ba3f3` (delivery);
пересмотрено по шагу `7a245d00` (builder_fix_2) по замечаниям Лайф-тестировщика.
Проверка на `roles/f6637ef6-1a1c-447e-828b-6ecfe31ff42c`, исходники — `main`
`a7f6adf8`, дерево `Sources` чистое. Ничего не удалено и не переписано:
это отчёт, судьбу каждого экрана владелец решает отдельно.

## Результат

В исходниках нашлось **14 экранов и крупных представлений, которые ни один
живой путь приложения не открывает** — это около 3 900 строк кода. Плюс
следствия: типы и даже целые файлы, которые держатся только на этих экранах
(`TFHeaderBackdrop`, линия текущего времени, выбор машины, окно разбора сводки,
три слоя «Ленты дня») и умрут вместе с ними. Ещё четыре маршрута навигации
объявлены, но никто их не открывает: `.secretaryChat` (за ним экран чата
Помощника) и три из пунктов 12–14.

Самое крупное — раздел «Координация» целиком (5 файлов, 929 строк): экран
состояний карточки V2, лента, граф причин, панель действий. Всё это не
подключено к приложению, хотя для логики есть тесты; сегодня координацию
показывает карточка ответа роли в чате.

Следом идут экраны, до которых не доводит ни одна дорога приложения: «Работа
агента» (`AgentWorkScreen`, 245 строк), «Лента дня» (`TimelineScreen`, 178
строк, и её слои — ещё 216), «Поиск» (`SearchScreen`, 202 строки). Их маршруты
(`.agentWork`, `.timeline`, `.search`) объявлены в `AppRoute`, но ни одна
кнопка, вкладка и пункт меню их не пушит.

Дальше по размеру — «Планирование → Список» (`UpcomingListView`, 351 строка) и
часовая сетка «Сегодня» (`TodayHoursView`, 424 строки): живые экраны давно
другие.

## Как считали

Каждый тип, объявленный как экран или крупное представление, проверен двумя
независимыми способами (методика — раздел 5 спецификации аналитика):

1. **Создание типа** — есть ли вообще `Имя(` или `Имя {` в `Sources`, в том
   числе в собственном файле. Ноль созданий = тип никто не рисует.
2. **Путь открытия** — упоминание в навигации: `AppRoute` (46 маршрутов),
   `RouteDestinationView`, корень вкладок `RootShellView`, шторки
   `.sheet`/`.fullScreenCover`, переходы `NavigationLink`, прямые вызовы.
3. **Обратные зависимости** — какие ещё типы, константы и функции из файла
   используются другими файлами: если файл жив только как поставщик одной
   утилиты, он не «мёртвый целиком».
4. **Следствия** — тип, который создаётся только внутри уже мёртвого файла,
   тоже мёртв (так умирает `TFHeaderBackdrop`).

Метки (по спецификации): **мёртвый** — есть живой двойник, обратных
зависимостей нет; **не подключён** — фича заявлена и покрыта тестами, но
wiring отсутствует; **используется** — опровергнутый кандидат.

## Сводка

**Мёртвые экраны**

- «Работа агента» — `AgentWorkScreen`, 245 строк.
- «Лента дня» — `TimelineScreen`, 178 строк, вместе со слоями
  `TimelineLayers` (216 строк).
- «Поиск» — `SearchScreen`, 202 строки.
- «Список» планирования — `UpcomingListView`, 351 строка.
- Часовая сетка «Сегодня» — `TodayHoursView` (424 строки, включая линию
  текущего времени).
- Строка задачи «Работы агента» — `AgentWorkTaskRow`, 223 строки.
- Лента подзадач карточки — `SubtaskFeedView` + выбор машины
  `SubtaskHostPicker`, 286 строк.
- Карточка и окно разбора сводки сервиса — `NotificationTicketCard` +
  `NotificationTicketDetailSheet`, 361 строка.
- Строка задачи в полосе дня — `UpcomingDayListRow`, ~50 строк.
- Сетка четырёх состояний агентов — `AgentStatusGrid`, 84 строки.
- Поле «Добавить подзадачу» из старой формы — `AddSubtaskRow`, ~25 строк.
- Число на ярлыке «Сегодня» — `TFTodayDateIcon`, ~60 строк.
- Строка задачи списка планирования — `UpcomingTaskRow`, 221 строка (жив
  только её хелпер `model(for:)`, которым пользуется шторка дня).

**Не подключён**

- Раздел «Координация» карточки — `CoordinationScreen` и ещё четыре
  представления (929 строк). Логика покрыта тестами, в приложение не
  подключена ни одна часть.

**Мёртвые маршруты**

- `.secretaryChat` — за ним `SecretaryChatScreen` (`RouteDestinationView.swift:138`).
- `.timeline`, `.search`, `.agentWork(focus:)` — за ними экраны из пунктов 12–14.
  Все четыре своей кнопки не имеют; три последних пытаются открыть только
  мёртвые представления (`AgentStatusGrid.swift:7–10`).

## Что было бы видно владельцу

Обычный ответ на вопрос «куда это ведёт»: никуда. Правка в этих файлах
выглядит в коде сделанной, но на телефоне её не увидеть — ровно случай
заглушки из `TodayScreen.swift`, с которого началась карточка.

## По каждому кандидату

### 1. `UpcomingListView` — «Список» планирования

- Файл: `Sources/Features/Upcoming/UpcomingListView.swift:15`, 351 строка,
  единственный тип в файле.
- Метка: **мёртвый**. Созданий нет нигде; имя встречается только в
  собственном файле, обратных зависимостей нет.
- Чем живёт сейчас: раздел «Планирование» держится на четырёх других
  представлениях, которые выбирает `UpcomingScreen`: «Сегодня»
  (`TodaySectionView`, строка 225), три дня (`UpcomingHoursView`, 239),
  неделя (`UpcomingWeekView`), месяц (`UpcomingMonthView`). Мёртв именно список
  по дням с приклеенными заголовками-днями (`LazyVStack` с
  `pinnedViews: [.sectionHeaders]`, строка 310). Раздел «Список» в живом
  приложении есть — его рисует `TodaySectionView` → `TodayListView`
  (`Sources/Features/Today/TodayListView.swift:85`): это `List` с секциями
  («Входящие», «Ждут вас», «Просроченные», дата, «Предстоящие»), и заголовки
  этих секций тоже прилипают к верхней кромке — `TodayListView` даже
  отдельно замеряет прилипший заголовок и отдаёт его в шапку вкладки
  (строки 123–155).
- Что ещё используется из файла: ничего.
- Что сюда вело: ничего — ни `AppRoute`, ни `NavigationLink`, ни шторки.

### 2. `TodayHoursView` — часовая сетка «Сегодня»

- Файл: `Sources/Features/Today/TodayHoursView.swift:32`, 424 строки;
  внутри же объявлена линия текущего времени `TodayNowLine` (строка 387).
- Метка: **мёртвый**. Созданий нет; четыре упоминания имени вне файла — все
  комментарии в `UpcomingHoursView.swift` (строки 18, 163, 189, 1155:
  «тот же приём, что в `TodayHoursView`»).
- Чем живёт сейчас: та же сетка по дням — `UpcomingHoursView`, её вызывают
  `TodaySectionView.swift:227` (раздел «Сегодня») и `UpcomingScreen.swift:239`
  (режим «три дня»).
- Что из файла ещё используется: ничего.

### 3. «Координация» карточки — не подключена

- Файлы и строки: `CoordinationScreen.swift` (266 строк: экран, окно
  разбора `ResolutionDetailsSheet` 224, строка сообщения `StreamMessageRow`
  200, заглушка ввода 175), `ReasonStrip.swift` (150), `ResolutionGraph.swift`
  (211), `StreamWindow.swift` (185), `ActionBar.swift` (117). Всего 929 строк.
- Метка: **не подключён**. Ни одно из этих представлений не создаётся
  нигде в `Sources`; вне папки `Features/Coordination/` нет ни одного
  упоминания этих типов.
- Почему не «мёртвый»: фича заявлена и проверена — `Tests/CoordinationTests.swift`
  гоняет чистую логику состояний, причин и графа (4 обращения к
  `CoordinationState`), а `CoordinationAPI.swift` описывает контракт
  координации V2: `contract_version=2.0.0`, маршруты `GET /api/coordination/*`,
  снятые с серверного `coordinationResolver.ts`, и два документа-канона —
  `docs/server/coordination-resolver.md` и `docs/ios/coordination-resolver-view.md`.
  То есть у экрана есть заявленная цель и готовый контракт, в отличие от
  остальных находок. Это недоделанная цель, а не мусор.
- Чем живёт сейчас: координацию в чате показывает карточка ответа роли
  `RoleCoordinationCard` (`RoleChatsScreen.swift:1970`).
- Что из файлов ещё используется: `CoordinationState`, `CoordinationCause`,
  `CoordinationCauseColor`, `CoordinationAPI` — только тестами.
- Особенность: комментарий в `CoordinationScreen.swift:7` говорит, что экран
  «рисуется поверх `TaskDetailScreen`» — этого экрана в коде давно нет
  (см. сверку ниже). Комментарий врёт.

### 4. `AgentWorkTaskRow` — строка задачи «Работы агента»

- Файл: `Sources/Features/Chat/AgentWorkTaskRow.swift:180`, 223 строки;
  в файле же `AgentWorkAvatarView` (18) и вспомогательные `AgentWorkDate`,
  `AgentWorkStateTag`.
- Метка: **мёртвый** (весь файл). Созданий нет; имя встречается только в
  собственном заголовочном комментарии.
- Чем живёт сейчас: ту же роль — строка задачи в списке — играет общая
  `DirectoryTaskRow`, но живёт она в живых экранах: «Задачи проекта»
  (`ProjectTasksScreen.swift:306`), «Архив» (`TaskArchiveScreen.swift:127`) и
  «Активность» (`ActivityScreen.swift:95`). Прежняя ссылка на
  `AgentWorkScreen.swift:125` неверна: этого экрана в приложении не видно
  (см. пункт 12).
- Что из файла ещё используется: ничего.

### 5. `SubtaskFeedView` + `SubtaskHostPicker` — лента подзадач

- Файлы: `Sources/Features/Task/Detail/SubtaskFeedView.swift:6` (162 строки),
  `Sources/Features/Task/Detail/SubtaskHostPicker.swift:21` (124 строки).
- Метка: **мёртвый**. `SubtaskFeedView` создаётся нигде; `SubtaskHostPicker`
  создаётся только внутри `SubtaskFeedView` (`:117`), то есть умирает
  следствием.
- Чем живёт сейчас: подзадачи в карточке рисует сам `TaskFormScreen`
  (секция подзадач, поле «Добавить подзадачу» — строки 2892–2933, модель
  `SubtaskDraft`).
- Что из файлов ещё используется: ничего; упоминания вне файлов — только
  комментарии (`SubtaskHostPicker.swift:5`, `TaskFormViewModel.swift:536`)
  и список путей в `Tests/RoleReplyRenderTests.swift:77,101` (тест проверяет,
  что в этих файлах текст роли идёт общим рендером — проверка формальная, она
  существует и без живого экрана).

### 6. `NotificationTicketCard` + `NotificationTicketDetailSheet` — сводка сервиса

- Файлы: `Sources/Features/Directory/Support/NotificationTicketCard.swift:8`
  (136 строк), `NotificationTicketDetailSheet.swift:10` (225 строк).
- Метка: **мёртвый** (оба файла целиком). Карточка не создаётся нигде,
  окно разбора создаётся только карточкой (`NotificationTicketCard.swift:60`).
  Типы `NotificationTicketStyle` и `ServiceTicketStatusCounts` используются
  только этими двумя файлами — значит умирают вместе с ними.
- Чем живёт сейчас: «Состояние системы» строит строки через `SystemSummaryRows`
  (`NotificationsScreen.swift:74`) и `ServiceTicketPresentation`.
- Что из файлов ещё используется: ничего.

### 7. `UpcomingDayListRow` — строка задачи в полосе дня

- Файл: `Sources/Features/Upcoming/UpcomingTaskChip.swift:58`, ~50 строк
  внутри файла на 107 строк.
- Метка: **мёртвый**. Созданий нет; упоминаний вне файла нет.
- Чем живёт сейчас: задачи в неделе и месяце — `UpcomingTaskChip`
  (`UpcomingWeekView.swift:88`, `UpcomingMonthView.swift:198`), в шторке дня —
  `TFTaskRow` (`UpcomingDaySheet.swift:38`).
- Что из файла ещё используется: `UpcomingTaskChip` — живой, файл удалять
  целиком нельзя.

### 8. `AgentStatusGrid` — четыре плитки состояний

- Файл: `Sources/Features/Directory/AgentStatusGrid.swift:3`, 84 строки;
  в файле же живой `ProjectStatusIcon` (41), которым пользуется карточка
  проекта (`ProjectCard.swift:132–134`).
- Метка: **мёртвый** (только сама сетка).
- Чем живёт сейчас: те же четыре состояния показывает живая строка сводки в
  карточке проекта — значок `ProjectStatusIcon` и число для «В работе»,
  «На проверке», «Заблокированы», «Пропали»
  (`Sources/Features/Directory/Support/ProjectCard.swift:119–132`; карточку
  создают `ProjectsScreen.swift:328` и `:347`). Прежняя ссылка на разделы
  «Работы агента» (`AgentWorkScreen.swift:226–229`) неверна: этот экран сам
  недостижим (см. пункт 12). Заодно важно: единственные ссылки самой сетки —
  плитки с переходом на маршрут `.agentWork`, то есть все четыре нажатия вели
  на мёртвый экран.
- Что из файла ещё используется: `ProjectStatusIcon` — живой.

### 9. `AddSubtaskRow` — поле «Добавить подзадачу» старой формы

- Файл: `Sources/Features/Task/Fields/SubtaskFormFieldView.swift:23`,
  ~25 строк; в файле же живая модель `SubtaskDraft`, которой пользуются
  `TaskFormScreen`, `TaskFormViewModel`, `QuickAddTaskView`.
- Метка: **мёртвый** (только само представление). Упоминания вне файла —
  комментарии (`:8`, `:15`).
- Чем живёт сейчас: поле ввода подзадачи прямо в `TaskFormScreen`
  (строки 2892–2933; комментарий `:98` объясняет, что поле перешло на блоки
  текста). Кнопка «Добавить подзадачу после» — `:1851`.

### 10. `TFTodayDateIcon` — число на ярлыке «Сегодня»

- Файл: `Sources/DesignSystem/Navigation/TFTabBar.swift:49`, ~60 строк внутри
  файла на 358 строк.
- Метка: **мёртвый**. Единственное упоминание вне файла — комментарий в
  `RootShellView.swift:48` («У «Сегодня» число накладывает `TFTodayDateIcon`»),
  и он врёт: число рисует `TFPillTabBar` по флагу `showsTodayDate`
  (`RootShellView.swift:296`).
- Что из файла ещё используется: почти весь файл живой — `TFTabBar` (создаётся
  в `RootShellView.swift:416`, когда тумблер «Таббар-пилюля» выключен),
  `TFCreateMenu`, `TFCreateMenuItem`, `TFTabItem`, `TFTabDrawIcon`. Удалять
  можно только сам `TFTodayDateIcon`.

### 11. `UpcomingTaskRow` — строка задачи списка планирования

- Файл: `Sources/Features/Upcoming/UpcomingTaskRow.swift:10`, 221 строка.
- Метка: **мёртвый** по следствию: единственное создание — внутри мёртвого
  `UpcomingListView.swift:316`.
- Что из файла ещё используется: статический хелпер `UpcomingTaskRow.model(for:)`
  живой — им строит строку шторка дня (`UpcomingDaySheet.swift:38`). Файл
  нельзя удалять целиком, только само представление.

### 12. `AgentWorkScreen` — «Работа агента»

- Файл: `Sources/Features/Chat/AgentWorkScreen.swift:24`, 245 строк; в файле же
  `AgentWorkFocus` (строка 8) — значение параметра маршрута.
- Метка: **мёртвый экран**. Единственное создание — `RouteDestinationView.swift:101`,
  то есть ветка маршрута `.agentWork`. Сам маршрут не пушит никто: плитки
  мёртвой сетки `AgentStatusGrid` (`AgentStatusGrid.swift:7–10`), больше
  вхождений нет.
- Чем живёт сейчас: сводку по агентам даёт «Команда»
  (`Sources/Features/Chat/AgentsScreen.swift:24` → `AgentsViewModel.swift:88–97`:
  «N работает · N на проверке · N свободен · N заблокирован»), а счётчики
  четырёх состояний — строка сводки в карточке проекта
  (`ProjectCard.swift:119–132`).
- Что из файла ещё используется: `AgentWorkFocus` — только как тип значения в
  объявлении маршрута (`AppRoute.swift:66`). Удалять экран — вместе с маршрутом
  `.agentWork` или с переносом этого перечисления в `AppRoute`.
- Особенность: файл лежит в `Features/Chat/`, хотя к чату не относится —
  он про задачи агентов, поэтому его легко пропустить при поиске по экранам
  «Обзора» и «Команды».

### 13. `TimelineScreen` + `TimelineLayers` — «Лента дня»

- Файлы: `Sources/Features/Today/TimelineScreen.swift:13`, 178 строк (в файле же
  `TimelineDay` — строка 165 — и функция `timelinePriorityColor` — 171);
  `Sources/Features/Today/TimelineLayers.swift`, 216 строк — три слоя
  («День» — 7, «Неделя» — 71, «Месяц» — 143) и хелпер `timelineFormatEnd` (209).
- Метка: **мёртвый экран, а за ним файл-следствие**. `TimelineScreen` создаётся
  только в `RouteDestinationView.swift:49` (ветка маршрута `.timeline`), а маршрут
  `.timeline` никто не пушит — ни одна вкладка, ни `RootShellView`, ни debug-маршрут.
  Слои `TimelineLayers` создаются только внутри `TimelineScreen.swift:32–34`,
  значит умирают вместе с ним.
- Чем живёт сейчас: день по часам показывает живая сетка `UpcomingHoursView`
  (`TodaySectionView.swift:227`, `UpcomingScreen.swift:239`), а неделя и месяц —
  `UpcomingWeekView` и `UpcomingMonthView`.
- Что из файлов ещё используется: `TimelineDay` и `timelinePriorityColor`
  объявлены в `TimelineScreen.swift`, а зовутся только из `TimelineLayers.swift`.
  То есть эти два файла — одна связка: удалять их надо вместе, по отдельности
  проект перестанет собираться.

### 14. `SearchScreen` — «Поиск»

- Файл: `Sources/Features/Directory/SearchScreen.swift:17`, 202 строки,
  единственный тип в файле.
- Метка: **мёртвый экран**. Единственное создание — `RouteDestinationView.swift:87`
  (ветка маршрута `.search`). Маршрут `.search` нигде не пушится: вхождение
  `.search` в `TFPillTabBar.swift:46` — это роль системной вкладки (`TabRole.search`),
  а не наш маршрут.
- Чем живёт сейчас: поиск есть внутри экранов — поле «Поиск проектов» в
  «Проектах» (`ProjectsScreen.swift:150`) и поиск по загруженным задачам в
  импорте Linear (`LinearImportScreen.swift:185`); общего экрана поиска в
  приложении нет.
- Что из файла ещё используется: ничего.

### 15. Маршруты `secretaryChat`, `timeline`, `search`, `agentWork`

- Метка: **мёртвые маршруты**. Из 46 маршрутов `AppRoute` таких четыре:
  `.secretaryChat` (`AppRoute.swift:106`), `.timeline` (`:17`), `.search` (`:51`)
  и `.agentWork(focus:)` (`:66`). Первый и `.timeline`, `.search` не пушит
  никто; `.agentWork` пытаются открыть только плитки мёртвой сетки
  (`AgentStatusGrid.swift:7–10`), и то безрезультатно.
- Обработка первого — `RouteDestinationView.swift:138` → `SecretaryChatScreen()`;
  остальных — `:48–49`, `:86–87`, `:100–101`.
- Значит, за тремя из них сидят три экрана из пунктов 12–14 — это одна причина,
  а не три разных.
- Чем живёт сейчас: `SecretaryChatScreen` (`RoleChatsScreen.swift:381`)
  объявлен, но создаётся только этой веткой маршрута — то есть экран живой
  лишь на бумаге. Чат с Помощником открывается по маршруту `roleChat(id:)`
  (`RootShellView.swift:300`, `openVoiceChat`).

## Только debug-маршрут или превью

Отдельная категория: эти представления открываются, но **только в отладочной
сборке через переменную окружения** — в релиз не попадают, мёртвыми их считать
нельзя. Все в `#if DEBUG`:

- `TaskFlowApp.swift:46–60` — галерея виджетов `WidgetStateGalleryScreen`,
  предпросмотр записи `VoiceRecordingWaveformPreview`, `AppDiagnosticsPreview`,
  чтение чата `RoleChatRoomScreen.readingPreviewChat`, `AgentChatComposerPreview`,
  предпросмотр документа `MarkdownDocumentPreviewScreen`.
- `RootShellView.swift:130` — панель роли (`TASKFLOW_PANEL_PREVIEW`),
  `:135` — вывод команды (`TASKFLOW_OWNER_COMMAND_PREVIEW`).
- `RootShellView.swift:251` — отладочный автопереход `TASKFLOW_DEBUG_ROUTE`
  (create, quickadd, expand, task, tasksheet, notifications, projects,
  alltasks, settings, serversettings, notes, noteeditor, today, upcoming,
  chat, rolechat, agents, models). Все они открывают настоящие маршруты
  приложения, кроме собственных превью, поэтому «только debug» они не
  становятся. Важно: маршрутов `.timeline`, `.search` и `.agentWork` в этом
  списке нет — то есть экраны из пунктов 12–14 не открываются даже в отладочной
  сборке.
- 18 файлов `Sources` содержат `#Preview` — это предпросмотр в Xcode, не
  маршрут.

Дополнительно: `Sources/Features/Upcoming/UpcomingFilterSheet.swift` (10 строк)
не содержит кода вообще — только комментарий о том, что шторку фильтров
заменило нативное меню 03.09.2026. Файл не экран, но и не нужен.

## Сверка списка аудита от 07.09.2026

| Пункт | Статус сейчас | Доказательство |
| --- | --- | --- |
| `TodayScreen.swift` (294) | закрыт | файла нет; имя встречается только в комментариях `TodayComputation.swift:5,25` |
| `TaskDetailScreen.swift` (502) | закрыт | файла нет; только комментарии (`TaskFormScreen.swift:2035,2107`, `CoordinationScreen.swift:7`) |
| `TaskDetailViewModel` (192) | закрыт | файла нет; только комментарии (`TaskFormViewModel.swift:171,519,536,573`) |
| `TaskJournalView` (300) | **ошибочно включён** | теперь `enum` с хелперами, живёт: `TaskFormScreen.swift:2060,2106` |
| `UpcomingListView` (346) | подтверждён мёртвым | см. пункт 1, 351 строка |
| `TFHeaderBackdrop` (73) | мёртв по следствию | создаётся только `UpcomingListView.swift:83` (мёртвый) и в своём `#Preview` |
| `UpcomingFilterSheet` (65) | закрыт | файла с таким типом нет; остался файл-комментарий на 10 строк |
| `ScreenStub` (30) | закрыт | файла нет; упоминание только в комментарии `RouteDestinationView.swift:5` |

## Ограничения

- Веб-клиент не проверялся: в этой сессии доступен только iOS-репозиторий,
  а веб заморожен (запись от 24.10.2026). Вывод по нему не делался.
- Проверка статическая: экран, который открывают по строковому идентификатору,
  через рефлексию или внешний диплинк вне `AppRoute`, неотличим от «никто не
  открывает». Таких мест в проверенном объёме не нашлось, но утверждать
  «других мёртвых экранов нет» нельзя — только «в проверенном объёме не
  найдено».
- Сборка, тесты и симулятор не запускались: по границам карточки это отчёт.
- Комментарии в коде — не доказательство: два места прямо утверждают
  неверное (`RootShellView.swift:48`, `CoordinationScreen.swift:7`).
- Ничего не удалено: каждый экран из списка ждёт отдельного слова владельца.
- Повторная проверка 25.10.2026 (после замечаний Лайф-тестировщика): заново
  перебраны все объявления типов-представлений (`357` в текущем дереве) —
  класс «ноль созданий» остался тем же, а дополнительно пройдена цепочка
  следствий: тип, который создаётся только внутри уже мёртвого экрана. Так
  добавились три экрана и файл `TimelineLayers`. Код по-прежнему не менялся:
  в ветке только этот документ.

## Приложение: как повторить

```bash
cd <worktree карточки>
git rev-parse --short HEAD          # a7f6adf8
git status --porcelain -- Sources   # пусто

# 1) все объявления представлений
grep -rn --include='*.swift' -E '^(public |internal |private |fileprivate )?(final )?(struct|class) [A-Za-z0-9_]+: .*View' Sources

# 2) создание конкретного типа (пример для трёх кандидатов из пунктов 12–14)
grep -rn --include='*.swift' -E '(^|[^A-Za-z0-9_.])(UpcomingListView|TodayHoursView|AgentWorkScreen|TimelineScreen|SearchScreen)[[:space:]]*[({]' Sources

# 3) обратные зависимости файла
grep -rn --include='*.swift' -w 'UpcomingTaskRow' Sources

# 4) маршруты и их использование (должны остаться только ветки в RouteDestinationView)
grep -n '^    case ' Sources/App/Navigation/AppRoute.swift
grep -rn --include='*.swift' -E '\.(secretaryChat|timeline|search|agentWork)\b' Sources

# 5) следствие: кто создаёт TimelineDayLayer/TimelineWeekLayer/TimelineMonthLayer
grep -rn --include='*.swift' -wE 'TimelineDayLayer|TimelineWeekLayer|TimelineMonthLayer' Sources
```

Результат на `a7f6adf8`: пункт 2 не находит ни одного живого создания
`UpcomingListView`, `TodayHoursView`, `AgentWorkScreen`, `TimelineScreen`
и `SearchScreen` (по одному вхождению на каждый — только ветка в
`RouteDestinationView`); пункт 4 для четырёх маршрутов находит только ветки
обработки — ни одного места, откуда маршрут открывают; пункт 5 показывает,
что три слоя «Ленты дня» создаются только в `TimelineScreen.swift:32–34`.
