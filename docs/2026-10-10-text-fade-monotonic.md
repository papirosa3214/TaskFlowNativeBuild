# Проявление букв без повторного затемнения

TextRenderer хранит время первого появления каждого глифа в State-модификаторе. Новое слово и изменение темпа очереди больше не меняют возраст старого текста. Добавленные буквы плавно проявляются за прежние 0,7 с; восстановленный снимок/пауза закрепляют уже видимое. Перенос строк сохраняет историю по порядку глифов. Шаблоны HTML не влияют на расчёт прозрачности соседнего текста.

Скорость pacer и немедленный показ HTML/виджетов сохранены. Изменены только renderer и передача fade. История не публикует изменения из draw в SwiftUI; дополнительные сетевые запросы/таймеры не введены.

## Проверка

До исправления детерминированный regression-тест воспроизвёл падение opacity старой буквы с 0,9446 до 0,0391 при поступлении нового слова. UI окна чата с HTML/виджетом открыт через XCUITest. После исправления XcodeBuildMCP: build + 24/24 PASS (23 unit, один UI), iPhone Air iOS 27. Проверены сохранение opacity при новых словах/смене rate, новые глифы с нулевой начальной opacity, пауза/снимок/уменьшение layout, прежние pacing и rich-content регрессии. HTML-кнопка остаётся интерактивной до окончания прозы.

Кадр подтверждает UI, численная монотонность — unit-тестами; субъективное мерцание на физическом iPhone не измерено. Временный UI-тест архивирован в папке отчёта.

До: /Users/max/Library/Developer/XcodeBuildMCP/workspaces/TaskFlowNativeBuild-9a1f0cbd5db2/result-bundles/test_sim_2026-10-10T18-51-00-172Z_pid66019_1762c8c6.xcresult
После: /Users/max/Library/Developer/XcodeBuildMCP/workspaces/TaskFlowNativeBuild-9a1f0cbd5db2/result-bundles/test_sim_2026-10-10T18-52-49-386Z_pid66019_3cfd736e.xcresult
Продукты: /Users/max/Library/Developer/XcodeBuildMCP/workspaces/TaskFlowNativeBuild-9a1f0cbd5db2/test-products/test_sim_2026-10-10T18-52-49-386Z_pid66019_584eb2a1.xctestproducts

На iPhone не установлено; push не выполнен.
