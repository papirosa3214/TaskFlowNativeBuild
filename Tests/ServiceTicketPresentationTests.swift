import XCTest
@testable import TaskFlow

/// Сводки сервера для карточек «Уведомлений»: понятное название и счётчики
/// «штатно / ошибок / предупреждений» без имён скриптов.
final class ServiceTicketPresentationTests: XCTestCase {
    // Живой ответ GET /notifications/digest с .110 (27.09.2026), списки урезаны.
    private let digestJSON = """
    {"date":"2026-09-27","count":2,"items":[{"id":"digest/2026-09-27","path":"digest:2026-09-27","title":"Сводка работы сервера","ts":"2026-09-27T09:00:06","source":"server-digest","level":"error","has_triage":true,"snippet":"2 ошибок · 2 предупреждений","links":["tf://task/bfb195ab-4653-4c6c-9d22-e8d1e8357ffd"],"revision":"f8ef841de6683c2cba3af387","checks":[{"name":"Обработка памяти помощников","area":"Сервер","status":"ok","message":"4 прогонов","source":"autonomy-110","ts":"2026-09-27T09:00:06","diagnostic_task_ids":["bfb195ab-4653-4c6c-9d22-e8d1e8357ffd"]}],"ok_count":12,"error_count":2,"warning_count":2},{"id":"critical/2026-09-27/bcdb01db0a63","path":"critical:2026-09-27:bcdb01db0a63","title":"Доставка уведомлений — требуется внимание","ts":"2026-09-27T09:00:06","source":"server-digest","level":"error","has_triage":true,"snippet":"1 ошибок","links":[],"revision":"a3cc5be5a3d98555bc2d2ef0","checks":[{"name":"Доставка уведомлений","area":"Доставка уведомлений","status":"error","message":"у отправителей НЕ УШЛО 17","source":"autonomy-110","ts":"2026-09-27T09:00:06","diagnostic_task_ids":[]}],"ok_count":0,"error_count":1,"warning_count":0}]}
    """

    func test_decodesDigestWithCountsAndChecks() throws {
        let resp = try JSONDecoder().decode(ServiceTicketInboxResponse.self, from: Data(digestJSON.utf8))
        XCTAssertEqual(resp.items.count, 2)
        let digest = resp.items[0]
        XCTAssertEqual(digest.path, "digest:2026-09-27")
        XCTAssertEqual(digest.revision, "f8ef841de6683c2cba3af387")
        XCTAssertEqual(digest.okCount, 12)
        XCTAssertEqual(digest.errorCount, 2)
        XCTAssertEqual(digest.warningCount, 2)
        XCTAssertEqual(digest.checks?.first?.name, "Обработка памяти помощников")
    }

    func test_serverCountsWinOverTruncatedChecks() throws {
        let resp = try JSONDecoder().decode(ServiceTicketInboxResponse.self, from: Data(digestJSON.utf8))
        let p = ServiceTicketPresentation(summary: resp.items[0])
        XCTAssertEqual(p.title, "Сводка работы сервера")
        XCTAssertEqual(p.okCount, 12)
        XCTAssertEqual(p.errorCount, 2)
        XCTAssertEqual(p.warningCount, 2)
    }

    func test_criticalPreviewNamesTheProblem() throws {
        let resp = try JSONDecoder().decode(ServiceTicketInboxResponse.self, from: Data(digestJSON.utf8))
        let p = ServiceTicketPresentation(summary: resp.items[1])
        XCTAssertEqual(p.errorCount, 1)
        XCTAssertEqual(p.preview, "Доставка уведомлений")
    }

    /// Старый формат inbox без счётчиков: считаем по уровню, название — человеческое.
    func test_legacyInboxItemWithoutCounts() throws {
        let json = """
        {"id":"inbox/2026-09-27/015133-autonomy-110","path":"/x.md","title":"Автономность .110 — сводка за сутки","ts":"2026-09-27T01:51:33","source":"autonomy-110","level":"error","has_triage":true,"snippet":"","links":[]}
        """
        let summary = try JSONDecoder().decode(ServiceTicketSummary.self, from: Data(json.utf8))
        let p = ServiceTicketPresentation(summary: summary)
        XCTAssertEqual(p.title, "Работа серверных механизмов")
        XCTAssertEqual(p.okCount, 0)
        XCTAssertEqual(p.errorCount, 1)
        XCTAssertEqual(p.warningCount, 0)
        XCTAssertEqual(p.preview, "Состояние сервиса и результаты проверки")
    }

    func test_previewListsTwoProblemsAndTheRest() {
        let checks = ["А", "Б", "В", "Г"].map {
            ServiceTicketCheck(name: $0, area: "Сервер", status: "error", message: "")
        }
        var summary = ServiceTicketSummary(
            id: "d", path: "digest:d", title: "Сводка", ts: "2026-09-27T09:00:06",
            source: "server-digest", level: "error", hasTriage: false, snippet: "", links: []
        )
        summary.checks = checks + [ServiceTicketCheck(name: "Д", area: "Сервер", status: "ok", message: "")]
        let p = ServiceTicketPresentation(summary: summary)
        XCTAssertEqual(p.preview, "А · Б · ещё 2")
        XCTAssertEqual(p.okCount, 1)
        XCTAssertEqual(p.errorCount, 4)
    }

    // MARK: - Язык строки (владелец 16.10.2026: «кривые сыры от мониторингов»)

    /// Живая проверка за 16.10.2026, текст дословно из GET /notifications/digest.
    private func liveDeliveryCheck() -> ServiceTicketCheck {
        ServiceTicketCheck(
            name: "Доставка уведомлений",
            area: "Доставляет уведомления тебе на телефон и в Telegram",
            status: "error",
            message: "11 уведомлений не дошли до тебя (xray-target-guard: 3, База знаний: 3, "
                + "Контроль процессов: 2, Работа серверных механизмов: 1, obsidian-journal-watch: 1, "
                + "infra-vpn-watch: 1). Нужно проверить, почему не работает доставка"
        )
    }

    /// Правка 1: сырые имена сторожей заменяются, числа и человеческие имена
    /// остаются как пришли.
    func test_humanizesEveryRawEmitterName() {
        let text = ServiceTicketPresentation.readable(liveDeliveryCheck())
        XCTAssertFalse(text.contains("xray-target-guard"))
        XCTAssertFalse(text.contains("obsidian-journal-watch"))
        XCTAssertFalse(text.contains("infra-vpn-watch"))
        XCTAssertTrue(text.contains("Сторож VPN: 3"))
        XCTAssertTrue(text.contains("Сборка журнала: 1"))
        XCTAssertTrue(text.contains("Сторож инфраструктуры: 1"))
        // Человеческие имена сервера не трогаем.
        XCTAssertTrue(text.contains("База знаний: 3"))
        XCTAssertTrue(text.contains("Контроль процессов: 2"))
        XCTAssertTrue(text.contains("11 уведомлений"))
    }

    /// Таблица заполнена только реально встречающимися именами: ни одно из
    /// 12 не выдумано (проверено по digest за 12–16.10).
    func test_emitterTableCoversAllKnownRawNames() {
        XCTAssertEqual(ServiceTicketPresentation.emitterNames.count, 12)
        for key in ServiceTicketPresentation.emitterNames.keys {
            XCTAssertFalse(key.isEmpty)
        }
    }

    /// Неизвестное имя НЕ прячется и не выдумывается — остаётся как пришло.
    func test_unknownEmitterStaysVisible() {
        let check = ServiceTicketCheck(name: "X", area: "Y", status: "error",
                                       message: "Сбой от unknown-guard-9000: 1")
        XCTAssertEqual(ServiceTicketPresentation.readable(check),
                       "Сбой от unknown-guard-9000: 1")
    }

    /// Правка 2: `area: "Сервер"` — заглушка, подпись не рисуется.
    func test_placeholderAreaIsDroppedButRealAreaKept() {
        let placeholder = ServiceTicketCheck(name: "Проверка сервиса", area: "Сервер",
                                             status: "ok", message: "Работает")
        XCTAssertNil(ServiceTicketPresentation.readableArea(placeholder))
        let real = ServiceTicketCheck(name: "База знаний",
                                      area: "Хранит уроки и документы, по которым ищут помощники",
                                      status: "ok", message: "Все 1525 документов доступны для поиска")
        XCTAssertEqual(ServiceTicketPresentation.readableArea(real),
                       "Хранит уроки и документы, по которым ищут помощники")
        XCTAssertNil(ServiceTicketPresentation.readableArea(
            ServiceTicketCheck(name: "N", area: "   ", status: "ok", message: "")))
    }

    /// Правка 3: `status: ok` с текстом об отказе не остаётся «успехом».
    func test_successStatusWithFailureTextIsDetected() {
        // Живой текст за 16.10: вчера был error, сегодня ok при том же тексте.
        XCTAssertTrue(ServiceTicketPresentation.contradictsSuccess(
            "Ночной журнал Obsidian за 2026-10-15 — проверка не прошла:"))
        XCTAssertTrue(ServiceTicketPresentation.contradictsSuccess(
            "Источник сообщил о сбое. VPN/прокси-цепочка TaskFlow↔Linear — проверка не прошла:"))
        XCTAssertTrue(ServiceTicketPresentation.contradictsSuccess(
            "✖️ Ollama (локальные модели) — УПАЛ"))
        // Настоящие успехи не должны ловиться.
        XCTAssertFalse(ServiceTicketPresentation.contradictsSuccess("Работает"))
        XCTAssertFalse(ServiceTicketPresentation.contradictsSuccess(
            "Быстрая: все 14 серверов памяти на свежем коде"))
        XCTAssertFalse(ServiceTicketPresentation.contradictsSuccess(
            "Все 1525 документов доступны для поиска"))
        XCTAssertFalse(ServiceTicketPresentation.contradictsSuccess("За сутки 4 прогона, сжимать было нечего"))
        XCTAssertFalse(ServiceTicketPresentation.contradictsSuccess(
            "Соединение работает; доступность подтверждена свежей проверкой."))
    }

    /// Такая строка уходит в «Тревоги», а не в «Работает в штатном режиме».
    func test_contradictingRowLandsInWarningBucket() {
        let checks = [
            ServiceTicketCheck(name: "Проверка сервиса", area: "Сервер", status: "ok",
                               message: "Ночной журнал Obsidian за 2026-10-15 — проверка не прошла:"),
            ServiceTicketCheck(name: "База знаний", area: "Хранит уроки", status: "ok",
                               message: "Все 1525 документов доступны для поиска"),
        ]
        let rows = SystemSummaryItem.compose(checks: checks, incidents: [])
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.first { $0.title == "Проверка сервиса" }?.kind, .warning)
        XCTAssertEqual(rows.first { $0.title == "База знаний" }?.kind, .normal)
    }

    /// Правка 4: незаконченная фраза помечается, законченная — не трогается.
    func test_truncatedMessageIsMarked() {
        XCTAssertEqual(ServiceTicketPresentation.markTruncated("проверка не прошла:"),
                       "проверка не прошла: подробности не пришли")
        XCTAssertEqual(ServiceTicketPresentation.markTruncated("Работает"), "Работает")
        // Хвост из пробелов не должен ломать проверку.
        XCTAssertEqual(ServiceTicketPresentation.markTruncated("проверка не прошла:   "),
                       "проверка не прошла: подробности не пришли")
    }

    /// Правки 1 и 4 вместе: реальная строка за 16.10 целиком.
    func test_liveRowReadsAsPlainSentence() {
        let rows = SystemSummaryItem.compose(checks: [liveDeliveryCheck()], incidents: [])
        let row = try? XCTUnwrap(rows.first)
        XCTAssertEqual(row?.area, "Доставляет уведомления тебе на телефон и в Telegram")
        XCTAssertTrue(row?.message.contains("Сторож VPN: 3") ?? false)
        XCTAssertTrue(row?.kind == .broken)
    }

    /// Реальная «Проверка сервиса» за 16.10 в приложении сегодня: обрезанный
    /// текст, заглушка вместо area, зелёный статус при отказе.
    func test_liveServiceCheckToday() {
        let check = ServiceTicketCheck(name: "Проверка сервиса", area: "Сервер", status: "ok",
                                       message: "Ночной журнал Obsidian за 2026-10-15 — проверка не прошла:")
        let rows = SystemSummaryItem.compose(checks: [check], incidents: [])
        let row = rows[0]
        XCTAssertNil(row.area)
        XCTAssertEqual(row.kind, .warning)
        XCTAssertEqual(row.message, "Ночной журнал Obsidian за 2026-10-15 — проверка не прошла: подробности не пришли")
    }

    /// Восстановленная проверка остаётся «Починено», а не «Тревоги».
    func test_recoveredCheckStaysRepaired() {
        let check = ServiceTicketCheck(name: "Xray Bots", area: "Проверяет доступность",
                                       status: "ok", message: "Соединение работает; доступность подтверждена.")
        check.recovered = true
        let rows = SystemSummaryItem.compose(checks: [check], incidents: [])
        XCTAssertEqual(rows[0].kind, .repaired)
    }
}
