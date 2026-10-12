# PT Sans Narrow в заголовках — 12.10.2026

## Работа

Владелец выбрал из списка вариантов гарнитуру для заголовков разделов «Обзора»
и верхних заголовков экранов: «предпоследний, который шрифт ПТ Санс Нароу».
Oswald заменён на **PT Sans Narrow**.

## Результат

Заголовки разделов «Обзора» и верхние заголовки всех экранов — PT Sans Narrow,
капс, по центру.

## Что сделано

- `Resources/Fonts/PT-Sans-Narrow-Bold.ttf` и `PT-Sans-Narrow-Regular.ttf` вместо
  двух файлов Oswald. Взяты из репозитория Google Fonts
  (`ofl/ptsansnarrow`), начертания статичные.
- `project.yml`: `UIAppFonts` перечисляет оба новых файла (не `Oswald-*`).
- `Sources/DesignSystem/Theme/Typography.swift`: в `.tfSectionDisplay` одно
  семейство `"PT Sans Narrow"`, начертание задаётся весом (`.bold` для крупного
  кегля, `.medium` для мелкого). Комментарий с обоснованием выбора гарнитуры
  переписан, Big Shoulders Display по-прежнему отпадает из-за отсутствия
  кириллицы.
- `Sources/DesignSystem/Components/TFNativeHeader.swift`: заголовок экрана
  переведён с `UINavigationBar.appearance()` на штатный слот
  `ToolbarItem(placement: .principal)`.
- `Sources/App/TaskFlowApp.swift`: вызов `TFNavBarTitleFont.configure()` убран —
  глобальной настройки шапки больше нет.

## Почему заголовок ушёл в `.principal` (важно на будущее)

Первый вариант — правильный по документации — `UINavigationBarAppearance
.titleTextAttributes` через прокси `UINavigationBar.appearance()` — на iOS 27
**не работает и молча**, без ошибки сборки. Проверено последовательно:

1. Чтение атрибутов сразу после записи возвращает пустой словарь — прокси их
   не хранит.
2. Обход живых навбаров (`UIWindow.subviews`, рекурсивно) находит **0**
   `UINavigationBar`: на iOS 27 SwiftUI рисует шапку сам, UIKit-навбара в
   иерархии нет.
3. Проверка «красным» подтвердила то же: заголовок остался серым и с системным
   шрифтом, и с PT Sans Narrow, и с системным шрифтом принудительно.
4. Проверка пустым `navigationTitle("")` показала, что заголовок рисует именно
   SwiftUI — значит атрибуты UIKit-application до него не доходят в принципе.

Отсюда: единственный штатный слот, которым задаётся шрифт, —
`ToolbarItem(placement: .principal)` с обычным `Text`. Слот системный, фон и
блюр прежние; своя шапка не рисуется.

Два побочных грабли того же дня:

- Класть `UIFontDescriptor.SymbolicTraits` прямо в словарь
  `UIFontDescriptor(fontAttributes:)` нельзя: CoreText ждёт там
  `CFDictionary` и падает `NSException «-[__SwiftValue objectForKey:]»` прямо в
  конфигурации — приложение не стартует. Только через `withSymbolicTraits`.
- `UIFont(name:)` ищет по **PostScript name**, а не по семейству: у PT Sans
  Narrow family = «PT Sans Narrow», PostScript = «PTSans-NarrowBold». В коде
  SwiftUI (`Font.custom`) указывается семейство, в UIKit — PostScript.

## Проверки

- Кириллица по таблице `cmap` (fontTools): U+0410 «А», U+044F «я», U+0451 «ё»,
  «—» и «№» — все на месте в обоих начертаниях.
- `BUILD SUCCEEDED` (iPhone Air, iOS 27).
- Оба файла шрифта в бандле приложения и в `UIAppFonts` собранного `Info.plist`
  (`plutil -p`).
- Кадры симулятора после установки: «Обзор», «Чаты», «Проекты» — на всех
  заголовок PT Sans Narrow капсом по центру, кнопка «назад» и меню на местах.

## Ограничения

- Верхние заголовки теперь рисуются слотом `.principal`. Экраны, у которых
  свой заголовок в этом слоте, не должны вызывать `tfNativeHeader`
  одновременно — иначе будет дубль. Проверено на экране открытого чата: он
  свой заголовок с составом участников рисует сам и `tfNativeHeader` не зовёт.
- Крупный заголовок (`.large`) с этой гарнитурой недостижим: iOS рисует его
  своим шрифтом. Слот `.principal` всегда компактный.

## Материалы

- `docs/2026-10-12-font-pt-sans-narrow.md`
- Кадры: `/tmp/tfshot/ptsn7-overview.png`, `ptsn7-chat.png`, `ptsn7-projects.png`
- Диагностические кадры (почему appearance не работает): `/tmp/tfshot/diag-red.png`,
  `diag-red-sysfont.png`, `diag4.png`