# Участники чата и автоматическая адресация — 16.10.2026

## Требование владельца
Помощника владельца можно пригласить в новый или существующий чат вместе с другими ролями. У обычного чата режим определяется составом: владелец + один собеседник — direct (без обязательного @); несколько собеседников — group (только @). При удалении остальных собеседников личный режим возвращается.

## Реализация
### iOS
Вместо префикса role_ используется наличие серверной учётки у включённой роли (RoleProfile.canJoinChat). Обе формы приглашения используют эту политику. В подробностях чата показано правило адресации для текущего kind; оно обновляется вместе с ответом сервера. Добавлен сценарий подсказок о составе и @.
SourceKit-LSP использован напрямую: documentSymbol подтвердил canJoinChat/isEnabled в RoleProfile и availableRoles/loadRoles в RoleChatsScreen. Swift-проверка выполняется сборкой Xcode.

### Сервер
Тип обычного чата вычисляется по числу фактических участников (включая создателя): >2 — group, иначе direct. Создание, добавление и удаление участника сохраняют состав и тип в одной транзакции. При старте исправляются старые неверные типы; история, сессии и участники сохраняются.
Системный chat-common, проектные чаты и темы задач сохраняют свой групповой контракт.

## Проверка
- До исправления chatComposition: 3/3 FAIL, подтверждены устаревшие kind.
- После: chats + chats-online + chats-common-lifecycle + chatComposition: 83/83 PASS.
- Добавлены ещё две проверки: сохранение проектной группы и восстановление старых kind при старте. Последний chatComposition: 5/5 PASS (итого 85 разных серверных тестов в затронутом наборе).
- Сборка сервера npm run build (tsc): PASS.
- Runtime-тест на замоканном Pi проверяет: личный ответ без @ → добавление второй роли → без @ ответа нет → @qa отвечает → удаление qa → без @ снова отвечает оставшаяся роль. Живые сообщения ролям в проверке не отправляются.
- iOS: 10 unit-тестов PASS (2 политики приглашения + 8 подсказок), один XCUITest PASS за 41.984 s. Проверены выбор помощника при создании, реальное создание группы с дизайнером, удаление помощника с переходом в direct и повторное приглашение с переходом в group. Сообщения ролям не отправлялись. Временный чат удалён, live DB подтверждает 0 оставшихся тестовых чатов.
- Кадры 03-removed-to-direct.png и 04-secretary-invited-to-group.png просмотрены: состав и правило адресации меняются сразу.
- Временный тест перенесён в папку доказательств, выполнен xcodegen generate. После теста восстановлен обычный запуск симулятора без тестовых переменных: SUCCEEDED, PID 27935. iPhone в рамках этой работы не использовался; проверку на устройстве владелец ранее взял на себя.
- git diff --check: без ошибок.

## Развёртывание .110
Очереди role_run_jobs и chat_message_queue перед перезапуском: unfinished=0.
Резервная копия SQLite: /home/maksim/.local/state/taskflow-backups/chat-composition-20261016-044331.db, integrity_check=ok.
Сервис taskflow-server перезапущен, is-active=active, /api/health: ok=true.
Живая БД: chat-secretary теперь group; обычных чатов с несоответствием kind составу — 0.

## Границы
Проектные чаты/темы не превращаются в личные. Голосовые возможности исходного чата помощника сохраняются. Правила выбора адресата в group/direct не переписаны: теперь существующий маршрутизатор получает актуальный kind.
Чужие незакоммиченные изменения в обеих рабочих копиях сохраняются.

## Артефакты iOS
Папка docs/2026-10-16-chat-composition/: 5 кадров, ios-result.json, RoleChatMembershipUITests.swift.
xcresult: /Users/max/Library/Developer/XcodeBuildMCP/workspaces/TaskFlowNativeBuild-6630a891c838/result-bundles/test_sim_2026-10-16T01-42-47-960Z_pid24776_fec113ea.xcresult.
Продукты: /Users/max/Library/Developer/XcodeBuildMCP/workspaces/TaskFlowNativeBuild-6630a891c838/test-products/test_sim_2026-10-16T01-42-47-960Z_pid24776_cc930d41.xctestproducts.
Полный экспорт: build_sim/chat-composition-evidence/ui/. iPhone Air Simulator iOS 27.0, UDID 9FF78D89-EE84-4914-AA56-D0A72D1AF43A.
Команда: xcodebuildmcp simulator test --project-path /Users/max/Проекты/TaskFlowNativeBuild/TaskFlow.xcodeproj --scheme TaskFlow --simulator-id 9FF78D89-EE84-4914-AA56-D0A72D1AF43A --derived-data-path /Users/max/Проекты/TaskFlowNativeBuild/build_sim --extra-args -only-testing:TaskFlowUITests/RoleChatMembershipUITests -only-testing:TaskFlowTests/RoleChatMembershipTests -only-testing:TaskFlowTests/HintCenterTests -parallel-testing-enabled NO --progress false --output json.
