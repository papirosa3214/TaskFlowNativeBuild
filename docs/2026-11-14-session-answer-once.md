# Ответ Помощника в новых сессиях — один, из одного набора блоков (14.11.2026)

## Что видел владелец

Скрин `IMG_9652`: в ответе таблица напечатана **дважды**, а абзацы после неё
показаны огрызками «Моя», «По», «Ко».

## Причина дубликата (по коду)

`OwnerSessionReply` (`Sources/Features/Sessions/OwnerSessionScreen.swift:586-599`)
рисовал ответ двумя слоями:

1. `RoleReplyMarkdown(text: SessionFeed.serverDisplayText(entry),
   serverBlocks: SessionFeed.serverTextBlocks(entry))` — готовое серверное
   представление;
2. `ChatStructuredOutputView(json: SessionFeed.serverEnvelopeExtras(entry))` —
   тот же `role_envelope` целиком, из которого `serverEnvelopeExtras` убирал
   только блоки `type == "text"`.

Таблица в конверте — отдельный блок `type: "table"`, поэтому второй слой
печатал её повторно. При этом сервер уже вложил её в первый слой:
`structuredOutputText` (`server/src/sessions/sessionRoleContractV1.ts:443+`)
переводит **все** типы `output` (text, heading, list, table, status, progress,
chart → ```widget, diagram, report, command, link) в markdown, а
`chatBlocksCached` (`server/src/lib/chatBlocks.ts`) разбирает этот текст в
`text_blocks`. Значит в `text_blocks` уже есть текст, таблица, виджет, HTML,
JSON-конверт и команда — второй слой для них не нужен.

## Что сделано (только новые сессии)

`SessionFeed.serverEnvelopeSecondLayer(_:)` (`SessionLiveTurn.swift:565-591`) —
второй слой строится из того, чего в `text_blocks` нет:

- файлы `artifacts` — их `structuredOutputText` не переносит в текст;
- `next_hint` и `needs_human` — подсказка и признак вопроса конверта;
- `output` при готовых блоках становится пустым, `ok` — `true`, `error`
  снимается: тело ответа и карточка ошибки уже в блоках.

Запись без `text_blocks` (сервер до этой правки) отдаётся по-старому через
`serverEnvelopeExtras` — иначе у старых записей пропали бы таблица и виджет.

`OwnerSessionReply` теперь вызывает один метод
(`OwnerSessionScreen.swift:591-596`), оформление и `VStack(spacing:)` не
менялись. Чаты ролей не тронуты: правка только в файлах сессий.

## Обрезание абзацев («Моя», «По», «Ко») — что проверено

Данные записи `ded048c5` сверены **живыми функциями сервера** на .110
(временный стенд вне репозитория, `chatBlocksCached` + `sessionDisplayText`):

- `display_text` — 1774 символа, `text_blocks` — `doc` (chars 276), `table`
  (chars 591), `doc` (chars 812);
- абзацы после таблицы — целые узлы без меток: 353, 264, 79 (ссылка
  `note://…`) и 61 символ;
- сервер ничего не режет.

В осевшем ответе на телефоне нет ни одного места, которое режет текст:
`serverTextBlocks` → `ChatRichContent.segments(fromServer:)` строит блоки
целиком, `RoleReplyMarkdown.documentBody` при отсутствии проявления (`fade`)
печатает блоки полностью. Единственные ножницы — пути живого проявления:

- `ChatRichContent.liveSegments(shown:scope:)` (`ChatRichContent.swift:160-171`)
  → `truncated(_:fraction:)` (`:188-210`) режет блоки по доле символов;
- `RoleReplyMarkdown.documentBody` (`RoleReplyMarkdown.swift:146-152`) при
  `fade` включает `roleReveal` отдельно на каждый блок;
- `SessionLiveTurnBubble` передаёт `fade: pacesText && !reduceMotion ? fade : nil`
  (`SessionLiveTurnView.swift:399-402`), т.е. живой ход проявляется по символам.

Ровно этот же признак — «первые буквы вместо абзаца» — уже был 07.11.2026 на
заголовках («Д / И / Итог»), и он записан в комментарии `documentBody`. Поэтому
наиболее вероятно, что «Моя / По / Ко» — кадр живого проявления, а не осевшая
запись. Данными это не подтверждается и не опровергается: нужен кадр после
конца хода и перезагрузки снимка.

Правку проявления не делал: `ChatRichContent` и `RoleReplyMarkdown` — общие с
чатами ролей, а владелец просил их не менять без его слова.

## Проверки

- RED → GREEN `python3 Tools/test_session_answer_once.py`: до правки
  `FAIL: в SessionLiveTurn.swift нет func serverEnvelopeSecondLayer(` (код 1),
  после — 7/7 проверок зелёные (дубликата нет; `artifacts`, `next_hint`,
  `needs_human` на месте; старый сервер получает конверт; конверт из одного
  текста второго слоя не даёт).
- `xcrun swiftc -parse` правленых файлов; сторож дизайн-системы `--diff HEAD`.
- Сборка Xcode, симулятор, UI-тесты и установка не запускались.

## Что осталось за владельцем

- Посмотреть ответ в приложении: таблица теперь одна.
- Сказать, целы ли абзацы после конца хода (и после перезагрузки снимка). Если
  огрызки видны и в осевшей записи — это отдельная правка проявления в общем
  `RoleReplyMarkdown`, её нужно разрешение: она задевает и чаты ролей.
