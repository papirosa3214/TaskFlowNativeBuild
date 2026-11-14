# Список дел агента Pi в новых сессиях (14.11.2026)

Работа: `LOCK-SESSION-PI-TODOS-20261114`. Только iOS, поток новых сессий
(`Sources/Features/Sessions/`). Чаты ролей и их поведение не менялись: у
общего компонента появились два необязательных параметра со значениями по
умолчанию, поведение ролей прежнее. Сервер не менялся — он уже отдаёт готовый
список (`GET /api/sessions/:id/todos`, контракт New-Todoist
`docs/current/pi-todo-list-sessions.md`, коммит сервера `e5dcf9ee`).

Поручение владельца (14.11.2026): показать в новых сессиях список дел агента Pi
«используя уже существующий компонент чеклиста из чатов, сохранив текущий вид
интерфейса и поведение кругляшков, без редизайна»; данные — только готовые с
сервера, разбора `details` на телефоне нет; отдельное состояние на активную
сессию, без утечки при переключении и задержке ответа.

Уточнение владельца (14.11.2026): маршрут читает уже сохранённую ветку, а
`tool_end` может прийти раньше записи `toolResult`, поэтому обновление идёт
после `message_end` записи, после восстановления и по завершении хода, без
ставки на один преждевременный `tool_end`.

## Найденный компонент (без нового вида)

- `ChatWorkPlanRows` — `Sources/Chat/Output/ChatWorkPlanStrip.swift:78`. Уже
  рисует чек-лист: строка «План · … · N из M · сейчас: …», кружки пунктов по
  `SubtaskWorkPlan.Item.State` (`pending`/`inProgress`/`done`/`blocked`),
  разворот по нажатию, долгое нажатие «Удалить чек-лист».
- Показ над полем ввода — `ChatComposerPill` (`Sources/Chat/Output/ChatComposerPill.swift:9`):
  сегмент `1/3` в пилюле, развёрнутый список в панели. Им же пользуется комната
  роли (`RoleChatRoomScreen`).
- Данные чек-листа — `ChatWorkPlan` (`Sources/Core/Models/ChatWorkPlan.swift`),
  пункты — `SubtaskWorkPlan.Item` (`Sources/Core/Models/SubtaskWorkPlan.swift`).

Новых компонентов вида не появилось: список дел сессии — это тот же
`ChatWorkPlan`, поэтому кружки, разворот и отступы те же. Изменения в общем
компоненте аддитивные, со значениями по умолчанию:

- `ChatWorkPlanRows.headerText: ((ChatWorkPlan) -> String)? = nil` — своя строка
  заголовка; у ролей остаётся прежняя `plan.summary(roleName:)`.
- `ChatComposerPill.planHeader: ((ChatWorkPlan) -> String)? = nil` — прокидывается
  в `headerText`;
- `ChatComposerPill.onDeletePlan` стал необязательным (у сессий удалять нечего).

## Что сделано

- `Sources/Features/Sessions/SessionTodos.swift` (новый) — разбор готового
  ответа сервера и отбор ответа. Никакой логики предметной области: статусы,
  порядок и счётчики берутся как пришли.
  - `available: false` или пустой список → `plan(sessionID:)` возвращает `nil`,
    полоса не появляется вовсе (не пустая строка).
  - `in_progress` → `.inProgress`, `completed` → `.done`, всё остальное
    (включая незнакомый статус) → `.pending`: закрытым кружком чужое состояние
    не рисуется.
  - у идущей задачи показывается её `activeForm` («ищу компонент»), как в самом
    Pi; остальные пункты — своим текстом.
  - `isNewer(_:than:)` — поздний ответ на старый запрос и ответ другой сессии
    поверх текущего не ложатся (`updatedAt`, затем `entryId`/содержимое).
- `SessionAPIClient.todos(sessionID:)` — один `GET /api/sessions/:id/todos`,
  тело разбирается как есть (`SessionTodosResponse`).
- `OwnerSessionScreen` — единственное состояние `@State private var todos`,
  план для пилюли `todoPlans`, заголовок `todoHeader` («Список дел · 1 из 3 ·
  сейчас: …»). Перечитывание:
  - при входе в сессию (после `model.open`);
  - после `message_end` — `model.state.messages.count` (в том числе запись
    `toolResult`; `tool_end` намеренно не триггер, он бывает раньше записи);
  - по завершении хода (`isStreaming` → `false`), т.е. и после восстановления;
  - при смене активной сессии: состояние очищается и читается заново.

  `reloadTodos` отбрасывает ответ, если активная сессия за время запроса
  сменилась, и не кладёт ответ, который старше уже показанного.

## Проверки (точечные, без симулятора и сборки Xcode)

1. XCTest на macOS: `python3 Tools/test_session_todos.py` — 5 тестов / 5
   проверок, GREEN. Стенд собирает настоящие `SessionTodos.swift`,
   `SubtaskWorkPlan.swift`, `ChatWorkPlan.swift`, `Sources/Core/Common/JSONValue.swift`
   (нужен `ChatWorkPlan`) и `Tests/SessionTodosTests.swift`.
   RED был настоящим: первый прогон упал на ответе без `tasks`
   (`keyNotFound: Key 'tasks' not found`) — список пропал бы целиком; после
   терпимого разбора поля GREEN.
2. `xcrun swiftc -parse` по пяти изменённым файлам — без ошибок.
3. `python3 Tools/design-system-guard.py --diff HEAD` — чисто.
4. `xcodegen generate` — новые файлы попали в проект (`project.yml` берёт
   каталоги `Sources` и `Tests` целиком).

Сборка Xcode, симулятор, UI-тесты и установка не запускались. Внешний вид
полосы оценивает владелец.

## Границы и ограничения

- Разбора `details` инструмента `todo` на телефоне нет: только готовый маршрут.
- Список может отставать на одну запись транскрипта (так устроен контракт) —
  следующий `message_end`/конец хода это закрывает.
- `blockedBy` разбирается, но отдельной строкой не показывается: у общего
  пункта чек-листа нет места под зависимости, а рисовать их оранжевым
  «ждёт ответа» значило бы подменить смысл кружка (без редизайна).
- Закрытый список (`status: stopped/finished`) полосой не помечается —
  у сессий список всегда показывается как рабочий, как список дел Pi.

## Файлы работы

`Sources/Features/Sessions/SessionTodos.swift` (новый),
`Sources/Features/Sessions/Engine/SessionAPIClient.swift`,
`Sources/Features/Sessions/OwnerSessionScreen.swift`,
`Sources/Chat/Output/ChatComposerPill.swift`,
`Sources/Chat/Output/ChatWorkPlanStrip.swift`,
`Tests/SessionTodosTests.swift` (новый),
`Tools/test_session_todos.py` (новый), `AGENT-WORK-SCOPES/2026-11.md`.
