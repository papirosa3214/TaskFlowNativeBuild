# Сессия 18.10.2026 — системный таббар: акцент раздела и круг «+»

Полный протокол сессии от первого сообщения владельца до текущего. Ничего не сглажено: включая неудачные попытки, откаты, тупики и мои ошибки.

- Проект: `/Users/max/Проекты/TaskFlowNativeBuild` (единственная каноничная копия)
- Файл правок: `Sources/DesignSystem/Navigation/TFPillTabBar.swift`
- Строка реестра: `LOCK-TABBAR-ACCENT-20261018` (`AGENT-WORK-SCOPES.md`)
- Симулятор: iPhone Air, iOS 27.0, UDID `9FF78D89-EE84-4914-AA56-D0A72D1AF43A`, 420×912 pt
- Бандл: `com.maksim.taskflow.native`
- Сборка: `xcodebuild -project TaskFlow.xcodeproj -scheme TaskFlow -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone Air,OS=27.0' -derivedDataPath build_sim build`

---

## 1. Задача

Покрасить в **системном** нижнем таббаре (iOS 27, линза):

1. Выбранный ярлык + название раздела — в акцент приложения `Color.tfRed`.
2. Круглую кнопку «+» справа — тоже красная. Референс владельца: чёрная пилюля с 4 ярлыками, выбранный подсвечен линзой, справа отдельный круглый стеклянный круг «+» салоново-красного цвета с тонким светлым ободком.

Референс-скриншот: `/Users/max/.minimax/v2/assets/2026/10/18/14-20-34-089-asset_20261018-142034-089_f6098fb3eaa5_ba917cc8-IMG_9119.jpg`

Параллельно была отложена владельцем задача «чат: окно ввода чёрное в светлой теме» (`LOCK-CHAT-COMPOSER-LIGHT-20261018`) — она ради таббара не начата.

---

## 2. Хронология

### Часть A. Акцент ярлыка — сделано и оставлено

`TabView(selection:)` в `TFPillTabBar.swift` получил `.tint(Color.tfRed)`. Выбранный ярлык с подписью красится в акцент, когда линза до него доходит. Подтверждено кадрами симулятора. Работает штатно, откатывать нечего.

### Часть B. Восемь попыток покрасить системный круг — все откачены

| # | Способ | Результат |
|---|---|---|
| 1 | `.tint(Color.tfRed)` на `TabView` | красит только ярлык, круг игнорирует |
| 2 | Своя подпись `Label` с красной иконкой | система рисует свой SF Symbol, игнорирует |
| 3 | Глобальный акцент приложения (`AccentColor.colorset` + `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME`) | `NSAccentColorName` подтверждён в Info.plist, цвет есть в `Assets.car` — красит ярлык, не круг. **Откачено по решению владельца** |
| 4 | `window.tintColor` через UIViewRepresentable | эффекта нет |
| 5 | `UITabBarAppearance.backgroundColor` | ломает стекло iOS 26+, панель становится прозрачной |
| 6 | Свой `Button` с `.glass` / `.glassEffect(.tint)` поверх | закрывает системный «+» |
| 7 | Диск в `.background()` под панелью | системное стекло преломляет его в радужное пятно |
| 8 | Роль `.search` вместо `.prominent` | плюс уезжает внутрь пилюли пятой вкладкой |

Два независимых исследования (англоязычные и русскоязычные источники, субагенты) дали тот же вывод: официального API цвета у `TabRole.prominent` нет ни в SwiftUI, ни в UIKit; настройки «Accent Color» на iOS/iPadOS не существует (только macOS); рабочий путь для системного акцента — `tabViewBottomAccessory` (iOS 26.1+), но он не про prominent-круг.

Вывод сессии: **системный круг покрасить нечем.** Рабочий путь — свой круг поверх системного.

### Часть C. Компоновка

Без системной prominent-вкладки не получится: четыре ярлыка растягиваются на всю ширину, «Чат» уезжает под круг. Решение: системную prominent-вкладку оставить, наш круг положить ровно на неё. Компромисс — слой приложения поверх системного, и в доступности два элемента «Создать» (системный и наш).

### Часть D. Геометрия — от «на глаз» к точным замерам

Сначала координаты подбирались на глаз по кадру (`safeAreaInsets.bottom + 22`, размер 48 pt, padding 20). Из-за этого круг то расходился с системным, то выглядел «наложенным».

Владелец потребовал: «Ты не можешь воспользоваться X-кодом… подключись и используй нативные инструменты». Подключился к Xcode MCP:

- `XcodeOpenWorkspace` → `TaskFlow.xcodeproj`, схема `TaskFlow`, назначение `iPhone Air`
- `DeviceInteractionStartWorkspaceSession` → UDID `9FF78D89-EE84-4914-AA56-D0A72D1AF43A` (интеракт только через субагента — тот не получил инструментов, но нашёл готовый дамп иерархии в `docs/2026-10-18-native-tabbar/simulator-first/system-tabbar-hierarchy.txt`)

**Точные координаты системы:**

```
Экран                 420 × 912 pt
TabBar                {0, 829, 420×83}
Button «Создать»      {337, 829, 62×62}   ← система, центр (368, 860)
Пилюля                {21, 829, 308×62}
Ярлыки                y 833, h 54
```

Круг переведён на эти числа: `createCircleSize = 62`, `createCircleEdgeInset = 21`, отступы `.padding(.trailing, 21)` / `.padding(.bottom, 21)`. `GeometryReader` с вычислениями от `safeAreaInsets` убран.

**Проверка сборки замером по пикселям** (`ffmpeg` → raw RGB, порог по красному):

| | Замерено | Задано | Система |
|---|---|---|---|
| Диаметр | 62.0 pt | 62 | 62 |
| Отступ справа | 21.3 pt | 21 | 21 |
| Отступ снизу | 21.3 pt | 21 | 21 |
| Центр | (367.9, 859.9) | (368, 860) | (368, 860) |

### Часть E. Стекло против заливки — три круга по кругу

Владелец: «если это мне материал стекло» → круг должен быть **стеклом**. Через `DocumentationSearch` Xcode найден нативный API: цвет стеклу задаёт **тинт**.

```swift
.glassEffect(.regular.tint(Color.tfRed).interactive(), in: .circle)
```

Появилась проблема с Swift: `private struct CreateCircleMaterial: ViewModifier` внутри дженерик-структуры `TFPillTabBar<Content>` — `Content` резолвился во внешний дженерик-параметр, а не в `Self.Content`. Вынес тип на уровень файла.

По его же просьбе («сделай красный чуть-чуть прозрачным») тинт получил `.opacity(0.78)` — замер центра круга стал `(206, 94, 83)` вместо `(194, 51, 37)`.

Владелец вернул круг назад: «зачем ты опять убрал красный, был же идеальный красный… заливка. Всё было чётко» → плоский тинт и стекло убраны, возвращена ровная заливка `Color.tfRedSolid` + тонкий светлый ободок `strokeBorder(Color.white.opacity(0.28), lineWidth: 1)`.

После отката его требование «чуть прозрачным» потерялось — по его же замечанию «ты че, по опять плоский круг сделал» заливка сделана полупрозрачной: `Color.tfRedSolid.opacity(0.86)`.

### Часть F. Тёмная тема

Владелец: «включи темную тему, заебал за дрот, в белой теме всё… тастить».

Тема в приложении своя: `TaskFlowApp.swift:83` — `.preferredColorScheme((AppAppearance(rawValue: appearanceRaw) ?? .dark).colorScheme)`, ключ `UserDefaults` `taskflow_appearance`, дефолт `dark`. Системная тема симулятора (`simctl ui appearance dark`) эффекта не дала. Сработало:

```bash
xcrun simctl spawn <udid> defaults write com.maksim.taskflow.native taskflow_appearance dark
```

Приложение запущено в тёмной теме.

### Часть G. «Круг должен ездить вместе с панелью»

Жалоба владельца: «У нас круг теперь всё время стоит, он не лазит вместе с панелью. Если её нету — и круг должен исчезать». Подтверждено его скриншотом: экран «Настройки» с кнопкой «Назад» — таббара нет, красный круг висит в углу.

Кто прячет панель: `RootShellView.swift:422` — `.toolbar(isPillTabBarEnabled && (quickAddDraft != nil || !(paths[tab]?.isEmpty ?? true)) ? .hidden : .automatic, for: .tabBar)`. Файл **вне разрешённых моей строкой реестра**.

Поиск в документации Xcode: читающего API у SwiftUI нет — `TabCustomization.tabBarVisibility` относится к пользовательской кастомизации, а не к `.toolbar(.hidden)`.

**Ложная гипотеза, которую я сначала принял:** определить видимость панели по нижнему safe area. Замер `NSLog` это опроверг: `safeAreaBottom = 34.0` **и при видимом таббаре** — панель в safe area не входит. С порогом 44 круг стал невидим на всех экранах.

**Источник истины найден через UIKit** (временная разведка `TFProbe` в логе):

```
TFProbe tabbar=nil                                  ← экран без панели
TFProbe UITabBarController.isHidden=false frame=(0, 829, 420, 83)   ← панель есть
```

Реализация: `TabBarVisibilityObserver: UIViewControllerRepresentable` в `.background(TabView)`, чтение в `viewDidLayoutSubviews`, публикация в `@Binding isTabBarVisible`, круг гасится через `.opacity()`.

**Проверка временным XCUITest** (`TempCreateCircleSwitchUITests`, `TASKFLOW` таб-таргет `TaskFlowUITests`) — прогон по всем вкладкам:

```
tab=Обзор        system=(337,829,62,62)  ours exists, visible=true
tab=Проекты      system=(337,829,62,62)  ours exists, visible=true
tab=Планирование system=(337,829,62,62)  ours exists, visible=true
tab=Чат          system=(337,829,62,62)  ours exists, visible=true
```

Вывод: в покое круг на месте на всех вкладках, разрыва в статике нет.

**Ошибка в реализации скрытия:** на маршруте `settings` лог показал `tabbar=nil`, и код решил «панели нет → гасим». Оказалось, что таббар бывает временно не найден и на экранах, где он ЕСТЬ — круг погас и там тоже (регресс, подтверждён кадром серого круга). Попытка починить через повторную проверку на следующем runloop — не доведена и **откачена целиком по требованию владельца**: «Лучше уж так, чем… не можешь сделать так, как уже было сделано».

### Часть H. Знания, записанные в базу

- Команда TaskFlow (`taskflow_remember`, scope=team): урок про тинт стекла, `.glassProminent` +27 pt, невозможность покраски системного круга, координаты `{337,829,62×62}`, safe area vs UIKit-таббар.
- RAGFlow «DataSet Research»: `2026-10-18-liquid-glass-tint-system-glass.md` (3473 символа) — таблица восьми откатанных способов, рецепт кода, разбор safe area против UIKit, ссылки на документацию Apple и WWDC.
- RAGFlow ранее: `2026-10-18-ios-prominent-tab-tint-research.md` (5115 символов).
- Agent memory: урок окраски системного стекла.

---

## 3. Технические выводы сессии

1. **Системный prominent-круг покрасить нечем** — API цвета нет ни в SwiftUI, ни в UIKit; 8 способов проверены сборками.
2. **Цвет системному стеклу задаёт тинт**: `glassEffect(.regular.tint(color).interactive(), in: .circle)`. Материал привязывается к **bounds вьюхи** — размер задаётся frame'ом. Заливка — не стекло, а крашеный диск.
3. **`.buttonStyle(.glass/.glassProminent)` добавляет ~27 pt полей** — элемент выглядит «раздутым». Стекло надо вешать напрямую на вьюху.
4. **Координаты — из UI-иерархии, не на глаз**; проверка сборки — замер по пикселям кадра.
5. **Видимость таббара через safe area не определяется**: 34 pt и при видимой панели. UIKit-даёт `UITabBarController.tabBar.isHidden` + frame; при скрытой панели таббар из иерархии пропадает (`nil`) — но и на старте бывает временно `nil`, что ломает логику.
6. **Тема приложения своя** — `taskflow_appearance` в UserDefaults, системная тема симулятора на неё не влияет.

---

## 4. Решения владельца (зафиксированы)

- Акцент выбранного раздела через `.tint(Color.tfRed)` — оставить.
- Круг «+» — плоская **заливка** акцентом, а не стекло: «идеальный красный, всё было чётко». Стеклянный вариант отвергнут.
- Заливка должна быть **чуть прозрачной** (сейчас `tfRedSolid.opacity(0.86)`).
- Глобальный акцент приложения (`AccentColor.colorset`) — удалён.
- Механизм скрытия круга вместе с панелью — откачен, лучше «как было».
- Тема для проверки — тёмная.
- Не запускать UI/XCUITest ради того, что видно глазами на кадре (правило из памяти; в этой сессии тест применялся только там, где тапнуть иначе было нечем).

---

## 5. Состояние рабочего дерева на момент записи

`Sources/DesignSystem/Navigation/TFPillTabBar.swift`:

- `.tint(Color.tfRed)` — на месте, работает.
- Системная prominent-вкладка `SwiftUI.Tab("Создать", …, role: .prominent)` — на месте, держит место справа.
- `.overlay(alignment: .bottomTrailing) { createButtonOverlay }`; `createButtonOverlay` — рамка `maxWidth/maxHeight, alignment: .bottomTrailing` без гашения.
- `createButton`: `Button` + `.buttonStyle(.plain)` + `.accessibilityIdentifier("tab.create.circle")` + `.frame(62×62)` + `CreateCircleMaterial()` + padding 21/21 + `ignoresSafeArea(.container, edges: .bottom)`.
- `CreateCircleMaterial`: `Circle().fill(Color.tfRedSolid.opacity(0.86))` + `strokeBorder(Color.white.opacity(0.22→0.28), 1)`.
- `TabBarVisibilityObserver` — **откатан** (скриптом, вывод `ok`, остатков в файле нет по grep).
- Временные `UITests/TempCreateCircleSwitchUITests.swift` и `TempCreateCircleTransitionUITests.swift` — команда удаления была прервана, их наличие не перепроверено.
- Сборка после отката наблюдателя **не подтверждена** (последняя подтверждённая — `BUILD SUCCEEDED` с наблюдателем внутри, где круг гас: лог `TFProbe tabbar visible=NO`).

Не сделано: обновление `docs/2026-10-18-tabbar-accent.md` под итог, кадры в `docs/2026-10-18-tabbar-accent/` (там лежат устаревшие `01-system-prominent-white.png` и `02-own-red-glass-circle.png` рядом с новыми `01-selected-tab-accent.png`, `02-final-red-circle.png`), перевод строки `LOCK-TABBAR-ACCENT-20261018` в `REVIEW`, коммит (не сделан; `TFPillTabBar.swift` в git — untracked).

---

## 6. Открытые вопросы

1. **Круг без панели** — не решено. Требование владельца: круг обязан исчезать вместе с панелью. Рабочая гипотеза (не доведена): состояние панели знает только `RootShellView.swift:422` — если владелец разрешит этот файл, флаг передаётся параметром детерминированно, без UIKit-костыля. Альтернатива — `tabViewBottomAccessory`.
2. **Прозрачность 0.86** — значение подобрано на глаз, владелец его не утверждал.
3. **Поведение на других устройствах** — координаты сняты на iPhone Air; 21 pt и 62 pt зашиты константами этой модели.
4. **Задача «чат: окно ввода чёрное в светлой теме»** (`LOCK-CHAT-COMPOSER-LIGHT-20261018`) — не начата.
5. **Тёмная тема в симуляторе выставлена через UserDefaults** — при переустановке приложения сбросится.

---

## 7. Кадры сессии

| Файл | Что на нём |
|---|---|
| `/tmp/tabbar_ok.png` | только `.tint` — красный выбранный ярлык |
| `/tmp/tabbar_appearance.png` | сломанное стекло от `UITabBarAppearance` |
| `/tmp/tabbar_disc2.png` | радужное пятно от диска под панелью |
| `/tmp/tabbar_gp2.png` | `.glassProminent`, круг 68 pt — «раздутый» |
| `/tmp/tabbar_circle.png` | круг 48 pt, первая ровная заливка |
| `/tmp/tabbar_exact.png` | круг 62 pt ровно по геометрии системы |
| `/tmp/tabbar_glass.png`, `/tmp/tabbar_glass_zoom.png` | стеклянный круг с тинтом (отвергнут) |
| `/tmp/tabbar_tint78.png` | тинт с прозрачностью 0.78 (замер `(206,94,83)`) |
| `/tmp/dark_root.png` | первая сборка в тёмной теме — круг уехал в угол (ошибка `GeometryReader`) |
| `/tmp/dark2_bar.png` | тёмная тема, круг на месте, стекло |
| `/tmp/final_bar.png` | тёмная тема, круг заливкой 62 pt на месте — принятая версия |
| `/tmp/settings_probe.png`, `/tmp/settings_corner2.png` | экран без панели: круг висит — баг |
| `/tmp/root_back.png` | регресс: круг погас на экране с панелью |