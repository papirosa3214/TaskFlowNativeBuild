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
}
