# MAK-124 — нативное закрытие карточки задачи

10.10.2026. Изменено только поведение окна карточки задачи. Список задач, семейные вкладки, их переходы и мягкая верхняя граница сохранены.

## Итог

В `TaskFormScreen.swift` удалён `.refreshable { await viewModel.refresh() }`: обновление потягиванием вниз конкурировало с жестом системного окна. В `ProjectTasksScreen.swift` к существующим `.medium/.large` добавлен `.presentationContentInteraction(.resizes)`. Собственных жестов закрытия и ограничений прокрутки нет. Временная диагностика удалена.

## Проверка

XCUITest на iPhone Air / iOS 27: открыть проект → карточку → развернуть → прокрутить до графа → открыть роль → закрыть роль жестом → закрыть карточку жестами по содержимому. Без крестика. Проверка `XCTAssertFalse(handle.exists)` прошла, кадр `no-refresh/D9213B62-38B8-44B3-998E-BC87D8308ADE.png` показывает возврат к списку.

Лог: `ROLE_AFTER visible=false`, `TASK_BEFORE handle=(160.0, 64.0, 100.0, 24.0)`, `TASK_AFTER exists=false`. Результат `/tmp/task-sheet-no-refresh-20261010.xcresult`, 1 тест прошёл. Копия временного теста сохранена как `.swift.txt`, из тестового target удалена.

Предыдущие варианты со scrollDisabled не решали проблему на телефоне и отменены. Предыдущие проверки без утверждения закрытия не подтверждали исправление. Переходы между семейными вкладками в этом тесте не проверялись; их код не менялся.

## Точный откат

Вернуть одну строку `.refreshable { await viewModel.refresh() }` после `.hideComposerScrollEdgeEffect()` в `TaskFormScreen.swift`. Удалить одну строку `.presentationContentInteraction(.resizes)` в sheet карточки `ProjectTasksScreen.swift`. Не восстанавливать целиком файлы: в них есть независимые изменения других работ.

## Телефон

`./install-iphone.sh`: BUILD SUCCEEDED, App installed. Исправленная версия запущена на физическом iPhone Air через devicectl. Жесты подтверждены на симуляторе; физическое взаимодействие владельца после установки пока не проверено. Лог установки: `/tmp/taskflow-install-no-refresh-20261010.log`.
