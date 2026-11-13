# Аудит кода TaskFlow Native — 14.11.2026

Задача владельца: «изучи проект от и до, скажи что противоречит, что неправильно
работает, что можно сделать проще и лучше».

Как проводился: только чтение. Пять независимых проходов по коду (Core, чат и
дизайн-система, экраны — два блока, документация и конфигурация), затем
перепроверка каждой находки, которую планируется править или вырезать, отдельным
субагентом с обязательным вердиктом «подтверждено / опровергнуто».
Сборка Xcode, тесты и симулятор не запускались — по правилу владельца от
25.10.2026. Поэтому всё, что касается внешнего вида, здесь не оценивается.

Масштаб: `Sources` — 484 файла Swift (App 7, Chat 46, Core 177, DesignSystem 57,
Features 197), `Tests` — 184, `UITests` — 51, `Widgets` — 3. `project.yml`
генерится xcodegen, deployment target iOS 18.0.

---

## Пять системных выводов

1. **Две версии одного продукта живут одновременно.** Старая комната чата
   (`Sources/Features/Roles/RoleChatRoomScreen.swift`, 3071 строка) помечена в
   шапке как «СТАРАЯ ВЕРСИЯ ЧАТА», новые — `Sources/Features/Sessions/`. Но весь
   трафик идёт в старую: на неё ведут `RoleChatsScreen.swift:786`,
   `TaskActivityFeed.swift:179`, `ChatArchiveScreen.swift:54`,
   `AttentionScreen.swift:145`. Дублируется рендерер живого хода
   (`RoleLiveTurnView` 1232 против `SessionLiveTurnView` 890), редьюсер
   (`Packages/NewChatCore/SessionReducer` считается параллельно с
   `SessionViewModel`), лента и обработчик WS.
2. **Несколько источников правды на одни данные.** Два кэша (GRDB `LocalStore` и
   `ResponseCache`), два метода на список задач (мёртвый `taskList` рядом с
   живым `taskListRaw`), три WS-клиента (`RealtimeClient`, `DeviceOpsChannel`,
   `SessionRealtimeClient`), пять модулей дат (`DateFormats`,
   `CalendarDateMath`, `TaskDay`, `DirectoryDate`, `RelativeTime` — в
   `DirectoryDate.swift:1-9` это признано прямо в комментарии), две живые панели
   таббара (`TFTabBar`, `TFPillTabBar`), два рендера таблиц.
3. **Ошибки гасятся `try?`.** Пустой список, нулевой счётчик и «Сохранено» — три
   состояния, которые в интерфейсе выглядят как нормальные данные. Самое дорогое
   следствие — «вернуть чат из архива» не работает никогда (см. раздел 2).
4. **Документация отстала от кода** и местами ведёт агента не туда: по
   `ARCHITECTURE.md` нельзя ни соблюсти правила проверки, ни найти живые экраны.
5. **Репозиторий замусорен.** 362 файла лежат в индексе, хотя `.gitignore` их
   игнорирует (330 файлов `*.xcresult`, 25 `*.mp4`), `.git` — 2,2 ГБ, рядом
   577 МБ `.git-mirror` и 4,1 МБ побайтового дубля графа
   `graft-архив-en-2026-11-11/`.

---

## 1. Что противоречит

### Документы против кода

| Где | Заявлено | Факт |
| --- | --- | --- |
| `ARCHITECTURE.md:31` | «около 190 файлов Swift» | 484 в `Sources` |
| `ARCHITECTURE.md:20` | в `Features` есть `Labels`, нет `Missions`/`Sessions` | папки `Labels` нет; `Missions` и `Sessions` есть и живые |
| `ARCHITECTURE.md:34` | `origin` — Gitea `maksim/taskflow-native-ios` | `origin` — GitHub `papirosa3214/TaskFlowNativeBuild`, Gitea — отдельный remote |
| `ARCHITECTURE.md:76` | «правки интерфейса проверять кадром симулятора» | противоречит правилу владельца от 25.10.2026 |
| `ARCHITECTURE.md:58` | `-destination … name=iPhone 17 Pro` | рабочее устройство — iPhone Air, iOS 27.0 |
| `ARCHITECTURE.md:35` | хук `.claude/hooks/guard-no-remote-sync.sh` | файла нет; фактически `guard_no_remote_sync.py` |
| `ARCHITECTURE.md:22` | Core описан без `Store` (GRDB) и `Text` | обе папки живые |
| `CLAUDE.md:124` | `archive/design-system-2026-09-11` | такой папки нет |
| `DESIGN.md:239,254,255` | три файла-эталона | файлов нет |
| `COMPONENTS.md` | справочник компонентов | ноль упоминаний подсказок (`Sources/DesignSystem/Hints/`), `TFActivityCube`, `Sessions` |
| `archive/README.md:20`, `docs/README.md:29-30` | таблицы и ссылки на файлы | части ссылок нет, `AGENT-WORK-SCOPES.md` вне git |
| `.github/workflows/ci.yml` | сборка на каждый push + automerge | `AGENTS.md` заявляет, что CI и автослияние отключены |

### Правила владельца, нарушенные в коде

- «Нижняя шторка закрывается свайпом, кнопок Закрыть/Готово нет» — нарушено в
  пяти местах: `ChatModelPickerSheet.swift:82,196`,
  `ChatWorkspaceChoice.swift:131`, `ChatComposerControlsView.swift:380`,
  `SelectableTextSheet.swift:20`. Канон — `TFBottomSheet.swift:43-48` («Кнопки
  закрытия нет намеренно»).
- «Выделение = `TFFont.body` 15 pt + bold, обычный текст на 5 % приглушён
  (решение 17.10.2026)» — `RoleReplyMarkdown.swift:277` даёт 0.94 (6 %), а жирный
  берёт отдельную группу `TFChatTypeGroup.emphasis`
  (`AppAppearance.swift:362-394`) со своей шкалой: кегль выделения перестаёт
  быть 15 pt и управляется отдельным регулятором.
- «`ReadableText` не трогать» — правка шкалы `emphasis` задевает `>30` мест
  сразу, потому что компонент общий.

### Конфигурация против правил

- `project.yml:44` и `:69` — `Resources/Fonts` подключён дважды.
- `SWIFT_VERSION: "5.10"` (`project.yml:8`) — такого языкового режима у Swift
  нет (4/4.2/5/6).
- `TaskFlowUITests` в `schemes.TaskFlow.test.targets` (~`:424`) — любой
  `xcodebuild test -scheme TaskFlow` поднимет симулятор, что запрещено.
- Четыре `Info.plist` (app, Widgets, Broadcast, VoiceMessageLab) трекаются в
  git, но генерируются xcodegen — грязное дерево после каждого `xcodegen`.
- `UIBackgroundModes: [location, audio]` (`project.yml:198-203`) при
  «геопозиция никуда не отправляется» — риск вопроса на App Review.
- `SettingsScreen.swift:159` «Системный таббар»: включённое состояние означает
  собственную пилюлю `TFPillTabBar`, не системный `TabView`.

---

## 2. Что работает неправильно

### Критично (падения, потеря данных, утечка между аккаунтами)

| Где | Проблема |
| --- | --- |
| `Features/Overview/CompletionHeatmap.swift:249` | `Dictionary(uniqueKeysWithValues:)` по `task_id`: повторное ревью задачи → `Fatal error: Duplicate values for key` |
| `Features/Tasks/TaskFormScreen.swift:212` | тот же приём по `id` карточек |
| `Core/Store/LocalStore.swift:108` | `UPDATE chat SET …, closed_at = NULL` — столбца `closed_at` нет в схеме `LocalDatabase.swift`; ошибка SQLite глотается `try?` в `ChatArchiveScreen.swift:106` → «вернуть из архива» не работает никогда |
| `Core/LiveActivityService.swift:197` | перетирает единственный слот `realtime.onEvent`, который держит `TaskFlowApp.swift:240`: пока висит островок, события сокета не доходят до сторов |
| `Core/Session/SessionStore.swift:140-146` + `App/TaskFlowApp.swift:178-185` | выход чистит Keychain и `LocalStore`, но не `ResponseCache`, не `ClosedTasksStore` (`closed-tasks.json`), не `ComposioCatalogCache`, и не сбрасывает сторы в памяти → данные прошлого пользователя на устройстве |
| `Features/Settings/SettingsScreen.swift:141` | тумблер «Вход по Face ID» ничего не защищает: `evaluatePolicy` в проекте нет, только `canEvaluatePolicy` для определения сенсора |
| `Features/Settings/SecretsScreen.swift:143`, `ServiceAccountsScreen.swift:298`, `ProviderDetailScreen.swift:321` | секреты и токены кладутся в общий `UIPasteboard` без `.localOnly` (уезжают по Handoff/Universal Clipboard) |

### Серьёзно (данные и поведение)

| Где | Проблема |
| --- | --- |
| `Features/Projects/ProjectTasksScreen.swift:85` | статусные фильтры не ограничены проектом — на экране проекта видны задачи других проектов |
| `ProjectTasksScreen.swift:285-296` | дерево пересобирается на каждую строку (O(rows×n) в `body`) и читает `relationshipTasks` вместо `source` → подзадачи иногда не показываются |
| `Features/Tasks/TaskFormViewModel.swift:330-392` | `loadIfNeeded()` грузит всегда и перезаписывает несохранённый текст карточки при push/реалтайме; готовый механизм слияния `adoptServerChanges` (`:489-499`) не используется |
| `Features/Knowledge/NoteEditorViewModel.swift:88-100` | «Сохранено» ставится безусловно, даже если правка не уехала; `catch` не хранит причину |
| `Features/Roles/RoleChatRoomScreen.swift:1782` | свои сообщения сопоставляются по равенству текста, а не по id |
| `RoleChatRoomScreen.swift:2893` | `deliver()` под `guard !isSending` без очереди: «Повторить» во время другой отправки молча ничего не делает |
| `Core/Store/SyncEngine.swift:69` | догрузка сообщений гейтится флагом, который ставится только при первом открытии чата (курица-и-яйцо) |
| `Chat/Output/RoleReplyMarkdown.swift:41` | при пустых серверных блоках рисуется «Не удалось получить подготовленное содержимое»; `ChatStructuredOutputView.swift:205-215` загоняет туда все списки |
| `Packages/NewChatCore/SessionReducer.swift:34-43` | `transientAssistantText` копится, но не читается; редьюсер всё равно гоняется на каждое событие |
| `Features/Inbox/AttentionScreen.swift:92-104` | четыре пути загрузки; `refreshable` молча не работает, если идёт опрос |
| `Features/Activity/AIUsageScreen.swift:33-39,301-313` | разделы JEV/OpenCode исчезают при нулевом расходе ролей; `loading` залипает навсегда при смене периода |
| `Features/Secretary/SecretaryVoiceScreen.swift:95-127` | при ошибке после `presentation.begin` не отключается комната и не закрывается Live Activity |
| `Features/ServiceNotifications/NotificationsScreen.swift` | лента уведомлений объявлена (`notificationRow`, `visibleNotifications`, `markAllRead`) и нигде не рисуется: уведомления грузятся, приходят по WS и не видны |
| `Features/Roles/AgentsScreen.swift:226-236` | владельцу профиль роли недостижим: тап открывает редактирование |

### Производительность и трафик

- `ChatFeedVirtualList.swift:369-377` — в `willDisplay` запоминается *оценка*
  высоты как измеренная, кэш самоподтверждается → лента прыгает.
- `RoleChatsScreen.swift:288` — каждое событие сокета запускает полную
  перезагрузку списка и запись в базу, без коалесера.
- `APIClient.swift:266` — любая не-GET мутация (реакция, «прочитано»)
  инвалидирует кэш ролей: `/roles` до 839 КБ на каждый тап.
- `ProjectsScreen.swift:230-247` — сводка по проектам пересчитывается дважды за
  проход `body` (O(P×T)×2 на кадр).
- `ProjectsScreen.swift:255` + `TaskStore.loadArchive()` — ради счётчика
  «в архиве» качается весь архив.
- `TaskCardContent.swift:2966-3008` — «загрузить если пусто» без флага загрузки:
  две карточки дают двойные полные загрузки задач/проектов/меток.
- `PlannerScreen.swift:211-231` — ревизия календаря зависит от всех задач,
  `DateFormatter` создаётся на каждый вызов.
- `RoleTranslation.swift:47` — четыре растущих словаря без вытеснения.
- `ProgressScreen`-подобные экраны создают `APIClient()` прямо в вью
  (`TaskCardContent.swift` — шесть штук в одном файле) мимо окружения.

---

## 3. Что можно сделать проще

1. **Дочить миграцию на «Сессии» и удалить старую комнату** — минус 3071 строка,
   минус второй рендерер живого хода, минус второй обработчик WS.
2. **Одна точка очистки данных пользователя**: `wipeUserData()` = LocalStore +
   ResponseCache + `closed-tasks.json` + in-memory кэши; на выходе и на 401.
3. **Один `APIClient` из окружения** вместо `APIClient()` в десятках мест.
4. **Один модуль дат** с Москвой по умолчанию вместо пяти.
5. **Один шаблон `load`/`mutate` для сторов**: `CancellationError` сегодня
   отсекается в `ProjectStore`, но не в `LabelStore`.
6. **Убрать дубли и мёртвый код** (список после перепроверки — раздел 5).
7. **Разнести файлы-монстры**: `TaskCardContent.swift` 3383,
   `RoleChatRoomScreen` 3071, `CollaborationPlanView` 1498,
   `RoleChat.swift` 1391.
8. **Привести документы в соответствие с кодом** одной правкой и решить судьбу
   `.github/workflows/ci.yml`.
9. **Почистить git-индекс**: `git rm -r --cached` по
   `git ls-files -ci --exclude-standard` (362 файла), `/.git-mirror/`,
   `/graft-архив-*/`, `/*.log`, `outputs/`, `ui-snapshots/`, `mockups/`, PNG в
   корне. Плюс 13,7 ГБ `build_check` + `build_dev` на диске.

---

## 4. Мусор и дубли в рабочем дереве

| Объект | Объём | Статус в git | Что делать |
| --- | --- | --- | --- |
| `.git-mirror/` | 577 МБ | не трекается, не игнорируется | `/.git-mirror/` в `.gitignore` или вынести из проекта |
| `graft-архив-en-2026-11-11/` | 4,1 МБ, 264 файла | не трекается; `manifest.json` побайтово равен `graft/manifest.json` | удалить, правило расширить до `/graft*/` |
| `graft-build-ru.log`, `graft-then-server.log`, `.graft-then-server.sh` | ~70 КБ | не трекается | в `.gitignore` |
| `docs/**/*.xcresult/**` | 330 файлов, два блоба по 8,5 МБ | **трекаются** вопреки `.gitignore:55` | `git rm -r --cached` |
| `docs/**/*.mp4` + `frames/`, `frames2/` | 25 файлов, 37 МБ (плюс 68 МБ кадров) | трекаются | снять с индекса, оставить 1–2 кадра |
| `.superpowers/` | 9 файлов | трекаются, хотя игнорируются | снять с индекса |
| `outputs/`, `ui-snapshots/`, `mockups/`, PNG в корне, `2026-11-08-…-spec.md` | 4,7 МБ + 7,3 МБ + 884 КБ | частично трекаются | перенести в `docs/<инициатива>/` или снять с индекса |
| `build_check/` 5,8 ГБ, `build_dev/` 2,9 ГБ, `build_device/` 5,0 ГБ | 13,7 ГБ | игнорируются корректно | оставить `build_device`, остальные — только с разрешения владельца |

Сквозное наблюдение: корень проблемы — 362 файла, попавшие в индекс до
появления `.gitignore`. Пока их не снять, любые новые правила игнора работают
только для новых файлов.

---

## 5. Перепроверка субагентами — что подтвердилось, а что нет

Каждый пункт, который планировалось править или вырезать, отдан отдельному
ревьюеру с заданием: подтвердить или опровергнуть по коду, указать точные
`file:line`, назвать риск правки и нужность теста. Ветка `audit/code-2026-11-14`
создана от `main` (`1c56c7f9`) до начала работ.

### Опровергнуто — править не нужно

| Находка | Почему |
| --- | --- |
| `LiveActivityService.swift:197` перетирает подписку приложения | Там **свой** экземпляр `RealtimeClient` (`:104`), а `TaskFlowApp.swift:240` пишет в слот другого объекта; общий клиент островок слушает через `addObserver` (`:145-147`). Остаётся только гигиена: переписать на `addObserver`, чтобы не трогать слот повторно |
| `ChatHTMLView.swift:62` кнопка «Закрыть» | Это `fullScreenCover`, свайпом не закрывается — кнопка нужна |
| Подпись «Системный таббар» (`SettingsScreen.swift:159`) | Верна: `isPillTabBarEnabled == true` → `TFPillTabBar` на системном `TabView`; выключено → свой `TFTabBar` |
| «`Resources/Fonts` дублируется в проекте» | В `project.pbxproj` дубля нет (xcodegen схлопывает): одна группа, 24 ttf по одному разу. В `project.yml` блок действительно продублирован — косметика |
| `RoleReplyMarkdown` кегль выделения «нарушает закреплённое 15 pt» | На дефолте `.emphasis` = `baseSize: 15` = `TFFont.body` + bold, решение держится; реальное расхождение — в документе (там «5 %», в коде `0.94`) и в том, что у группы свой ключ `taskflow_chat_type_emphasis` |
| `archive/README.md:20` | Строка цела; битая — `:21` (`design-system-2026-09-11/`) |
| `COMPONENTS.md` без `Sessions` | `Sessions` — экран, а не компонент; претензия верна только для `TFActivityCube`/`TFActivityStatus` и подсказок |
| `Dictionary(uniqueKeysWithValues:)` как живая авария | Механика падения верна, но триггер недостижим: `task_id` — `PRIMARY KEY` в `task_review_history` (в живой базе 397 строк, дублей 0), `branch_cards` идут через `UNION` по `tasks.id`. Правим как защиту от будущего контракта |
| `loadIfNeeded` «затирает всё» | Путь тихого обновления защищён `adoptServerChanges`, автосохранение через 400 мс. Окно потери узкое: закрытие вложенной шторки, возврат из связанной задачи, офлайн, висячие вложения |

### Подтверждено и уточнено

- `LocalStore.swift:108` — `closed_at` в схеме нет (единственная миграция `v1` в
  `LocalDatabase.swift:67-136`), ошибка глотается `try?` в
  `ChatArchiveScreen.swift:106`. Строка скопирована с сервера
  (`server/src/lib/chatArchive.ts:98`, там таблица `chats` и `closed_at` есть).
  Сломан не серверный возврат из архива (экран перечитывает список), а локальный
  кеш: чат остаётся скрытым в первом кадре и в офлайне. Дополнительно: `showChat`
  не обновляет `payload_json`, а `RoleChat.archivedAt` читается из него
  (`RoleChat.swift:42,70`) — чище писать в стор ответ `unarchiveRoleChat`
  (`APIClient+RoleChats.swift:96`).
- Биометрия: `evaluatePolicy` — **0 совпадений** по `Sources/`; токен лежит
  `kSecAttrAccessibleAfterFirstUnlock` (`KeychainService.swift:100`). Дешевле и
  честнее снять тумблер; доделывать разблокировку — отдельная работа с тестом.
- Выход: кроме `ResponseCache`/`ClosedTasksStore`/`ComposioCatalogCache` остаются
  in-memory сторы (`TaskFlowApp.swift:41-44`), `RolesCache` (до 640 КБ),
  `UserDefaults` (`roleChat.mode.*`, `roleChat.model.*`, `taskflow_settings_*`),
  аватарки ролей, `device-token` в Keychain. Первый кадр после входа может
  рисоваться из кэша чужой сессии (`APIClient.swift:89-96` — 21 место
  `cachedXxx()`); `ClosedTasksStore` вообще не делает сетевого шага — снимок
  показывается из файла. `LocalStore.clearAll` без `VACUUM` — удалённые строки
  остаются в свободных страницах базы.
- Секреты в буфере: `localOnly` в проекте — 0 совпадений, хелпера нет;
  копируются именно значение секрета (`SecretsScreen.swift:143`) и API-токен
  (`ServiceAccountsScreen.swift:298`); `ProviderDetailScreen.swift:321` — короткий
  код OAuth-устройства, риск низкий.
- `ServiceNotificationsClient.swift:10` — адрес можно выводить из
  `APIClient.baseURL` (порт 5198), таймаут задать явно (сейчас 60 с).
- `SecretaryVoiceScreen.swift:95-127` — в `catch` не вызываются `presentation.end`,
  `disconnect`, `requestStop`, `endVoiceActivity`; откат стоит вынести в
  `abandonCall(...)` и звать из `catch` и из `didDisconnectWithError`.
- Мёртвое — подтверждено по 0 вызовов: `taskList`/`TaskListPage`
  (`APIClient+Tasks.swift:69,85-106`), `deleteTask(id:)` (`:272`),
  `archiveDate` (`TaskArchiveScreen.swift:179`), `isCustomKeyboardEnabled`
  (`SettingsViewModel.swift:29-40,58,68`), `isSendingVoice` (`ChatVoiceComposer.swift:76`),
  `sessionControls` (`:39-43`), `stretches` (`ChatComposerPill.swift:40`), лента
  уведомлений целиком (`NotificationsScreen.swift:18-20,195-269,271-341,396-407`)
  вместе с `serviceTicketDetails`/`dayCounts` и `resolutionSheetItem`.
- **Не мёртвое, а недовыложенное:** `projectArchiveSection`
  (`TaskArchiveScreen.swift:134`) тянет целую готовую секцию «Проекты» в архиве;
  `onSendVoice` — весь механизм отправки аудио в комнате
  (`RoleChatRoomScreen.swift:59-60,168,1308,1320,1561,2982,3037`), сейчас голос
  ходит только расшифровкой в черновик; `transientAssistantText` — единственное
  место, где копятся дельты стрима (`SessionReducer.swift:36`).
- Маршруты: `.upcoming` — корень вкладки «Входящие» (единственный вход в
  `AttentionScreen`); `.chatRole(id:)` — вход в комнаты из ряда историй
  (`ChatStoriesHeader.swift:196`); `.activity` ведёт в `AIUsageScreen`, а не в
  `ActivityScreen` — расхождение имени и экрана; `.noteCreate`/`.projectCreate`
  живые, но за двумя выключенными по умолчанию тумблерами
  (`SettingsScreen.swift:160,165`).
- `xcodebuild test -scheme TaskFlow` поднимает симулятор, потому что в
  `test.targets` схемы лежат все три бандла (`project.yml:424,432`). Перенос
  UI-тестов в отдельную схему сам по себе симулятор не убирает: `TaskFlowTests`
  тоже iOS-бандл.
- `SWIFT_VERSION: "5.10"` — значение недопустимое (`swiftc -swift-version 5.10`
  отвечает `invalid value`), сейчас маскируется нормализацией Xcode. После
  правки обязательна одна инкрементальная сборка.
- `ci.yml` в HEAD: сборка на `macos-26` на каждый push и `gh pr merge` в job
  `automerge` — прямо против решения от 05.11.2026. Включён ли Actions
  фактически, офлайн не установить.

---

## 6. План работ

Статусы: `[ ]` — не начато, `[~]` — проверено субагентом, `[x]` — сделано.

### Очередь A — падения и потеря данных
- [~] `CompletionHeatmap.swift:249`, `TaskFormScreen.swift:212` — заменить
  `uniqueKeysWithValues` на `Dictionary(_:uniquingKeysWith:)`.
- [~] `LocalStore.swift:108` — убрать `closed_at` из UPDATE.
- [~] `LiveActivityService.swift:197` — перейти на `addObserver`, слот `onEvent`
  убрать.
- [~] `TaskFormViewModel.swift:330-392` — слияние вместо перезаписи.

### Очередь B — данные пользователя
- [ ] `wipeUserData()` на выходе и на 401 (перепроверено, объём работ понятен:
  `ResponseCache`, `ClosedTasksStore.reset()`, `ComposioCatalogCache`,
  `RolesCache`, четыре стора в памяти, `VACUUM` в `clearAll`).
- [~] `UIPasteboard` с `.localOnly` — перепроверено, хелпера в проекте нет,
  замена точечная (2 реальных секрета + 1 код устройства).
- [ ] биометрия: снять тумблер (дешевле) или доделать `evaluatePolicy` — нужно
  слово владельца.
- [~] `ServiceNotificationsClient` — адрес из `APIClient.baseURL`, таймаут 15 с.

### Очередь C — мёртвый код и дубли
- [~] перепроверка достижимости: `taskList`, `TaskListPage`, `deleteTask`,
  `projectArchiveSection`, `archiveDate`, `isCustomKeyboardEnabled`,
  `stretches`, `sessionControls`, `onSendVoice`, `isSendingVoice`,
  `transientAssistantText`, лента уведомлений.

### Очередь D — документы и конфигурация
- [~] правка `ARCHITECTURE.md`, `COMPONENTS.md`, `DESIGN.md`, `CLAUDE.md`,
  `archive/README.md`, `docs/README.md`.
- [~] `project.yml`: двойной `Resources/Fonts`, `SWIFT_VERSION`, UI-тесты вне
  схемы `TaskFlow`, `Info.plist` из индекса.
- [~] `.github/workflows/ci.yml` — только по слову владельца.

### Очередь E — требуют решения владельца, не правятся молча
- Лента уведомлений: вернуть в интерфейс или вырезать ~200 строк
  (`NotificationsScreen` рисует только сводку `SystemSummaryRows`, а комментарий
  в коде обещает «поток внутри» — это может быть регресс, а не мёртвый код).
- Отправка голосового как аудио: доделать или вырезать весь механизм.
- Секция «Проекты» в архиве (`projectArchiveSection`): подключить или удалить.
- `transientAssistantText`: доделать потоковый предпросмотр или вырезать.
- Уведомления об ошибке после начала звонка (`SecretaryVoiceScreen`).
- Старая комната роли: удалять после миграции — это решение о продукте.
- `0.94 → 0.95` в `RoleReplyMarkdown.swift:277` — смена вида всего приложения.
- `git rm --cached` четырёх сгенерированных `Info.plist`.
- Чистка git-индекса (362 файла), удаление `build_check`/`build_dev`,
  судьба `.github/workflows/ci.yml`.
- `SWIFT_VERSION: "5.10" → "5.0"` — правка простая, но требует сборки.
