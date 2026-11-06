# План калибровки типографики приложения

> **Для владельца:** план касается только интерфейса основного iOS-приложения TaskFlow. `Sources/Chat/**` и текст чата не изменяются.

**Цель:** сделать пять настроек размера и выбор гарнитуры единым, измеримым и предсказуемым механизмом для всего интерфейса приложения.

**Архитектура:** один Foundation-only резолвер вычисляет базовый размер, оптическую поправку и кривую Dynamic Type; SwiftUI-адаптер применяет результат ровно один раз. Все текстовые места приложения получают одну из пяти семантических групп. Экран настроек использует тот же резолвер, что и производственные экраны.

**Стек:** Swift, SwiftUI, CoreText, XCTest/host-side Swift tests, Python guard scripts.

Связанная спецификация: `docs/superpowers/specs/2026-11-07-app-typography-calibration-design.md`.

---

## 1. Зафиксировать измерения и падающие проверки

**Файлы:**

- создать `Tools/test_app_typography_resolver.swift`;
- создать `Tools/test_app_typography_coverage.py`;
- создать `Tools/measure_app_font_metrics.swift`;
- изменить только при необходимости запуска `Package.swift` или точечный test runner проекта.

**Шаги:**

1. Вынести текущий CoreText-замер кириллических «Н» и «н» в воспроизводимый инструмент.
2. Добавить RED-проверки:
   - минимальный итоговый базовый кегль не ниже 11 pt;
   - пять ступеней каждой группы строго возрастают;
   - максимальная ступень каждой гарнитуры не выглядит мельче System/standard;
   - в интерфейсе вне `Sources/Chat/**` нет необоснованного обхода пяти групп;
   - выбранная группа возвращает тот же размер, который показывает экран настроек.
3. Запустить только эти проверки и сохранить ожидаемое исходное падение: 9,35 pt, Cormorant/Caveat и 36 обходов.

## 2. Ввести чистый резолвер пяти групп

**Файлы:**

- создать `Sources/DesignSystem/Theme/AppTypographyResolver.swift`;
- изменить `Sources/DesignSystem/Theme/AppAppearance.swift`;
- изменить `Sources/DesignSystem/Theme/TypographyPreferences.swift`;
- изменить `Tools/test_app_typography_resolver.swift`.

**Шаги:**

1. Описать пять явных лестниц из спецификации вместо общего множителя.
2. Ввести собственный Foundation-only `AppTypographyCurve`, не зависящий от `Font.TextStyle`.
3. Добавить таблицу поправок `гарнитура × группа × вес`, полученную из CoreText-метрик.
4. Возвращать из резолвера базовый `Double`, кривую и данные семейства; не создавать `SwiftUI.Font` в чистом слое.
5. Обеспечить lossless mapping: ни одна семантическая группа или ступень не сливается с соседней округлением.
6. Добиться GREEN для арифметики, монотонности, минимума и допуска оптической высоты 8%.

## 3. Оставить один владелец Dynamic Type и живое обновление

**Файлы:**

- изменить `Sources/DesignSystem/Theme/Typography.swift`;
- создать `Sources/DesignSystem/Theme/AppTypographyStore.swift`;
- изменить `Sources/App/TaskFlowApp.swift`;
- изменить точечные тесты резолвера.

**Шаги:**

1. Инъецировать app-only `@Observable AppTypographyStore` через environment без корневого `.id`.
2. В `TFTextStyleModifier` получать размер только через новый резолвер.
3. Применять `@ScaledMetric` ровно один раз с кривой группы.
4. Для пользовательской гарнитуры после масштабирования использовать `.custom(_:fixedSize:)`, для System — `.system(size:)`.
5. Проверить host-тестом, что смена одной группы меняет только стили этой группы и не затрагивает остальные.

## 4. Сделать настройки правдивым производственным образцом

**Файлы:**

- изменить только app-ветку `Sources/Features/Settings/FontSettingsScreen.swift`;
- при необходимости изменить app-only компоненты предпросмотра в том же файле;
- изменить `Tools/test_app_typography_resolver.swift`.

**Шаги:**

1. Удалить отдельную формулу предпросмотра приложения.
2. Строить образец через тот же `TFTextStyleModifier`/резолвер, что используют реальные экраны.
3. Показывать фактический базовый кегль выбранной гарнитуры до Dynamic Type, а не `base × multiplier`.
4. Подписать пять ступеней стабильно и не смешивать их с системными accessibility-категориями.
5. Не менять экран и хранение настроек чата.

## 5. Подключить к пяти группам весь интерфейс приложения

**Файлы с известными обходами:**

- `Sources/DesignSystem/Components/AvatarCropEditor.swift`;
- `Sources/DesignSystem/Components/TFMarkdownSourceEditor.swift`;
- `Sources/DesignSystem/Hints/HintOverlay.swift`;
- `Sources/Features/Markdown/MarkdownDocumentRenderer.swift`;
- `Sources/Features/Overview/CompletionHeatmap.swift`;
- `Sources/Features/Projects/ProjectsScreen.swift`;
- `Sources/Features/Roles/RoleLoadScreen.swift`;
- `Sources/Features/Roles/RoleTranslation.swift`;
- `Sources/Features/Settings/RemoteMachinesScreen.swift`;
- `Sources/Features/Settings/SecretsScreen.swift`;
- `Sources/Features/Tasks/Detail/AttemptLadderView.swift`;
- `Sources/Features/Tasks/Detail/PlanWorkSelectionView.swift`;
- `Sources/Features/Tasks/Detail/SubtaskHostPicker.swift`;
- `Sources/Features/Tasks/Detail/TaskCodeChangesViews.swift`;
- `Sources/Features/Tasks/Detail/TaskOutcomeSection.swift`;
- `Sources/Features/Tasks/Detail/TaskPreparationView.swift`;
- `Sources/Features/Tasks/QuickAddTaskView.swift`;
- `Sources/Features/Tasks/TaskCardContent.swift`;
- изменить `Tools/test_app_typography_coverage.py`.

**Шаги:**

1. Для каждого из 36 мест назначить одну из существующих пяти групп по смыслу, не по текущему числу.
2. Моноширинным фрагментам сохранить семейство, но брать размер из группы.
3. Геометрические глифы в аватарах/значках исключать только точечно, с объясняющим комментарием и allowlist-проверкой.
4. Запретить новые прямые системные text styles во всём интерфейсе приложения, исключая `Sources/Chat/**`.
5. Добиться GREEN: ноль необоснованных обходов.

## 6. Сравнение декоративных гарнитур и точечная приёмка

**Файлы:**

- создать `docs/typography/app-font-comparison.md`;
- обновить `docs/superpowers/specs/2026-11-07-app-typography-calibration-design.md` фактическими коэффициентами и решением владельца;
- обновить относящиеся точечные тесты.

**Шаги:**

1. Сформировать сравнение System, Cormorant, Caveat и Marck Script для всех пяти групп, regular/bold и кириллических «Н/н».
2. До ограничения или удаления гарнитур отдельно получить решение владельца: полный интерфейс с калибровкой либо только заголовки/исключение из списка приложения.
3. Запустить только целевые проверки:
   - preferences storage test;
   - system-font-style guard;
   - resolver metrics test;
   - app typography coverage test;
   - `git diff --check` по изменённым файлам.
4. Отдельно проверить diff: в `Sources/Chat/**` изменений нет.
5. Зафиксировать работу отдельными читаемыми коммитами и доставить в `main` по правилам репозитория.

## Граница текущей работы

Этот документ — план, а не реализация. На текущем этапе не запускаются симулятор/UI-тесты, приложение не устанавливается на iPhone и исходный код не меняется. После утверждения плана реализация идёт последовательно RED → GREEN; субъективная визуальная приёмка остаётся за владельцем.
