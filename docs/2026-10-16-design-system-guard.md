# Сторож дизайн-системы — 16.10.2026

## Результат
Модели больше не могут нарисовать UI мимо `Sources/DesignSystem/` и промолчать.
Правку ловит единый сторож `Tools/design-system-guard.py`, и он же говорит, чем
заменить. Сторож стоит на трёх входах: шаг сборки (падает у любой модели, чем бы
она ни собирала), хук Claude Code (блокирует правку до записи) и ручной прогон.

Заодно исправлен повод: на экране «Оценщик JEV» тумблеры сценариев были нарисованы
голым системным `Toggle` — крупнее и зелёные. Теперь это `TFToggle` (меньше и
красный), как на всех остальных экранах.

## Что сделано
- `Tools/design-system-guard.py` — один источник правил. Режимы: полный отчёт по
  `Sources/`, `--paths`, `--diff [REV]` (только добавленные строки + новые файлы),
  `--fragment` и `--new-file` для правки со stdin. Отключение правила осознанно —
  строка `// design-system-guard: ignore`.
- Правила: `raw-toggle` (голый `Toggle`), `system-text-color`
  (`.primary`/`.secondary`/`.tertiary`), `text-font-size` (`.font(.system(size:))`
  на `Text`) — ошибки, роняют сборку; `bespoke-button` (своя кнопка с красной
  заливкой вместо `TFButton`) — предупреждение, сборку не роняет.
- `project.yml` → `preBuildScripts` цели `TaskFlow`: `.worktrees` только по правкам
  (`--diff HEAD`), чтобы старое несоответствие сборку не роняло.
- `.claude/hooks/guard_design_system.py` + запись в `.claude/settings.json`
  (PreToolUse `Edit|Write`): блокирует правку один раз с объяснением, повтор той же
  правки проходит.
- `Sources/Features/Settings/JevSettingsScreen.swift`: `scenario(_:)` переведён на
  `TFToggle` в строке `HStack { Text(…); Spacer(); TFToggle(…) }`; ярлык и
  identifier перенесены на тумблер.
- `AGENTS.md` (раздел «Сторож дизайн-системы») и `COMPONENTS.md` (у `TFToggle`) —
  правила и таблица замен.

## Проверка
- Отчёт по всему коду сторожа: 44 ошибки и 1 предупреждение в старом коде
  (главным образом сырой кегль и системные цвета текста). Это отчёт, не блокировка:
  сборка смотрит только правки.
- `--diff HEAD` на чистом дереве — «чисто», код 0. После правки JEV — снова «чисто».
- Синтетическая проверка: новый файл `Sources/TempGuardCheck.swift` с голым
  `Toggle` → сторож даёт ошибку на строке 4 и код 1 (файл удалён).
- Хук end-to-end: `Edit` с фрагментом голого `Toggle` → код 2 и объяснение.
- Сборка iPhone Air (iOS 27.0, UDID `9FF78D89-EE84-4914-AA56-D0A72D1AF43A`):
  **BUILD SUCCEEDED**; в логе шаг «Сторож дизайн-системы» → «чисто».
- Временный XCUITest `JevToggleDesignSystemUITests` (заглушечный сервер на
  `127.0.0.1:3399` отдаёт владельца и настройки JEV): экран открылся, тумблеры
  сценариев найдены по `jev-scenario-*`, **TEST SUCCEEDED, EXIT=0**. Кадр
  `jev-scenarios.png`: «Выбор шаблона плана» и «Роли для подзадач» — маленькие
  красные `TFToggle`, как на остальных экранах.
- Приложение возвращено к обычному запуску (`simctl launch`, PID 89093).

## Ограничения
- **Найдена поломка репозитория, не связанная с задачей.** Закоммиченный
  `JevSettingsScreen.swift:50` зовёт `.tfScreenBackground()`, а сам
  `Sources/DesignSystem/Components/TFScreenBackground.swift` в git НЕ добавлен —
  он есть только в рабочей копии `/Users/max/Проекты/TaskFlowNativeBuild` как
  untracked. Любая сборка строго из репозитория падает на этом. Чтобы собрать,
  файл скопирован в worktree как untracked (как и в основной копии); в коммит он
  не входит. В основной копии тем же способом вне git лежат
  `Sources/Features/Settings/RemoteMachines{Model,Screen}.swift` — их НЕ копировал
  (мой код их не использует, это чуждая работа в процессе).
- Полная очистка старого кода (67 сырых кеглей, 11 системных цветов текста, 8
  голых `Toggle` в 6 файлах) не делалась: сторож смотрит только правки. Остальные
  голые `Toggle`: `WebhooksScreen` (124, 128), `TodayScreen` (261),
  `MemoryScreen` (339), `ChatVoiceComposer` (136, 215), `QuickAddTaskView` (415).
- Отдельно замечено: в `project.yml` ключ `UIAppFonts` задан дважды (блок
  PT-Sans-Narrow и блок Handjet-Metric) — второй, вероятно, затирает первый. Вне
  рамок этой задачи, не правил.

## Артефакты
Папка `docs/2026-10-16-design-system-guard/`:
- `jev-scenarios.png` — экран «Оценщик JEV» с тумблерами `TFToggle`;
- `JevToggleDesignSystemUITests.swift` — исходник временного UI-теста;
- `jev_stub.py` — заглушечный сервер для кадра.

`Tools/design-system-guard.py`, `.claude/hooks/guard_design_system.py` — сам сторож.
