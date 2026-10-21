# Выделенная линия Разработчика → MacBook / Xcode MCP (не актуально)

04.10.2026. Назначение: роль builder в TaskFlow на .110 получает инструменты MacBook автоматически при новом запуске в режиме work. Другие роли и plan/review/reply не получают их. У уже запущенной сессии список инструментов не меняется.

## Рабочая копия
- `/Users/max/Проекты/TaskFlowDeveloper`, ветка `codex/developer-mac`, исходная база `a86d0acd`.
- Каноническая `/Users/max/Проекты/TaskFlowNativeBuild` через файловый gateway неизменяема.
- Разработчик обязан соблюдать AGENT-WORK-SCOPES; владелец разрешил именно выделенную копию как рабочую папку этой линии, несмотря на унаследованное указание канонического пути в AGENTS.md. Не менять канонический путь в Git-документах ради локального окружения.
- Перед сборкой: `mcp__xcode__mac_prepare` (xcodegen).
- Xcode MCP defaults: TaskFlow.xcodeproj, scheme TaskFlow, Simulator iPhone 18 Pro; отдельная DerivedData `build_developer`. Симулятор пока общий, новый отдельный симулятор не создавался.

## Инструменты
47 инструментов: XcodeBuildMCP 2.7.0 (40) и 7 gateway-команд.
`mcp__xcode__mac_status`, `mac_read_file`, `mac_write_file`, `mac_diff`, `mac_prepare`, `mac_commit` (только явно перечисленные пути), `mac_push` (только codex/*).
Имена Xcode включают `list_schemes`, `session_show_defaults`, `build_sim`, `build_run_sim`, `test_sim`, debugging. Перед реальной сборкой проверить defaults; изменения и проверку UI выполнять через XCUITest по правилам проекта. Xcode IDE / mcpbridge Apple отдельно не включался: канал использует XcodeBuildMCP.

## Транспорт и управление
- Сервер: `/home/maksim/taskflow/roles/builder/mcp/xcode.json`.
- Скрипт stdio для MCP-клиента: `/home/maksim/taskflow/roles/builder/scripts/mac-xcode-mcp.sh`.
- MCP client config: `/home/maksim/taskflow/roles/builder/mcp/client.json`.
- Ключ `.110`: `/home/maksim/.ssh/taskflow-builder/mac_ed25519` (0600). Ключи и приватный конфиг не хранятся в Git.
- Mac authorized_keys: отдельная запись taskflow-builder-mac; from=.110, restrict, forced gateway `Tools/developer-mac-gateway.py`. Без интерактивной SSH-консоли и forwarding. Host key закреплён в dedicated known_hosts; адрес по mDNS.
- Журнал входов Mac: `/Users/max/Library/Logs/TaskFlowDeveloper/access.jsonl`.
- Отключение: удалить только строку taskflow-builder-mac из authorized_keys и убрать builder/mcp/xcode.json. Остальные SSH-входы не затрагиваются.

## Реальная граница доступа
Это ограничение выдачи инструментов по роли плюс выделенный SSH-ключ, НЕ системная песочница. Все роли сервера исполняются под общей Unix-учёткой maksim; MCP Xcode работает под max на Mac. Отдельные Unix-пользователи/изоляция нужны, чтобы исключить обход через общий доступ к файловой системе. Xcode сборки выполняют код проекта; forced SSH не ограничивает полномочия самого Xcode MCP. Разработчик должен использовать только выделенную папку. При недоступном Mac включённый канал явно сообщает ошибку подключения; работа builder требует доступности Mac.

## Приёмка
- .110 → Mac SSH gateway status/prepare PASS.
- Реальный MCP initialize/listTools PASS (40 tools); list_schemes нашёл TaskFlow, TaskFlowWidgets, VoiceMessageLab.
- Runtime connector: builder/work 47 tools, architect/work 0, builder/plan 0; реальные mac_read_file/mac_write_file PASS. Тестовый файл удалён.
- session_show_defaults подтвердил выделенные пути и схему.
- SSH uname отклонён; read ../TaskFlowNativeBuild/AGENTS.md отклонён.
- 24 профильных теста builderXcode/inProcessRun PASS; TypeScript compilation PASS.
- Новый реальный модельный запуск, сборка/дебаг через этот канал и push из developer clone не выполнялись; подпись устройств может потребовать разблокировки keychain в SSH-сессии.
- Сервер runtime развёрнут на .110 без миграций. Backup `/home/maksim/backups/taskflow/20261004-builder-xcode`. Проверяется health после завершения.
