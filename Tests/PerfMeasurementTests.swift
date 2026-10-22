import XCTest
@testable import TaskFlow

/// Замеры производительности — LOCK-OPT-PERF-20261022.
///
/// Не проверка «правильно/неправильно», а эталонные числа: с ними сравниваются
/// следующие правки. Каждый тест печатает строку «ЗАМЕР …» в вывод прогона.
/// Источник чисел в отчёте `docs/2026-10-22-code-review-and-performance.md`.
@MainActor
final class PerfMeasurementTests: XCTestCase {

    func testЗамерСнимкаСегодня() {
        let tasks = (0..<300).map { index in
            let due: String?
            switch index % 4 {
            case 0: due = "2026-10-20"
            case 1: due = "2026-10-22"
            case 2: due = "2026-10-25"
            default: due = nil
            }
            return TestTaskFactory.makeTask(id: "t\(index)", title: "Задача \(index)", dueDate: due)
        }
        let iterations = 100
        // Холодный путь: данные меняются → снимок собирается заново.
        var coldStart = DispatchTime.now().uptimeNanoseconds
        for index in 0..<iterations {
            _ = TodayComputation(
                allTasks: tasks + [TestTaskFactory.makeTask(id: "x\(index)")],
                currentUser: nil,
                agents: [],
                filters: .empty,
                showAgentTasks: false,
                visibleProjectIds: [],
                today: "2026-10-22",
                activeHourDate: "2026-10-22",
                isLoading: false,
                isError: false
            )
        }
        let coldElapsed = Double(DispatchTime.now().uptimeNanoseconds - coldStart) / 1_000_000

        // Горячий путь: те же данные → отдача из кэша.
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<iterations {
            _ = TodayComputation(
                allTasks: tasks,
                currentUser: nil,
                agents: [],
                filters: .empty,
                showAgentTasks: false,
                visibleProjectIds: [],
                today: "2026-10-22",
                activeHourDate: "2026-10-22",
                isLoading: false,
                isError: false
            )
        }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        print("ЗАМЕР today: \(iterations) сборок на 300 задачах — холодная \(String(format: "%.3f", coldElapsed / Double(iterations))) мс, из кэша \(String(format: "%.4f", elapsed / Double(iterations))) мс")
    }

    func testЗамерДереваЗаметок() {
        let model = NotesViewModel()
        model.folders = (0..<10).map { ApiJournalFolder(id: $0, name: "Папка \($0)", parentId: nil) }
        model.notes = (0..<200).map { index in
            NoteListItem(
                id: "n\(index)",
                title: "Заметка \(index)",
                folderId: index % 10,
                preview: "Текст \(index)",
                createdAt: String(format: "2026-10-%02d 12:00:00", index % 28 + 1),
                updatedAt: String(format: "2026-10-%02d 12:00:00", index % 28 + 1)
            )
        }
        let iterations = 100
        // Холодный путь: заметки меняются → дерево собирается заново.
        var coldStart = DispatchTime.now().uptimeNanoseconds
        for index in 0..<iterations {
            model.notes.append(NoteListItem(
                id: "x\(index)",
                title: "Новая \(index)",
                folderId: index % 10,
                preview: "",
                createdAt: "2026-10-22 12:00:00",
                updatedAt: "2026-10-22 12:00:00"
            ))
            _ = model.rows
        }
        let coldElapsed = Double(DispatchTime.now().uptimeNanoseconds - coldStart) / 1_000_000

        // Горячий путь: те же данные → отдача из кэша.
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<iterations {
            _ = model.rows
        }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        print("ЗАМЕР notes: \(iterations) сборок на 200 заметках/10 папках — холодная \(String(format: "%.3f", coldElapsed / Double(iterations))) мс, из кэша \(String(format: "%.4f", elapsed / Double(iterations))) мс")
    }

    func testЗамерРазбораMarkdown() {
        let reply = """
        # Отчёт по оптимизации

        Проверил **горячие пути** приложения: список задач, чат, экран «Сегодня».

        ## Что нашёл

        - `MarkdownParser.parse` вызывается в `Binding`-геттере карточки задачи
        - `RoleReplyMarkdown` разбирает markdown заново на каждом рендере

        Обычный текст без разметки, который тоже нужно проверить на скорость разбора.
        """
        let iterations = 2000
        // Первый разбор — холодный (кэша нет), дальше — из кэша.
        let coldStart = DispatchTime.now().uptimeNanoseconds
        _ = MarkdownParser.parse(reply)
        let cold = Double(DispatchTime.now().uptimeNanoseconds - coldStart) / 1_000_000

        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<iterations {
            _ = MarkdownParser.parse(reply)
        }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        print("ЗАМЕР markdown: холодный разбор \(String(format: "%.3f", cold)) мс; \(iterations) повторов — \(String(format: "%.1f", elapsed)) мс всего, \(String(format: "%.4f", elapsed / Double(iterations))) мс на разбор")
    }

    func testЗамерРазбораДат() {
        let samples = (0..<300).map { index in
            String(format: "2026-10-%02d %02d:%02d:%02d", index % 28 + 1, index % 24, index % 60, index % 60)
        }
        let start = DispatchTime.now().uptimeNanoseconds
        for sample in samples { _ = DateFormats.sqliteUTC(sample) }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        print("ЗАМЕР дат: \(samples.count) разборов — \(String(format: "%.2f", elapsed)) мс всего, \(String(format: "%.2f", elapsed * 1000 / Double(samples.count))) мкс на дату")
    }
}
