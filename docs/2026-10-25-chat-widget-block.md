# Чат: виджеты вернулись в ответы ролей (блок `widget` контракта v1)

**Дата:** 25.10.2026. **Автор:** Разработчик (builder). **Scope:** LOCK-CHAT-WIDGET-BLOCK-20261025.

## Симптом

В ответах ролей вместо виджетов владелец видел «**Тип блока «widget» пока не поддерживается**».

## Причина

С переходом ролей на JSON-контракт v1 клиент рисует ответ роли из поля `role_envelope` (`RoleChatsScreen.swift:2222`), а не из текста сообщения. В `ChatStructuredOutputView.blockView` (switch по `block.type`) были ветки `text/heading/list/table/status/progress/chart/diagram/report/handoff/command/link`, а `widget` и `html` отсутствовали — блок попадал в `default` и превращался в заглушку. До JSON-контракта виджет приходил ```widget-фенсом внутри текста и рисовался `ChatWidgetView`, поэтому работал.

Сервер здесь не при чём: `roleContractV1.ts` блок `widget` допускает и сам предписывает его ролям. Правка — только в iOS-клиенте.

## Что сделано (`Sources/Features/Chat/ChatStructuredOutputView.swift`)

1. В модель `StructuredOutputBlock` добавлены поля `widget` (объект виджета, `JSONValue`) и `html` (строка) с разбором по `CodingKeys`.
2. В `blockView` добавлены ветки `case "widget"` и `case "html"`.
3. `widgetBlock` сериализует объект виджета назад в JSON и отдаёт его тому же `ChatWidgetView(json:widgetKey:checklist:)`, что и markdown-путь. Идентификатор доступности — `chat.structured-output.widget`.
4. `htmlBlock` отдаёт содержимое `ChatHTMLView(html:allowsCommands:)`. Идентификатор — `chat.structured-output.html`.
5. Блок `widget` получает номер в сообщении (`widgetKey(in:before:)`) — тем же порядком, каким его считает сервер (`chatChecklist.ts`): блоки `widget` и `chart` (график тоже ложится ```widget-фенсом). Нужен отметкам checklist.

Серверная логика, схема контракта и промпты ролей не менялись.

## Проверка

- `xcrun --sdk iphonesimulator swiftc -parse Sources/Features/Chat/ChatStructuredOutputView.swift` — PARSE_OK.
- `git diff --check` — чисто.
- Сборка, установка на iPhone и живой кадр — за владельцем (сборка iOS-приложения вне зоны роли).

## Ограничения

- Живой рендер виджета в чате не снимался: нужна сборка на iPhone (владелец).
- Блок `html` возвращён тем же приёмом; если владелец считает это лишним сверх вопроса про виджет — откат одной ветки.
- Композитные виджеты (несколько секций в одном блоке) сервер разбивает на под-блоки и нумерует иначе — для checklist-ключей это край; в обычном случае нумерация совпадает.
