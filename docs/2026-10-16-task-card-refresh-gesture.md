# Карточка: конфликт refresh и жестов шторки — 16.10.2026

## Дефект и причина
Путь владельца: календарь → список → Входящие → карточка задачи.
`UpcomingScreen` задавал `.refreshable` для всей `content`. Внутри неё `TodaySectionView` открывал собственную `taskCardSheet`. Поэтому `List` карточки наследовал родительский `EnvironmentValues.refresh`, создавал pull-to-refresh и перехватывал вертикальные жесты. Наличие общих presentationDetents/resizes этого не исправляло.

Прямой DEBUG-вход в карточку и открытие из общего списка `ProjectTasksScreen` работали: там refresh внутрь шторки не попадал. Именно поэтому прежняя проверка пропустила дефект.

## Воспроизведение
1. Контроль: настоящий прямой вход и строка общего списка, 1 UI-тест PASS (35.831 s); обе карточки refresh:none, medium → large → medium → закрыта.
2. После уточнения владельца проверен точный путь Входящих: `testCalendarInboxCardGestures`, FAIL с тремя ожидаемыми проверками — не раскрывается, не закрывается, refresh:inherited вместо refresh:none. Тест не менял задачи и не сохранял связи.
3. На кадрах before-inbox-source.png и before-inbox-after-pull-down.png видны Входящие и карточка, оставшаяся на половинной высоте после свайпов.

Для выбора реального списка запуск использовал DEBUG route upcoming и launchArguments `-plannerSection today -today_layout list -today_list_tab inbox -hints.enabled NO`. Это тот же UpcomingScreen/TodaySectionView, которые работают у владельца. Переменные не подменяют сеть или механизм шторки.

## Исправление
- Убран `.refreshable` с общего предка контента календаря.
- Обновление перенесено к конкретным календарным представлениям трёх дней, недели и месяца. В почасовом виде TodaySectionView обновление также стоит у сетки, вне владельца taskCardSheet.
- У списка TodaySectionView сохранён его собственный refresh. Обновление списков, первоначальная загрузка и события данных не отключены.
- Добавлен DEBUG accessibilityValue refresh:none/refresh:inherited у List карточки для точной проверки причины; визуальное оформление не меняется.
- Добавлены стабильный ID кнопки DirectoryTaskRow и DEBUG route alltasks для контрольного реального входа. Они не создают отдельный тестовый интерфейс.

## Проверка после исправления
Неизменный `testCalendarInboxCardGestures`: **PASS 1/1, 0 failures, 18.517 s**. Карточка из Входящих имеет refresh:none; проверки высоты medium → large → medium и исчезновения карточки после свайпа прошли. Кадры after-inbox-large.png и after-inbox-after-dismiss.png просмотрены: карточка раскрыта, затем виден исходный список Входящих без шторки.
Итого выполнены один контрольный прогон до уточнения пути и два прогона точной регрессии (до/после). Дополнительная необходимая проверка после воспроизведения выполнена по указанию владельца продолжать работу и проводить необходимые проверки без повторных подтверждений. Успешные сценарии не гонялись повторно.
TEST BUILD SUCCEEDED, iPhone Air Simulator iOS 27.0, UDID 9FF78D89-EE84-4914-AA56-D0A72D1AF43A. Изменение теста и затем Swift-кода потребовало инкрементальной сборки соответствующих продуктов; test execution использовал готовый .xctestproducts.
Временный тест перенесён в папку доказательств, из UITests удалён, выполнен xcodegen generate. После проверки восстановлен обычный запуск без DEBUG-маршрута и аргументов: launch-app SUCCEEDED, PID 73360. Симулятор открыт видимым окном через open_sim.
Плавность/CPU/FPS не измерялись: исправлялся конфликт жестов, утверждений о производительности нет. Каждый режим календаря отдельно в UI не обходился; перенос обновления в них проверен по исходникам и сборке.
Физический iPhone не используется по прямому указанию владельца в этой задаче.

## Артефакты
Папка docs/2026-10-16-task-card-refresh-gesture содержит выбранные кадры и JSON MCP.
Полный экспорт контрольного прогона: build_sim/taskcard-refresh-evidence/control/.
Полный экспорт регрессии до исправления: build_sim/taskcard-refresh-evidence/inbox-before/.

XcodeBuildMCP workspace: /Users/max/Library/Developer/XcodeBuildMCP/workspaces/TaskFlowNativeBuild-6630a891c838/.
Контроль: result-bundles/test_sim_2026-10-16T00-37-36-204Z_pid56684_92cbbaed.xcresult.
До исправления: result-bundles/test_sim_2026-10-16T00-44-01-902Z_pid67971_cf0de4a1.xcresult.

Урок: проверять именно фактический путь владельца. Одинаковый sheet-компонент не гарантирует одинакового поведения при разном окружении предков.

После исправления: result-bundles/test_sim_2026-10-16T00-45-40-739Z_pid70785_db2de945.xcresult.
Готовые продукты после исправления: test-products/test_sim_2026-10-16T00-45-40-739Z_pid70785_d44d975a.xctestproducts в том же workspace.
Полные вложения после исправления: build_sim/taskcard-refresh-evidence/inbox-after/.
JSON: control-result.json, inbox-before-result.json, inbox-after-result.json; временный тест TaskCardRefreshGestureUITests.swift лежит рядом с кадрами в папке отчёта.

Чужие изменения .codex/config.toml, SettingsScreen.swift, RemoteMachinesSection.swift, RemoteMachinesUITests.swift и каталог </ не изменялись и не включаются в коммит.
