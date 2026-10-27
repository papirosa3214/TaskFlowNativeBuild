import Foundation

protocol LinearImportServing: Sendable {
    func linearIssues(cursor: String?, sourceProjectID: String?) async throws -> LinearIssuePage
    func linearSourceProjects() async throws -> LinearSourceProjectList
    func linearPreview(issueIDs: [String], projectID: String?) async throws -> LinearImportPreview
    func importLinear(previewID: String) async throws -> LinearImportResult
    func projects() async throws -> [ApiProject]
}

private struct LinearPreviewJob: Decodable {
    let jobID: String
    let status: String
    let preview: LinearImportPreview?
    let error: String?
    enum CodingKeys: String, CodingKey { case status, preview, error; case jobID = "job_id" }
}

extension APIClient: LinearImportServing {
    func linearIssues(cursor: String?, sourceProjectID: String?) async throws -> LinearIssuePage {
        try await request(.get, "/integrations/linear/issues", query: LinearIssueQuery.items(cursor: cursor, projectID: sourceProjectID))
    }
    func linearSourceProjects() async throws -> LinearSourceProjectList {
        try await request(.get, "/integrations/linear/projects")
    }
    func linearPreview(issueIDs: [String], projectID: String?) async throws -> LinearImportPreview {
        var body: [String: JSONValue] = ["issue_ids": .array(issueIDs.map(JSONValue.string)), "async": .bool(true)]
        if let projectID { body["project_id"] = .string(projectID) }
        let started: LinearPreviewJob = try await request(.post, "/integrations/linear/preview", body: body)
        let deadline = Date().addingTimeInterval(11 * 60)
        while Date() < deadline {
            try Task.checkCancellation()
            let job: LinearPreviewJob = try await request(.get, "/integrations/linear/previews/\(started.jobID)")
            if job.status == "ready", let preview = job.preview { return preview }
            if job.status == "failed" { throw LinearImportClientError.preparation(job.error ?? "Не удалось загрузить структуру Linear.") }
            try await Task.sleep(for: .seconds(1))
        }
        throw LinearImportClientError.preparation("Подготовка заняла слишком долго. Выберите меньше задач.")
    }
    func importLinear(previewID: String) async throws -> LinearImportResult {
        try await request(.post, "/integrations/linear/import", body: ["preview_id": JSONValue.string(previewID)])
    }
}

/// Автоимпорт из Linear (служба сервера): включён или выключен.
struct LinearAutoImportState: Decodable { let enabled: Bool }

extension APIClient {
    func linearAutoImport() async throws -> LinearAutoImportState {
        try await request(.get, "/integrations/linear/autoimport")
    }
    func setLinearAutoImport(enabled: Bool) async throws -> LinearAutoImportState {
        try await request(.patch, "/integrations/linear/autoimport", body: ["enabled": JSONValue.bool(enabled)])
    }
}
