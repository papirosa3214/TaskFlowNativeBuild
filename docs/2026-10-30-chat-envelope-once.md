# Ответ роли в чате показывается один раз (30.10.2026)

## Проблема

Владелец 30.10.2026: в чате на iOS ответ роли приходит дважды — сначала
«не до конца собранный» плоский markdown (таблица markdown, виджет сырым
```widget json```), затем тот же ответ собранными нативными блоками.

## Причина

В базе на каждый ответ роли ровно одно сообщение — дубль рисует клиент.

1. Сервер кладёт в `message.text` markdown-версию конверта
   (`server/src/lib/roleContractV1.ts:410 structuredOutputText`): таблица
   превращается в markdown, виджет — в сырой JSON в блоке ```widget.
2. Живой ход отдаёт ту же плоскую версию
   (`server/src/runtime/chatLiveTurn.ts:645 unwrapRoleEnvelope`).
3. iOS в `RoleChatLiveTurn.completed(with:)` дописывает этот текст в
   доигрывающий пузырь, а строка готового сообщения рисует пункты хода
   (`closedTurnItems`) рядом с `role_envelope` — который `ChatStructuredOutputView`
   показывает нативными блоками.

Итог: одна и та же информация в двух видах. Подробный разбор — в памяти
команды и в заметке `note://88300ffe-0bcc-4fbd-bd8c-6e15aae0b447`.

## Правка

Убираем не конверт, а его плоскую копию: нативные блоки рисуются один раз,
текст ответа в пунктах хода больше не дублирует их.

### `Sources/Core/Models/RoleChat.swift`

- `RoleChatMessage.hasStructuredAnswer` — признак ответа-конверта
  (`roleEnvelopeJSON != nil`). Одинаково для structured v1 и legacy `role.v1`,
  где финал тоже рисуется `ChatStructuredOutputView`.
- `RoleChatLiveTurn.withoutAnswerText(_:of:)` — общий фильтр: из пунктов
  убирается текст, который уже показывает ответ; реплики хода, которых в
  ответе нет («сейчас проверю…»), остаются. Обычный ответ без конверта
  фильтр не трогает.
- `RoleChatLiveTurn.itemsWithoutAnswerText(for:)` и
  `RoleChatSteps.itemsWithoutAnswerText(of:)` — доступ к тому же фильтру.
- `completed(with:)`: у ответа-конверта плоская копия не дописывается в
  пузырь (`finalText` пуст), пункты хода фильтруются.

### `Sources/Features/Roles/RoleChatsScreen.swift`

- `closedTurnItems[message.id]` и печать шагов идут через фильтр
  (`itemsWithoutAnswerText(for:)` / `itemsWithoutAnswerText(of:)`), а не
  напрямую — иначе плоская копия вернулась бы в строку сообщения.

Файл экрана во время правки переехал другим агентом из `Sources/Features/Chat/`
в `Sources/Features/Roles/` — учтено в реестре (`AGENT-WORK-SCOPES.md`).

## Проверки

| Проверка | Результат |
| --- | --- |
| `Tools/test_chat_envelope_answer_once.py` (новый, хост, swiftc) | RED → GREEN: сначала падал на «в закрытом ходе остался текст ответа», после правки PASS |
| `Tools/test_chat_completion_text.py` (регресс, фикстура под новый контракт) | PASS |
| `swiftc -parse` по `RoleChat.swift` и `RoleChatsScreen.swift` | PASS |
| `Tools/design-system-guard.py --diff HEAD` | чисто |

Симулятор, сборка приложения и UI-тесты не выполнялись (запрет владельца
25.10.2026). Живой прогон на iPhone и вид ответа оценивает владелец.

## Чего не делали

- Сервер не трогали: `message.text` остаётся плоским резервом для старых
  клиентов и для поиска по переписке.
- Обычные ответы без конверта ведут себя как раньше: текст остаётся один раз.
