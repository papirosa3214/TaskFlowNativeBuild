# Назначение отдельно от запуска

По указанию владельца 04.10.2026 возвращено разделение действий в меню карточки.

- Выбор роли сохраняет `owner_selected_role` и `assignee_id`, не вызывает `/run` и не поднимает `ready_for_pickup`.
- Выбор «Автоматически» снимает явное назначение без запуска диспетчера.
- Кнопка «Запустить исполнителя» сохраняет прежний явный механизм запуска.

Изменён только обработчик назначения в `TaskFormScreen.swift` и его комментарии. Уже принятые сервером запуски этим изменением не отменяются.

Проверка: xcodegen generate; XcodeBuildMCP build_sim, Debug / iPhone Air — BUILD SUCCEEDED. Проверен обработчик: нет вызовов launchExecutor/runAgent/startTask или изменения ready-флага. UI-сценарий и физический iPhone не проверены.

Лог сборки: `/Users/max/Library/Developer/XcodeBuildMCP/workspaces/TaskFlowNativeBuild-6630a891c838/logs/build_sim_2026-10-04T17-24-28-096Z_pid6216_b9da74d7.log`.
