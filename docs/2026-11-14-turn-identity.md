# Идентичность живого хода: исправление ревью 5951f4fa

Дата: 14.11.2026. Основание: поручение владельца — исправить замечания
независимого ревью опубликованного `5951f4fa`, сохранить чаты ролей, чужие
правки и прежние функции; только целевые проверки; симулятор, UI-тесты и
установка запрещены.

## Что было не так

1. `Sources/Features/Sessions/Engine/SessionViewModel.swift` присваивал
   `liveTurn.sessionID` — свойство `private(set)`: код не собирался.
2. Область живой разметки строилась из изменяемых `sessionID` и `startedAt`
   (`ChatLiveBlockScope.session(_:turnStartedAt:)`, `ISO8601Format()` без долей).
   Два хода в одну секунду получали одну область, событие без `agent_start` —
   область `live`, а смена снимка переприсваивала `sessionID` старому ходу: запись
   блоков и чтение на экране могли разойтись.
3. Ключ кэша живого куска знал у документа только число символов, у таблицы
   только размеры: разные payload с одинаковым исходным текстом делили одну
   запись `ParsedValueCache`, и один ответ рисовался разметкой другого.

## Что изменено

- `Sources/Core/Models/ChatServerBlock.swift` — вместо `ChatLiveBlockScope`
  (сессия + секунда начала) `ChatLiveTurnIdentity`: сессия и номер хода
  (`UUID`), выданный один раз; `scope` = `"turn:<номер>"` и не пересчитывается.
  Добавлен `ChatServerBlock.cacheKey` — полное содержимое блока (документ и
  таблица — канонический JSON с сортировкой ключей, виджет/JSON/HTML — сам
  текст, `hashValue` убран).
- `Sources/Features/Sessions/SessionLiveTurn.swift` — ход хранит
  `ChatLiveTurnIdentity`; `beginTurn(at:)` выдаёт новый номер на каждый
  `agent_start`, событие без `agent_start` выдаёт номер при первом событии,
  `bind(sessionID:)` сбрасывает элементы и область только при смене сессии
  (снимок той же сессии ход сохраняет).
- `Sources/Features/Sessions/Engine/SessionViewModel.swift` —
  `liveTurn.bind(sessionID: snapshot.id)` вместо присваивания `private(set)`
  свойства.
- `Sources/Chat/Feed/ChatRichContent.swift` — `liveCacheKey` =
  `"live:" + block.cacheKey`.

## Проверки (без симулятора)

Стенд `python3 Tools/test_chat_live_block_scope.py` собирает настоящие файлы
(модель хода `SessionLiveTurn.swift`, реестр `ChatServerBlock.swift`, разбор
`ChatRichContent.swift`, модели `Core/Models` и `Core/Common`) и настоящий
`SessionLiveReplyContent` из `SessionLiveTurnView.swift`; тесты —
`Tests/ChatLiveBlockScopeTests.swift`.

- RED на базовом SHA `5951f4fa`: `python3 Tools/test_chat_live_block_scope.py
  --against=5951f4fa` — 7 тестов (два теста смены снимка требуют `bind` и на
  базе не собираются), 3 падения: `testTwoTurnsInSameSecondKeepOwnBlocks`
  (область `identity-same-second:2025-11-24T16:00:00Z` совпала у двух ходов и
  первый ход потерял свой виджет) и
  `testLiveCacheKeySeparatesDifferentPayloads` (ключ `live:doc/16:Итог: два
  пункта` одинаков у документа с марками и без).
- Заявленный дефект сборки воспроизведён на базе: `python3
  Tools/test_chat_live_block_scope.py --defect=5951f4fa` — компилятор на
  настоящем файле модели из этого SHA: `error: cannot assign to property:
  'sessionID' setter is inaccessible`.
- GREEN: тот же стенд без флагов — 9 из 9 (включая смену снимка: та же сессия
  сохраняет ход, другая — сбрасывает).
- `Tools/test_session_live_turn.py` переведён на настоящие модели (копии
  `RoleChatLiveItem`/`RoleChatThinking`/`RoleChatLiveStep`/`RoleTurnUsage` убраны)
  и получил `--against=SHA`: 14 из 15. Падает
  `testThinkingDeltasGrowOneThoughtUntilText` — и на базовом `5951f4fa` ровно так
  же (`python3 Tools/test_session_live_turn.py --against=5951f4fa`): тест ждёт
  накопления кусков размышления, а код с 13.11.2026 показывает только текст,
  размеченный сервером. Это чужая правка вне задачи, поведение не менялось.
- `python3 Tools/test_chat_live_block_scope.py --typecheck` — проверка типов
  затронутого кода на настоящих типах: собирает модуль `NewChatCore` из
  `Packages/NewChatCore`, берёт настоящий `SessionSnapshot` и точное выражение
  из модели экрана — `liveTurn.bind(sessionID: snapshot.id)`; вместе с ним
  проверяются настоящие `SessionLiveTurn`, `ChatServerBlock`, `ChatRichContent`
  и файл тестов. Ошибок типов нет.
- Точечно зелёные: `test_live_pacer_order`, `test_role_chat_live_delta` (17),
  `test_role_chat_live_slots` (3), `test_server_document`,
  `test_server_only_render` — чаты ролей и общий реестр без области работают
  как раньше.
- Сторож дизайн-системы `python3 Tools/design-system-guard.py --diff HEAD` —
  чисто.

## Ограничения

- Сборка Xcode не запускалась: на машине висит чужой
  `xcodebuild test-without-building` (UI-раннер AgentDeviceRunner на
  симуляторе, процесс 38540, 0% CPU) — правило «одна сборка за раз». Поэтому
  проверка типов сделана компилятором `swiftc` (режим `--typecheck` выше):
  изменённая строка модели экрана проверена с настоящим `SessionSnapshot`, но
  весь `SessionViewModel` в отдельном компиляторе не собирается — ему нужны сеть,
  хранилище и UIKit. Сборку приложения надо повторить, когда чужая закончится.
- Симулятор, UI-тесты и установка на iPhone не запускались.
- Внешний вид на телефоне оценивает владелец.
