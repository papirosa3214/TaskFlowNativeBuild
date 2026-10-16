# Унификация карточки задачи — 16.10.2026

## Результат
Продолжение `28f48358`: оставшиеся входы существующей карточки используют общую шторку `taskCardSheet` с medium/large и interaction resizes. После закрытия остаётся экран-источник. Создание дочерней, привязка существующей дочерней и выбор родителя сохранены.

| Источник | Механизм |
| --- | --- |
| Проекты, календарь, Сегодня, метки, нагрузка ролей, профиль и работа агента, заметки, ссылки сообщений | taskCardSheet, исходный коммит 28f48358 |
| Поиск, уведомления, лента, статистика | taskCardNavigation → taskCardSheet |
| Задача чата, виджет task://, очередь ролей, импорт Linear | TaskCardLink → taskCardSheet |
| Связанные карточки внутри карточки, DEBUG task/tasksheet | taskCardSheet / taskCardSheetPresentation |

Добавлена подсказка «Связанные задачи» и unit-проверка её завершения. Архивный просмотр только для чтения и создание новой задачи сохраняют свои сценарии. Прямых NavigationLink к taskDetail в Sources больше нет. Старый case фабрики маршрутов сохранён для совместимости; текущие входы карточек через него не проходят.

## Проверка
- TEST BUILD SUCCEEDED: iPhone Air Simulator, iOS 27.0, UDID 9FF78D89-EE84-4914-AA56-D0A72D1AF43A.
- HintCenterTests: 7/7 PASS.
- Первый UI-прогон: FAIL в тесте — строковый NSPredicate с frame.size.height вызвал NSInvalidArgumentException.
- Второй UI-прогон: проверены увеличение высоты medium → large, раскрытие связей, открытие короткой карточки дочерней, обе кнопки, отсутствие второй кнопки скрытия клавиатуры и скрытие клавиатуры. Затем FAIL в тесте: цикл продолжил свайпы после исчезновения карточки. Ошибка цикла исправлена.
- После прямого разрешения владельца выполнена только оставшаяся проверка `testCardDismissalReturnsToSource`: **1/1 PASS, 0 failures, 18.774 s**. Карточка раскрыта, закрыта свайпами, task.content исчез, «ОБЗОР» доступен для нажатия. Кадр 08 визуально проверен: открыт исходный экран без шторки.
- Полный длинный тест после исправления цикла заново не запускался: успешно пройденные шаги не повторялись.
- Подсказки в UI-проверках отключены только аргументом запуска `-hints.enabled NO`; постоянные настройки не менялись.
- Временный UI-тест перенесён из UITests в папку доказательств, выполнен xcodegen generate.
- Восстановлен обычный запуск без DEBUG-маршрута и тестовых аргументов: launch-app SUCCEEDED, PID 23902.
- git diff --check: без ошибок.

## Артефакты
Папка `docs/2026-10-16-task-card-unification/`:
- 01-medium.png, 02-large.png — начальная и раскрытая шторка;
- 03-links.png — три действия связей;
- 04-child-keyboard.png, 05-child-keyboard-hidden.png — короткая карточка;
- 07-before-dismissal.png, 08-returned-to-source.png — финальная проверка;
- TaskCardUnifyUITests.swift — исходник временного теста;
- attempt-1-result.json, attempt-2-result.json, attempt-3-result.json — результаты MCP.

Полные экспорты вложений, видео и AX-иерархии сохранены локально в `build_sim/taskcard-evidence/attempt-{1,2,3}/`; массовые артефакты не добавляются в Git согласно .gitignore.

XcodeBuildMCP workspace: `/Users/max/Library/Developer/XcodeBuildMCP/workspaces/TaskFlowNativeBuild-6630a891c838/`.

| Прогон | xcresult в result-bundles/ |
| --- | --- |
| 1 | test_sim_2026-10-16T00-07-19-504Z_pid10166_29b76abc.xcresult |
| 2 | test_sim_2026-10-16T00-09-08-881Z_pid13189_4fbf07c4.xcresult |
| 3 PASS | test_sim_2026-10-16T00-12-20-600Z_pid19647_22ec7b4e.xcresult |

Готовые продукты финальной проверки: `test-products/test_sim_2026-10-16T00-12-20-600Z_pid19647_55599620.xctestproducts` в том же workspace. Повтор неизменного теста — test-without-building; после изменения Swift-теста продукты пересобираются инкрементально.

Целевой запуск: `xcodebuildmcp simulator test --project-path /Users/max/Проекты/TaskFlowNativeBuild/TaskFlow.xcodeproj --scheme TaskFlow --simulator-id 9FF78D89-EE84-4914-AA56-D0A72D1AF43A --derived-data-path /Users/max/Проекты/TaskFlowNativeBuild/build_sim --extra-args -only-testing:TaskFlowUITests/TaskCardUnifyUITests/testCardDismissalReturnsToSource -parallel-testing-enabled NO --progress false --output json`.

## Ограничения и оставшаяся приёмка
Владелец 16.10.2026 разрешил не проводить проверки через iPhone в рамках этой задачи и взял физическую проверку на себя. Она не блокирует завершение работы агента; установка и тесты на iPhone не проводились. Исходники и отчёт отправлены в GitHub и Gitea. Строки остаются REVIEW для приёмки владельцем. Доработок кода по согласованному плану не осталось.

Каждый экран-источник отдельно не обходился: подключения проверены по исходникам и сборке, поведение — на общем компоненте. Реальная запись диктовки и сохранение связей на сервере этим тестом не проверяются. На кадре 04 виден системный первый экран клавиатуры «Speed up your typing»; обычная раскладка клавиатуры этим кадром не подтверждена. Проверки производительности и утверждений о FPS/нагрузке нет.

Чужие изменения SettingsScreen, RemoteMachinesSection, RemoteMachinesUITests, .codex/config.toml и каталог </ сохранены и не включены в коммит.
