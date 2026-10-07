# Цикл работы агента с iOS-клиентом TaskFlow

Полный путь задачи по нативному клиенту: от карточки до телефона. Читать
целиком перед первой правкой; детали правил — в файлах, на которые здесь
ссылки, а не здесь.

## Карта: что где лежит

| Что | Где |
| --- | --- |
| Исходник (единственная копия) | `/Users/max/Проекты/TaskFlowNativeBuild` на MacBook |
| Мак по сети | `max@MacBook-Pro-Maksim.local` — только по имени, адрес плавает по DHCP; логин `max` |
| Бэкенд и веб TaskFlow (сюда натив не кладётся) | `~/Проекты/New-Todoist` на .110 (`192.168.1.110`) |
| Доска задач | `https://192.168.1.110:5180` |
| Секреты (vault) | только на .110: `~/.claude/vault-run.py`, `~/.claude/vault-get.py` |
| Реестр разрешённых правок | `AGENT-WORK-SCOPES.md` в корне репозитория |
| Правила кода и проверки | `CLAUDE.md` (Claude), `AGENTS.md` (остальные агенты) |
| Дизайн-система и компоненты | `DESIGN.md`, `COMPONENTS.md`, `ARCHITECTURE.md` |
| Описание проекта для сборки | `project.yml` → `xcodegen generate` → `TaskFlow.xcodeproj` (в `.gitignore`) |
| Код | `Sources/` (`App`, `Core`, `DesignSystem`, `Features/<Экран>`) |
| Тесты | `Tests/` (юнит), `UITests/` (XCUITest), `SnapshotTests/` |
| Отчёты по работам | `docs/ГГГГ-ММ-ДД-<тема>.md`, кадры — в папке `docs/ГГГГ-ММ-ДД-<тема>/` |
| Граф кода | `graft/` в корне; `~/.local/graft/node_modules/.bin/graft` |
| Установка на iPhone | `install-iphone.sh` в корне |
| Сборочные папки (не трогать, не коммитить) | `build_sim`, `build_device`, `build_dev`, `build_check`, `.build` |

Бандл приложения — `com.maksim.taskflow.native`. Схема — `TaskFlow`.
Минимальная iOS — 18.0.

## Откуда ты работаешь

**С мака** (сессия запущена в каталоге репозитория) — команды напрямую.

**С .110** (Claude Code, Гермес, Codex и др.) — всё идёт через ssh на мак.
Инструменты Homebrew видны только в логин-шелле, поэтому команды
оборачиваются в `zsh -lc`:

```bash
ssh max@MacBook-Pro-Maksim.local "zsh -lc 'cd ~/Проекты/TaskFlowNativeBuild && git status -sb'"
```

У Claude Code на .110 есть MCP `XcodeBuildMCP` — он сам ходит на мак по ssh
(`max@MacBook-Pro-Maksim.local`, `xcodebuildmcp mcp`) и даёт сборку,
симулятор, UI-автоматизацию и отладку. Конфиг его возможностей —
`.xcodebuildmcp/config.yaml` в репозитории.

Копия репозитория на .110 или где-либо ещё — источник потерянной работы
(прецеденты 02.09 и 08.09.2026). Код живёт в одном каталоге на маке и
переносится только через git.

## Цикл

### 1. Карточка

Многошаговая работа — карточка в TaskFlow до первой правки (протокол —
`AGENT-PROTOCOL.md` в `~/Проекты/New-Todoist`). Взял — `taskflow_claim`,
дальше `taskflow_heartbeat`. Готово, когда карточка взята и в ней видна
постановка.

### 2. Граница правки

Открой `AGENT-WORK-SCOPES.md` и заведи строку `IN_PROGRESS`: Lock ID, что
чиним, точный список разрешённых файлов, как проверим. Менять можно только
файлы из этой строки; смежную проблему — назвать владельцу и ждать ответа.
Готово, когда строка записана и в ней перечислен каждый файл, который
собираешься трогать.

### 3. Найти код

Сначала граф, потом поиск руками:

```bash
ssh max@MacBook-Pro-Maksim.local "zsh -lc 'cd ~/Проекты/TaskFlowNativeBuild && ~/.local/graft/node_modules/.bin/graft ask \"task detail screen\"'"
```

Спрашивать английскими словами и именами типов: русский запрос «экран
карточки задачи» вернул пусто, английский — `TaskFormScreen.swift`. Пусто — `graft grep
"<литерал>"`, `graft callers <символ>`. Найденное сверь по исходнику: граф
может отстать. Готово, когда открыт настоящий файл экрана, а не заглушка.

### 4. Правка

- С мака — обычными инструментами редактора.
- С .110 — точечно по ssh: прочитать `ssh max@… 'cat ~/Проекты/TaskFlowNativeBuild/<файл>'`,
  записать через heredoc или скрипт замены на маке. Удобнее редактировать
  локально — можно вытащить ОДИН файл в `/tmp` на .110, поправить, вернуть
  `scp` на то же место и сразу удалить временный файл. Каталогами (`rsync`,
  `scp -r`) в репозиторий ничего не заливать.
- Добавил или удалил файл — обязательно `xcodegen generate`, иначе он не
  попадёт в проект. Ассеты прописываются в `sources` в `project.yml`.

Готово, когда изменены только файлы из строки реестра (`git status -s`).

### 5. Сборка

Через XcodeBuildMCP: в начале сессии `session_show_defaults`; если пусто —
`session_set_defaults` с `projectPath:
/Users/max/Проекты/TaskFlowNativeBuild/TaskFlow.xcodeproj`, `scheme:
TaskFlow`, симулятор. XcodeBuildMCP сам `xcodegen` не запускает — после
добавления файлов сначала шаг 4.

Или командой (с .110 — внутри `ssh … "zsh -lc '…'"`):

```bash
cd ~/Проекты/TaskFlowNativeBuild && xcodegen generate && xcodebuild -project TaskFlow.xcodeproj -scheme TaskFlow -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build_sim build 2>&1 | grep -E 'error:|BUILD (SUCCEEDED|FAILED)' | head -30
```

Полный лог не выводить — фильтр и потолок. Готово при `BUILD SUCCEEDED`.

### 6. Запуск в симуляторе

Вход без экрана логина — токен не нужен: в домашней сети приложение входит
само (`POST /auth/lan` при старте без токена, дальше токен лежит в Keychain):

```bash
SIMCTL_CHILD_TASKFLOW_DEBUG_ROUTE=today xcrun simctl launch <UDID> com.maksim.taskflow.native
```

Ключа `TASKFLOW_AGENT_TOKEN` в vault нет — снят намеренно; не искать и не
подменять другим токеном.
`TASKFLOW_DEBUG_ROUTE` открывает экран сразу: `overview`, `settings`,
`notes`, `projects`, `notifications`, `chat`, `today`, `upcoming`,
`noteeditor:<id>`, `task:<id>`, `expand`, `quickadd`. Booted-симуляторов
несколько — UDID указывать явно (`list_sims`). Готово, когда нужный экран
открыт с данными.

### 7. Проверка

Интерфейс проверяется кадром, снятым временным XCUITest: элементы ищутся по
`accessibilityIdentifier`/`label`, кадр — `XCTAttachment(screenshot:)`,
выгрузка — `xcrun xcresulttool export attachments`. Ручной тап по
координатам скриншота промахивается (points против пикселей ×3). Баг не
поддаётся со второй попытки — `NSLog` в подозрительное место и
`xcrun simctl spawn <UDID> log show --last 5m --predicate 'process == "TaskFlow"' --style compact`.
Временный тест после сверки удалить. Готово, когда кадр показывает
исправленное состояние, а затронутые тесты зелёные.

### 8. Отчёт и коммит

- Отчёт `docs/ГГГГ-ММ-ДД-<тема>.md` + кадры в одноимённую папку.
- Строку реестра перевести в `REVIEW`, описать сделанное; сделанное сверх
  задачи назвать отдельно.
- Коммит в `main` на маке, отдельный на каждую независимую правку; мусор
  (пустые файлы, `.detach_logs/`, `.superpowers/…`) не добавлять.
- Push — по просьбе владельца. Remotes: `origin` и `github` — GitHub
  `papirosa3214/TaskFlowNativeBuild`, `gitea` — Gitea на .110
  `maksim/taskflow-native-ios` (ssh-алиас `gitea` есть только на маке).
- Карточку — в `review` с приложенными кадрами (`taskflow_comment(files=…)`),
  не закрывать.

Готово, когда `git status -s` чист от рабочих файлов, строка в `REVIEW`,
карточка в `review` с кадром.

### 9. На телефон (по просьбе владельца)

```bash
cd ~/Проекты/TaskFlowNativeBuild && ./install-iphone.sh
```

Скрипт сам пересобирает, подписывает (`-allowProvisioningUpdates`) и ставит
на iPhone владельца (UDID зашит в скрипте). Бесплатная подпись
живёт 7 дней. Тот же скрипт запускает кнопка «Задачник» в пульте .110
(служба InfraPanelInstaller на маке).
