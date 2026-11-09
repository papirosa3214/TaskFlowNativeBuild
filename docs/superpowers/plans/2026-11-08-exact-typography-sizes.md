# Exact Typography Sizes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Заменить пять фиксированных ступеней точными кеглями `8…72 pt`, подключить к ним заголовки и оба списка задач.

**Architecture:** Foundation-only `TypographyPreferences` хранит, ограничивает и мигрирует точные кегли. Токены SwiftUI берут эти значения и сохраняют системное Dynamic Type. `FontSettingsScreen` даёт компактный числовой ввод, а `TFNativeHeader` рисует экранные заголовки капсом в группе «Заголовок».

**Tech Stack:** Swift 6, SwiftUI, Foundation/UserDefaults, host `swiftc` test, TaskFlow design system.

**Spec:** `docs/superpowers/specs/2026-11-08-exact-typography-sizes-design.md`

## Global Constraints

- Кегль — целое число от 8 до 72 pt.
- Приложение и чат хранят настройки независимо.
- Старые ступени однократно мигрируют в точные кегли без видимого скачка.
- Dynamic Type сохраняется.
- Экранные заголовки капсом; названия задач не преобразуются.
- Не менять веса, цвета, геометрию строк задач и моноширинность кода.
- Без симулятора, UI-тестов и iPhone.

## Review Focus

- Точный кегль, уже сохранённый по новому ключу, миграция не затирает.
- Ступени `small`, `compact`, `standard`, `large`, `xlarge` переносятся с округлением от текущего видимого размера.
- Значения ниже 8 и выше 72 сохраняются как 8 и 72.
- Изменение кегля приложения не меняе чат и наоборот.
- Пустой и нечисловой ввод не затирает последнее корректное значение.

---

### Task 1: Exact-size storage and migration

**Files:**
- Modify: `Sources/DesignSystem/Theme/TypographyPreferences.swift`
- Modify: `Tools/test_typography_preferences.swift`
- Modify: `Sources/DesignSystem/Theme/AppAppearance.swift`

**Interfaces:**
- Produces: `TypographyPreferences.pointSizeKey(for:group:)`, `pointSize(for:group:defaultValue:defaults:)`, `savePointSize(_:for:group:defaults:)`, `appGroup(forTextStyle:)`, и миграцию v2.
- Produces: `TFTypeGroup.size`, `TFTypeGroup.save(size:)`, `TFChatTypeGroup.size`, `TFChatTypeGroup.save(size:)`.

- [ ] **Step 1: Add failing host tests** for all five Review Focus cases plus routing `listTitle → body`, `action → secondary`, `caption → tertiary`.
- [ ] **Step 2: Run RED:** `swiftc Sources/DesignSystem/Theme/TypographyPreferences.swift Tools/test_typography_preferences.swift -o /tmp/taskflow-typography-preferences-tests && /tmp/taskflow-typography-preferences-tests`; expected compile failure for the new API.
- [ ] **Step 3: Implement** exact keys, clamp `8...72`, independent app/chat persistence and one-time v2 migration using legacy multipliers `0.85/0.92/1/1.08/1.17`.
- [ ] **Step 4: Route** `TFTypeGroup` and `TFChatTypeGroup` through exact integer sizes while retaining `TFTypeScale` only as legacy migration vocabulary and revision trigger.
- [ ] **Step 5: Run GREEN** with the same host command; expected `PASS typography preferences`.

### Task 2: Typography consumers and numeric editor

**Files:**
- Modify: `Sources/DesignSystem/Theme/Typography.swift`
- Modify: `Sources/DesignSystem/Components/TFNativeHeader.swift`
- Modify: `Sources/Features/Settings/FontSettingsScreen.swift`

**Interfaces:**
- Consumes: exact-size APIs from Task 1.
- Produces: Dynamic-Type-aware exact sizing for application text, section display, native headers and chat; compact integer fields `8...72 pt` for all groups.

- [ ] **Step 1: Replace** multiplier reads in `TFTextStyleModifier`, `TFSectionDisplayModifier`, `.tfChat` and previews with exact group sizes multiplied by the existing Dynamic Type ratio where applicable.
- [ ] **Step 2: Change** `TFNavBarTitleFont.title` to accept an effective point size and make `TFNativeHeaderModifier` derive it from the exact heading size plus Dynamic Type.
- [ ] **Step 3: Replace** segmented size pickers with right-aligned integer `TextField`s, `pt` suffix and a keyboard «Готово» action; invalid input leaves the last valid value.
- [ ] **Step 4: Parse** the three Swift files; expected no diagnostics.

### Task 3: Tasks and archive hierarchy

**Files:**
- Modify: `Sources/Features/Projects/ProjectTasksScreen.swift`
- Verify only: `Sources/Features/Tasks/TaskArchiveScreen.swift`
- Verify only: `Sources/DesignSystem/Components/TFTaskRow.swift`

**Interfaces:**
- Consumes: exact heading and list groups from Tasks 1–2.
- Produces: `ЗАДАЧИ` through the shared native header; `АРХИВ` continues through that same header; both lists retain `listTitle/action/caption` routing.

- [ ] **Step 1: Limit** the custom `.principal` toolbar in `ProjectTasksScreen` to actual project screens, so the common task list uses `tfNativeHeader("Tasks")` and its exact heading group.
- [ ] **Step 2: Audit** `TaskArchiveScreen` uses `tfNativeHeader("Archive")` and `DirectoryTaskRow`, and `TFTaskRowContent` maps title/description/metadata to `listTitle/action/caption`.
- [ ] **Step 3: Parse** `ProjectTasksScreen.swift`; expected no diagnostics.

### Task 4: Targeted verification and direct delivery

**Files:**
- Create: `docs/2026-11-08-exact-typography-sizes.md`
- Modify: `AGENT-WORK-SCOPES/2026-11.md`
- Modify: `docs/реестр-сводка.md`
- Include: the approved spec and this plan.

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces: documented and published `main`.

- [ ] **Step 1: Run** the focused host test; expected `PASS typography preferences`.
- [ ] **Step 2: Run** `swiftc -parse` for every changed Swift file, `python3 Tools/design-system-guard.py --diff HEAD`, and `git diff --check`.
- [ ] **Step 3: Review** the exact changed-file list and staged diff; preserve unrelated untracked or concurrent changes.
- [ ] **Step 4: Write** the delivery report, set the scope row to `REVIEW`, regenerate the digest.
- [ ] **Step 5: Commit** only enumerated files, push `origin main`, then `github main`, and verify both remote refs equal the published SHA.
