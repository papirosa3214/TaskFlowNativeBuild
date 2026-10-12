# Заголовки экранов капсом по центру — 12.10.2026

## Работа

Поручение владельца: верхние заголовки всех экранов («Обзор», «Проекты», «Входящие»,
«Чаты» и прочие) перевести в капс той же гарнитуры, что и заголовки разделов
«Обзора», и держать по центру — однородно на всех экранах.

## Результат

Все заголовки на экранах — капс Oswald по центру. Реализовано системной шапкой,
собственных шапок не добавляли.

## Что сделано

- `Sources/DesignSystem/Theme/Typography.swift` — ранее (отдельная строка):
  `TFSectionDisplayModifier` и `.tfSectionDisplay(style:color:)` для заголовков
  разделов, `TFFont.sectionDisplayTracking = 0.6`.
- `Sources/DesignSystem/Components/TFNativeHeader.swift`:
  - `enum TFNavBarTitleFont.configure()` — меняет ТОЛЬКО `titleTextAttributes` /
    `largeTitleTextAttributes` у `UINavigationBar.appearance()`. Фон, блюр и
    scroll edge effect не трогаются: на iOS 27 их рисует система, ручная
    имитация уже чинилась.
  - Гарнитура `UIFont(name: "Oswald", ...)`. Family в файле = «Oswald», «Bold» —
    начертание (name ID 2), поэтому `UIFont(name: "Oswald Bold")` молча падает
    на системный шрифт.
  - `tfNativeHeader` вызывает `.navigationTitle(title.uppercased())` — у
    навбара нет атрибута «капс», регистр задаётся строкой.
  - Дефолт `displayMode` изменён с `.large` на `.inline` (см. ниже).
- `Sources/App/TaskFlowApp.swift` — `TFNavBarTitleFont.configure()` один раз в
  `init()` после `AppAppearance.migratePreference()`.

## Проверки

- `BUILD SUCCEEDED` (iPhone Air, iOS 27).
- Кадры симулятора после установки: «Обзор», «Чаты», «Проекты», «Настройки» —
  на всех заголовок капсом Oswald по центру.

## Ограничения

- Владелец попросил образец Big Shoulders Display, но у этой гарнитуры НЕТ
  кириллицы (проверено по `cmap`, ни Google Fonts, ни оригинальный репозиторий).
  Стоит Oswald Bold — ближайшая узкая жирная гротеск-гарнитура с полной
  кириллицей. Выбор гарнитуры для заголовков разделов «Обзора» ещё открыт:
  варианты с кириллицей показаны в
  `docs/2026-10-12-overview-yellow-display/font-variants.png`.

## Материалы

- `docs/2026-10-12-navbar-caps.md`
- Кадры: `/tmp/tfshot/nav-overview.png`, `nav-chat3.png`, `nav-projects.png`,
  `nav-settings.png`.

## Рецепт на будущее: почему `.inline`

Режим `.large` на iOS 27 рисуется СИСТЕМНЫМ шрифтом и всегда слева — атрибуты
`largeTitleTextAttributes` из appearance до него не доходят. С `.inline` тот же
appearance работает, и заголовок садится по центру. Крупного заголовка по центру
iOS не рисует в принципе, а владельцу нужен именно центр. Проверено 12.10.2026 на
экране «Чаты»: с дефолтным `.large` остался системный шрифт и левое
выравнивание, после смены дефолта — Oswald капсом по центру.