// Tests/ServiceTicketMarkdownParserTests.swift
import XCTest
@testable import TaskFlow

final class ServiceTicketMarkdownParserTests: XCTestCase {
    // Живой файл с .110, curl+ssh 27.09.2026 (урезан ради читаемости теста,
    // содержимое совпадает по структуре с настоящим).
    private let liveExample = """
    # Автономность .110 — сводка за сутки

    - когда: 2026-09-27T01:51:33
    - от кого: autonomy-110
    - уровень: error
    - тревога: да
    - приёмка: rendezvous.py v1

    ## Сводка (для отображения в приложении)

    ```
    Сводка уведомлений от 27.09.26

    **Работают в штатном режиме:**
    - сжатие памяти: 4 прогонов, свёрнуто 0 записей

    **Не отработали в штатном режиме:**
    - доставка тревог: у отправителей НЕ УШЛО 13
    По данным проблемным местам создана карточка на диагностику:
    tf://task/demo-diag-uuid-1 (27.09.2026, Codex)
    ```
    """

    func test_parsesLiveExample() throws {
        let d = try XCTUnwrap(ServiceTicketMarkdownParser.parse(liveExample))
        XCTAssertEqual(d.title, "Автономность .110 — сводка за сутки")
        XCTAssertEqual(d.when, "2026-09-27T01:51:33")
        XCTAssertEqual(d.from, "autonomy-110")
        XCTAssertEqual(d.level, "error")
        XCTAssertTrue(d.isAlarm)
        XCTAssertEqual(d.diagnosticTaskId, "demo-diag-uuid-1")
        XCTAssertTrue(d.notWorkingText?.contains("НЕ УШЛО") == true)
        XCTAssertTrue(d.resolutionItems.isEmpty) // Phase 4 блока в этом файле ещё нет
    }

    // Сконструированная фикстура Phase 4 — backend её пока не пишет, см. спеку.
    private let withPhase4Block = """
    # Тикет с итогом устранения

    - когда: 2026-09-27T02:00:00
    - от кого: demo
    - уровень: error
    - тревога: да

    ## Сводка (для отображения в приложении)
    ```
    demo
    ```

    ## Итог по устранению
    - доставка тревог — (исправлено)
    - доступ к базе — (не исправлено: нет доступов у исполнителя)
    - канал telegram — (не исправлено, нужно ваше решение по вопросу выбора канала:
      1) переключить на резервный канал
      2) увеличить таймаут отправки
      3) отключить проверку до утра
      4) свой вариант)
    """

    func test_parsesPhase4ResolutionBlock_bestEffort() throws {
        let d = try XCTUnwrap(ServiceTicketMarkdownParser.parse(withPhase4Block))
        XCTAssertEqual(d.resolutionItems.count, 3)
        XCTAssertEqual(d.resolutionItems[0].problem, "доставка тревог")
        XCTAssertEqual(d.resolutionItems[0].status, .fixed)
        XCTAssertEqual(d.resolutionItems[1].status, .unresolved(reason: "нет доступов у исполнителя"))
        guard case .needsDecision(let options) = d.resolutionItems[2].status else {
            return XCTFail("expected needsDecision")
        }
        XCTAssertEqual(options, [
            "переключить на резервный канал",
            "увеличить таймаут отправки",
            "отключить проверку до утра"
        ])
    }

    func test_returnsNil_onGarbage() {
        XCTAssertNil(ServiceTicketMarkdownParser.parse("случайный текст без нужных полей"))
    }
}
