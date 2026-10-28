# Исправление device-сборки «Входящих»

29.10.2026 владелец сообщил о падении сборки с установкой на iPhone после синхронизации main.

## Причина

Из существующего `build_device/Logs/Build/07E73521-E11C-4256-8F39-70F1779CC158.xcactivitylog` извлечена диагностика:

`AttentionScreen.swift:140:37: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions`.

Строка «Идёт сейчас» выделена из большого SwiftUI body в `runningRow`, тип назначения явно указан как AppRoute. После этого device-компилятор показал точную ошибку: `AttentionScreen.swift:171:17: type 'AppRoute' has no member 'agentWork'` (лог `/tmp/taskflow-attention-device-build.log`, BUILD FAILED).

Вызов `.agentWork(focus: nil)` пришёл из коммитов переходов «Входящих» 6dd2ccb7/64496628. Это не ошибка tfText/tfoText при merge: tfText существует, а .agentWork в AppRoute отсутствует. При отсутствии task_id строка теперь использует существующий маршрут `.roleLoad` → RoleLoadScreen (экран занятости ролей). При наличии task_id по-прежнему открывается соответствующая задача. Разметка строки сохранена.

## Проверка

Исправлена компиляторная несовместимость маршрута, новая логика обработки данных не добавлялась; unit-тест не создавался. Ошибка подтверждена компилятором до исправления.

Команда device-сборки без подписи и установки:

```sh
xcodebuild -project TaskFlow.xcodeproj -scheme TaskFlow \
  -destination 'generic/platform=iOS' -derivedDataPath build_device \
  CODE_SIGNING_ALLOWED=NO build
```

Результат: **BUILD SUCCEEDED**, полный лог `/tmp/taskflow-attention-device-build-green.log`.

`python3 Tools/design-system-guard.py --diff HEAD` — чисто; `git diff --check` — успешно.

Симулятор, UI-тесты и установка не выполнялись. Подпись, установка на телефон и визуальная приёмка этой сборкой не проверены. Сторонние untracked файлы сохранены.
