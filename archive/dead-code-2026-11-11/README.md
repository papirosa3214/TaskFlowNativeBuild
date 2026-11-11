# Архив мёртвого кода — 2026-11-11

Реестр: `LOCK-DEAD-CODE-ARCHIVE-20261111`, Scope `DEAD-CODE`.
Основание: владелец 11.11.2026 — «вычистить то, чем не пользуюсь». Аудит: rg по Sources, VoiceMessageLab, Widgets, Broadcast и тестам; на файлы нет ссылок из приложения.

Файлы сохранены здесь с прежними относительными путями. Ничего не удалено насовсем.

| файл | откуда вырезан | почему мёртв (кто на него ссылался) | что убрано в живых файлах вместе с ним |
| --- | --- | --- | --- |
| `Sources/Features/Roles/SubagentRail.swift` | `Sources/Features/Roles/` | Только свой тест `Tests/SubagentRailTests.swift`, в приложении не используется | — |
| `Sources/Features/Roles/RoleMessageReveal.swift` | `Sources/Features/Roles/` | Не используется; тест `Tools/test_role_message_reveal_interrupt.py` перенесён вместе | — |
| `Sources/Chat/Panels/ChatRoomsPanel.swift` | `Sources/Chat/Panels/` | Не используется; связан с `ChatEdgeRail` | — |
| `Sources/Chat/Panels/ChatEdgeRail.swift` | `Sources/Chat/Panels/` | Не используется; `chatEdgeRailStretch` и `ChatEdgeRailMetrics` читают только переносимые файлы | — |
| `Sources/Chat/Shared/ProviderQuotaSheet.swift` | `Sources/Chat/Shared/` | Не используется | — (в `Tools/design-system-baseline.txt` остались записи о нём, базу не трогали) |
| `Sources/Features/Coordination/StreamWindow.swift` | `Sources/Features/Coordination/` | `MessageDeliveryChip` использовался только в `Tests/CoordinationTests.swift` | `Tests/CoordinationTests.swift`: удалены `testAllDeliveryStatesHaveUniqueSymbol`, `testQueuedMinutesAppearInChipText` и заголовок `// MARK: - 4 состояния доставки сообщения` |
| `Sources/Features/ServiceNotifications/NotificationTicketDetailSheet.swift` | `Sources/Features/ServiceNotifications/` | Не используется; упоминается только в строке-списке `Tests/RoleReplyRenderTests.swift` | `Tests/RoleReplyRenderTests.swift`: убраны записи пути из `roleTextPlaces` |
| `Sources/Features/ServiceNotifications/NotificationTicketCard.swift` | `Sources/Features/ServiceNotifications/` | Не используется; в тестах только комментарий | — (`Tools/design-system-guard.py:321` оставлен как есть) |
| `Sources/Core/Networking/ThingsBridgeAPI.swift` | `Sources/Core/Networking/` | Вызывался только из `loadThingsBridge`/`syncThings` (тоже мёртвые) | `Sources/Features/Settings/IntegrationsScreen.swift`: удалены функции `loadThingsBridge()` и `syncThings(taskStore:projectStore:)` |
| `Sources/Core/ChatScrollTrace.swift` | `Sources/Core/` | Не используется; тесты `Tests/ChatScrollTraceTests.swift` и `Tools/test_chat_scroll_trace.py` перенесены вместе | — |
| `Sources/Features/Tasks/Detail/SubtaskFeedView.swift` | `Sources/Features/Tasks/Detail/` | Не используется; в `Tests/RoleReplyRenderTests.swift` и `Tools/design-system-baseline.txt` только строки путей | `Tests/RoleReplyRenderTests.swift`: убраны записи пути из `roleTextPlaces` и `candidates` |
| `Sources/Features/Tasks/Detail/SubtaskHostPicker.swift` | `Sources/Features/Tasks/Detail/` | Не используется; связан с `SubtaskFeedView` | — (записи в `Tools/design-system-baseline.txt` оставлены) |
| `Sources/DesignSystem/Navigation/SwipeBackEnabler.swift` | `Sources/DesignSystem/Navigation/` | `swipeBackEnabled()` не вызывается | — |
| `Sources/Core/Models/TaskRoleContent.swift` | `Sources/Core/Models/` | Не используется; тест `Tests/TaskRoleContentTests.swift` перенесён вместе | — |
| `Sources/Core/Models/AgentDetails.swift` | `Sources/Core/Models/` | Типы использовались только мёртвыми методами `APIClient+AgentDetails` | `Sources/Core/Networking/APIClient+AgentDetails.swift`: удалены `agentDetails`, `mcpServersCatalog`, `skillsCatalog`, `updateAgentConnection`, `updateAgentPermissions`, структуры `McpCatalogEntry`, `SkillCatalogEntry` и заголовки `// MARK: - Чтение`, `// MARK: - Каталожные записи`. Живые `saveAgentApiToken`, `rotateAgentApiToken`, `RotatedAgentToken` оставлены |
| `Sources/Core/Networking/APIClient+ChatAttachments.swift` | `Sources/Core/Networking/` | `extractTasksFromAttachment`, `attachmentSupportsTaskExtraction` не вызываются | — |
| `Sources/DesignSystem/Components/TFHeaderBackdrop.swift` | `Sources/DesignSystem/Components/` | Не используется: единственная ссылка — собственный `#Preview`; шапки экранов теперь системные (`.tfNativeHeader`), самодельные подложки не нужны | `COMPONENTS.md`: убран раздел «Подложка шапки»; `Sources/Features/Tasks/TaskCardContent.swift`: комментарий больше не ссылается на компонент |

Тесты, перенесённые вместе с кодом: `Tests/SubagentRailTests.swift`, `Tests/ChatScrollTraceTests.swift`, `Tests/TaskRoleContentTests.swift`, `Tools/test_chat_scroll_trace.py`, `Tools/test_role_message_reveal_interrupt.py`.

## Оставлены в живом дереве (не переносились)

- `Sources/Features/Roles/ChatSearchScreen.swift` — живые модели `ChatSearchHit`/`ChatSearchEnvelope` (`RoleChatsScreen.swift`, `APIClient+RoleChats.swift`).
- `Sources/App/Navigation/ChatBackAction.swift` — в файле живой ключ `openRoute` (используется в ~8 экранах).
- `VoiceMessageLab/Audio/VoiceActivityGate.swift` — явно перечислен в `project.yml` (строка 25) и покрыт `VoiceMessageLabTests`.
- `Sources/Core/Common/LastValueCache.swift` — нужен `MarkdownParser.parseIncremental` (`Sources/Core/Text/MarkdownParser.swift`), покрытому `Tests/MarkdownParseIncrementalTests.swift`.

## Как вернуть

1. Вернуть файл на прежний путь: `git mv archive/dead-code-2026-11-11/<путь> <путь>` (пример: `git mv archive/dead-code-2026-11-11/Sources/Chat/Panels/ChatEdgeRail.swift Sources/Chat/Panels/ChatEdgeRail.swift`).
2. Восстановить вырезанные в живых файлах строки из `git show <коммит-до-переноса>:<путь>`.
3. `xcodegen generate`.
