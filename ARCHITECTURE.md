# TaskFlow Native — архитектура

Нативный клиент TaskFlow на SwiftUI для iPhone. Сервер (Fastify + SQLite,
репозиторий `New-Todoist` на `.110`) и его API живут отдельно и здесь не
правятся.

> Переписан 22.09.2026 по живому коду. Прежняя редакция описывала структуру
> `native/…` внутри серверного репозитория и сборку через `scripts/sync-build.sh` —
> ни того, ни другого больше нет. Расходится документ с кодом — прав код.

## Где что лежит

| Путь | Что |
| --- | --- |
| `project.yml` | описание проекта для xcodegen; `.xcodeproj` генерится и в git не хранится |
| `Sources/App/` | точка входа, корневая навигация, таббар |
| `Sources/DesignSystem/` | `Theme` (токены), `Components`, `Navigation` |
| `Sources/Core/` | `Models`, `Networking`, `Realtime`, `Session`, `Store`, `Stores`, `Speech`, `Text`, `Common` + файлы в корне (Live Activity, удержание фона, диагностика, журнал клиента) |
| `Sources/Chat/` | чат с ролями: `Composer`, `Feed`, `Output`, `Panels`, `Shared`, `Widgets` |
| `Sources/Features/<Экран>/` | по папке на экран: `Activity`, `Coordination`, `Inbox`, `Knowledge`, `Markdown`, `Missions`, `Overview`, `Planner`, `Projects`, `Roles`, `Routines`, `Secretary`, `ServiceNotifications`, `Sessions`, `Settings`, `Tasks` |
| `Resources/` | Assets.xcassets, Info.plist, entitlements, шрифты |
| `Widgets/` | виджеты и Live Activity |
| `Tests/`, `UITests/`, `SnapshotTests/` | тесты |
| `VoiceMessageLab/` | отдельная песочница по голосовым сообщениям |
| `Tools/` | вспомогательные скрипты |
| `spec/` | спецификации, снятые с веб-версии в начале проекта |
| `graft/` | граф кода: ранжированный поиск по узлам с точными `file:line` |
| `docs/` | рабочие документы проекта |
| `archive/` | то, что выведено из работы, но выбрасывать рано |

Всего 754 файла Swift по таргетам: `Sources/` — 486, `Tests/` — 185,
`UITests/` — 51, `VoiceMessageLab/` — 11, `VoiceMessageLabTests/` — 7,
`Packages/` — 8, `Widgets/` — 3, `SnapshotTests/` — 2, `Broadcast/` — 1.

**Это единственный исходник клиента.** Копии на `.110` нет с 08.09.2026, код
переносится только через git: штатный `origin` — GitHub
`papirosa3214/TaskFlowNativeBuild` (с 05.11.2026 push идёт прямо в `main`, без PR
и CI), дополнительно есть `gitea` — `maksim/taskflow-native-ios`.
Любой файловый синк в этот каталог отклоняет хук
`.claude/hooks/guard_no_remote_sync.py` (`.claude/settings.json`, PreToolUse → Bash).

## Технические решения

- **SwiftUI**, `deploymentTarget iOS 18.0` (`project.yml`). Порог занижен
  сознательно: новое включается через `#available`, а не поднятием планки.
- **Проект генерится xcodegen** из `project.yml`. Причина историческая и
  по-прежнему верная: общий `project.pbxproj` был бы вечным источником
  конфликтов, а xcodegen собирает таргет из содержимого папок.
- **Ассеты обязаны быть в `sources`** в `project.yml` — ключа `resources` у
  таргета в xcodegen нет, и каталог, положенный не туда, молча не попадёт в
  бандл.
- **Данные:** `@Observable`-сторы поверх `APIClient` (async/await, URLSession);
  реалтайм — `Sources/Core/Realtime`.
- **Bundle id:** префикс `com.maksim.taskflow`, у приложения —
  `com.maksim.taskflow.native`.

## Потоки чатов: сессии и роли (14.11.2026)

В приложении два независимых потока чата, и они развиваются **раздельно**.
Комната роли (`RoleChatRoomScreen`) — прежний чат с ролями. Сессия
(`OwnerSessionScreen`) — новый чат-сессия, вход в списке помечен «Сессии
(бета)»: `Sources/Features/Roles/RoleChatsScreen.swift:221-226`.

Правило владельца: решения одной стороны можно брать за образец и копировать,
но **потоки не объединять** до отдельного решения. Работа над сессиями не
должна менять комнату роли: у них разные транспорты, состояние и хранение
(см. таблицы), общими остаются только виды и реестр разметки.

### Сессия (`Sources/Features/Sessions/`)

| Этап | Путь | Что происходит |
| --- | --- | --- |
| Экран | `Sources/Features/Sessions/OwnerSessionScreen.swift:27` | лента `ScrollView` + `ScrollViewReader`, внизу `ChatFeedScrollPolicy.followsBottom` (~:161); лента — `Sources/Features/Sessions/SessionLiveTurnView.swift:74`/`:364` |
| Движок | `Sources/Features/Sessions/Engine/SessionViewModel.swift` | `start` :306, `select` :351, `open` :368, `send` :394, `abort` :445, `branch` :458, `fork` :472, `receive` :486, `recoverAfterReconnect` :503, `refreshSnapshot` :529, `installSnapshot` :547 |
| Состояние | `Packages/NewChatCore/Sources/NewChatCore/SessionReducer.swift:24`, `Packages/NewChatCore/Sources/NewChatCore/SessionModels.swift:263` | `SessionState`: снимок, сообщения, `transientAssistantText`, `lastCursor`, `seenCursors`, `childActivity`, `needsSnapshotReset`, `commandDelivery` |
| События | `Sources/Features/Sessions/Engine/SessionRealtimeClient.swift` | свой сокет `/ws` (:110), возврат в передний план :72, приём :124, обрыв :183 (задержка 0, затем `min(2^(n-2), 30)` :190) |
| HTTP | `Sources/Features/Sessions/Engine/SessionAPIClient.swift` | `snapshot` :182, `events(after:)` :186, `prompt` :194, `abort` :198, `branch` :202, `fork` :206 (`/api/sessions/…`) |
| Живой ответ | `Sources/Features/Sessions/SessionLiveTurn.swift:15` | `ChatLiveTurnIdentity` + `scope` :37; `register` :54; `apply` :103 — `assistant_text_delta` :140 берёт **серверный** `text`, `message_end` :156 кладёт хвост и полный текст размышлений, `tool_start/update/end` :181-208 |
| Разметка на экране | `Sources/Features/Sessions/SessionLiveTurnView.swift:488`, `:902-904` | пейсер `RoleLiveTextPacer.ingest(…, scope:)` → `ChatRichContent.liveSegments(shown:scope:)` |
| Остановка | `Sources/Features/Sessions/Engine/SessionViewModel.swift` `abort` :445; `Sources/Features/Sessions/SessionLiveTurn.swift:236`, `:385` | причина из `stopReason` сообщения → `ChatInterruptionBadge` (`Sources/Chat/Feed/ChatInterruptionBadge.swift:6`, показан в `Sources/Features/Sessions/OwnerSessionScreen.swift:501`); частичный ответ помечается |
| Восстановление | `Sources/Features/Sessions/Engine/SessionViewModel.swift:503`, `:547` | переподключение → `events?after=cursor`; `resetRequired` → новый снимок; `installSnapshot` не теряет курсор; неизвестный ответ — `pendingOutgoing` и повтор `send` |
| Хранение | — | локальной базы нет: `LocalStore`/SQLite в `Sources/Features/Sessions` и `Packages/NewChatCore` не используется (проверено поиском). После холодного запуска состояние берётся с сервера |

### Роль (`Sources/Features/Roles/`)

| Этап | Путь | Что происходит |
| --- | --- | --- |
| Вход | `Sources/Features/Roles/RoleChatRoomLoader.swift:24` | чат из `LocalStore`, иначе `APIClient.roleChat` → `RoleChatRoomScreen(chat:)` |
| Экран | `Sources/Features/Roles/RoleChatRoomScreen.swift` | подписка :1140 (`realtime.addChatObserver(chatID:includeGlobal:)` + `ChatEventBatchBox`), `applyLiveDelta` :1246, `loadLiveTurns` :1942, `refresh` :2723, `send` :2869 / `deliver` :2893, `stopTurns` :1874, `loadComposerStatus` :1156 |
| События | `Sources/Core/Realtime/RealtimeClient.swift:16` | общий сокет `/ws` :252, backoff `min(30, 1.6^n)` :441, `onReconnected` :161; событие `.roleChatLive` — `Sources/Core/Realtime/RealtimeEvent.swift:194` |
| Протокол хода | `Sources/Core/Realtime/RoleChatLiveDelta.swift:11` | `chats:live:start/patch/end`, `seq` обязан расти на 1, иначе `.needsSnapshot` :311; при разборе блоки кладутся в реестр **без области** (`Sources/Core/Models/RoleChat.swift:512`, `:556`) |
| Состояние | `Sources/Features/Roles/RoleChatLiveStore.swift:19` | коробки и слоты живых ходов, активность, «печатает» |
| HTTP | `Sources/Core/Networking/APIClient+RoleChats.swift` | сообщения :146, живой снимок :214/:219, отправка :254, остановка :286 |
| Хранение | `Sources/Core/Store/LocalStore.swift`, `Sources/Core/Store/ChatCacheRow.swift` | SQLite-кеш чатов и сообщений: комната открывается офлайн из базы, сервер — источник правды |
| Живой ответ | `Sources/Core/Models/RoleChat.swift:615`, `:684`, `:769`, `:916` | `RoleLiveTextPacer`: `ingest`, `advance`, `pacingParts` (берёт блоки из реестра по `scope`) |

### Общие компоненты и цена их правки

| Компонент | Кто использует | Что сломается при правке |
| --- | --- | --- |
| `Sources/Core/Models/ChatServerBlock.swift:92` `ChatLiveBlockRegistry` | обе стороны | ключ — текст **и** область: роли область не передают (`nil`), сессии — `ChatLiveTurnIdentity.scope`. Смена правил ключа смешает или спрячет разметку у обеих сторон |
| `Sources/Core/Models/ChatServerBlock.swift:150` `ChatLiveTurnIdentity` | сессии | область хода `"turn:<номер>"` выдаётся один раз; возврат к сессии/времени вернёт смешивание двух ходов |
| `Sources/Chat/Feed/ChatRichContent.swift:54`, `:165`, `:182` | обе стороны | `segments(fromServer:key:)` и `liveSegments` кэшируют разбор по `cacheKey`; ослабление ключа — чужой ответ нарисован разметкой другого |
| `Sources/Chat/Output/RoleReplyMarkdown.swift:3` | обе стороны и ещё больше 30 мест | рисует **только** подготовленные сервером блоки. `readableText` закреплён решением владельца 17–25.10.2026 (`LOCK-CHAT-WINDOW-BEHAVIOUR-20261025`): менять начертание нельзя |
| `Sources/Features/Roles/RoleLiveTurnView.swift:146`, `:399`, `:556`; `RoleThinkingWindow` :743; `RoleLiveBlocks` :1203 | роли; сессии держат копию `Sources/Features/Sessions/SessionLiveTurnView.swift` | общего рефакторинга нет: правка «как у ролей» без такой же правки копии разводит стороны, а слияние копий — это и есть объединение потоков |
| `Sources/Chat/Feed/ChatFeedVirtualList.swift`, `Sources/Chat/Feed/ChatFeedScrollPolicy.swift` | роли — виртуальная лента; сессии — `ScrollView` + только политика низа | виртуальная лента ролей и обычная лента сессий имеют разную механику прокрутки |
| `Sources/Core/Store/LocalStore.swift`, `Sources/Core/Store/ChatCacheRow.swift` | только роли | правка кеша видна ролям; сессий она не касается — не считать это общей основой |

### Известное и непроверенное

- **Проверено по коду** (14.11.2026): пути выше, раздельность транспортов, отсутствие локальной базы у сессий, правило ключа реестра, `message_end` как источник хвоста разметки.
- **Не проверено в этом репозитории:** серверная часть (`New-Todoist` на `.110`) — `server/src/runtime/ownerSessionEvents.ts`, темп разметки 300 мс и формат конвертов описаны в `CLAUDE.md` §«Тонкий клиент без нагрева» и здесь не воспроизводились.
- **Стенды** (наличие, не текущий результат): `Tools/test_session_live_turn.py`, `Tools/test_chat_live_block_scope.py`, `Tools/test_live_pacer_order.py`, `Tools/test_role_chat_live_delta.py`, `Tools/test_role_chat_live_slots.py`, `Tools/test_server_document.py`, `Tools/test_server_only_render.py`. Перед ссылкой на «зелено» их надо прогнать на текущем `main`.
- **История:** `docs/2026-11-14-session-live-scope.md` и `docs/2026-11-14-turn-identity.md` — отчёты о правках области живой разметки; первый описывает уже удалённую `ChatLiveBlockScope`, второй её заменил.

### Запрет переноса серверного разбора на телефон

Разбор ответа (таблицы, виджеты, конверт JSON v1, карточки) делает сервер; телефон
только раскладывает пришедшие `text_blocks` и рисует. Правило владельца
13.11.2026 — `CLAUDE.md` §«Тонкий клиент без нагрева (не менять)». Добавлять
разбор Markdown/HTML на клиенте, «дорисовывать» блоки из сырого текста или
обходить отсутствие блоков локальным парсером нельзя: экран показывает
`Не удалось получить подготовленное содержимое` — это признак потери серверной
разметки, а не повод разбирать текст на телефоне.

## Сборка

```bash
# Только по отдельному поручению владельца: по умолчанию проверяются
# логика и статические проверки, симулятор не поднимается.
cd "$HOME/Проекты/TaskFlowNativeBuild" && xcodegen generate && \
  xcodebuild -project TaskFlow.xcodeproj -scheme TaskFlow -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone Air,OS=27.0' \
  -derivedDataPath build_sim -jobs 2 build
```

Каталоги `build_*` — результаты сборок, в git не входят и занимают десятки
гигабайт; чистить их безопасно.

## Порядок работы

1. **Весь код заморожен по умолчанию.** Править можно только файлы,
   перечисленные в строке со статусом `IN_PROGRESS` в реестре работ
   (`AGENT-WORK-SCOPES/<месяц>.md`, указатель — `AGENT-WORK-SCOPES.md`).
   Взялся за работу — заведи строку, закончил — переведи в `REVIEW`.
2. **Ничего сверх задачи.** Увидел смежную проблему — скажи и дождись ответа.
3. **Сначала граф, потом поиск руками.** `graft ask "<что ищу>"` отдаёт узлы с
   точными `file:line`; ручной обход уводит в мёртвый код.
4. **Расходится `spec/` с кодом — верить коду.** Спецификации снимались с веба
   07.09.2026 и с тех пор не пересматривались.
5. **Правки интерфейса проверяются логикой** (целевые unit-тесты,
   статические проверки, `diff`). Симулятор, скриншоты и UI-тесты — только по
   отдельному прямому поручению владельца; внешний вид принимает он сам.

Полные правила — `CLAUDE.md` и `AGENTS.md` в корне.
