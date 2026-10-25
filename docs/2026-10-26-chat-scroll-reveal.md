# Чат с ролью: скролл и проявление текста

Дата: 26.10.2026
Lock: `LOCK-CHAT-SCROLL-REVEAL-20261026`
Исполнитель: Antigravity

## Жалоба владельца

Три проблемы в чате с ролями:
1. При отправке сообщения экран «улетает» — скролл прыгает к дну до появления пузыря
2. Текст ответа роли (JSON-конверт) появляется весь разом, без «печатания»
3. Лента дёргается при росте контента

## Причины

### 1. Скролл при отправке
В `send()` вызывался `chatScrollPosition.scrollTo(edge: .bottom)` **до** `pendingOutgoing.append(pending)`.
SwiftUI получал команду скроллить к `.bottom` до того, как новая строка появлялась в ленте.
После появления строки лента перестраивалась — получался двойной прыжок.

### 2. Текст JSON-конверта без проявления
В `roleMessageContent()` ветка с `ChatStructuredOutputView` (JSON-конверт, формат `role_envelope`)
**не** оборачивалась в `.roleMessageReveal(...)`. Механизм проявления был подключён только к
простым markdown-ответам, а все ответы через JSON-конверт (основной формат с октября 2026)
появлялись целиком.

### 3. Дёрганье скролла
`.defaultScrollAnchor(.bottom, for: .sizeChanges)` включалась всегда, когда пользователь
не прокрутил вручную (`!isPositionedByUser`). Но `isPositionedByUser` сбрасывается при любом
программном `scrollTo`, то есть после каждого нового сообщения привязка к `.bottom` для
`sizeChanges` включалась заново. При проявлении текста (рост размера кадр за кадром) лента
постоянно тащилась к `.bottom`, вызывая дёрганье.

## Правки

### `Sources/Features/Chat/RoleChatsScreen.swift`

1. **`send()` (строка ~2545)**: `scrollTo(edge: .bottom)` перенесён **после** `pendingOutgoing.append(pending)`.
   Добавлена задержка `Task.sleep(for: .milliseconds(50))`, чтобы SwiftUI успел вставить строку
   в LazyVStack, и скролл точно попал на пузырь «в пути».

2. **`roleMessageContent()` (строка ~2232)**: `ChatStructuredOutputView` обёрнут в
   `.roleMessageReveal(text: message.text, messageID: message.id, animate: ...)` с тем же
   условием анимации, что и у plain-markdown ветки: `chatIsNearBottom && message.id == messages.last?.id`.

3. **`messageScroll` (строка ~1580)**: условие `defaultScrollAnchor` для `.sizeChanges` дополнено
   проверкой `!chatIsNearBottom`:
   ```swift
   .defaultScrollAnchor(chatScrollPosition.isPositionedByUser || !chatIsNearBottom ? nil : .bottom, for: .sizeChanges)
   ```
   Теперь автоматическая привязка к `.bottom` при изменении размера включается **только** когда
   пользователь находится у дна ленты. Если пользователь прокрутил вверх, рост контента не
   тащит ленту вниз.

## Проверки

- Сторож дизайн-системы: чисто
- Правка декоративная (отступы скролла, анимация): unit-тесты не требуются
- Визуальная приёмка — за владельцем
