---
name: taskflow-sim-run
description: Запуск и проверка TaskFlow iOS в симуляторе, когда владелец прямо поручил посмотреть в симуляторе («заряжай симулятор», «проверь в симуляторе», «запусти»). Только iPhone Air на iOS 27.0 — Xcode сам сбрасывает назначение на iPhone 18 Pro, и проверка молча идёт по старой сборке.
---

# Запуск TaskFlow в симуляторе: только iPhone Air (27.0)

Владелец 12.11.2026: «ты опять запускаешь не тот симулятор». Xcode после
`xcodegen` и иногда сам по себе переключает назначение на iPhone 18 Pro. Тогда
`RunProject` ставит свежую сборку туда, а кадры с iPhone Air показывают старую,
и правка «не появляется».

Симулятор трогать только по прямому поручению владельца (CLAUDE.md проекта).

## Константы

| Что | Значение |
|---|---|
| Назначение в Xcode | `iPhone Air (27.0)` |
| UDID | `9FF78D89-EE84-4914-AA56-D0A72D1AF43A` |
| Бандл | `com.maksim.taskflow.native` |
| Workspace | `XcodeListWorkspaces` → путь `TaskFlow.xcodeproj` |

## Порядок — каждый раз

1. `mcp__xcode__XcodeListRunDestinations`: если `activeDestinationDisplayTitle`
   не `iPhone Air (27.0)` — `mcp__xcode__XcodeSwitchRunDestination` на него.
   После каждого `xcodegen generate` — обязательно.
2. `mcp__xcode__RunProject` с `workspaceIdentifier`.
3. Хук `.claude/hooks/check_sim_target.py` после RunProject сам сверяет, на
   какой загруженный симулятор легла свежая сборка. Пришло предупреждение
   «Сборка ушла на …» — шаг 1 и RunProject заново; кадрам до этого не верить.
4. Смотреть и управлять — device-инструментами T3 (`device_open` с этим UDID,
   команда `agent-device`, `device_screenshot`). Не `xcrun simctl` для тапов.
5. Чужие симуляторы (iPhone 18 Pro и др.) не выключать и не загружать без
   слова владельца — только сказать, что они загружены.

## Установка на iPhone владельца — только скриптом

Когда владелец просит «поставь на телефон»: `cd ~/Проекты/TaskFlowNativeBuild && ./install-iphone.sh`.
Не запускать `mcp__xcode__RunProject` на устройство «iPhone Air (Максим)» — это
вторая, Debug-сборка рядом с Release скрипта, Мак греется вдвое (владелец
12.11.2026: «с нуля очень сильно грузятся, Мак кипяток»). Скрипт собирает в
постоянную `build_device` и перегенерирует проект только при изменении
`project.yml` (`xcodegen --use-cache`). После установки вернуть назначение
Xcode на `iPhone Air (27.0)`.

## Прокрутка в agent-device

Быстрый `scroll up <доля>` иногда не доходит до приложения (журнал 12.11.2026:
смещение не менялось). Тянуть медленно: `scroll up --pixels 300 --duration-ms 600`.
Не уверен, что жест дошёл, — `NSLog` в обработчик и `log show` по процессу
`TaskFlow`, а не третья попытка на глаз.
