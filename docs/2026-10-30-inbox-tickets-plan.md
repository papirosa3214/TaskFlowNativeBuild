# Входящие обращения — Implementation Plan

> Исполнение: текущий агент, последовательно по executing-plans. Дизайн утверждён владельцем 30.10.2026. Повторное согласование этапов не требуется.

**Goal:** отображать только незакрытые обращения к владельцу отдельными нативными тикетами.
**Architecture:** добавить `tickets` к существующему GET /api/attention, сохранив legacy groups для старого клиента. Новая iOS использует tickets; вопросы открывает через RoleQuestionCard и действующий API ответа, остальные обращения — через существующие карточки задач.
**Tech Stack:** TypeScript/Fastify/SQLite и SwiftUI/Foundation/XCTest.
**Spec:** docs/2026-10-30-inbox-tickets-design.md.

## Ограничения

Только сервер .110 и нативный клиент. Не менять веб, чужие правки, общую типографику. Без браузера, симулятора, UI-тестов и установки. Серверные тесты --maxWorkers=4. Никаких изменений прав от открытия тикета.

## Review Focus

Два разных вопроса одной задачи; закрытый/просроченный вопрос; чужой чат; устаревшее предложение плана; старый сервер без tickets. Покрыть тестами соответствующего слоя.

## 1. Проекция сервера

Файлы server/src/lib/ownerInbox.ts (новый), server/src/routes/attention.ts, server/test/ownerInbox.test.ts (новый), AGENT-WORK-SCOPES.md и docs/2026-10-30-owner-inbox.md в серверном worktree.

- [x] Написать и запустить RED тест GET /api/attention: вопрос без blocked виден, после ответа исчезает, два ID сохраняются, не-владелец не получает вопросы, старые предложения/закрытые задачи исключены.
- [x] Реализовать `ownerInbox(userId: string): OwnerInboxTicket[]`, только чтение. Устойчивые ID question/clarification/plan-op/plan/decision; исходные данные и существующие цели перехода.
- [x] GREEN целевого теста и прежних attention тестов; tsc. Commit, push ветки, PR и контроль CI.

## 2. Клиент

Файлы Sources/Core/Models/AttentionFeed.swift, Sources/Features/Attention/AttentionScreen.swift, Tests/AttentionCardContextTests.swift, Tools/test_attention_card_context.py.

- [x] RED: разбор tickets и выбор доступного действия; старый ответ не становится пустым успешным списком; некорректная цель не даёт выполнить действие.
- [x] Добавить необязательный tickets и модель тикета. Перестроить экран на TFCard, переиспользовать RoleQuestionCard для ответа. После ответа/возврата/foreground перезагрузка. Ошибка и неподдерживаемый сервер явно различаются с пустым списком.
- [x] GREEN host XCTest, Swift parse, design guard.

## 3. Подсказка и доставка

Файлы Sources/DesignSystem/Hints/HintScenarios.swift, Tests/AttentionCardContextTests.swift, Tools/test_attention_card_context.py, docs/2026-10-30-inbox-tickets-result.md.

- [x] Добавить inboxTickets с реальным якорем; host тест завершения подсказки.
- [x] Проверить diff, совместимость, новые зависимости и права. Итог с фактическими проверками и ограничениями. Commit только своих файлов и push origin main. Проверить фактическое состояние серверного PR/выкладки; не обещать приёмку на устройстве.

## Фактический итог

Реализация и локальные проверки выполнены. PR39 проходит CI; итог с ограничениями — docs/2026-10-30-inbox-tickets-result.md. Слияние и выкладка контролируются отдельно; чекбоксы выше обозначают выполненные шаги реализации, не приёмку на устройстве.
