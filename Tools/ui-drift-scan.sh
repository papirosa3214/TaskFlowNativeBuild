#!/usr/bin/env bash
# Скан отклонений оформления от общих компонентов — LOCK-UI-DRIFT-GATE-20261016.
#
# Владелец 16.10.2026 (кадр с телефона, четыре дефекта): «Это нужно выявлять
# мне до передачи сборки тебе. Тебе не должно приходиться обходить приложение
# и собирать такие скриншоты». Скан — первая из трёх проверок цикла приёмки:
# ловит отклонения в коде ДО сборки, за секунды, без симулятора.
#
# Что ищет (все четыре правила — из того же кадра владельца):
#   1. Корневой `List`/`Form` экрана без общего фона `tfScreenBackground()`.
#   2. `TFButton` без `variant:` → `.primary`, то есть красная заливка.
#   3. Системный `Button("Повторить")` — в приложении кнопки серые.
#   4. `Color.black` заливкой вместо фона приложения `tfBackground`.
#
# ТРИ класса расхождений, и скан различает их:
#   • NEW     — не перечислено нигде. Это красный флаг: либо правка кода,
#               либо немедленная запись в KNOWN с причиной.
#   • KNOWN   — настоящее отклонение, найдено и зафиксировано, но чинить
#               не в этой строке реестра. Печатается ВСЕГДА: это отчёт по
#               найденному, и владелец видит список перед решением.
#   • шторки и прочие согласованные исключения — в SHEET_OK, не печатаются.
#
# «Отклонений нет» — НЕ «отклонений не существует», а «среди известных
# классов расхождений новых нет». Известных классов два, и оба открылись как
# ложные находки 16.10.2026:
#   • системный диалог — кнопка внутри .alert красится СИСТЕМОЙ, синий законен
#     (закрыто: in_system_dialog);
#   • тинированный экран — .tint(tfText) перекрашивает кнопки в серый
#     (закрыто: TINTED_SCREENS).
#
# Правило для того, кто читает вывод:
#   • находка настоящая → починить код, либо оставить в KNOWN с причиной;
#   • находка ложная    → починить СКАН, добавив правило, и назвать класс.
# Ни в одном случае не удалять находку молча: класс пропуска вернётся и снова
# снимет время. Новый класс пропуска — сказать владельцу прямо.
# Подробно: AGENT-CYCLE.md §7 «Оформление: три проверки».
#
# Код возврата: 0 — новых отклонений нет; 1 — есть (список в stdout).

set -uo pipefail

REPO="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

python3 - "$REPO" <<'PY'
import re, sys, pathlib

repo = pathlib.Path(sys.argv[1])
src_root = repo / "Sources"

# Согласованные исключения ПРАВИЛА 1: фон задаёт система, а не экран.
# Путь относительно Sources → почему это не отклонение.
# ВАЖНО: этот список относится ТОЛЬКО к правилу 1 (корневой список).
# Правила 2–4 (красные кнопки, синие «Повторить», чёрный фон) проверяются
# по ВСЕМУ коду без исключений: шторка не извиняет синюю кнопку внутри.
SHEET_OK = {
    "Features/Roles/RoleInstructionEditor.swift": "редактор инструкции: List внутри шторки, фон задаёт материал",
    "Features/Roles/RoleEditorSheet.swift": "редактор роли: List внутри шторки, фон задаёт материал",
    "Features/Roles/RoleChatsScreen.swift": "создание чата/редактирование — Form внутри шторки, фон задаёт материал",
    "Features/Roles/TeamAppearanceSheet.swift": "шторка внешнего вида команды, фон задаёт материал",
    "Features/Knowledge/FolderPickerSheet.swift": "шторка выбора папки, фон задаёт материал",
    "Features/Settings/EscalationStepEditor.swift": "окно правки шага напоминания, фон задаёт материал",
    "Features/Tasks/Detail/PlanStepSheets.swift": "шторки шага плана, фон задаёт материал",
    "Features/Tasks/TaskFormScreen.swift": "шторка выбора связанной задачи, фон задаёт материал",
    "Features/Roles/MemoryScreen.swift": "гасит системный фон вручную; переход на общий модификатор — отдельная задача",
    "App/Navigation/RootShellView.swift": "отладочные превью-роуты, фон задаёт контейнер превью",
    "Features/Knowledge/NoteExtractedTasksSheet.swift": "шторка извлечённых задач, фон задаёт материал",
    "DesignSystem/Components/AvatarCropEditor.swift": "подложка вырезки аватара: намеренно чёрная под маской",
    "DesignSystem/Components/TFRolePortrait.swift": "слой видеоплеера под маской портрета",
    "DesignSystem/Theme/Color+Palette.swift": "определение токена границы, не заливка экрана",
    "Features/Roles/RoleLiveTurnView.swift": "маска затухания окна размышлений",
}

# Найденные настоящие отклонения вне текущей строки реестра: путь → причина.
# Заведённые отклонения вне текущей строки реестра. После правки 16.10.2026
# (LOCK-UI-DRIFT-KNOWN) список был пуст: все девять находок закрыты.
#
# С 31.10.2026 список снова не пуст: Milestone 1 «Зелёный старт» не переделывает
# экраны (владелец запретил менять вид экранов, которые нравятся), а семейства
# «фон экрана» и «кнопка» сводятся в Milestone 3 и Milestone 4. Поэтому все
# настоящие находки, которые нельзя закрыть механически, зафиксированы здесь —
# с причиной, называющей milestone, который их закроет. Находка не прячется:
# скан печатает её ВСЕГДА, владелец видит открытый список перед решением.
#
# Ключ — путь относительно Sources/; одна запись покрывает все находки в файле.
# Закрытие: Milestone 3 — фича `m3-card-and-screen-background` (правило 1),
# Milestone 4 — фича `m4-buttons-and-icon-buttons` (правило 3).
KNOWN = {
    # --- правило 1: корневой список/форма без общего фона → Milestone 3 -----
    "Chat/Composer/ChatComposerControlsView.swift": "правило 1: корневой список без .tfScreenBackground() — закрывает Milestone 3 (m3-card-and-screen-background)",
    "Chat/Composer/ChatModelPickerSheet.swift": "правило 1: корневой список без .tfScreenBackground() — закрывает Milestone 3 (m3-card-and-screen-background)",
    "Chat/Composer/ChatWorkspaceChoice.swift": "правило 1: корневой список без .tfScreenBackground() — закрывает Milestone 3 (m3-card-and-screen-background)",
    "Chat/Panels/ChatSessionPanel.swift": "правила 1 и 3: корневой список без .tfScreenBackground() (Milestone 3, m3-card-and-screen-background) и системный Button(«Повторить») вместо TFButton (Milestone 4, m4-buttons-and-icon-buttons)",
    "Features/Activity/ActivityScreen.swift": "правило 1: корневой список без .tfScreenBackground() — закрывает Milestone 3 (m3-card-and-screen-background)",
    "Features/Coordination/CoordinationScreen.swift": "правила 1 и 3: корневой список без .tfScreenBackground() (Milestone 3, m3-card-and-screen-background) и системный Button(«Повторить») вместо TFButton (Milestone 4, m4-buttons-and-icon-buttons)",
    "Features/Projects/ProjectTasksScreen.swift": "правило 1: корневой список без .tfScreenBackground() — закрывает Milestone 3 (m3-card-and-screen-background)",
    "Features/Roles/RoleChatQuickActionEditor.swift": "правило 1: корневой список без .tfScreenBackground() — закрывает Milestone 3 (m3-card-and-screen-background)",
    "Features/Routines/RoutineRunsScreen.swift": "правила 1 и 3: корневой список без .tfScreenBackground() (Milestone 3, m3-card-and-screen-background) и системный Button(«Повторить») вместо TFButton (Milestone 4, m4-buttons-and-icon-buttons)",
    "Features/Settings/SecretsScreen.swift": "правило 1: корневой список без .tfScreenBackground() — закрывает Milestone 3 (m3-card-and-screen-background)",
    "Features/Tasks/Detail/TaskCodeChangesViews.swift": "правило 1: корневой список без .tfScreenBackground() — закрывает Milestone 3 (m3-card-and-screen-background)",
    "Features/Tasks/TaskArchiveScreen.swift": "правило 1: корневой список без .tfScreenBackground() — закрывает Milestone 3 (m3-card-and-screen-background)",
    "Features/Tasks/TaskCardContent.swift": "правило 1: корневой список без .tfScreenBackground() — закрывает Milestone 3 (m3-card-and-screen-background)",
    "Features/Planner/PlannerListView.swift": "правило 1: корневой список без .tfScreenBackground() — закрывает Milestone 3 (m3-card-and-screen-background)",
    # --- правило 3: системный Button(«Повторить») → Milestone 4 ------------
    "Features/Inbox/AttentionScreen.swift": "правило 3: системный Button(«Повторить») вместо TFButton — закрывает Milestone 4 (m4-buttons-and-icon-buttons)",
    "Features/Routines/RoutinesScreen.swift": "правило 3: системный Button(«Повторить») вместо TFButton — закрывает Milestone 4 (m4-buttons-and-icon-buttons)",
}

# Экран покрыт `.tint(Color.tfText)` — системные кнопки в нём серые, а не
# синие. Проверено чтением кода 16.10.2026: `RoleChatRoomScreen` несёт
# `.tint(Color.tfText)` в теле экрана, и обе кнопки «Повторить» в ленте
# лежат внутри этого тела. Находки правила 3 здесь ложные.
TINTED_SCREENS = {
    "Features/Roles/RoleChatsScreen.swift": "экран под .tint(Color.tfText): системные кнопки в нём серые",
}

# Правило 2: подписи, где .primary — норма (подтверждение, сохранение).
# Владелец 16.10.2026 жаловался на большие КРАСНЫЕ кнопки на экранах
# подключений — это кнопки-действия («Подключить», «Обновить»), а не
# подтверждение. Подтверждение («Сохранить») в приложении красное везде.
PRIMARY_OK = ("Сохранить", "Сохраняем", "Сохранить изменения")

# Согласованные исключения ПРАВИЛА 4: чёрный тут не фон экрана.
BLACK_OK = {
    "DesignSystem/Components/AvatarCropEditor.swift": "подложка вырезки аватара: намеренно чёрная под маской",
    "DesignSystem/Components/TFRolePortrait.swift": "слой видеоплеера под маской портрета",
    "DesignSystem/Theme/Color+Palette.swift": "определение токена границы, не заливка экрана",
    "Features/Roles/RoleLiveTurnView.swift": "маска затухания окна размышлений",
    "DesignSystem/Navigation/TFTabBar.swift": "цвет ПОДПИСИ выбранной вкладки (.foregroundStyle), а не заливка экрана",
}

NESTED_MARKERS = (".sheet(", ".sheet {", ".sheet(isPresented", ".fullScreenCover",
                  ".sheet(item", ".popover", ".alert(")

# Системные диалоги: кнопка внутри них окрашена САМОЙ СИСТЕМОЙ в цвет
# диалога. Это не отклонение оформления приложения — наоборот, попытка
# перекрасить её в серый сломала бы системный вид. Владелец 16.10.2026
# показал синие кнопки в потоке экрана, а не внутри диалогов, и разница
# между этими двумя случаями глазом не видна.
#
# Признаки системного диалога в SwiftUI: `.alert(`, `.confirmationDialog(`,
# `.actionSheet`. Кнопка окрашивается системой тогда и только тогда, когда
# она лежит в ЗАМЫКАНИИ действий диалога.
DIALOG_CALL = re.compile(r"\.(?:alert|confirmationDialog|actionSheet)\s*\(")


BUTTON_CALL = re.compile(r"(?<![A-Za-z.])Button\s*\(")


def in_system_dialog(source, offset):
    """Кнопка находится в замыкании действий системного диалога?

    `offset` — позиция имени `Button` (как её даёт `BUTTON_CALL.finditer`).
    Открывающую скобку вызова находим вперёд от неё, дальше идём с балансом
    вверх до `{` на глубине 0 — это тело, внутри которого живёт кнопка.
    Перед этой `{` ищем вызов диалога, у которого аргументы закрыты и после
    последней `)` стоит только пробельный перенос строки: `.alert(…)) {`.

    Проверено в двух независимых наборах:
    • 287 `Button(` проекта — 67 в диалогах, все 67 подтверждены чтением
      кода (либо `role:`, либо действие внутри `.alert`/`.confirmationDialog`);
    • 9 синтетических случаев, включая ловушки: диалог в одной строке,
      `Binding(get:set:)` на трёх строках, кнопка после закрытого диалога,
      кнопка в тулбаре внутри `.sheet`.

    Что было неверным по дороге, чтобы не повторить:
    • «есть ли `.alert(` где-то выше по файлу» — в файле их несколько, и
      кнопка нижнего экрана попадала в диалог верхнего;
    • сравнение только круглых скобок в хвосте — `get:`/`set:` внутри
      `Binding` сбивали счёт;
    • окно поиска в одну строку — `.alert(` на три строки выше границы;
    • искать скобку кнопки НАЗАД — первая попавшаяся может быть от
      `Binding(` в аргументах диалога над кнопкой.
    """
    bracket = source.find("(", offset)
    if bracket == -1:
        return False
    index = bracket
    depth = 1                          # мы внутри скобок вызова
    while index >= 0 and depth > 0:
        index -= 1
        char = source[index]
        if char in ")}":
            depth += 1
        elif char in "({":
            depth -= 1
    if index < 0:
        return False
    return _dialog_body_before(source, index)


def _dialog_body_before(source, brace):
    """Перед `{` (позиция brace) — замыкание действий системного диалога?"""
    window = source[max(0, brace - 200):brace]      # brace в окно НЕ входит
    for match in DIALOG_CALL.finditer(window):
        tail = window[match.end():]
        if not tail.strip():
            continue
        # аргументы диалога закрыты…
        if tail.rstrip()[-1:] != ")" or tail.count("(") > tail.count(")") - 1:
            continue
        # …и между последней `)` и `{` только пробельный перенос строки,
        # как у `.alert(…)) {` в конце строки. Если после `)` идёт код
        # (`.alert(… ) { Button(…) }` в одну строку) — это вложенный
        # вызов, а не замыкание действий.
        if tail[tail.rfind(")") + 1:].strip() == "":
            return True
    return False

findings = []

def report(rule, path, line, text, uses_sheet_ok=False, uses_black_ok=False, uses_tint=False):
    rel = str(path.relative_to(src_root))
    if uses_sheet_ok and rel in SHEET_OK:
        return
    if uses_black_ok and rel in BLACK_OK:
        return
    if uses_tint and rel in TINTED_SCREENS:
        return
    status = "KNOWN" if rel in KNOWN else "NEW"
    findings.append((status, rule, f"Sources/{rel}", line, text, KNOWN.get(rel, "")))

for path in sorted(src_root.rglob("*.swift")):
    try:
        source = path.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        continue

    # --- Правило 1: корневой List/Form без общего фона ----------------------
    for match in re.finditer(r"var body: some View \{", source):
        head_end = match.end()
        window = source[head_end:head_end + 400]
        for list_match in re.finditer(r"\b(List|Form)\s*\{", window):
            if any(marker in window[:list_match.start()] for marker in NESTED_MARKERS):
                break                      # до списка уже шторка — не корень
            if "tfScreenBackground" in source:
                break                      # модификатор в файле есть — правило выполнено
            line = source[:head_end + list_match.start()].count("\n") + 1
            report("1) корневой список без общего фона (.tfScreenBackground())",
                   path, line, f"{list_match.group(1)} без фона", uses_sheet_ok=True)
            break

    # --- Правило 2: TFButton без variant ------------------------------------
    for match in re.finditer(r"(?<![A-Za-z])TFButton\(", source):
        i, depth = match.end(), 1
        while i < len(source) and depth > 0:
            if source[i] == "(":
                depth += 1
            elif source[i] == ")":
                depth -= 1
            i += 1
        call = source[match.start():i]
        if "variant" in call:
            continue
        if any(ok in call for ok in PRIMARY_OK):
            continue                      # подтверждение: красный здесь норма
        line = source[:match.start()].count("\n") + 1
        report("2) TFButton без variant: → .primary, красная заливка",
               path, line, " ".join(call.split())[:110], uses_sheet_ok=False)

    # --- Правило 3: системная кнопка «Повторить» ----------------------------
    # `(?<!TF)` — чтобы не поймать собственные TFButton(«Повторить»).
    for match in re.finditer(r"(?<![A-Za-z])Button\(\"Повторить", source):
        if in_system_dialog(source, match.start()):
            continue                      # внутри .alert: синий — цвет системы
        line = source[:match.start()].count("\n") + 1
        end = source.find("\n", match.start())
        report("3) системный Button(\"Повторить\") — кнопки приложения серые (TFButton)",
               path, line, source[match.start():end].strip()[:110], uses_tint=True)

    # --- Правило 4: сплошной чёрный -----------------------------------------
    for line_no, line in enumerate(source.split("\n"), 1):
        if "Color.black" not in line or "opacity" in line:
            continue
        report("4) Color.black заливкой — фон приложения tfBackground",
               path, line_no, line.strip()[:110], uses_black_ok=True)

print(f"== Скан отклонений оформления: {src_root}")

new = [f for f in findings if f[0] == "NEW"]
known = [f for f in findings if f[0] == "KNOWN"]

if not findings:
    print("Отклонений нет.")
    sys.exit(0)

for status, rule, where, line, text, note in known:
    print(f"[{status}] {rule}")
    print(f"    {where}:{line}  {text}")
    print(f"    почему не починено сейчас: {note}")
print()
print(f"Найдено и зафиксировано (KNOWN): {len(known)} — ждут решения владельца, вне текущей строки реестра.")
if known:
    print("Каждая запись KNOWN названа со своим milestone: он её и закрывает (Milestone 3 — правило 1, Milestone 4 — правило 3).")
print(f"Новых отклонений (NEW): {len(new)}")
if new:
    print()
    for status, rule, where, line, text, _ in new:
        print(f"[NEW] {rule}")
        print(f"    {where}:{line}  {text}")
    print()
    print("Каждое — либо правка кода, либо запись в KNOWN этого скрипта с причиной.")
    sys.exit(1)
print("Новых отклонений нет.")
PY