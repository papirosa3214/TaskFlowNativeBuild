import XCTest
@testable import TaskFlow

/// Раскладка полок базы знаний и состояние заметки в индексе.
///
/// Экран базы знаний с 09.11.2026 — не дневник, а полки датасетов RAGFlow
/// (владелец: «там есть дата-сеты по тематикам», «добавлять или исключать
/// эти датасеты прямо через мобильное приложение»). Что считать полкой и
/// куда попадает исключённый датасет — правило, а не оформление, поэтому
/// живёт в модели и проверяется здесь.
final class KnowledgeBaseTests: XCTestCase {
    private func section(_ id: Int, _ title: String) -> KnowledgeSection {
        KnowledgeSection(id: id, title: title, position: id, datasetCount: nil)
    }

    func testSectionsKeepOwnerOrderAndUnsectionedIsLast() {
        let datasets = [
            KnowledgeDatasetRef(id: "loose", sectionId: nil, enabled: true),
            KnowledgeDatasetRef(id: "docs", sectionId: 1, enabled: true),
            KnowledgeDatasetRef(id: "code", sectionId: 2, enabled: true),
        ]
        let shelves = KnowledgeLibrary.shelves(
            datasets: datasets, sections: [section(1, "Документация"), section(2, "Код")]
        )
        XCTAssertEqual(shelves.map(\.title), ["Документация", "Код", "Без раздела"])
        XCTAssertEqual(shelves.map(\.datasetIds), [["docs"], ["code"], ["loose"]])
    }

    func testDisabledDatasetDisappearsFromEveryShelf() {
        // Владелец исключил «Память — заметки»: её не должно быть ни в разделе,
        // ни в «Без раздела» — иначе исключение ничего не значит.
        let datasets = [
            KnowledgeDatasetRef(id: "memory", sectionId: 1, enabled: false),
            KnowledgeDatasetRef(id: "loose-memory", sectionId: nil, enabled: false),
            KnowledgeDatasetRef(id: "docs", sectionId: 1, enabled: true),
        ]
        let shelves = KnowledgeLibrary.shelves(datasets: datasets, sections: [section(1, "Темы")])
        XCTAssertEqual(shelves.map(\.datasetIds), [["docs"]])
        XCTAssertEqual(shelves.map(\.title), ["Темы"])
    }

    func testEmptySectionStaysVisible() {
        // Раздел только что создан — он должен быть на экране, иначе человек
        // не найдёт, куда положить датасет.
        let shelves = KnowledgeLibrary.shelves(datasets: [], sections: [section(7, "Новый раздел")])
        XCTAssertEqual(shelves.count, 1)
        XCTAssertEqual(shelves[0].datasetIds, [])
        XCTAssertEqual(shelves[0].sectionId, 7)
    }

    func testUnsectionedShelfIsNotShownWhenEmpty() {
        let shelves = KnowledgeLibrary.shelves(
            datasets: [KnowledgeDatasetRef(id: "docs", sectionId: 3, enabled: true)],
            sections: [section(3, "Темы")]
        )
        XCTAssertEqual(shelves.map(\.id), ["section-3"])
    }

    func testIndexedNoteNeedsNoAttention() {
        XCTAssertEqual(NoteIndexState(server: "indexed").label, "В поиске")
        XCTAssertFalse(NoteIndexState(server: "indexed").needsAttention)
        XCTAssertFalse(NoteIndexState(server: nil).needsAttention)
    }

    func testQueuedIndexingAndErrorAskForAttention() {
        XCTAssertEqual(NoteIndexState(server: "queued").label, "В очереди на индексацию")
        XCTAssertEqual(NoteIndexState(server: "indexing").label, "Индексируется")
        XCTAssertEqual(NoteIndexState(server: "error").label, "Не попала в поиск")
        XCTAssertTrue(NoteIndexState(server: "queued").needsAttention)
        XCTAssertTrue(NoteIndexState(server: "indexing").needsAttention)
        XCTAssertTrue(NoteIndexState(server: "error").needsAttention)
    }

    func testUnknownServerStateMeansIndexed() {
        // Сервер не прислал состояние — заметка всё равно попала в индекс
        // суточным прогоном; показывать тревогу без причины нельзя.
        XCTAssertEqual(NoteIndexState(server: "что-то новое"), .unknown)
        XCTAssertEqual(NoteIndexState(server: "что-то новое").label, "В поиске")
    }

    // ── Поиск: совпадение запроса с результатом ────────────────────────────

    private func chunk(_ text: String, document: String = "taskflow-1.md") -> ApiKnowledgeChunk {
        ApiKnowledgeChunk(
            text: text,
            score: 0.5,
            documentName: document,
            title: nil,
            project: nil,
            docId: nil
        )
    }

    private func status(_ run: String, message: String? = nil) -> KnowledgeDocumentStatus {
        KnowledgeDocumentStatus(
            id: "doc-1",
            name: "taskflow-1.md",
            run: run,
            progress: nil,
            message: message,
            chunkCount: nil
        )
    }

    func testResultsBelongToTheQueryInTheField() {
        // Владелец видел «ничего не нашлось» там, где куски были: ответ
        // показываем только для того запроса, что сейчас в поле (дебаунс).
        var search = KnowledgeSearch()
        guard case let .ready(token, query) = search.begin("полки") else {
            return XCTFail("запрос из четырёх букв должен уйти на сервер")
        }
        XCTAssertEqual(query, "полки")
        XCTAssertTrue(search.accept(token: token, query: query, results: [chunk("полки датасетов")]))

        XCTAssertEqual(search.results(for: "полки").count, 1)
        XCTAssertEqual(search.results(for: "пол").count, 0, "в поле другой запрос — старые куски не показываем")
        XCTAssertEqual(search.results(for: "  полки\n").count, 1, "пробелы вокруг запроса ничего не значат")
    }

    func testStaleAnswerDoesNotOverrideNewestSearch() {
        var search = KnowledgeSearch()
        guard case let .ready(oldToken, oldQuery) = search.begin("датасеты") else {
            return XCTFail("старый запрос должен иметь номер")
        }
        guard case let .ready(newToken, newQuery) = search.begin("датасеты RAGFlow") else {
            return XCTFail("новый запрос должен иметь номер")
        }
        XCTAssertNotEqual(oldToken, newToken)
        XCTAssertTrue(search.accept(token: newToken, query: newQuery, results: [chunk("свежий кусок")]))

        // Ответ на старый запрос пришёл позже — он не перебивает новый.
        XCTAssertFalse(search.accept(token: oldToken, query: oldQuery, results: [chunk("старый кусок")]))
        XCTAssertEqual(search.results(for: "датасеты RAGFlow").map(\.text), ["свежий кусок"])
        XCTAssertEqual(search.results(for: "датасеты").count, 0)
        XCTAssertFalse(search.isCurrent(oldToken))
        XCTAssertTrue(search.isCurrent(newToken))
    }

    func testFailedNewestSearchLeavesNoOldChunks() {
        // Ошибка сервера — это ошибка, а не «ничего не нашлось», но старые
        // куски под новым запросом оставаться не должны.
        var search = KnowledgeSearch()
        guard case let .ready(token, query) = search.begin("полки") else {
            return XCTFail("запрос должен уйти на сервер")
        }
        _ = search.accept(token: token, query: query, results: [chunk("полки датасетов")])

        guard case let .ready(newToken, newQuery) = search.begin("полки разделов") else {
            return XCTFail("новый запрос должен уйти на сервер")
        }
        XCTAssertTrue(search.accept(token: newToken, query: newQuery, results: []))
        XCTAssertEqual(search.results(for: "полки разделов").count, 0)
        XCTAssertEqual(search.results(for: "полки").count, 0, "старый ответ под новым запросом не живёт")
    }

    func testSingleLetterQueryClearsResultsAndInvalidatesPendingAnswer() {
        // Retrieval на односложный запрос отдаёт случайные куски — такой
        // запрос не отправляем и ждать его ответ уже некому.
        var search = KnowledgeSearch()
        guard case let .ready(token, query) = search.begin("база") else {
            return XCTFail("запрос должен уйти на сервер")
        }
        _ = search.accept(token: token, query: query, results: [chunk("база знаний")])

        guard case .tooShort = search.begin(" б ") else {
            return XCTFail("одна буква — не запрос")
        }
        XCTAssertFalse(search.isCurrent(token), "ответ на прежний запрос устарел")
        XCTAssertEqual(search.results(for: "база").count, 0)
        XCTAssertEqual(search.results(for: "б").count, 0)
    }

    // ── Название документа и подпись статуса ───────────────────────────────

    func testDocumentNamePrefersNoteTitleAndDropsMarkdownSuffix() {
        // В индексе заметка зовётся `taskflow-<uuid>.md`: человеку это имя
        // ничего не говорит, но строка без названия остаться не должна.
        XCTAssertEqual(
            KnowledgeDocumentDisplay.title("Вторник 1", name: "taskflow-7f3a.md"), "Вторник 1"
        )
        XCTAssertEqual(KnowledgeDocumentDisplay.title("", name: "taskflow-7f3a.md"), "taskflow-7f3a")
        XCTAssertEqual(KnowledgeDocumentDisplay.title(nil, name: "README.md"), "README")
        XCTAssertEqual(KnowledgeDocumentDisplay.title(nil, name: "spec.pdf"), "spec.pdf")
    }

    func testStatusSubtitleSpeaksOnlyAboutWorkAndFailures() {
        // «В поиске» — норма, о ней молчим (владелец: «зачем ты мне это
        // говоришь»); говорим только про разбор и срыв.
        XCTAssertNil(KnowledgeDocumentDisplay.subtitle(indexed: true, status: nil))
        XCTAssertNil(
            KnowledgeDocumentDisplay.subtitle(indexed: false, status: status("DONE")),
            "статус пришёл раньше списка — документ уже в поиске"
        )
        XCTAssertEqual(
            KnowledgeDocumentDisplay.subtitle(indexed: false, status: nil),
            "Разбирается — в поиске пока нет"
        )
        XCTAssertEqual(
            KnowledgeDocumentDisplay.subtitle(indexed: false, status: status("RUNNING")),
            "Разбирается — в поиске пока нет"
        )
        XCTAssertEqual(
            KnowledgeDocumentDisplay.subtitle(indexed: false, status: status("FAIL", message: "пустой файл")),
            "Разбор сорвался: пустой файл"
        )
        XCTAssertEqual(
            KnowledgeDocumentDisplay.subtitle(indexed: false, status: status("FAIL")),
            "Разбор сорвался"
        )
    }
}
