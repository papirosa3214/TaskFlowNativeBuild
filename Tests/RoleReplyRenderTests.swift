import XCTest
import Foundation
@testable import TaskFlow

/// Один рендер ответов ролей во всём приложении — LOCK-IOS-ROLE-REPLY-RENDER-20261020,
/// карточка 19f57bc9 (родитель a50e564d, владелец 20.10.2026): «всё, что пишут
/// роли, должно показываться одним компонентом».
///
/// Тест работает по исходникам, а не по кадрам (как `UIStyleGateTests`): он
/// компилируется вместе с приложением и ловит отклонение в том же запуске,
/// что и сборка. Смысл в том, чтобы новый экран с сырым `Text` ответа роли
/// не появился снова тихо.
///
/// Файл намеренно НЕ зависит от нового кода (`RoleReplyMarkdown.preview`) —
/// только читает исходники. Благодаря этому он собирается и на коде до
/// правки и там падает: это и есть проверка «было сломано — стало исправлено».
/// Поведение самой функции `preview(of:)` проверяет `RoleReplyPreviewTests`.
final class RoleReplyRenderTests: XCTestCase {

    // MARK: - Исходники

    /// Корень репозитория: рядом с папкой `Tests` в распакованной проверке.
    private static var repoRoot: URL? {
        // #filePath = <repo>/Tests/RoleReplyRenderTests.swift
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // <repo>
    }

    private func source(_ relativePath: String) throws -> String {
        let root = try XCTUnwrap(Self.repoRoot, "не найден корень репозитория рядом с Tests")
        let url = root.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func allSwiftSources() throws -> [(path: String, text: String)] {
        let root = try XCTUnwrap(Self.repoRoot, "не найден корень репозитория рядом с Tests")
        let sources = root.appendingPathComponent("Sources")
        // Песочница сборки по-разному пускает перечисление подкаталогов и обход
        // каталога: пустой результат одного не значит, что файлов нет.
        var paths = (try? FileManager.default.subpathsOfDirectory(atPath: sources.path)) ?? []
        if paths.isEmpty, let walked = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil) {
            paths = walked.compactMap { ($0 as? URL)?.path.replacingOccurrences(of: sources.path + "/", with: "") }
        }
        var result: [(String, String)] = []
        for path in paths where path.hasSuffix(".swift") {
            let url = sources.appendingPathComponent(path)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            result.append(("Sources/" + path, text))
        }
        XCTAssertGreaterThan(result.count, 100, "Sources почти пуст — тест ничего не проверяет")
        return result
    }

    // MARK: - Правило 1. Второго разборщика разметки в приложении нет

    /// `NotificationTicketStyle.markdownText` разбирал инлайн-разметку сводки
    /// через `AttributedString(markdown:)` — второй разборщик рядом с общим
    /// рендером. В приложении их должен быть ровно один.
    func testNoSecondMarkdownParserInSources() throws {
        let offenders = try allSwiftSources()
            .filter { $0.text.contains("AttributedString(markdown:") }
            .map(\.path)
        XCTAssertEqual(
            offenders, [],
            "Второй разборщик разметки: \(offenders.joined(separator: ", ")). "
                + "Разметку ответа роли разбирает только RoleReplyMarkdown"
        )
    }

    // MARK: - Правило 2. Места, где показывают текст роли, идут через общий рендер

    /// Экраны из карточки: результат шага плана, итог задачи, сводка сторожа,
    /// разбор вопроса между ролями, ответ Помощника владельца, подготовка
    /// карточки.
    ///
    /// Общий рендер ответа роли сегодня — это `RoleReplyMarkdown` и его
    /// обёртка `TaskRoleReply` (она внутри зовёт тот же `RoleReplyMarkdown`
    /// и разбор JSON сервера). Экран, который показывает текст роли, обязан
    /// идти через одного из них — иначе ответ снова уедет в сырой `Text`.
    private static let roleTextPlaces = [
        "Sources/Features/Tasks/TaskCardContent.swift",
        "Sources/Features/Tasks/Detail/PlanStepSheets.swift",
        "Sources/Features/Tasks/Detail/TaskOutcomeSection.swift",
        "Sources/Features/Tasks/Detail/TaskPreparationView.swift",
        "Sources/Features/Roles/RoleCoordinationCard.swift",
    ]

    func testRoleTextPlacesUseCommonRenderer() throws {
        for path in Self.roleTextPlaces {
            let text = try source(path)
            XCTAssertTrue(
                text.contains("RoleReplyMarkdown(") || text.contains("TaskRoleReply("),
                "\(path): текст роли должен рисоваться общим рендером RoleReplyMarkdown"
            )
        }
    }

    /// Итог шага плана — самая частая жалоба: ответ роли со звёздочками и
    /// таблицей показывался строкой `Text(result)` в трёх разных местах.
    func testStepResultIsNeverPlainText() throws {
        let candidates = ["Sources/Features/Tasks/TaskFormScreen.swift",
                          "Sources/Features/Tasks/Detail/PlanStepSheets.swift"]
        let offenders = try candidates.filter { try source($0).contains("Text(result)") }
        XCTAssertEqual(offenders, [], "Итог шага показан сырым Text в: \(offenders.joined(separator: ", "))")
    }

    /// Превью ответа роли в строке: короткое, в две строки, с системным
    /// усечением хвоста, а полный ответ открывается общей шторкой.
    ///
    /// С 29.10.2026 (поручение владельца, `docs/2026-10-29-subtask-result-preview.md`)
    /// ответ роли читается под подзадачей, а не отдельными строками в секции
    /// «Итог» — превью живёт в карточке (`TaskCardContent.swift`), и разметка
    /// внутри двухстрочного превью разбирается системно, только инлайновая.
    func testOutcomeRowPreviewGoesThroughCommonRenderer() throws {
        let card = try source("Sources/Features/Tasks/TaskCardContent.swift")
        XCTAssertTrue(card.contains("OutcomeTextRow("),
                      "ответ роли в строке должен открываться общей шторкой OutcomeTextRow")
        XCTAssertTrue(card.contains("lineLimit(2)") && card.contains("truncationMode(.tail)"),
                      "превью ответа роли — две строки с системным усечением хвоста")
        XCTAssertTrue(card.contains("interpretedSyntax: .inlineOnlyPreservingWhitespace"),
                      "в двухстрочном превью разбирается только инлайновая разметка")
        XCTAssertFalse(card.contains("Text(result)"),
                       "ответ роли в строке показан сырым Text")
    }
}
