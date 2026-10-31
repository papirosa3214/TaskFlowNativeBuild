# Milestone 1 «Зелёный старт» — доказательство зелёной базы (31.10.2026)

Фича `m1-verify-green-baseline` миссии `dd8e55d5`. Утверждения: VAL-INFRA-011,
VAL-INFRA-012, VAL-INFRA-013. База миссии — `737f86e6`.

Задача фичи — не починка, а доказательство: после трёх предыдущих фич Milestone 1
(импорты тестов, пути в хостовых скриптах, красный бандл, честный ноль NEW в скане)
проверить, что база зелёная и что поведение приложения не изменилось.

## 1. VAL-INFRA-011 — под `Sources/` только устаревшие литералы путей

Единственная правка этой фичи в `Sources/` — три литерала пути в
`Sources/Features/Roles/RoleChatsScreen.swift` (DEBUG-стенд шатания, `#if DEBUG`,
строки 1049, 1056, 1096). Они указывали на файлы, переехавшие при рефакторинге
папок `8212bc89`: `Sources/Features/Chat/RoleActionGroup.swift` и
`Sources/Features/Chat/RoleLiveTurnView.swift` → `Sources/Features/Roles/…`.

```
$ rg -n "Sources/Features/Chat/" Sources/Features/Roles/RoleChatsScreen.swift
(нет совпадений)

$ python3 -c "import re,os; t=open('Sources/Features/Roles/RoleChatsScreen.swift').read(); \
  ps=set(re.findall(r'Sources/[A-Za-z0-9_./+-]*\.swift', t)); print([p for p in ps if not os.path.exists(p)])"
[]

$ git diff --name-only 737f86e6..HEAD -- Sources
Sources/Features/Notifications/ServiceTicketPresentation.swift
Sources/Features/Roles/RoleChatsScreen.swift
```

Про `Sources/Features/Notifications/ServiceTicketPresentation.swift`: это **не** правка
этой фичи, а разрешённая VAL-INFRA-014 поведенческая правка фичи
`m1-fix-red-xctest-bundle` (коммит `6089ab3f`) — `markTruncated(_:)` не убирал
хвостовые пробелы перед дописыванием «подробности не пришли». Сделан RED → GREEN,
перечислен в отчёте `docs/2026-10-31-red-bundle-repair.md` и в allow-list
VAL-STRUCT-006. Прочий код под `Sources/` не тронут.

Остальные литералы путей в файле (`Sources/Core/Models/RoleChat.swift`,
`Sources/DesignSystem/Components/FlowLayout.swift`) существуют. Строка
`"scrollPosition Sources/Features/Chat"` — это пример команды grep в том же DEBUG-стенде,
а не литерал пути к файлу; она перечислена в контракте вне трёх подлежащих правке.

## 2. VAL-INFRA-012 — `project.yml` не тронут, проект перегенерируется

```
$ git diff --exit-code 737f86e6..HEAD -- project.yml   # пусто, exit 0
$ xcodegen generate
Created project at .../TaskFlow.xcodeproj
```

## 3. Сводный гейт milestone'а (`services.yaml: gate`) — exit 0

| Проверка | Результат |
|---|---|
| `python3 Tools/design-system-guard.py --folder` | «Сторож дизайн-системы: чисто.», exit 0 |
| `bash Tools/ui-drift-scan.sh` | «Новых отклонений (NEW): 0», KNOWN 23, exit 0 |
| `python3 Tools/control-color-guard.py --folder` | exit 0, нарушений нет |
| `python3 Tools/screen-heading-guard.py` | exit 0, нарушений нет |
| `Tools/test_*.py` | 50/50 зелёные (`host_count=50 host_fail=0`) |

Лог: `.worktrees/_bg/infra-gate.log`.

## 4. VAL-INFRA-013 — сборка, запуск и рендер на разрешённом симуляторе

Устройство: iPhone Air, iOS 27.0, UDID `9FF78D89-EE84-4914-AA56-D0A72D1AF43A`
(единственный загруженный; другие не загружались).

```
$ xcodebuild … -destination 'generic/platform=iOS Simulator' … build
** BUILD SUCCEEDED **                                     # .worktrees/_bg/infra-013-build.log

$ xcodebuild … -destination 'platform=iOS Simulator,id=9FF78D89-…' … test -only-testing:TaskFlowTests
** TEST SUCCEEDED **
Executed 1001 tests, with 0 failures (0 unexpected)
# .worktrees/_derived/Logs/Test/Test-TaskFlow-2026.10.31_20-32-02-+0300.xcresult

$ xcrun simctl install 9FF78D89-… .worktrees/_derived/Build/Products/Debug-iphonesimulator/TaskFlow.app
install_exit=0
$ SIMCTL_CHILD_TASKFLOW_DEBUG_ROUTE=overview xcrun simctl launch 9FF78D89-… com.maksim.taskflow.native
com.maksim.taskflow.native: 21987
$ xcrun simctl io 9FF78D89-… screenshot docs/2026-10-31-infra/root.png
```

Кадр `root.png` — 258 139 байт, 1260×2736 пикселей (полное разрешение iPhone Air,
420×912 @3x), на нём отрисован экран «ОБЗОР» с живыми данными: тепловая карта
активности за месяцы, «Загрузка ролей — свободны», «Состояние системы — не
починено: 9», «Мои рутины — 2 активных».

`root-fixture.png` — тот же экран в офлайн-режиме (фикстура
`Tools/websocket-energy-fixture.py` на `127.0.0.1:3307`, `TASKFLOW_LINEAR_CARD_DEMO=1`,
`TASKFLOW_DEBUG_TOKEN=fixture`): приложение ходит на фикстуру (`/api/tasks`,
`/api/auth/me`, `/api/chats` — 200), но фикстура не отдаёт `/api/stats/review-history`,
поэтому панель истории показывает «История недоступна». Это ограничение фикстуры,
а не приложения.

**Грабли, которые соблюдены:** у `xcrun simctl launch` нет флага `--env` — переменные
окружения задаются префиксом `SIMCTL_CHILD_`; фикстура поднята отдельным долгоживущим
фоновым процессом (порт 3307), а не `nohup … &` внутри одной shell-команды.

Внешний вид оценивает владелец; миссия визуальной приёмки не заявляет.
