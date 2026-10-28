# Доступ ролей к GitHub — 28.10.2026

## Причина
Роль по «Входящим» не могла открыть PR: обычный gh на .110 не использовал
имеющийся GITHUB_TOKEN из vault. На Mac Git HTTPS не использовал авторизованный gh.

## Настройка
- .110: `~/.claude/skills/taskflow/bin/gh` вызывает `/usr/bin/gh` через
  `~/.claude/vault-run.py --secret GH_TOKEN=GITHUB_TOKEN`. Значение токена
  не копировалось и не печаталось. Каталог включён в PATH службы сервера
  через `~/.config/systemd/user/taskflow-server.service.d/94-github-cli.conf`.
  `daemon-reload` выполнен; новый PATH применяется при ближайшей выкладке.
- Mac, репозиторий TaskFlowNativeBuild: локальный credential helper для
  https://github.com — `/opt/homebrew/bin/gh auth git-credential`.
- Песочница роли сохраняется. Для отправки из песочницы используется
  операция host git_push / taskflow_host_push, выполняющая Git на хосте.

## Проверки
- Обычный gh на .110 разрешается в wrapper; gh api показывает pull/push
  репозитория papirosa3214/New-Todoist; gh pr list проходит.
- bash -lc на .110 также видит wrapper.
- Mac: git push --dry-run для roles/inbox-attention-20261028 в github и gitea
  прошёл. Фактической отправки ветки этими проверками не выполнялось.

## Сохранённая работа
Серверный коммит 0882902d сохранён в preserve/attention-0882902d по разрешению
владельца. Ветка роли roles/inbox-attention-20261028 тоже сохранена. Рабочий
main возвращён к github/main для доставки исправления ручных запусков, PR #12.

## Уточнение после проверки среды роли
Первые gh/git проверки выше выполнялись ВНЕ песочницы и не доказывали доступ
самой роли. Роль повторно подтвердила отказ чтения ~/.config/gh. Передача токена
в песочницу не внедрялась: владелец выбрал существующий Composio MCP.

Фактический рабочий путь: GitHub разрешён всем 11 ролям, владелец прошёл
стандартную авторизацию обычного сервиса GitHub (не отдельного GitHub MCP).
Общий SYSTEM.md обновлён у 11 ролей, PR сервера #13 влит и выложен.
Через connectRoleComposio(claude_code, work) выполнены SEARCH_TOOLS и затем
GITHUB_GET_REPOSITORY_PERMISSIONS_FOR_A_USER через MULTI_EXECUTE_TOOL.
Оба репозитория вернули admin с push=true; ошибок 0 из 2.
Это проверка среды роли через реальный MCP, а не проверка owner gh.
