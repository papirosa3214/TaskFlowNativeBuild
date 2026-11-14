# Аудит кода TaskFlow Native — 14.11.2026

Задача владельца: «изучи проект от и до, скажи что противоречит, что неправильно
работает, что можно сделать проще и лучше».

Как проводился: только чтение. Пять независимых проходов по коду (Core, чат и
дизайн-система, экраны — два блока, документация и конфигурация), затем
перепроверка каждой находки, которую планируется править или вырезать, отдельным
субагентом с обязательным вердиктом «подтверждено / опровергнуто».
Сборка Xcode, тесты и симулятор не запускались — по правилу владельца от
25.10.2026. Поэтому всё, что касается внешнего вида, здесь не оценивается.

Масштаб на момент первого прохода: `Sources` — 484 файла Swift (App 7, Chat 46,
Core 177, DesignSystem 57, Features 197), `Tests` — 184, `UITests` — 51,
`Widgets` — 3. После работ в ветке `audit/code-2026-11-14`: `Sources` — 486
(+`SafePasteboard.swift`, +`ChatCacheRow.swift`), `Tests` — 185
(+`ChatCacheRestoreTests.swift`), остальное без изменений. `project.yml`
генерится xcodegen, deployment target iOS 18.0.

---

## Как читать этот документ

Документ писался в три захода, и его части отвечают на разные вопросы:

- разделы 1–4 — **первоначальные находки** (14.11, до перепроверки; строки
  оставлены как были — это история аудита);
- раздел 5 — **вердикты перепроверки**: что подтвердилось, что опровергнуто;
- раздел 6 — **что фактически сделано** в ветке и что осталось.

Главнее всего сводка ниже. Если строка в разделе 1 или 2 расходится со сводкой,
верна сводка: там сегодняшнее состояние, в разделах 1–2 — то, как находка
выглядела при обнаружении.

Три состояния у каждой находки:

- **исправлено** — правка в ветке, назван коммит и проверка;
- **остаётся** — подтверждено, но не правилось: нужен объём работ или слово
  владельца (раздел 6, очередь E);
- **опровергнуто** — перепроверка не подтвердила, править не нужно
  (раздел 5).

### Сводка состояния на 14.11.2026

| Находка | Вердикт | Состояние |
| --- | --- | --- |
| `CompletionHeatmap.swift:249`, `TaskFormScreen.swift:212` — `uniqueKeysWithValues` | подтверждено (триггер недостижим, правим как защиту от будущего контракта) | **исправлено** `9b76b802` |
| «Вернуть чат из архива»: `LocalStore` писал в несуществующий столбец, а `payload_json` не обновлял | подтверждено | **исправлено** `9b76b802` + эта работа: в кеш идёт тело ответа сервера (`ChatCacheRow`, `LocalStore.restoreChat`), признаки архива и закрытия снимаются и в столбце, и в модели. Тест без симулятора — `Tools/test_chat_cache_restore.py`, полный путь через SQLite — `Tests/LocalDbSyncTests.swift` (нужен iOS-бандл) |
| `LiveActivityService.swift:197` перетирает подписку на сокет | **опровергнуто** — свой экземпляр клиента | не правим |
| Выход из аккаунта: остаются `ResponseCache`, `ClosedTasksStore`, `ComposioCatalogCache`, сторы в памяти | подтверждено | **остаётся** — объём работ понятен, нужно решение владельца |
| Биометрия: тумблер «Вход по Face ID» ничего не защищает (`evaluatePolicy` — 0 мест) | подтверждено | **остаётся** — нужно слово владельца: снять тумблер или доделать |
| Секреты уходят в общий `UIPasteboard` | подтверждено | **исправлено** `a7bdceb4` (`SafePasteboard.copySecret`) |
| Документы расходятся с кодом (`ARCHITECTURE.md`, `COMPONENTS.md`, `DESIGN.md`, `archive/README.md`, `docs/README.md`) | подтверждено | **исправлено** `1d0570be`, кроме одной строки: `docs/README.md:29` говорит «в Git каталог не входит» про `docs/реестр-сводка.md`, а файл отслеживается; относительные ссылки в `DESIGN.md`, задеты той правкой, — эта работа |
| `CLAUDE.md:124` — ссылка на `archive/design-system-2026-09-11` | подтверждено (папки нет) | **остаётся** — вне правки `1d0570be` |
| `.github/workflows/ci.yml` — сборка на push и `automerge` | подтверждено | **остаётся** — только по слову владельца |
| `project.yml`: двойной `Resources/Fonts`, `SWIFT_VERSION: "5.10"`, UI-тесты в схеме, четыре `Info.plist` в индексе | подтверждено | **остаётся** — правка конфигурации требует сборки |
| Мёртвый код с нулём вызовов | подтверждено поимённо | **исправлено частично** `59d7d625`: `taskList`/`TaskListPage`, `deleteTask(id:)`, `archiveDate`, `isSendingVoice`. Остальное — не мёртвое или решение владельца |
| Лента уведомлений не рисуется; `projectArchiveSection`, `onSendVoice`, `transientAssistantText` недовыложены | подтверждено | **остаётся** — решение о продукте (очередь E) |
| Два чата, два кэша, пять модулей дат, файлы-монстры, 362 файла в индексе | подтверждено | **остаётся** — отдельные работы, не правки «по пути» |

---

## 1. Что противоречит

### Документы против кода

Все строки, кроме отмеченных «остаётся», исправлены в `1d0570be`.

| Где | Заявлено | Факт | Статус |
| --- | --- | --- | --- |
| `ARCHITECTURE.md:31` | «около 190 файлов Swift» | 484 в `Sources` (486 после правок ветки) | исправлено `1d0570be` |
| `ARCHITECTURE.md:20` | в `Features` есть `Labels`, нет `Missions`/`Sessions` | папки `Labels` нет; `Missions` и `Sessions` есть и живые | исправлено `1d0570be` |
| `ARCHITECTURE.md:34` | `origin` — Gitea `maksim/taskflow-native-ios` | `origin` — GitHub `papirosa3214/TaskFlowNativeBuild`, Gitea — отдельный remote | исправлено `1d0570be` |
| `ARCHITECTURE.md:76` | «правки интерфейса проверять кадром симулятора» | противоречит правилу владельца от 25.10.2026 | исправлено `1d0570be` |
| `ARCHITECTURE.md:58` | `-destination … name=iPhone 17 Pro` | рабочее устройство — iPhone Air, iOS 27.0 | исправлено `1d0570be` |
| `ARCHITECTURE.md:35` | хук `.claude/hooks/guard-no-remote-sync.sh` | файла нет; фактически `guard_no_remote_sync.py` | исправлено `1d0570be` |
| `ARCHITECTURE.md:22` | Core описан без `Store` (GRDB) и `Text` | обе папки живые | исправлено `1d0570be` |
| `CLAUDE.md:124` | `archive/design-system-2026-09-11` | такой папки нет: `TFScreenHeader`/`TFHeaderAction` вырезаны `e4ddd413` | **остаётся** |
| `DESIGN.md:239,254,255` | три файла-эталона | файлов нет; эталоны заменены на живые (`TaskCardContent.swift:493`, `RoleLoadScreen.swift:53`, `SettingsScreen.swift:216`), назначение каждой ссылки сверено с кодом | исправлено `1d0570be` + эта работа (префикс `../` у трёх ссылок) |
| `COMPONENTS.md` | справочник компонентов | ноль упоминаний подсказок (`Sources/DesignSystem/Hints/`) и `TFActivityCube` | исправлено `1d0570be` |
| `archive/README.md:21` | строка про `design-system-2026-09-11/` | каталога не было никогда | исправлено `1d0570be` |
| `docs/README.md:29-30` | ссылки на `реестр-сводка.md` и `AGENT-WORK-SCOPES.md` | ссылки на неотслеживаемые файлы заменены путями (`1d0570be`), но утверждение «в Git не входит» верно только для реестра: `docs/реестр-сводка.md` отслеживается (коммит `e7b07a49`), правила в `.gitignore` для него нет | частично исправлено `1d0570be`, **остаётся** |
| `.github/workflows/ci.yml` | сборка на каждый push + automerge | `AGENTS.md` заявляет, что CI и автослияние отключены | **остаётся** |

Ещё один факт, найденный при этой правке и не исправленный: в `DESIGN.md`
осталось 18 ссылок с префиксом `../Sources/…`. Документ лежит в корне
репозитория, поэтому `../` лишний и ссылки не открываются; тронуты и исправлены
только те три, что задеты правкой `1d0570be`.

### Правила владельца, нарушенные в коде

- «Нижняя шторка закрывается свайпом, кнопок Закрыть/Готово нет» — нарушено в
  пяти местах: `ChatModelPickerSheet.swift:82,196`,
  `ChatWorkspaceChoice.swift:131`, `ChatComposerControlsView.swift:380`,
  `SelectableTextSheet.swift:20`. Канон — `TFBottomSheet.swift:43-48` («Кнопки
  закрытия нет намеренно»). **Остаётся**: это вид интерфейса, правка без
  поручения владельца не делается.
- «Выделение = `TFFont.body` 15 pt + bold, обычный текст на 5 % приглушён
  (решение 17.10.2026)» — **опровергнуто** (§5): на дефолте `.emphasis` =
  `baseSize: 15` + bold, решение держится. Реальное расхождение — в документе
  (там «5 %», в коде `0.94`) и в том, что у группы `TFChatTypeGroup.emphasis`
  (`AppAppearance.swift:362-394`) свой ключ `taskflow_chat_type_emphasis`.
  Не правим.
- «`ReadableText` не трогать» — правка шкалы `emphasis` задела бы `>30` мест,
  потому что компонент общий. **Опровергнуто**: правки не требуется.

### Конфигурация против правил

| Где | Что | Статус |
| --- | --- | --- |
| `project.yml:44`, `:69` | `Resources/Fonts` подключён дважды | **остаётся** (в собранном проекте дубля нет, xcodegen схлопывает) |
| `project.yml:8` | `SWIFT_VERSION: "5.10"` — такого режима у Swift нет (4/4.2/5/6) | **остаётся**, правка требует сборки |
| `project.yml:424,432` | `TaskFlowUITests` в `test.targets` схемы — любой `xcodebuild test -scheme TaskFlow` поднимает симулятор | **остаётся** |
| `Info.plist` (app, Widgets, Broadcast, VoiceMessageLab) | трекаются в git, но генерируются xcodegen — грязное дерево после каждого `xcodegen` | **остаётся** |
| `project.yml:198-203` | `UIBackgroundModes: [location, audio]` при «геопозиция никуда не отправляется» — риск вопроса на App Review | **остаётся** |
| `SettingsScreen.swift:159` | «Системный таббар»: подпись верна (`TFPillTabBar` на системном `TabView`) | **опровергнуто** |

---

## 2. Что работает неправильно

Строки без пометки — подтверждены и **остаются открытыми**. Пометки:
`исправлено` — сделано в ветке, `опровергнуто` — не правим (раздел 5).

### Критично (падения, потеря данных, утечка между аккаунтами)

| Где | Проблема |
| --- | --- |
| `Features/Overview/CompletionHeatmap.swift:249` | `Dictionary(uniqueKeysWithValues:)` по `task_id`: повторное ревью задачи → `Fatal error: Duplicate values for key`. **исправлено** `9b76b802` |
| `Features/Tasks/TaskFormScreen.swift:212` | тот же приём по `id` карточек. **исправлено** `9b76b802` |
| `Core/Store/LocalStore.swift` (`showChat`, бывшая строка `:108`) | `UPDATE chat SET …, closed_at = NULL` — столбца `closed_at` в схеме нет (`LocalDatabase.swift`, единственная миграция `v1`), ошибка SQLite глоталась `try?` в `ChatArchiveScreen.swift`. Плюс вторая половина: `payload_json` не обновлялся, а `RoleChat.archivedAt`/`closedAt` читаются именно из него. **исправлено**: `9b76b802` (столбец) + эта работа (`ChatCacheRow`/`LocalStore.restoreChat` пишут тело ответа сервера, признаки архива снимаются и в модели) |
| `Core/LiveActivityService.swift:197` | якобы перетирает слот `realtime.onEvent`, который держит `TaskFlowApp.swift:240`. **опровергнуто**: там свой экземпляр клиента (`:104`), общий слушается через `addObserver` (`:145-147`) |
| `Core/Session/SessionStore.swift:140-146` + `App/TaskFlowApp.swift:178-185` | выход чистит Keychain и `LocalStore`, но не `ResponseCache`, не `ClosedTasksStore` (`closed-tasks.json`), не `ComposioCatalogCache`, и не сбрасывает сторы в памяти → данные прошлого пользователя на устройстве. **остаётся** |
| `Features/Settings/SettingsScreen.swift:141` | тумблер «Вход по Face ID» ничего не защищает: `evaluatePolicy` в проекте нет, только `canEvaluatePolicy` для определения сенсора. **остаётся** |
| `Features/Settings/SecretsScreen.swift:143`, `ServiceAccountsScreen.swift:298`, `ProviderDetailScreen.swift:321` | секреты и токены кладутся в общий `UIPasteboard` без `.localOnly`. **исправлено** `a7bdceb4` (`SafePasteboard.copySecret`) |

### Серьёзно (данные и поведение)

| Где | Проблема |
| --- | --- |
| `Features/Projects/ProjectTasksScreen.swift:85` | статусные фильтры не ограничены проектом — на экране проекта видны задачи других проектов |
| `ProjectTasksScreen.swift:285-296` | дерево пересобирается на каждую строку (O(rows×n) в `body`) и читает `relationshipTasks` вместо `source` → подзадачи иногда не показываются |
| `Features/Tasks/TaskFormViewModel.swift:330-392` | `loadIfNeeded()` грузит всегда и перезаписывает несохранённый текст карточки при push/реалтайме; готовый механизм слияния `adoptServerChanges` (`:489-499`) не используется. **уточнено** (§5): окно узкое, но открыто |
| `Features/Knowledge/NoteEditorViewModel.swift:88-100` | «Сохранено» ставится безусловно, даже если правка не уехала; `catch` не хранит причину |
| `Features/Roles/RoleChatRoomScreen.swift:1782` | свои сообщения сопоставляются по равенству текста, а не по id |
| `RoleChatRoomScreen.swift:2893` | `deliver()` под `guard !isSending` без очереди: «Повторить» во время другой отправки молча ничего не делает |
| `Core/Store/SyncEngine.swift:69` | догрузка сообщений гейтится флагом, который ставится только при первом открытии чата (курица-и-яйцо) |
| `Chat/Output/RoleReplyMarkdown.swift:41` | при пустых серверных блоках рисуется «Не удалось получить подготовленное содержимое»; `ChatStructuredOutputView.swift:205-215` загоняет туда все списки |
| `Chat/Output/ChatHTMLView.swift:62` | кнопка «Закрыть». **опровергнуто**: это `fullScreenCover`, свайпом не закрывается |
| `Packages/NewChatCore/SessionReducer.swift:34-43` | `transientAssistantText` копится, но не читается; редьюсер всё равно гоняется на каждое событие |
| `Features/Inbox/AttentionScreen.swift:92-104` | четыре пути загрузки; `refreshable` молча не работает, если идёт опрос |
| `Features/Activity/AIUsageScreen.swift:33-39,301-313` | разделы JEV/OpenCode исчезают при нулевом расходе ролей; `loading` залипает навсегда при смене периода |
| `Features/Secretary/SecretaryVoiceScreen.swift:95-127` | при ошибке после `presentation.begin` не отключается комната и не закрывается Live Activity |
| `Features/ServiceNotifications/NotificationsScreen.swift` | лента уведомлений объявлена (`notificationRow`, `visibleNotifications`, `markAllRead`) и нигде не рисуется: уведомления грузятся, приходят по WS и не видны. **остаётся** — решение о продукте |
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

Ничего из этого в ветке не делалось: каждый пункт — отдельная работа.

1. **Дочить миграцию на «Сессии» и удалить старую комнату** — минус 3071 строка,
   минус второй рендерер живого хода, минус второй обработчик WS.
2. **Одна точка очистки данных пользователя**: `wipeUserData()` = LocalStore +
   ResponseCache + `closed-tasks.json` + in-memory кэши; на выходе и на 401.
3. **Один `APIClient` из окружения** вместо `APIClient()` в десятках мест.
4. **Один модуль дат** с Москвой по умолчанию вместо пяти.
5. **Один шаблон `load`/`mutate` для сторов**: `CancellationError` сегодня
   отсекается в `ProjectStore`, но не в `LabelStore`.
6. **Убрать дубли и мёртвый код** (что вырезано и что сознательно оставлено —
   раздел 6, очередь C).
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
только для новых файлов. **В ветке ничего из этого не менялось**: чистка
индекса и удаление файлов — только по слову владельца.

---

## 5. Перепроверка субагентами — что подтвердилось, а что нет

Каждый пункт, который планировалось править или вырезать, отдан отдельному
ревьюеру с заданием: подтвердить или опровергнуть по коду, указать точные
`file:line`, назвать риск правки и нужность теста. Ветка `audit/code-2026-11-14`
создана от `main` (`1c56c7f9`) до начала работ; в ней же сделаны правки,
отмеченные в этой таблице словом «исправлено».

### Опровергнуто — править не нужно

| Находка | Почему |
| --- | --- |
| `LiveActivityService.swift:197` перетирает подписку приложения | Там **свой** экземпляр `RealtimeClient` (`:104`), а `TaskFlowApp.swift:240` пишет в слот другого объекта; общий клиент островок слушает через `addObserver` (`:145-147`). Остаётся только гигиена: переписать на `addObserver`, чтобы не трогать слот повторно |
| `ChatHTMLView.swift:62` кнопка «Закрыть» | Это `fullScreenCover`, свайпом не закрывается — кнопка нужна |
| Подпись «Системный таббар» (`SettingsScreen.swift:159`) | Верна: `isPillTabBarEnabled == true` → `TFPillTabBar` на системном `TabView`; выключено → свой `TFTabBar` |
| «`Resources/Fonts` дублируется в проекте» | В `project.pbxproj` дубля нет (xcodegen схлопывает): одна группа, 24 ttf по одному разу. В `project.yml` блок действительно продублирован — косметика |
| `RoleReplyMarkdown` кегль выделения «нарушает закреплённое 15 pt» | На дефолте `.emphasis` = `baseSize: 15` = `TFFont.body` + bold, решение держится; реальное расхождение — в документе (там «5 %», в коде `0.94`) и в том, что у группы свой ключ `taskflow_chat_type_emphasis` |
| `archive/README.md:20` | Строка цела; битая — `:21` (`design-system-2026-09-11/`); исправлено `1d0570be` |
| `COMPONENTS.md` без `Sessions` | `Sessions` — экран, а не компонент; претензия верна только для `TFActivityCube`/`TFActivityStatus` и подсказок |
| `Dictionary(uniqueKeysWithValues:)` как живая авария | Механика падения верна, но триггер недостижим: `task_id` — `PRIMARY KEY` в `task_review_history` (в живой базе 397 строк, дублей 0), `branch_cards` идут через `UNION` по `tasks.id`. Правим как защиту от будущего контракта — исправлено `9b76b802` |
| `loadIfNeeded` «затирает всё» | Путь тихого обновления защищён `adoptServerChanges`, автосохранение через 400 мс. Окно потери узкое: закрытие вложенной шторки, возврат из связанной задачи, офлайн, висячие вложения — поэтому в план оно попало последним |

### Подтверждено и уточнено

- **Возврат чата из архива — исправлено.** `closed_at` в схеме нет
  (единственная миграция `v1` в `LocalDatabase.swift:67-136`), ошибка глоталась
  `try?` в `ChatArchiveScreen.swift`. Строка скопирована с сервера
  (`server/src/lib/chatArchive.ts:98`, там таблица `chats` и `closed_at` есть).
  Сломан был не серверный возврат, а локальный кеш: чат оставался скрытым в
  первом кадре и в офлайне. Вторая половина — `payload_json`: модель чата
  собирается из него (`RoleChat.swift:42,70`), и пока в теле лежали
  `closed_at`/`archived_at`, восстановленный чат считался архивным
  (`RoleChat.isArchived`) и рисовался приглушённым
  (`RoleChatsScreen.swift:788`). Сделано (`9b76b802` + эта работа): столбец
  чистится, а в кеш идёт тело ответа сервера
  (`LocalStore.restoreChat(id:serverBody:)`), без тела — признаки архива
  снимаются в том, что лежит. Логика разбора — `ChatCacheRow` (без GRDB), тест
  `Tests/ChatCacheRestoreTests.swift`, прогон без симулятора:
  `python3 Tools/test_chat_cache_restore.py`.
- Биометрия: `evaluatePolicy` — **0 совпадений** по `Sources/`; токен лежит
  `kSecAttrAccessibleAfterFirstUnlock` (`KeychainService.swift:100`). Дешевле и
  честнее снять тумблер; доделывать разблокировку — отдельная работа с тестом.
  Не сделано: нужно слово владельца.
- Выход: кроме `ResponseCache`/`ClosedTasksStore`/`ComposioCatalogCache` остаются
  in-memory сторы (`TaskFlowApp.swift:41-44`), `RolesCache` (до 640 КБ),
  `UserDefaults` (`roleChat.mode.*`, `roleChat.model.*`, `taskflow_settings_*`),
  аватарки ролей, `device-token` в Keychain. Первый кадр после входа может
  рисоваться из кэша чужой сессии (`APIClient.swift:89-96` — 21 место
  `cachedXxx()`); `ClosedTasksStore` вообще не делает сетевого шага — снимок
  показывается из файла. `LocalStore.clearAll` без `VACUUM` — удалённые строки
  остаются в свободных страницах базы.
- **Секреты в буфере — исправлено** (`a7bdceb4`): `SafePasteboard.copySecret`
  помечает значение `.localOnly`. Было: `localOnly` в проекте — 0 совпадений,
  хелпера нет; копировались значение секрета (`SecretsScreen.swift:143`) и
  API-токен (`ServiceAccountsScreen.swift:298`); `ProviderDetailScreen.swift:321`
  — короткий код OAuth-устройства, риск низкий.
- `ServiceNotificationsClient.swift:10` — адрес можно выводить из
  `APIClient.baseURL` (порт 5198), таймаут задать явно (сейчас 60 с). Не сделано.
- `SecretaryVoiceScreen.swift:95-127` — в `catch` не вызываются `presentation.end`,
  `disconnect`, `requestStop`, `endVoiceActivity`; откат стоит вынести в
  `abandonCall(...)` и звать из `catch` и из `didDisconnectWithError`. Не сделано.
- **Мёртвое — частично вырезано** `59d7d625` (по 0 вызовов): `taskList`/
  `TaskListPage` (`APIClient+Tasks.swift:69,85-106`), `deleteTask(id:)` (`:272`),
  `archiveDate` (`TaskArchiveScreen.swift:179`), `isSendingVoice`
  (`ChatVoiceComposer.swift:76`). Сознательно оставлено: `stretches`
  (`ChatComposerPill.swift:40`) и `sessionControls` — оба фиксируют решения
  владельца, удаление меняет вид без пользы. Также оставлено
  `isCustomKeyboardEnabled` (`SettingsViewModel.swift:29-40,58,68`): исправлено
  только ложное утверждение в комментарии — таргета клавиатуры в `project.yml`
  нет, само свойство живёт.
- **Не мёртвое, а недовыложенное** (решение владельца, не вырезано): лента
  уведомлений целиком (`NotificationsScreen.swift:18-20,195-269,271-341,396-407`)
  вместе с `serviceTicketDetails`/`dayCounts` и `resolutionSheetItem`;
  `projectArchiveSection` (`TaskArchiveScreen.swift:134`) тянет целую готовую
  секцию «Проекты» в архиве; `onSendVoice` — весь механизм отправки аудио в
  комнате (`RoleChatRoomScreen.swift:59-60,168,1308,1320,1561,2982,3037`), сейчас
  голос ходит только расшифровкой в черновик; `transientAssistantText` —
  единственное место, где копятся дельты стрима (`SessionReducer.swift:36`).
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
  правки обязательна одна инкрементальная сборка. Не правилось.
- `ci.yml` в HEAD: сборка на `macos-26` на каждый push и `gh pr merge` в job
  `automerge` — прямо против решения от 05.11.2026. Включён ли Actions
  фактически, офлайн не установить. Не правилось: только по слову владельца.

---

## 6. План работ и что фактически сделано

Статусы: `[ ]` — не начато, `[~]` — проверено, но не сделано, `[x]` — сделано,
`[—]` — снято после перепроверки.

### Очередь A — падения и потеря данных
- [x] `CompletionHeatmap.swift:249`, `TaskFormScreen.swift:212` —
  `Dictionary(_:uniquingKeysWith:)` вместо `uniqueKeysWithValues`, коммит
  `9b76b802`.
- [x] Локальный кеш чата при возврате из архива — `9b76b802` + эта работа:
  `ChatCacheRow`, `LocalStore.restoreChat`, тело ответа сервера в `payload_json`,
  тест `Tests/ChatCacheRestoreTests.swift` (`Tools/test_chat_cache_restore.py`,
  без симулятора) и полный путь в `Tests/LocalDbSyncTests.swift`.
- [—] `LiveActivityService.swift:197` — перепроверка опровергла, слот не
  перетирается.
- [ ] `TaskFormViewModel.swift:330-392` — слияние вместо перезаписи. Окно
  потери узкое (§5), поэтому последним.

### Очередь B — данные пользователя
- [ ] `wipeUserData()` на выходе и на 401 (объём понятен: `ResponseCache`,
  `ClosedTasksStore.reset()`, `ComposioCatalogCache`, `RolesCache`, четыре стора
  в памяти, `VACUUM` в `clearAll`).
- [x] `UIPasteboard` с `.localOnly` — `SafePasteboard.copySecret`, коммит
  `a7bdceb4`.
- [ ] биометрия: снять тумблер (дешевле) или доделать `evaluatePolicy` — нужно
  слово владельца.
- [~] `ServiceNotificationsClient` — адрес из `APIClient.baseURL`, таймаут
  явный. Перепроверено, не сделано.

### Очередь C — мёртвый код и дубли
- [x] вырезано по 0 вызовов, коммит `59d7d625`: `taskList`/`TaskListPage`,
  `deleteTask(id:)`, `archiveDate`, `isSendingVoice`.
- [~] сознательно оставлено: `stretches`, `sessionControls` (решения владельца),
  `isCustomKeyboardEnabled` (живое свойство, поправлен только комментарий).
- [ ] решение владельца, не сделано: лента уведомлений, `projectArchiveSection`,
  `onSendVoice`, `transientAssistantText` (очередь E).

### Очередь D — документы и конфигурация
- [x] `ARCHITECTURE.md`, `COMPONENTS.md`, `DESIGN.md`, `archive/README.md`,
  `docs/README.md` — `1d0570be`; относительные ссылки в `DESIGN.md`, задеты
  той правкой, — эта работа (три ссылки, назначение сверено с кодом).
- [ ] `docs/README.md:29` — «в Git каталог не входит» про
  `docs/реестр-сводка.md` неверно: файл отслеживается (коммит `e7b07a49`),
  правила в `.gitignore` для него нет. Плюс две битые ссылки на папки, которых
  нет: `docs/ПЛАН Стриминг Чата Агента/`, `docs/ПЛАН Супер Секретарь/`
  (`docs/README.md:13-14`). Снять с индекса или поправить текст — решение
  владельца.
- [ ] `CLAUDE.md:124` — ссылка на `archive/design-system-2026-09-11` осталась.
- [ ] `project.yml`: двойной `Resources/Fonts`, `SWIFT_VERSION`, UI-тесты вне
  схемы `TaskFlow`, `Info.plist` из индекса — правка конфигурации требует
  сборки, не делалось.
- [ ] `.github/workflows/ci.yml` — только по слову владельца.
- [~] `DESIGN.md`: 18 оставшихся ссылок с префиксом `../Sources/…` не
  открываются (документ лежит в корне). Вне правки, не тронуты.

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

---

## 7. Чем этот аудит не подтверждён

Честная граница проверки: всё ниже в этой работе не запускалось.

- Сборка Xcode, тесты и симулятор — по правилу владельца от 25.10.2026 не
  запускались. Значит, компиляция правок ветки проверена только чтением и
  точечными прогонами чистой логики (`Tools/test_chat_cache_restore.py`).
  Тесты из `Tests/` (включая `Tests/LocalDbSyncTests.swift`) требуют
  iOS-тестового бандла — они не прогонялись.
- Сервер (`192.168.1.110`) из этой сессии недоступен (ssh отвергает ключ),
  поэтому серверная сторона архивации и возврата читалась только по документам
  `docs/2026-11-08-chat-archive*.md`.
- Внешний вид не оценивался: ни один экран не открывался.
- Включён ли GitHub Actions фактически — офлайн не установить.
