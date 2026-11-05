/// Документы итога карточки по смыслу (владелец 05.11.2026): сам результат
/// отдельно, отчёты ролей о проделанной работе отдельно. Порядок задаёт сервер.
public struct TaskOutcomeDocumentGroups<Document> {
    public let results: [Document]
    public let reports: [Document]

    public init(_ documents: [Document], kind: (Document) -> String?) {
        results = documents.filter { kind($0) != "report" }
        reports = documents.filter { kind($0) == "report" }
    }
}
