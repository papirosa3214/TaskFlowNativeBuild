# Отмена обновления проектов

## Результат
Отменённая загрузка больше не показывает красную ошибку Swift.CancellationError. Уже загруженные проекты остаются на экране.

## Что сделано
ProjectStore отдельно обрабатывает отмену обычной и архивной загрузки. Реальные ошибки продолжают отображаться. Проверочная кнопка доступна только в DEBUG при TASKFLOW_PROJECT_CANCELLATION_TEST=1 и отсутствует при обычном запуске.

## Проверки
До исправления регрессия упала с точным текстом со скриншота. После исправления: 3/3 проверки на симуляторе iPhone Air iOS 27.0 и 3/3 на физическом iPhone Air iOS 27.0.1. Проверены отмена без ошибки с сохранением данных, настоящая ошибка сервера и экран проектов через XCUITest. UI-тест отменяет настоящий запрос через ProjectStore/APIClient. После проверки обычный запуск на iPhone успешен, PID 20986.

## Ограничения
Причина отмены в исходном эпизоде не установлена. Исправлена реакция приложения на штатную отмену. Производительность не менялась и не измерялась.

## Материалы
Доказательства: docs/2026-10-11-project-cancellation/{before,after,device}.xcresult и кадры в simulator/ и device/. Временный UI-тест сохранён рядом с доказательствами и удалён из UITests; постоянная регрессия — Tests/ProjectCancellationTests.swift. Проверки: xcodebuildmcp simulator test и device test, only-testing TaskFlowTests/ProjectCancellationTests и TaskFlowUITests/ProjectCancellationUITests. Продукты и исходные логи — в Library/Developer/XcodeBuildMCP/workspaces/TaskFlowNativeBuild-6630a891c838.
