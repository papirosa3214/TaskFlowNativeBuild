# Git-доставка iOS-клиента: незакоммиченное и локальные ветки — 02.11.2026

Поручение владельца: «Посмотри все изменения, которые есть… в локальном репозитории
iOS приложения. Посмотри все ветки, которые там есть, есть ли что-то незакоммиченное,
соответственно, надо закоммитить локально и запушить на GitHub».

## Что было в репозитории

Рабочая копия `main` была синхронна с GitHub (`af35857a`, PR #16 влит). Незакоммиченного
кода в `main` не было — только локальные артефакты. Реальная незакоммиченная работа
лежала в трёх worktree.

| Worktree | Что было | Решение |
| --- | --- | --- |
| `.worktrees/host-6a0b387e…` | `project.yml` — из схемы убраны `TaskFlowTests` и `TaskFlowSnapshotTests`; новый `UITests/QAChatWindowUITests.swift` | Правка `project.yml` — локальная оптимизация прогона тестов, в репозиторий не годится: откачена (патч сохранён). UI-тест закоммичен и запушен отдельной веткой |
| `.worktrees/host-824684dcf0ac…` | `Color+Palette.swift` — тёплый белый `static let`; `Tools/test_chat_envelope_answer_once.py`; `extract_status_icon.py`; `remove_dead_screens.py` | Всё устарело: в `main` тон текста уже сделан иначе (выбираемый владельцем `TFTextTone`, коммит `9e87b0dc`), скрипт в `main` новее (`itemsWithoutAnswerText`, `Sources/Features/Roles/`), работа обоих python-скриптов уже в `main`. Откачено, копии убраны в корзину (сохранены в `/tmp/taskflow-preserved-20261102/`) |
| `.worktrees/2980844e…` | только артефакты сборки (`build_qa/`) и кадры (`qa-shots/`) | Закоммичена сама работа ветки, артефакты — в `.gitignore` |
| `.factory/worktrees/bcb64c5b/…/m3-before` | правка `Tests/Today/TodayFilterEngineTests.swift` | Та же правка уже закоммичена в `droid/repair-taskflow-test` (`63d3ab29`) — дубль, ничего не теряется |

Страховка до любых действий: всё содержимое worktree и незакоммиченное из `main`
скопировано в `/tmp/taskflow-preserved-20261102/`.

## Что запушено

| Ветка | PR | Содержание |
| --- | --- | --- |
| `test/qa-chat-window` | [#18](https://github.com/papirosa3214/TaskFlowNativeBuild/pull/18) (черновик) | UI-тест «разведка окон чата». Не запускался — правило владельца 25.10.2026 |
| `chore/gitignore-local-artifacts` | [#19](https://github.com/papirosa3214/TaskFlowNativeBuild/pull/19) | Локальные артефакты в `.gitignore` + строка реестра |
| `roles/2980844e-f961-439a-b970-15903a358896` | [#20](https://github.com/papirosa3214/TaskFlowNativeBuild/pull/20) | Догон сущностей по курсору (`main` влит в ветку, конфликтов не было) |
| `droid/repair-taskflow-test` | без PR | 24 коммита работы на старой базе — только бэкап |
| `docs/handover-20261102` | [#17](https://github.com/papirosa3214/TaskFlowNativeBuild/pull/17) | Сборка была красной из-за очереди macOS-раннеров (`The job was not acquired by Runner of type hosted`), не из-за кода — прогон перезапущен |

Все пуши — и в `github` (локальное зеркало, как в `AGENT-CYCLE.md`), и в `origin`
(настоящий GitHub), чтобы PR жили на GitHub.

## Что намеренно не запушено

- **Ветки, уже влитые в `main`**: `docs/design-md-five-groups`, `feature/composio-screen-cache`,
  `feature/hints-mission-control`, `m3-onto-main`, `roles/4792cc59…`, `roles/host-6a0b…`,
  `roles/host-8246…`, `roles/host-d7bbbfe…`, `roles/host-f839d01…`, `roles/host-fde30a…`,
  `secretary/dead-screens`, `traycer/taskflownativebuild-wild-octopus`. Их содержимое уже
  в `main`, отдельные ветки на GitHub были бы мусором.
- **`roles/inbox-attention-20261028`** — устарела: её экран «Входящие» построен на своём
  API-контракте (`ApiAttentionItem`/`ApiAttentionToday`/`ApiAttentionRunning`/`ApiAttentionUpcoming`),
  в `main` уже `ApiAttentionTicket` из более поздней работы.
- **`droid/repair-taskflow-test`** — 24 коммита, база на 77 коммитов старше `main`. Слияние
  сейчас — это перенос всей структурной переработки поверх нового `main`; такую работу
  нужно заводить осознанно (rebase), а не вливать в PR.

## Проверки

- `python3 Tools/test_entity_sync.py` (работа ветки PR #20) — 10 unit-тестов
  `EntitySyncPolicyTests` зелёные, статические проверки зелёные.
- `swiftc -parse UITests/QAChatWindowUITests.swift` — синтаксис без ошибок.
- `git check-ignore` — ни один tracked-файл под новые паттерны `.gitignore` не попадает.
- Сборка приложения локально не гонялась: CI собирает схему `TaskFlow` в каждом PR, а
  симулятор и установка на iPhone — только по отдельному поручению владельца
  (правило 25.10.2026). UI-тесты не запускались.
- Визуальную приёмку делает владелец.
