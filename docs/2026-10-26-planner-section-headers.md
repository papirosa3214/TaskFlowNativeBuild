# Подзаголовки секций «Планирования» — как в карточке задачи, без подложки

Дата: 26.10.2026
Реестр: `LOCK-PLANNER-SECTION-HEADERS-20261026`

## Результат

Подзаголовки секций ленты «Планирования» («Входящие», «Ждут вас», «Просроченные»,
«Сегодня», «Предстоящие») набрали тот же шрифт, кегль и жирность, что подзаголовки
карточки задачи («Задача», «План», «Лента активности»), и лишились непрозрачной
подложки.

| | Было | Стало |
| --- | --- | --- |
| Шрифт | системный San Francisco | системный San Francisco (тот же, что в карточке) |
| Кегль | 13 pt | 20 pt |
| Жирность | regular | semibold |
| Цвет | `tfSub` (серый) | `tfText` (белый в тёмной теме, `#171717` в светлой) |
| Разрядка | +0.10 | −0.40 |
| Подложка | `Color.tfBackground` (в тёмной теме — чёрная) | прозрачная |

## Что сделано

Правка одна — `Sources/Features/Today/TodayListView.swift`, функция `header(_:)`
(единственное место, где рисуются подзаголовки секций ленты планирования;
`TodayListView` используется только из `TodaySectionView`, а тот — только из
`UpcomingScreen`, вкладка «План», режим «Все задачи»).

1. `Text(section.title)` переведён с `.tfText(.action)` + `Color.tfSub` на
   `.tfText(.taskTitle)` + `Color.tfText` + `.textCase(nil)` — ровно как в
   `taskSectionHeader(_:)` карточки задачи (`Sources/Features/Task/TaskFormScreen.swift`).
   `.tfText(.taskTitle)` — это `TFTextStyle.baseSize = 20`, вес `semibold`,
   трекинг `TFFont.taskTitleTracking = −0.40`, кегль масштабируется под Dynamic Type.
2. Убрана непрозрачная подложка `.background(Color.tfBackground)`. Подложка появилась
   в ревизии списка от 24.10.2026 (коммит `9b284a62`), когда лента переехала из
   `LazyVStack` c `pinnedViews: [.sectionHeaders]` в `List`; до этого подложки не
   было — так и просил владелец 03.09.2026, о чём прямо написано в соседнем
   `UpcomingListView.dateHeader(_:)` («тот же приём, что у соседних подзаголовков
   секций в TodayListView.header(_:): прилипает, но полностью прозрачный, никакого
   фона под текстом»). Решение владельца 26.10.2026 («подложка… была прозрачной»)
   вернуло это поведение.

Комментарии в коде обновлены: старое решение 12.10.2026 («заголовки как везде»,
13 pt `tfSub`) помечено отменённым, чтобы его снова не «унифицировали».

## Проверки

- Сторож дизайн-системы: `python3 Tools/design-system-guard.py --diff` — чисто.
- Сборка: `xcodebuild -project TaskFlow.xcodeproj -scheme TaskFlow -sdk iphonesimulator
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build_sim ARCHS=arm64
  ONLY_ACTIVE_ARCH=YES build` — BUILD SUCCEEDED. Симулятор не загружался, только
  компиляция.
- Юнит-тесты не добавлялись: правка декоративная, проверять текст исходника тестом
  смысла не имеет. Существующие `Tests/Today/TodaySectionTrackerTests.swift` затрагивают
  только логику `showsHeader(among:)`, которая не менялась.

### Зависимость: HEAD не компилируется (не связано с этой правкой)

Коммит владельца `a3fda8fc` («на экране загрузки ролей видно работу в чате без карточки»,
26.10.2026 00:29) оставляет проект без компиляции:

```
Sources/Features/Directory/RoleLoadScreen.swift:239:40: error: cannot find 'row' in scope
```

`chatContour(_:laneIndex:)` (строка 238) обращается к `row`, которого у неё нет в области
видимости: `row` — параметр `chatLanes(_:)`. Готовая правка (передать `row` в
`chatContour`):

```swift
// chatLanes(_:)
chatContour(item, laneIndex: laneIndex, row: row)

// chatContour(_:laneIndex:)
private func chatContour(_ item: RoleLoadLayout.ChatContour, laneIndex: Int, row: RoleLoadLayout.RoleRow) -> some View {
```

Чтобы убедиться, что правка подзаголовков компилируется, эта правка была применена
**временно локально** только на время сборки, после чего откачена
(`git checkout -- Sources/Features/Directory/RoleLoadScreen.swift`). Чужой файл в
рабочем дереве не изменён — сборка «BUILD SUCCEEDED» относится к состоянию с этой
временной правкой. Без неё проект не собирается ни с какой правкой подзаголовков.
Решение по этому коммиту — за владельцем.

Отдельно: сборка с `-destination 'generic/platform=iOS Simulator'` без `ARCHS=arm64`
падает на линковке — `libtext_processing_rs.a` из FluidAudio/NemoTextProcessing собран
только под arm64, а generic-назначение тянет ещё и x86_64-слайс. Для проверки компиляции
нужен `ARCHS=arm64 ONLY_ACTIVE_ARCH=YES`.

## Ограничения

- Кадры в симуляторе не снимались: симулятор не трогаем по прямому указанию владельца
  от 25.10.2026. Внешний вид оценивает владелец.
- Соседние заголовки диапазонов планирования (`UpcomingListView.dateHeader(_:)` —
  даты «Один день», «Неделя») не тронуты: владелец называл подзаголовки «Входящие»,
  «Ждут вас». Если нужно привести и их к виду карточки — отдельная правка.
- Раздел «Просроченные» и раньше не выделялся красным в самом заголовке (красным
  был только значок, а значков у секций нет) — цвет текста ровно такой, как у
  остальных подзаголовков.

## Материалы

- `Sources/Features/Today/TodayListView.swift` — `header(_:)`.
- `Sources/Features/Task/TaskFormScreen.swift` — `taskSectionHeader(_:)`, образец.
- `Sources/Features/Upcoming/UpcomingListView.swift` — `dateHeader(_:)`, соседний
  пример прозрачной подложки.
- `Sources/DesignSystem/Theme/Typography.swift` — `TFTextStyle.taskTitle`,
  `TFTextStyleModifier`.
