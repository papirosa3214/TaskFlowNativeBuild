# Установка на телефон — оптимизированная сборка — 29.10.2026

## Задача

Владелец, 29.10.2026: «скрипт не будет тянуть опять эту какую-то дебаг сборку
неоптимизированную… сборку сделать и установить на телефон и команду дать
запуска скрипта, который ты будешь пользоваться».

## Почему это было важно

`install-iphone.sh` звал `xcodebuild` без `-configuration`, а в схеме TaskFlow
стоит `run: config: Debug` — на телефон с 27.10.2026 уезжала Debug-сборка.
В профиле iPhone (`TaskFlow.cpu_resource-*.ips`, 13 срабатываний за 11 дней)
это и видно: рядом с бинарником лежит `TaskFlow.debug.dylib` — неоптимизированный
Swift.

Разбор JSON от Debug-сборки не меняется (Foundation собран заранее и одинаково),
но SwiftUI и собственная логика в Debug тяжелее в разы — а на телефоне это и
есть основная работа приложения.

## Что сделано

- `install-iphone.sh`: конфигурация сборки — `CONFIG="${CONFIG:-Release}"`,
  путь установки берётся от конфигурации (`$CONFIGURATION-iphoneos`), проверка,
  что сборка вообще получилась. Debug-сборка доступна явно: `CONFIG=Debug
  ./install-iphone.sh`.
- `project.yml`: в конфигурации Release включено условие компиляции
  `TASKFLOW_DEV_ROUTES`.
- `Sources/App/Navigation/RootShellView.swift`: три блока debug-роута
  (`TASKFLOW_DEBUG_ROUTE`) переведены с `#if DEBUG` на
  `#if DEBUG || TASKFLOW_DEV_ROUTES`.

### Почему debug-роут оставлен в Release

Отладочный автопереход на нужный экран (`TASKFLOW_DEBUG_ROUTE=overview`,
`settings`, `task:<id>`) — рабочий инструмент владельца на телефоне, он описан
в `AGENT-CYCLE.md`. Если бы Release его вырезал, владелец потерял бы способ
открыть нужный экран, а Debug-сборку он больше не ставит. Поэтому в Release
собирается только этот роут; отладочные стенды (галерея кадров, превью ленты,
фикстуры экранов) остались строго в Debug — они для агентов, не для телефона.

В Debug-сборку попадает всё то же: `TASKFLOW_DEV_ROUTES` там не нужен, условие
`#if DEBUG` уже истинно.

## Проверки

- Сборка: `xcodebuild -configuration Release -destination id=… -derivedDataPath
  build_device -allowProvisioningUpdates build` — **BUILD SUCCEEDED**, подпись
  «Apple Development: inet2938@mail.ru», профиль
  «iOS Team Provisioning Profile: com.maksim.taskflow.native».
- Установка: `xcrun devicectl device install app` — «App installed», bundle
  `com.maksim.taskflow.native`, версия 1.0 (1).
- Запуск: `devicectl device process launch` — приложение запущено; процесс
  жив (PID 2181), расширение виджетов тоже работает.
- Доказательства, что сборка оптимизированная:
  - в `.app` **нет** `TaskFlow.debug.dylib` (в Debug-сборке он был);
  - swift-код: Debug — 135,8 МБ (`TaskFlow.debug.dylib`), Release — 81,4 МБ
    (главный бинарник), весь `.app` 216 → 159 МБ;
  - сборка идёт с `-O` (конфигурация Release), глобальных символов 26 752
    (у Debug-сборки символы не вырезаны).
- Весь скрипт прогнан целиком: `./install-iphone.sh` — сборка, установка,
  запуск, «✓ Готово».

Симулятор, UI-тесты и кадры не выполнялись (запрет владельца от 25.10.2026).
Внешний вид и скорость — на оценку владельцу: он же смотрит на телефон.

## Связанные работы

- Профили и разбор JSON: `docs/2026-10-29-window-payloads.md`.
- Реестр: `LOCK-INSTALL-RELEASE-20261029`.
