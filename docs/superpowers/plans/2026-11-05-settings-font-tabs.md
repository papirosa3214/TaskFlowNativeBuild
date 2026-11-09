# Settings Font Tabs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Заменить раздутый «Внешний вид» одним экраном «Шрифт» с независимыми вкладками приложения и чата, а также убрать имя голоса и вложенные рамки сервера.

**Architecture:** Foundation-only `TypographyPreferences` владеет ключами и одноразовой миграцией. `FontSettingsScreen` рисует две нативные вкладки и живые образцы. Типографика и цвет чата получают свои хранилища и центральные токены; хром чата остаётся в стиле приложения.

**Tech Stack:** Swift 6, SwiftUI, Foundation/UserDefaults, XcodeGen, host `swiftc` test, existing TaskFlow design system.

**Spec:** `docs/superpowers/specs/2026-11-05-settings-font-tabs-design.md`

## Global Constraints

- Минимальная iOS: 18.0.
- Системные `Picker(.segmented)` и `Slider` без tint/background/overlay/scaleEffect/рамок.
- Не менять веса и кегль `RoleReplyMarkdown.readableText` иначе, чем через существующие шесть групп чата.
- Код чата остаётся моноширинным.
- Не запускать симулятор, UI-тесты или установку на iPhone.
- Полные тестовые прогоны запрещены; только целевой host-тест, parse/сборка и сторож.

## Review Focus

- Уже настроенные пять групп не затираются миграцией.
- Новый тон чата первый раз копирует прежний тон, но потом меняется независимо.
- Светлая тема не окрашивается пользовательским тоном.
- HTML-ответы, Markdown, виджеты и структурированный вывод берут тон чата, а композер/шапка — тон приложения.
- Смена вкладки и движение ползунка не выбрасывают экран и сразу обновляют образец.

---

### Task 1: Preference storage and migration

**Files:**
- Create: `Sources/DesignSystem/Theme/TypographyPreferences.swift`
- Create: `Tools/test_typography_preferences.swift`
- Modify: `Sources/DesignSystem/Theme/AppAppearance.swift`
- Modify: `Sources/App/TaskFlowApp.swift`

**Interfaces:**
- Produces: `TypographyContext { app, chat }`, `TypographyPreferences.migrateIfNeeded(_ defaults: UserDefaults)`, context-specific tone/face keys, and existing five/six scale keys.

- [ ] **Step 1: Write the failing host test** for untouched per-group values, migration of a legacy global scale only into missing app groups, one-time chat-tone copy, and independent app/chat face keys.
- [ ] **Step 2: Run RED:** `swiftc Sources/DesignSystem/Theme/TypographyPreferences.swift Tools/test_typography_preferences.swift -o /tmp/taskflow-typography-preferences-tests && /tmp/taskflow-typography-preferences-tests`; expected compile failure because the source API does not exist.
- [ ] **Step 3: Implement** the Foundation-only preference/migration API; call it once from `TaskFlowApp.init()`; remove the root `TFTextScale` override while retaining the existing `...xxxLarge` Dynamic Type cap.
- [ ] **Step 4: Run GREEN** with the same command; expected `PASS typography preferences`.

### Task 2: Font settings screen and navigation

**Files:**
- Create: `Sources/Features/Settings/FontSettingsScreen.swift`
- Modify: `Sources/Features/Settings/SettingsScreen.swift`
- Modify: `Sources/App/Navigation/AppRoute.swift`
- Modify: `Sources/App/Navigation/RouteDestinationView.swift`
- Modify: `Sources/DesignSystem/Theme/AppAppearance.swift`
- Modify: `Sources/DesignSystem/Theme/Typography.swift`

**Interfaces:**
- Consumes: `TypographyContext` and context-specific keys from Task 1.
- Produces: `AppRoute.fontSettings`, `FontSettingsScreen`, app/chat face selection, five app and six chat slider bindings.

- [ ] **Step 1: Add** `.fontSettings` to the route enum/factory and a single `navRow(icon: "textformat", title: "Шрифт", route: .fontSettings)` to user settings; remove `appearanceSection`, its state and the legacy global-size UI.
- [ ] **Step 2: Build** `FontSettingsScreen` with a native segmented picker, tone swatches, `Menu` titled «Стиль шрифта», discrete native sliders and live samples. The app sample uses all five groups; the chat sample uses all six.
- [ ] **Step 3: Wire** app face/tone and chat face/tone independently; keep chat code `.monospaced`.
- [ ] **Step 4: Generate project:** `xcodegen generate`; expected success because a new source file was added.
- [ ] **Step 5: Parse changed Swift:** `swiftc -parse` on the new screen and directly changed standalone Swift files; expected no diagnostics.

### Task 3: Complete chat tone/style coverage

**Files:**
- Modify: `Sources/DesignSystem/Theme/Color+Palette.swift`
- Modify: `Sources/DesignSystem/Theme/Typography.swift`
- Modify: `Sources/Chat/Output/RoleReplyMarkdown.swift`
- Modify: `Sources/Chat/Output/ChatHTMLView.swift`
- Modify: `Sources/Chat/Output/ChatStructuredOutputView.swift`
- Modify: `Sources/Chat/Output/ChatWidgetView.swift`
- Modify: `Sources/Chat/Output/ResolutionPlanBlock.swift`
- Modify: `Sources/Chat/Output/ChatWorkPlanStrip.swift`
- Modify: `Sources/Chat/Output/RoleQuestionCard.swift`
- Modify: `Sources/Chat/Widgets/WidgetSemantics.swift`
- Modify: `Sources/Chat/Widgets/WidgetCompareView.swift`
- Modify: `Sources/Chat/Widgets/WidgetStatusViews.swift`
- Modify: `Sources/Chat/Widgets/WidgetLayoutVariants.swift`
- Modify: `Sources/Chat/Widgets/WidgetTimeViews.swift`
- Modify: `Sources/Chat/Feed/ChatFeedParts.swift`
- Modify: `Sources/Chat/Feed/ChatFeedMarks.swift`
- Modify: `Sources/Chat/Feed/SelectableTextSheet.swift`

**Interfaces:**
- Consumes: chat tone and face from Task 1.
- Produces: `Color.tfChatText` and context-aware `.tfChat(...)` fonts used only by chat content.

- [ ] **Step 1: Add** `Color.tfChatText` with the same light-theme rule as `tfText`; make `.tfChat(...)` use the saved chat face except `.mono`.
- [ ] **Step 2: Replace** application text tokens with `tfChatText` only in feed/output/widget content; do not change composer, picker, session panel, nav header or buttons.
- [ ] **Step 3: Update** `ChatHTMLView` CSS and selectable-text UIKit bridge to the chat token.
- [ ] **Step 4: Audit:** `rg -n 'TFTextTone.saved|Color\.tfText' Sources/Chat/Output Sources/Chat/Widgets Sources/Chat/Feed`; every remaining occurrence must be justified as chrome/non-content or replaced.

### Task 4: AI voice and server borders

**Files:**
- Modify: `Sources/Features/Settings/SettingsScreen.swift`
- Modify: `Sources/Features/Settings/SystemControlSection.swift`
- Modify: `Sources/Features/Settings/ServerRestartRow.swift`
- Modify: `Sources/Features/Settings/ServerStatusSection.swift`

**Interfaces:**
- Produces: voice row without trailing technical name and server content without nested `TFCard` containers.

- [ ] **Step 1: Remove** `secretaryVoiceValue` and omit the trailing view while preserving the navigation chevron.
- [ ] **Step 2: Unwrap** the three nested bordered `TFCard` containers, retaining their row stacks, dividers, tasks, alerts and error banners unchanged.
- [ ] **Step 3: Parse** the four files with `swiftc -parse`; expected no diagnostics.

### Task 5: Targeted verification, documentation and direct delivery

**Files:**
- Create: `docs/2026-11-05-settings-font-tabs.md`
- Modify: `AGENT-WORK-SCOPES/2026-11.md`
- Modify: `docs/реестр-сводка.md`

**Interfaces:**
- Consumes: all prior tasks.
- Produces: verified, documented and published `main`.

- [ ] **Step 1: Run** the focused host preference test; expected PASS.
- [ ] **Step 2: Run** `python3 Tools/design-system-guard.py --diff HEAD`; expected no new violations.
- [ ] **Step 3: Run** a device-only unsigned build (`generic/platform=iOS`, no simulator) in the background; expected `BUILD SUCCEEDED`.
- [ ] **Step 4: Review** `git diff --check`, exact changed-file list and scoped diff; do not include unrelated untracked files.
- [ ] **Step 5: Write** the delivery report and set the registry row to REVIEW; regenerate the digest.
- [ ] **Step 6: Commit only enumerated files**, push `origin main`, then update `github main`; verify both refs equal the published SHA. Do not create a PR.
