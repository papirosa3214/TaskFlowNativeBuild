#!/usr/bin/env python3
"""Сторож дизайн-системы TaskFlow.

Зачем (владелец 16.10.2026): модели пишут UI мимо `Sources/DesignSystem/` —
голый системный `Toggle` (крупнее и зелёный вместо `TFToggle`), системные
цвета текста, сырой кегль на `Text`, самодельные кнопки. Сторож ловит это в
момент правки и говорит, чем заменить: «не соответствует — надо так».

Один источник правил для всех: этот скрипт. Его зовут три входа:
  • шаг сборки (`project.yml`, `preBuildScripts`) — `--folder`, сканирует
    локальную папку `Sources/` целиком, а НЕ `git diff`: в рабочем цикле
    правка коммитится до сборки, diff пустой, и гейт молчал бы;
  • хук Claude Code (`.claude/hooks/guard_design_system.py`) — режимы
    `--fragment` / `--new-file`, блокирует правку до записи;
  • вручную — `python3 Tools/design-system-guard.py` (отчёт по всему коду).

Базовый снимок `Tools/design-system-baseline.txt` — нарушения, которые были
в коде на момент включения. Их гейт не роняет сборку (иначе проект стал бы
несобираемым до конца чистки), но печатает ВСЕГДА: это список работы. Роняет
только новое. Снимок должен только уменьшаться: починил нарушение — убирай
его строку.

Режимы:
  (без флагов)        отчёт по всему `Sources/`
  --paths F [F ...]   только перечисленные файлы
  --folder            вся локальная папка `Sources/` (то, что зовёт сборка)
  --diff [REV]        только строки, добавленные относительно REV (по умолчанию
                      HEAD) в `Sources/`, плюс целиком новые (untracked) файлы
  --baseline [PATH]   файл базового снимка (по умолчанию
                      `Tools/design-system-baseline.txt`)
  --fragment          текст правки со stdin — как отдельный фрагмент (Edit)
  --new-file PATH     новое содержимое файла PATH со stdin; проверяются только
                      добавленные строки относительно того, что лежит на диске

Код возврата: 1, если есть НОВЫЕ ошибки (error); 0 при чистом результате и при
одних предупреждениях (warn). Нарушения из базового снимка код возврата не
роняют — они в счётчике «уже было».

Осознанный отказ от правила — строка `// design-system-guard: ignore`
в самой строке нарушения.
"""
from __future__ import annotations

import argparse
from collections import Counter
import os
import re
import subprocess
import sys
import importlib.util
from pathlib import Path

_heading_spec = importlib.util.spec_from_file_location("screen_heading_guard", Path(__file__).with_name("screen-heading-guard.py"))
_heading_module = importlib.util.module_from_spec(_heading_spec)
_heading_spec.loader.exec_module(_heading_module)
scan_screen_headings = _heading_module.scan_screen_headings

_color_spec = importlib.util.spec_from_file_location("control_color_guard", Path(__file__).with_name("control-color-guard.py"))
_color_module = importlib.util.module_from_spec(_color_spec)
_color_spec.loader.exec_module(_color_module)
scan_control_colors = _color_module.scan_control_colors

# Временно выключенные правила (владелец 23.10.2026): красных кнопок и
# системного синего в коде много, чистить их сейчас не берёмся — сторож на
# них не ругается и сборку не роняет. Сами правила и их тесты остаются:
# включаются обратно удалением строки из этого набора.
DISABLED_RULE_IDS = {"red-button", "implicit-system-blue", "system-blue-color"}


def _enabled(rows):
    return [row for row in rows if row[2] not in DISABLED_RULE_IDS]
COLOR_RULES = {"red-button", "system-blue-color", "implicit-system-blue"}


def new_color_findings(path, old_text, new_text):
    """Color may change by removing an ancestor modifier, without changing the control line."""
    previous = Counter((row[2], row[3]) for row in scan_control_colors(path, old_text))
    result = []
    for row in scan_control_colors(path, new_text):
        key = (row[2], row[3])
        if previous[key]: previous[key] -= 1
        else: result.append(row)
    return result

IGNORE_MARK = "design-system-guard: ignore"

# Шапка файла базового снимка (Tools/design-system-baseline.txt).
BASELINE_HEADER = """# Базовый снимок сторожа дизайн-системы: нарушения, которые уже были в коде
# на момент его включения (16.10.2026). Сборку они НЕ роняют — иначе проект
# стал бы несобираемым до конца чистки, — но печатаются всегда как список работы.
#
# Формат: путь<TAB>правило<TAB>строка кода (табуляция обязательна).
# Номер строки не хранится намеренно: он сдвигается от чужой правки выше по
# файлу, и снимок по номерам ложно объявил бы старое нарушение новым.
#
# Починил нарушение — УБЕРИ его строку отсюда. Снимок должен только уменьшаться.
# Перегенерировать (только осознанно, для новых правил):
#   python3 Tools/design-system-guard.py --write-baseline
"""

# Пары «что ищем — чем заменить». Правило error роняет сборку, warn только
# сообщает.
RULES = [
    {"id": "red-button", "severity": "error", "title": "красная кнопка (включая TFButton.primary по умолчанию)",
     "fix": "нейтральная кнопка как в настройках: TFButton(..., variant: .secondary); цвет текста — tfText, без tfRed/tfCoral/tint(.red)"},
    {"id": "system-blue-color", "severity": "error", "title": "явный системный синий цвет или accentColor",
     "fix": "для обычных действий и выбора используй .tint(Color.tfText) / .foregroundStyle(Color.tfText); цвет смысловых данных — из палитры"},
    {"id": "implicit-system-blue", "severity": "error", "title": "не задан нейтральный цвет интерактивного элемента: риск системного синего",
     "fix": "задай нейтральный .tint(Color.tfText) элементу или его контейнеру; для кнопок используй нейтральный компонент дизайн-системы"},
    {
        "id": "screen-heading-consistency",
        "severity": "error",
        "title": "разный стиль заголовков одного уровня внутри экрана",
        "fix": "сверь соседние разделы указанного экрана: используй общий компонент без переопределения шрифта, цвета и регистра; детали в Tools/screen-heading-scopes.json",
    },
    {
        "id": "raw-toggle",
        "severity": "error",
        "title": "голый системный `Toggle`",
        "fix": "используй `TFToggle(isOn:)` — единственный тумблер приложения "
               "(меньше и красный): HStack { Text(\"…\"); Spacer(); TFToggle(isOn: $x) }",
    },
    {
        "id": "system-text-color",
        "severity": "error",
        "title": "системный цвет текста (`.primary`/`.secondary`/`.tertiary`)",
        "fix": "цвет из палитры: `tfText` (основной) / `tfSub` (вторичный) / `tfDim` (третичный)",
    },
    {
        "id": "text-font-size",
        "severity": "error",
        "title": "сырой кегль `.font(.system(size:))` на `Text`",
        "fix": "ступень шкалы через `.tfText(.body/.action/.meta/…)` — все размеры живут "
               "в `Sources/DesignSystem/Theme/Typography.swift`",
    },
    {
        "id": "system-font-style",
        "severity": "error",
        "title": "системный стиль шрифта (`.font(.headline)`, `Font.body`…) — не подчиняется «Настройки → Шрифт»",
        "fix": "ступень шкалы через `.tfText(.title/.body/.action/.meta/…)`: только она "
               "слушает ползунки «Настройки → Шрифт» (владелец 06.11.2026)",
    },
    {
        "id": "bespoke-button",
        "severity": "warn",
        "title": "похоже на самодельную кнопку со своей рамкой/фоном",
        "fix": "готовые кнопки: `TFButton` (полноширинная, нейтральные secondary/outline), "
               "`TFIconButton` (иконка, тап-зона 44×44)",
    },
    # Ниже — правила из свода критериев аудита дизайн-системы
    # (`docs/2026-10-16-design-system-audit/external-references.md`, группы A–G):
    # внешние ориентиры Apple HIG и WCAG, сведённые в проверяемые утверждения.
    {
        "id": "text-too-small",
        "severity": "error",
        "title": "кегль меньше 11 pt — ниже минимума iOS (B2)",
        "fix": "минимум 11 pt: ступень `.tfText(.caption)`. Если это глиф (`Image`), "
               "а не текст, правило не применяется",
    },
    {
        "id": "light-font-weight",
        "severity": "error",
        "title": "светлое начертание (`.ultraLight`/`.thin`) — HIG не рекомендует (B4)",
        "fix": "обычное или полужирное начертание: `.regular` / `.medium` / `.semibold`",
    },
    {
        "id": "alert-ok-button",
        "severity": "error",
        "title": "кнопка диалога «OK»/«ОК» — не называет результат (C4.3)",
        "fix": "назови результатом или глаголом: «Повторить», «Удалить», «Закрыть», «Понятно»",
    },
    {
        "id": "alert-generic-title",
        "severity": "error",
        "title": "заголовок диалога «Ошибка»/«Error» — не описывает ситуацию (C4.2)",
        "fix": "опиши ситуацию словами экрана: «Не удалось сохранить задачу», «Нет связи с сервером»",
    },
    {
        "id": "custom-font",
        "severity": "warn",
        "title": "свой шрифт вне `DesignSystem/` (B1)",
        "fix": "шрифт берётся из шкалы `Sources/DesignSystem/Theme/Typography.swift`, "
               "а не задаётся на экране",
    },
    # --- Milestone 3 «Фундамент канона»: состояния экрана (F15–F17) ---
    {
        "id": "raw-empty-state",
        "severity": "error",
        "title": "сырой `ContentUnavailableView` вместо `TFEmptyState`",
        "fix": "пустое состояние рисует `TFEmptyState` (иконка, текст, описание, действие); "
               "форма поиска — `TFEmptyState(search:)`",
    },
    {
        "id": "raw-loading",
        "severity": "error",
        "title": "сырой `ProgressView` как состояние загрузки вместо `TFLoading`",
        "fix": "индикатор загрузки — `TFLoading(.inline)` или `TFLoading(.block)`; "
               "точечный индикатор (спиннер в кнопке или в строке) — только в файлах из LOADING_POINT_ALLOWED",
    },
    {
        "id": "raw-error-banner",
        "severity": "error",
        "title": "ошибка системным диалогом вместо `TFErrorBanner`",
        "fix": "ошибку в потоке показывает `TFErrorBanner(..., variant: .block)`; "
               "прочие системные диалоги (с действиями) законны",
    },
    # --- Milestone 3 «Фундамент канона»: строка списка и заголовок раздела (F18–F19) ---
    {
        "id": "raw-list-row",
        "severity": "error",
        "title": "ручная строка списка с шевроном вместо `TFListRow`",
        "fix": "строка списка — `TFListRow(...)`; шеврон рисует канон сам "
               "(`chevron: .shown`) или получает его в `trailing:`",
    },
    {
        "id": "raw-caps-heading",
        "severity": "error",
        "title": "ручной «капс»-заголовок вместо `TFSectionHeader`",
        "fix": "заголовок раздела — `TFSectionHeader(\"…\", style: .caps)`; "
               "второй компонент-заголовок в приложении не заводится",
    },
    # --- Milestone 3 «Фундамент канона»: карточка и фон экрана (F20–F21) ---
    {
        "id": "raw-card",
        "severity": "error",
        "title": "ручная подложка карточки вместо `TFCard`",
        "fix": "карточка — `TFCard(surface:radius:) { … }`; вторая поверхность — "
               "`surface: .card2`, радиус переносится в параметр (вид не меняется)",
    },
    {
        "id": "raw-screen-background",
        "severity": "error",
        "title": "ручной фон экрана вместо `.tfScreenBackground()`",
        "fix": "фон экрана — `.tfScreenBackground()`: он гасит системный фон списка "
               "и оставляет фон приложения под `refreshable`",
    },
    {
        "id": "raw-sheet",
        "severity": "error",
        "title": "голый `.sheet` вместо `tfSheet`",
        "fix": "шторка — `.tfSheet(isPresented:)` или `.tfSheet(item:)`: только так "
               "в ней виден системный цвет, а не чёрный фон приложения",
    },
    {
        "id": "raw-pill",
        "severity": "error",
        "title": "самодельная плашка-капсула вместо `TFPill`",
        "fix": "плашка — `TFPill`: текстовая форма `TFPill(\"…\", color:)` либо "
               "форма с произвольным содержимым `TFPill(surface:radius:)`; "
               "собственный `clipShape` с радиусом `pill` — не заводится",
    },
]

TOGGLE = re.compile(r"(?<![\w.])Toggle\s*\(")
SYSTEM_COLOR = re.compile(r"\.foreground(Style|Color)\(\.(primary|secondary|tertiary)\b")
TEXT_FONT = re.compile(r"\.font\(\.system\(size:")
TEXT_CTOR = re.compile(r"\bText\s*\(")
IMAGE_CTOR = re.compile(r"\bImage\s*\(")
BUTTON = re.compile(r"(?<![\w.])Button\s*[\\({]")
# Своя главная кнопка: заливка красным вручную вместо `TFButton`.
BESPOKE_FILL = re.compile(r"\.background\((?:Color\.)?tfRed(Solid)?\b")

# --- Критерии аудита (external-references.md, группы A–G) ---
# B2: кегль меньше 11 pt. Число ловим из вызова, сравниваем в check_line.
FONT_SIZE = re.compile(r"\.font\(\.system\(size:\s*([0-9]+(?:\.[0-9]+)?)")
# B4: светлые начертания. `.light` нарочно НЕ в списке — слишком много
# одноимённых совпадений (`thinMaterial`, `lightning`, `.highlight`).
LIGHT_WEIGHT = re.compile(r"\.fontWeight\(\s*\.(?:ultraLight|thin)\b|\.weight\(\s*\.(?:ultraLight|thin)\b")
# C4.3: кнопка диалога, не называющая результат.
VAGUE_BUTTON = re.compile(r"(?<![\w.])Button\s*\(\s*\"(?:OK|Ok|ok|ОК|Ок|ок)\"")
# C4.2: заголовок диалога без описания ситуации.
GENERIC_ALERT = re.compile(r"\.alert\s*\(\s*\"(?:Ошибка|ОШИБКА|Ошибка!|Error|ERROR|Ошибка:)\"")
# B1: свой шрифт. В `DesignSystem/` он законен (шкала и компоненты), вне — нет.
CUSTOM_FONT = re.compile(r"\.font\(\s*\.custom\(|Font\.custom\(")
MIN_TEXT_SIZE = 11.0

# --- Milestone 3: состояния экрана (F15–F17) ---
# F15: сырое `ContentUnavailableView` — только внутри канона `TFEmptyState`.
EMPTY_STATE = re.compile(r"\bContentUnavailableView\b")
# F16: безымянный или текстовый спиннер. `ProgressView(value:…)` — это
# детерминированный индикатор прогресса, другое понятие, и в проверку не входит.
LOADING_SPINNER = re.compile(r"(?<![\w.])ProgressView\s*\(\s*(?:\)|\"[^\"]*\")")
# F17: «ошибки» в `.alert` без действия — их место в потоке, в баннере.
# Список заголовков закрытый: прочие системные диалоги (с действиями) законны.
ERROR_ALERT_TITLES = (
    "Не получилось",
    "Не удалось загрузить темы",
    "Не удалось открыть группу",
)
ERROR_ALERT = re.compile(
    r"\.alert\s*\(\s*\"(?:%s)\"" % "|".join(re.escape(t) for t in ERROR_ALERT_TITLES)
)
# Точечные индикаторы: спиннер рядом с текстом или оверлей поверх содержимого.
# Это другое понятие, не «состояние загрузки», — файлы из контракта
# (VAL-UI-003, allow-list) остаются с системным спиннером.
LOADING_POINT_ALLOWED = {
    "Chat/Composer/ChatVoiceComposer.swift",
    "Chat/Composer/ChatWorkspaceChoice.swift",
    "Chat/Feed/ChatFeedParts.swift",
    "Chat/Output/RoleReplyMarkdown.swift",
    "Features/Knowledge/NoteEditorScreen.swift",
    "Features/Settings/ServerRestartRow.swift",
    "Features/Settings/ServerStatusSection.swift",
    "Features/Settings/VoiceModelsScreen.swift",
}

# --- Milestone 3: строка списка (F18) и заголовок раздела (F19) ---
# F18: ручная строка списка. Признак — шеврон `"chevron.right"`, нарисованный
# рядом со строкой руками. Шеврон, переданный канону `TFListRow` (в
# `trailing:`) или нарисованный им самим, — законен: он лежит внутри вызова
# `TFListRow(…)`, и это видно по скобкам (см. `tf_list_row_lines`).
LIST_ROW_CHEVRON = re.compile(r'"chevron\.right"')
# Шерон, который не в строке списка: указатель внутри карточки, раскрывающая
# пара (вниз/вправо) или шеврон внутри самого компонента дизайн-системы.
LIST_ROW_CHEVRON_ALLOWED = {
    "DesignSystem/Components/TFCard.swift",       # канон `TFListRow` рисует шеврон сам
    "DesignSystem/Components/TFTextField.swift",  # шеврон внутри компонента
    "Features/Knowledge/NotesScreen.swift",       # раскрывающая пара шевронов у папки
    "Features/Roles/RoleActionGroup.swift",       # раскрывающая пара
    "Features/Roles/RoleLiveTurnView.swift",      # указатель внутри карточки чата
    "Features/ServiceNotifications/NotificationTicketCard.swift",  # указатель в шапке карточки
    "Features/Tasks/TaskCardContent.swift",       # указатели и раскрывающая пара внутри карточки
    "Features/Tasks/Detail/TaskCodeChangesViews.swift",  # указатель внутри карточки
    "Features/Tasks/Detail/TaskOutcomeSection.swift",    # указатель в карточке вердикта
}
# F19: «капс»-заголовок, собранный руками из верхнего регистра.
# Два написания ловим оба: `Text(title.uppercased())` (как было в
# `SettingsCapsLabel`) и `Text("ЗАГОЛОВОК").uppercased()`.
CAPS_HEADING = re.compile(
    r"Text\s*\([^)]*uppercased\s*\(\s*\)"      # верхний регистр внутри скобок
    r"|Text\s*\([^)]*\)\s*\.uppercased\s*\(\s*\)"  # верхний регистр модификатором
)
# Удалённая обёртка «капс-заголовка» (F19) — имя не должно вернуться.
REMOVED_CAPS_LABEL = re.compile(r"\bSettingsCapsLabel\b")
# Подпись языка в блоке кода — не заголовок раздела.
CAPS_HEADING_ALLOWED = {
    "Features/Markdown/MarkdownDocumentRenderer.swift",
}

# --- Milestone 3: карточка (F20) и фон экрана (F21) ---
# F20: подложка карточки, собранная руками. Признак — `.background(Color.tfCard)`
# или `.background(Color.tfCard2)`: та же палитра, что у канона `TFCard`, но
# мимо него. Внутри DesignSystem это законно (тело канона и его частные
# случаи), снаружи — нет: подложка обязана браться из `TFCard`.
RAW_CARD = re.compile(r"\.background\(\s*Color\.tfCard2?\s*\)")
# Подложки, которые законны вне `TFCard`:
#   - `TFTabBar.swift` — запасной вариант таббара (решение владельца 31.10.2026);
#   - `TFBadge.swift` — нейтральная пилюля (`TFPill` с фоном `card`);
#   - `TFTaskRow.swift` — подложка строки задачи;
#   - `TFAvatar.swift`, `TFTextField.swift` — собственные подложки компонентов.
# Внутри DesignSystem правило вообще не проверяется (см. `rel.startswith("DesignSystem/")`).
RAW_CARD_ALLOWED = {
    "DesignSystem/Navigation/TFTabBar.swift",
}
# F21: фон экрана, собранный руками. Признак — `.background(Color.tfBackground)`
# на корне экрана: канон — модификатор `.tfScreenBackground()`, который гасит
# системный фон списка и кладёт фон приложения под `refreshable`.
# Сквозная подложка на весь экран (`.ignoresSafeArea()`) — другое понятие,
# её ловит другой шаблон и она в allow-list.
RAW_SCREEN_BACKGROUND = re.compile(r"\.background\(\s*Color\.tfBackground\s*\)")
RAW_SCREEN_BACKGROUND_ALLOWED = {
    # Сквозная подложка на весь экран (не «фон экрана»).
    "Features/Secretary/SecretaryVoiceScreen.swift",
    "Chat/Composer/ChatVoiceComposer.swift",
}
# Владелец 05.11.2026: шторка снизу вверх — оригинального цвета. Голый `.sheet`
# не сообщает содержимому, что оно в шторке, и фон приложения красит её в чёрный.
RAW_SHEET = re.compile(r"(?<!`)\.sheet\s*\(\s*(?:(?:item|isPresented)\s*:|$)|(?<![\w.`])sheet\s*\(\s*(?:item|isPresented)\s*:")
RAW_SHEET_ALLOWED = {
    # Сам `tfSheet`: единственное место, где зовётся системный `.sheet`.
    "DesignSystem/Components/TFSheet.swift",
}
# F12: самодельная плашка — капсула, скруглённая `TFRadius.pill`, собранная
# руками: либо подложка `tfCard`/`tfCard2` под скруглением-капсулой, либо
# отступы под скруглением-капсулой. Канон — `TFPill` (две формы: текстовая
# и с произвольным содержимым).
RAW_PILL = re.compile(
    r"\.background\(\s*Color\.tfCard2?\s*\)"
    r"[^\n]*\n\s*\.clipShape\(\s*RoundedRectangle\(\s*cornerRadius:\s*TFRadius\.pill\s*\)\s*\)"
    r"|"
    r"\.padding\([^\n]*\)\s*\n\s*\.clipShape\(\s*RoundedRectangle\(\s*cornerRadius:\s*TFRadius\.pill\s*\)\s*\)"
)
# Графические примитивы, которые лишь похожи на плашку: их скругление — часть
# рисунка, а не подложка-бейдж.
RAW_PILL_ALLOWED = {
    "Features/Planner/PlannerWeekView.swift",   # ячейка дня в недельной сетке
    "Chat/Widgets/WidgetTimeViews.swift",       # ячейка тепловой карты и легенда
}


def strip_comment(line: str) -> str:
    """Убирает `//…` вне строковых литералов."""
    out = []
    in_string = False
    escaped = False
    i = 0
    while i < len(line):
        ch = line[i]
        if in_string:
            out.append(ch)
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == '"':
                in_string = False
        else:
            if ch == '"':
                in_string = True
                out.append(ch)
            elif ch == "/" and i + 1 < len(line) and line[i + 1] == "/":
                break
            else:
                out.append(ch)
        i += 1
    return "".join(out)


def statement_head(lines, index: int) -> str:
    """Строка-«голова» выражения, к которому относится модификатор на index.

    Идём вверх, пока строки начинаются с `.` (цепочка модификаторов); первая
    строка, не начинающаяся с `.`, — начало выражения.
    """
    j = index
    while j >= 0:
        if not lines[j].strip().startswith("."):
            return lines[j]
        j -= 1
    return lines[index] if 0 <= index < len(lines) else ""


def sources_rel(path: str) -> str:
    """Путь файла внутри `Sources/` через «/» — для правил по файлам.

    `check_line` получает абсолютный путь, а правила Milestone 3 записаны
    относительно `Sources/` (так же, как в контракте).
    """
    norm = path.replace("\\", "/")
    marker = "/Sources/"
    idx = norm.rfind(marker)
    if idx >= 0:
        return norm[idx + len(marker):]
    return norm


def preview_lines(lines) -> set:
    """Номера строк (1-based) внутри блоков `#Preview` / `PreviewProvider`.

    Превью — не экран приложения: в нём системные компоненты показывать можно.
    """
    inside = set()
    total = len(lines)
    index = 0
    while index < total:
        stripped = lines[index].strip()
        if stripped.startswith("#Preview") or "PreviewProvider" in stripped:
            depth = 0
            started = False
            cursor = index
            while cursor < total:
                depth += lines[cursor].count("{") - lines[cursor].count("}")
                if "{" in lines[cursor]:
                    started = True
                inside.add(cursor + 1)
                if started and depth <= 0:
                    break
                cursor += 1
            index = cursor + 1
            continue
        index += 1
    return inside


def tf_list_row_lines(lines) -> set:
    """Номера строк (1-based), лежащих ВНУТРИ вызова `TFListRow(…)`.

    Шеврон, переданный канону в `trailing:` (или нарисованный каноном самим),
    — законен; ручной шеврон рядом со строкой — нет. Разница видна по
    синтаксису: канон всегда открыт своей скобкой, поэтому достаточно
    посчитать вложенность скобок и запомнить строки, попавшие внутрь
    вызова с именем `TFListRow`.
    """
    inside = set()
    stack = []          # стек открытых скобок: (имя, номер строки)
    in_string = False
    escaped = False
    line = 1
    text = "\n".join(lines)
    index = 0
    length = len(text)
    while index < length:
        char = text[index]
        if char == "\n":
            line += 1
            index += 1
            continue
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            index += 1
            continue
        if char == '"':
            in_string = True
            index += 1
            continue
        if char == "(":
            back = index - 1
            while back >= 0 and (text[back].isalnum() or text[back] == "_"):
                back -= 1
            stack.append((text[back + 1:index], line))
            index += 1
            continue
        if char == ")":
            if stack:
                name, opened = stack.pop()
                if name == "TFListRow":
                    for number in range(opened, line + 1):
                        inside.add(number)
            index += 1
            continue
        index += 1
    return inside


# Системные стили шрифта идут мимо шкалы `.tfText` и не слушают «Настройки →
# Шрифт» (владелец 06.11.2026: «любой текст должен реагировать на ручки»).
# Ловим `.font(.headline)`, `.font(Font.body.weight(…))`, `.font(.system(.caption…))`
# и `Font.callout` где угодно. Сама шкала собирается из системных кривых —
# файл шкалы исключён.
_TEXT_STYLES = r"(?:largeTitle|title[23]?|headline|subheadline|body|callout|footnote|caption2?)"
SYSTEM_FONT_STYLE = re.compile(
    r"\.font\(\s*(?:Font)?\." + _TEXT_STYLES + r"\b"
    r"|\.font\(\s*(?:Font)?\.system\(\s*\."
    r"|\bFont\." + _TEXT_STYLES + r"\b"
)
SYSTEM_FONT_STYLE_ALLOWED = {"DesignSystem/Theme/Typography.swift"}


def check_line(path: str, lines, index: int, preview=None, canon_lines=None):
    """Возвращает список сработавших правил для строки (index — 0-based)."""
    raw = lines[index]
    if IGNORE_MARK in raw:
        return []
    if preview and (index + 1) in preview:
        return []          # строка внутри `#Preview` — не экран приложения
    code = strip_comment(raw)
    hits = []
    if not path.endswith("Components/TFToggle.swift") and TOGGLE.search(code):
        hits.append("raw-toggle")
    # --- Milestone 3: состояния экрана (F15–F17) ---
    # В режиме `--fragment` файл неизвестен, а правила F15/F16 зависят от пути
    # (канон `TFEmptyState` и точечные спиннеры) — там они не проверяются.
    rel = sources_rel(path)
    known_file = path != "<правка>"
    if known_file and EMPTY_STATE.search(code) and rel != "DesignSystem/Components/TFEmptyState.swift":
        hits.append("raw-empty-state")
    if (known_file
            and LOADING_SPINNER.search(code)
            and not rel.startswith("DesignSystem/")
            and rel not in LOADING_POINT_ALLOWED):
        hits.append("raw-loading")
    if ERROR_ALERT.search(code):
        hits.append("raw-error-banner")
    # --- Milestone 3: строка списка (F18) и заголовок раздела (F19) ---
    # Оба правила требуют знать файл, поэтому в режиме `--fragment` (правка
    # без файла) они не проверяются — как и правила F15/F16.
    if known_file:
        if (LIST_ROW_CHEVRON.search(code)
                and rel not in LIST_ROW_CHEVRON_ALLOWED
                and (canon_lines is None or (index + 1) not in canon_lines)):
            hits.append("raw-list-row")
        if (CAPS_HEADING.search(code)
                and not rel.startswith("DesignSystem/")
                and rel not in CAPS_HEADING_ALLOWED):
            hits.append("raw-caps-heading")
    if REMOVED_CAPS_LABEL.search(code):
        hits.append("raw-caps-heading")
    # --- Milestone 3: карточка (F20) и фон экрана (F21) ---
    # Оба правила смотрят на код вне DesignSystem: там, где живут каноны.
    if not rel.startswith("DesignSystem/"):
        if RAW_CARD.search(code) and rel not in RAW_CARD_ALLOWED:
            hits.append("raw-card")
        if (RAW_SCREEN_BACKGROUND.search(code)
                and rel not in RAW_SCREEN_BACKGROUND_ALLOWED):
            hits.append("raw-screen-background")
    if RAW_SHEET.search(code) and rel not in RAW_SHEET_ALLOWED:
        hits.append("raw-sheet")
    if SYSTEM_FONT_STYLE.search(code) and rel not in SYSTEM_FONT_STYLE_ALLOWED:
        hits.append("system-font-style")
    if SYSTEM_COLOR.search(code):
        hits.append("system-text-color")
    head = strip_comment(statement_head(lines, index))
    # B2 важнее общего «сырой кегль»: если размер ниже минимума, называем
    # именно это — иначе на одной строке сыпались бы два правила.
    size_match = FONT_SIZE.search(code)
    too_small = (size_match is not None
                 and float(size_match.group(1)) < MIN_TEXT_SIZE
                 and TEXT_CTOR.search(head)
                 and not IMAGE_CTOR.search(head))
    if too_small:
        hits.append("text-too-small")
    elif TEXT_FONT.search(code) and TEXT_CTOR.search(head):
        hits.append("text-font-size")
    if LIGHT_WEIGHT.search(code):
        hits.append("light-font-weight")
    if VAGUE_BUTTON.search(code):
        hits.append("alert-ok-button")
    if GENERIC_ALERT.search(code):
        hits.append("alert-generic-title")
    # B1: свой шрифт законен внутри дизайн-системы (шкала и её компоненты),
    # вне её — это уже свой шрифт на экране.
    if CUSTOM_FONT.search(code) and "DesignSystem/" not in path.replace("\\", "/"):
        hits.append("custom-font")
    if BUTTON.search(code):
        window = "\n".join(strip_comment(x) for x in lines[max(0, index - 2): index + 8])
        if BESPOKE_FILL.search(window):
            hits.append("bespoke-button")
    return hits


def scan_raw_pill(path: str, source: str):
    """Самодельные плашки-капсулы: подложка `tfCard`/`tfCard2` или отступы
    под скруглением-капсулой. Канон — `TFPill`. Проверка многострочная,
    поэтому делается по тексту файла, а не по строке."""
    rel = sources_rel(path)
    if rel.startswith("DesignSystem/") or rel in RAW_PILL_ALLOWED:
        return []
    if path == "<правка>":
        rel = ""
    findings = []
    lines = source.splitlines()
    for found in RAW_PILL.finditer(source):
        line = source.count("\n", 0, found.start()) + 1
        if line > len(lines):
            continue
        if "design-system-guard: ignore" in lines[line - 1]:
            continue
        findings.append((path, line, "raw-pill", lines[line - 1].strip()))
    return findings


def scan_file(path: str, only_lines=None):
    """Собирает находки в файле. only_lines — множество номеров (1-based)."""
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as handle:
            lines = handle.read().splitlines()
    except OSError:
        return []
    findings = []
    preview = preview_lines(lines)
    canon_lines = tf_list_row_lines(lines)
    for index in range(len(lines)):
        if only_lines is not None and (index + 1) not in only_lines:
            continue
        for rule_id in check_line(path, lines, index, preview, canon_lines):
            findings.append((path, index + 1, rule_id, lines[index].strip()))
    findings.extend(row for row in scan_control_colors(path, "\n".join(lines)) if only_lines is None or row[1] in only_lines)
    findings.extend(row for row in scan_raw_pill(path, "\n".join(lines)) if only_lines is None or row[1] in only_lines)
    return findings


def scan_fragment(text: str):
    lines = text.splitlines()
    findings = []
    preview = preview_lines(lines)
    for index in range(len(lines)):
        for rule_id in check_line("<правка>", lines, index, preview):
            findings.append(("<правка>", index + 1, rule_id, lines[index].strip()))
    findings.extend(scan_control_colors("<правка>", text))
    findings.extend(scan_raw_pill("<правка>", text))
    return findings


def walk_sources(root: str):
    for dirpath, _dirs, files in os.walk(os.path.join(root, "Sources")):
        for name in files:
            if name.endswith(".swift"):
                yield os.path.join(dirpath, name)


def diff_added_lines(root: str, rev: str):
    """{абсолютный путь: множество добавленных строк} + список новых файлов."""
    try:
        out = subprocess.run(
            ["git", "-C", root, "diff", "--unified=0", "--no-color", rev, "--", "Sources"],
            capture_output=True, text=True, timeout=30,
        ).stdout
    except Exception:
        out = ""
    added = {}
    current = None
    newno = None
    for line in out.splitlines():
        if line.startswith("+++ "):
            target = line[4:].strip()
            if target == "/dev/null":
                current = None
                continue
            if target.startswith("b/"):
                target = target[2:]
            current = os.path.join(root, target)
            added.setdefault(current, set())
            continue
        if line.startswith("@@"):
            match = re.match(r"^@@ -\S+ \+(\d+)(?:,(\d+))? @@", line)
            newno = int(match.group(1)) if match else None
            continue
        if current is None or newno is None:
            continue
        if line.startswith("+"):
            added.setdefault(current, set()).add(newno)
            newno += 1
        elif line.startswith("-"):
            continue
        elif line.startswith(" "):
            newno += 1
    untracked = []
    try:
        listing = subprocess.run(
            ["git", "-C", root, "ls-files", "--others", "--exclude-standard", "--", "Sources"],
            capture_output=True, text=True, timeout=30,
        ).stdout
        untracked = [os.path.join(root, p) for p in listing.splitlines() if p.strip()]
    except Exception:
        untracked = []
    return added, untracked


def load_baseline(root: str, path=None):
    """Множество (путь, правило, текст строки) — нарушения на включении сторожа.

    Формат строки — три поля через табуляцию: `путь<TAB>правило<TAB>строка`.
    Номер строки намеренно НЕ хранится: он сдвигается от чужой правки выше по
    файлу, и снимок по номерам ложно объявлял бы старое нарушение новым.
    Пустые строки и строки с `#` пропускаются. Нет файла — пустое множество:
    тогда гейт считает новым всё найденное.
    """
    target = path or os.path.join(root, "Tools", "design-system-baseline.txt")
    if not os.path.isabs(target):
        target = os.path.join(root, target)
    if not os.path.exists(target):
        return set()
    entries = set()
    try:
        with open(target, "r", encoding="utf-8") as handle:
            lines = handle.read().splitlines()
    except OSError:
        return set()
    for raw in lines:
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        parts = raw.split("\t")
        if len(parts) < 3:
            continue
        entries.add((parts[0], parts[1], "\t".join(parts[2:])))
    return entries


def render(findings, baseline=None):
    findings = [row for row in findings if row[2] not in DISABLED_RULE_IDS]
    by_rule = {rule["id"]: rule for rule in RULES}
    # Базовый снимок: нарушения, которые были в коде на момент включения
    # сторожа. Их не роняем сборку — иначе гейт заблокирует всё разом и
    # проект станет несобираемым до конца чистки. Печатаются ВСЕГДА: это
    # список работы, а не «всё в порядке». Роняет только то, чего в снимке
    # не было, — то есть новая правка мимо системы.
    new_findings, known_findings = [], []
    # Ключ сопоставления — (файл, правило, текст строки), БЕЗ номера строки:
    # номера сдвигаются от чужой правки выше по файлу, и снимок по номерам
    # ложно объявил бы старое нарушение новым. Текст строки при сдвиге не
    # меняется, а изменение самой строки — это уже новая правка, её и надо
    # показать.
    for finding in findings:
        rel = finding[0]
        if os.path.isabs(rel):
            try:
                rel = os.path.relpath(rel)
            except ValueError:
                pass
        key = (rel, finding[2], finding[3])
        (known_findings if baseline and key in baseline
         else new_findings).append(finding)
    errors = [f for f in new_findings if by_rule[f[2]]["severity"] == "error"]
    warns = [f for f in new_findings if by_rule[f[2]]["severity"] == "warn"]
    if not findings:
        print("Сторож дизайн-системы: чисто.")
        return 0
    order = {"error": 0, "warn": 1}
    new_findings = sorted(new_findings, key=lambda f: (order[by_rule[f[2]]["severity"]], f[0], f[1]))
    print("Сторож дизайн-системы TaskFlow: НЕ СООТВЕТСТВУЕТ.")
    for path, line, rule_id, _text in new_findings:
        rule = by_rule[rule_id]
        marker = "ОШИБКА" if rule["severity"] == "error" else "внимание"
        shown = path
        if os.path.isabs(path):
            try:
                shown = os.path.relpath(path)
            except ValueError:
                shown = path
        print("  [%s] %s:%d — %s [%s]" % (marker, shown, line, rule["title"], rule_id))
        print("      надо: %s" % rule["fix"])
    print("")
    print("Осознанное отклонение от правила — добавь в строку «// %s»." % IGNORE_MARK)
    if known_findings:
        print("Уже было в коде на момент включения сторожа: %d — ждут чистки, сборку не роняют." % len(known_findings))
        print("Полный список: python3 Tools/design-system-guard.py")
    if errors:
        print("Новых ошибок: %d. Сборка не пройдёт." % len(errors))
    if warns:
        print("Новых предупреждений: %d (сборку не роняют)." % len(warns))
    return 1 if errors else 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Сторож дизайн-системы TaskFlow")
    parser.add_argument("--root", default=os.environ.get("SRCROOT") or os.getcwd())
    parser.add_argument("--paths", nargs="*")
    parser.add_argument("--diff", nargs="?", const="HEAD", default=None)
    parser.add_argument("--fragment", action="store_true")
    parser.add_argument("--new-file", default=None)
    parser.add_argument("--folder", action="store_true",
                        help="сканировать локальную папку Sources/ целиком, а не git diff")
    parser.add_argument("--baseline", default=None,
                        help="файл базового снимка (по умолчанию Tools/design-system-baseline.txt)")
    parser.add_argument("--write-baseline", action="store_true",
                        help="перезаписать снимок текущими находками (осознанно, для новых правил)")
    args = parser.parse_args()
    root = os.path.abspath(args.root)

    if args.write_baseline:
        rows = []
        for path in sorted(walk_sources(root)):
            for found in scan_file(path):
                rows.append([os.path.relpath(path, root), found[2], found[3]])
        target = args.baseline or os.path.join(root, "Tools", "design-system-baseline.txt")
        if not os.path.isabs(target):
            target = os.path.join(root, target)
        header = BASELINE_HEADER
        with open(target, "w", encoding="utf-8") as handle:
            handle.write(header + "\n".join("\t".join(row) for row in rows) + "\n")
        print("Снимок перезаписан: %d нарушений." % len(rows))
        return 0

    if args.fragment:
        return render(scan_fragment(sys.stdin.read()))

    if args.new_file:
        new_text = sys.stdin.read()
        existing = args.new_file if os.path.isabs(args.new_file) else os.path.join(root, args.new_file)
        try:
            with open(existing, "r", encoding="utf-8", errors="replace") as handle:
                old_lines = {line.strip() for line in handle.read().splitlines()}
        except OSError:
            old_lines = set()
        new_lines = new_text.splitlines()
        findings = []
        canon_lines = tf_list_row_lines(new_lines)
        for index in range(len(new_lines)):
            # Строка, уже лежавшая в файле дословно, — старое соответствие,
            # его не приписываем этой правке.
            if new_lines[index].strip() in old_lines and new_lines[index].strip():
                continue
            for rule_id in check_line(existing, new_lines, index, None, canon_lines):
                findings.append((args.new_file, index + 1, rule_id, new_lines[index].strip()))
        try:
            old_text = Path(existing).read_text()
        except OSError:
            old_text = ""
        findings.extend(new_color_findings(existing, old_text, new_text))
        findings.extend(scan_screen_headings(root, overrides={existing: new_text}, affected={existing}))
        return render(findings)

    if args.folder:
        baseline = load_baseline(root, args.baseline)
        findings = []
        for path in sorted(walk_sources(root)):
            findings.extend(scan_file(path))
        findings.extend(scan_screen_headings(root))
        return render(findings, baseline)

    if args.diff is not None:
        added, untracked = diff_added_lines(root, args.diff)
        findings = []
        for path, lineset in added.items():
            findings.extend(row for row in scan_file(path, only_lines=lineset) if row[2] not in COLOR_RULES)
            old = subprocess.run(["git", "-C", root, "show", args.diff + ":" + os.path.relpath(path, root)], capture_output=True, text=True).stdout
            try:
                current_text = Path(path).read_text()
            except OSError:
                current_text = ""
            findings.extend(new_color_findings(path, old, current_text))
        for path in untracked:
            findings.extend(scan_file(path))
        findings.extend(scan_screen_headings(root, affected=set(added) | set(untracked)))
        return render(findings)

    if args.paths:
        findings = []
        for path in args.paths:
            full = path if os.path.isabs(path) else os.path.join(root, path)
            findings.extend(scan_file(full))
        findings.extend(scan_screen_headings(root, affected={os.path.abspath(path if os.path.isabs(path) else os.path.join(root, path)) for path in args.paths}))
        return render(findings)

    findings = []
    for path in sorted(walk_sources(root)):
        findings.extend(scan_file(path))
    findings.extend(scan_screen_headings(root))
    return render(findings)


if __name__ == "__main__":
    sys.exit(main())
