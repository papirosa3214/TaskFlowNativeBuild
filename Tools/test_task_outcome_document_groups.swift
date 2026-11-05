import Foundation

@main
struct TaskOutcomeDocumentGroupsHostTests {
    private struct Doc: Equatable {
        let id: String
        let kind: String?
    }

    static func main() {
        reportsGoToTheirOwnGroup()
        oldServerWithoutKindKeepsDocumentsInResult()
        print("PASS task outcome document groups")
    }

    /// Владелец 05.11.2026: сначала сам документ, отчёты о работе — отдельно.
    private static func reportsGoToTheirOwnGroup() {
        let groups = TaskOutcomeDocumentGroups(
            [Doc(id: "report", kind: "report"), Doc(id: "doc", kind: "result"), Doc(id: "summary", kind: "outcome")],
            kind: \.kind
        )
        check(groups.results.map(\.id) == ["doc", "summary"], "result group is wrong: \(groups.results)")
        check(groups.reports.map(\.id) == ["report"], "report group is wrong: \(groups.reports)")
    }

    /// Сервер без поля `kind` не прячет документы и не называет их отчётами.
    private static func oldServerWithoutKindKeepsDocumentsInResult() {
        let groups = TaskOutcomeDocumentGroups([Doc(id: "a", kind: nil)], kind: \.kind)
        check(groups.results.map(\.id) == ["a"], "document without kind is lost")
        check(groups.reports.isEmpty, "document without kind became a report")
    }

    private static func check(_ condition: Bool, _ message: String) {
        guard condition else {
            print("FAIL: \(message)")
            exit(1)
        }
    }
}
