# Удаление мёртвых экранов iOS-клиента

Дата: 27.10.2026. Карточка: `f6637ef6-1a1c-447e-828b-6ecfe31ff42c`, шаг `builder_delete_dead_screens`.

## Что было

Аудит мёртвых экранов (25.10.2026) и повторная проверка QA нашли три экрана,
которые лежат в коде, но в приложение не попадают: ни одна вкладка, пункт
меню, переход или отладочный маршрут их не открывает.

- «Работа агента» (`AgentWorkScreen.swift`, 235 строк) — маршрут `.agentWork`
  открывали только плитки мёртвой `AgentStatusGrid.swift:7-10`.
- «Лента» (`TimelineScreen.swift`, 178 строк) — маршрут `.timeline` не
  открывается нигде; экран создаётся только в `RouteDestinationView.swift:48-49`.
- «Поиск» (`SearchScreen.swift`, 202 строк) — маршрут `.search` не открывается
  нигде; экран создаётся только в `RouteDestinationView.swift:86-87`.

## Что сделано

Один коммит. По правилу контракта «одна строка на экран» правка идёт целиком:
case в `AppRoute` + ветка в `RouteDestinationView` + строка в таблице «Имена
корневых вью» (`spec/INTEGRATION.md`). Заглушек в проекте нет — их и не
заводили.

Удалено:

- маршруты `.agentWork`, `.timeline`, `.search` (`Sources/App/Navigation/AppRoute.swift`);
- ветки `.agentWork`, `.timeline`, `.search` в фабрике маршрутов
  (`Sources/App/Navigation/RouteDestinationView.swift`);
- файлы `Sources/Features/Chat/AgentWorkScreen.swift`,
  `Sources/Features/Directory/AgentStatusGrid.swift`,
  `Sources/Features/Directory/SearchScreen.swift`,
  `Sources/Features/Today/TimelineScreen.swift`;
- `Sources/Features/Today/TimelineLayers.swift` — три слоя «Ленты дня»
  (216 строк), которые создавались только из удаляемого экрана;
- три строки таблицы «Имена корневых вью» в `spec/INTEGRATION.md` (`/timeline`,
  `/search`, `/agent-work`) и примечание, что нативного аналога этих маршрутов
  нет.

Перенесено: `ProjectStatusIcon` жил в удаляемом `AgentStatusGrid.swift`, но им
рисует живая карточка проекта (`Support/ProjectCard.swift:132-136`). Значок
переехал в новый файл `Sources/Features/Directory/Support/ProjectStatusIcon.swift`
без изменения вида.

## Проверки

- Поиск по всему `Sources`: после правки не осталось ни одного обращения к
  `.agentWork`, `.timeline`, `.search`, `AgentWorkScreen`, `TimelineScreen`,
  `SearchScreen`, `AgentStatusGrid`, `TimelineLayers`. Внешних входов (deep link,
  отладочный маршрут, пуш с сервера) у этих экранов не было и раньше.
- Сторож дизайн-системы — чисто.
- Сторож заголовков экранов — чисто.
- Сборка generic iOS — BUILD SUCCEEDED (см. раздел «Ограничения»).
- Сборка и запуск в симуляторе, UI-тесты и кадры не выполнялись: по прямому
  указанию владельца от 25.10.2026 симулятор агентам не трогать.

## Ограничения

- Изменение не перенесено в `main`: перенос за Аналитиком (ответственный за
  интеграцию) после положительного ревью.
- Симулятор и живой iPhone не проверялись — по указанию владельца от
  25.10.2026. Проверка после удаления — отдельный шаг Лайф-тестировщика.
- `AgentWorkTaskRow.swift` (223 строки) остался в коде: он мёртвый и по
  аудиту, но в этот шаг не входил (владельцем поручено удаление четырёх
  экранов и трёх маршрутов). Строка `AgentWorkTaskRow` осталась живой в
  `docs/2026-10-22-task-date-first.md` как пример.
- Веб-клиент не трогался: он заморожен, `/search`, `/timeline`, `/agent-work`
  в вебе остались как были.

## Материалы

- Коммит: один, в ветке `roles/f6637ef6-1a1c-447e-828b-6ecfe31ff42c`.
- Реестр границ: строка `LOCK-DEAD-SCREENS-DELETE-20261027` в
  `AGENT-WORK-SCOPES.md`.
- Отчёт QA с находками: заметка `f4562462-14a8-4817-ab99-071d819e8c0d`.
