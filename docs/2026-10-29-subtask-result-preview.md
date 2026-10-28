# Ответ подзадачи в карточке

Поручение владельца от 29.10.2026: экономить место, читать полный ответ у самой подзадачи.

- Под подзадачей — исходный ответ в две строки с системным усечением хвоста (`lineLimit(2)`, `truncationMode(.tail)`). Короткий ответ не получает искусственное троеточие. Markdown внутри строки обрабатывается системным AttributedString.
- Нажатие использует прежний `OutcomeTextRow` и его `.sheet`: снизу открывается тот же `OutcomeTextSheet`, с прежними detents medium/large и кнопкой «Готово». В окно передаются полный `displayResult` и серверные блоки; короткий ответ не генерируется и не сохраняется.
- Из отображения «Итога» убраны `outcome.nodes`: проверено чтением server/src/lib/taskOutcome.ts на .110, все эти строки получены из subtasks, в том числе при наличии collaboration plan. Сервер и сохранённые данные не менялись.
- Вердикт, документы (включая самостоятельный итог), ветка, автослияние и кодовые изменения сохранены. Если есть только ответы шагов, пустая секция не появляется.
- `RoleReplyMarkdown.readableText` не менялся. Это корректировка существующего просмотра ответа, новый сценарий подсказок не добавлялся.

## Проверки

Целевые `TaskOutcomeTests` выполнены через временный Swift Package на macOS, без симулятора: скопированы реальные исходники TaskOutcome, ChatServerBlock, AgentComponent, JSONValue, DateFormats, CalendarDateMath, AgentTextSanitizer и сам XCTest-файл. Подмен и стабов нет. Package: target TaskFlow + test target TaskFlowTests, swift-tools-version 6.0, swiftLanguageModes [.v5]. Команда: `swift test --package-path /tmp/taskflow-outcome-tests`.

RED на старом коде: 4 теста, ровно одно ожидаемое падение `testSubtaskResultsAloneDoNotShowOutcomeSection` (XCTAssertTrue). GREEN после правки: 4 теста, 0 падений. Дополнительно проверены вердикт, документ и ветка по отдельности, исходный полный результат сохранён.

`python3 Tools/design-system-guard.py --diff HEAD` — чисто. `swiftc -frontend -parse` двух изменённых UI-файлов и `git diff --check` — успешно. Это синтаксическая проверка, не полная сборка iOS.

Симулятор, UI-тесты, установка на iPhone и визуальная приёмка не выполнялись. Push не выполнялся. Изменения предназначены для локального main; внешний вид оценивает владелец.
