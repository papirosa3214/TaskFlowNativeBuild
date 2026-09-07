# Нативный клиент TaskFlow (iOS, SwiftUI)

> **Эта копия на `.110` нерабочая.** Не вносить здесь изменения, не запускать
> `sync-build.sh` и не собирать приложение. Единственный native-исходник на
> MacBook: `/Users/max/Проекты/TaskFlowNativeBuild`.

Работать с native-клиентом можно только в канонической папке MacBook:

```bash
cd "$HOME/Проекты/TaskFlowNativeBuild"
./scripts/build.sh sim | device
```
- **Ассеты обязаны быть в `sources` в `project.yml`** — ключа `resources`
  у таргета в xcodegen нет. Каталог, положенный не туда, молча не попадает
  в бандл (так пропадал `Assets.car` и вместе с ним альтернативные значки).
- **Шапки экранов** — общий компонент `Sources/DesignSystem/Components/TFScreenHeader.swift`
  (48pt, заголовок `.title` по центру, `FrostedGlass(axis: .top)`). Экраны,
  рисующие шапку сами, обязаны совпадать с ним по геометрии — иначе владелец
  сразу видит разнобой.
- **Свой навбар:** экран со своей шапкой обязан скрывать системный —
  `.toolbar(.hidden, for: .navigationBar)`, иначе поверх нашей стрелки
  рисуется вторая, системная.
- **Экран логина в симуляторе — не преграда.** В отладочной сборке есть штатный
  вход по токену: переменная окружения `TASKFLOW_DEBUG_TOKEN` кладётся прямо в
  Keychain при старте (`SessionStore.bootstrap()`, блок `#if DEBUG`). Токен —
  ключ `TASKFLOW_AGENT_TOKEN` в vault на .110, доставать так:
  `python3 ~/.claude/vault-run.py --secret TASKFLOW_AGENT_TOKEN` (значение в чат
  не печатать, передавать каналом в ssh). В UI-тесте:
  `app.launchEnvironment["TASKFLOW_DEBUG_TOKEN"] = <токен>`.
  Рядом работает `TASKFLOW_DEBUG_ROUTE` — открыть нужный экран сразу при старте
  (`overview`, `settings`, `notes`, `projects`, `notifications`, `chat`, `today`,
  `upcoming`, `noteeditor:<id>`, `task:<id>`, `expand`, `quickadd`).
  Проверено 02.09.2026: приложение снесено с симулятора и запущено с токеном —
  «Обзор» открылся с данными, экрана входа не было.
- **Проверка правок интерфейса — кадром симулятора**, а не на глаз: временный
  XCUITest со `XCTAttachment(screenshot:)`, потом `xcrun xcresulttool export
  attachments` и замер пикселей. Временный тест удалять после сверки.
- **Жест/UI-баг не поддаётся со второй попытки на глаз — сразу `NSLog` в
  подозрительное место**, не гонять третью-пятую попытку вслепую по
  скриншотам/синтетическим свайпам. `print()` не долетает ни до `simctl
  launch --stdout`, ни до `log show` — только `NSLog`. Читать так:
  `xcrun simctl spawn <device-udid> log show --last Nm --predicate 'process == "TaskFlow"' --style compact`.
  Пример 07.09.2026: `UpcomingHoursView.swift` — драг не давал заблокировать
  скролл; один `NSLog` в `handleUIGestureRecognizerAction` показал, что
  `recognizer.view` у `UIGestureRecognizerRepresentable` — это хостинг-view
  ВСЕГО экрана, а не вьюха карточки, и настоящий `UIScrollView` от SwiftUI
  `ScrollView` — его ПОТОМОК, а не предок, поэтому поиск вверх по
  `.superview` всегда возвращал `nil`. Без лога это гадание заняло бы ещё
  десяток кругов.
- **Несколько booted-симуляторов сразу — указывать `device`/UDID явно.**
  `launch` без явного устройства молча берёт первый booted, который может
  быть не тем, за которым наблюдает владелец — путаница «я ничего не менял,
  а фикс не появился» именно отсюда.
