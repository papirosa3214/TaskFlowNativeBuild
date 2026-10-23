import Foundation

// Рутины (крон-задачи) — `/api/schedules`.
// Контракт: заметка «Рутины и расписание TaskFlow», раздел «6. API»;
// серверная часть — `server/src/routes/schedules.ts`.
public extension APIClient {

    /// `GET /api/schedules` — список рутин.
    func schedules() async throws -> [ApiSchedule] {
        let response: ApiSchedulesResponse = try await request(.get, "/schedules")
        return response.schedules
    }

    /// `GET /api/schedules/:id/runs` — история запусков.
    func scheduleRuns(id: String) async throws -> [ApiScheduleRun] {
        let response: ApiScheduleRunsResponse = try await request(.get, "/schedules/\(id)/runs")
        return response.runs
    }

    /// `POST /api/schedules` — создать рутину.
    @discardableResult
    func createSchedule(_ body: ApiScheduleCreateRequest) async throws -> ApiSchedule {
        let response: ApiScheduleResponse = try await request(.post, "/schedules", body: body)
        return response.schedule
    }

    /// `PATCH /api/schedules/:id` — правка, пауза, возобновление.
    @discardableResult
    func patchSchedule(id: String, fields: [String: JSONValue]) async throws -> ApiSchedule {
        let response: ApiScheduleResponse = try await request(.patch, "/schedules/\(id)", body: fields)
        return response.schedule
    }

    /// `DELETE /api/schedules/:id` — удалить рутину (созданные карточки не трогаются).
    func deleteSchedule(id: String) async throws {
        let _: APIOkResponse = try await request(.delete, "/schedules/\(id)")
    }

    /// `POST /api/schedules/:id/run-now` — запуск вне расписания.
    @discardableResult
    func runScheduleNow(id: String) async throws -> ApiScheduleRunNowResponse {
        try await request(.post, "/schedules/\(id)/run-now")
    }

    /// `GET /api/schedules/preview` — ближайший запуск и подпись правила
    /// (считает сервер — клиент не дублирует правила расписания).
    func schedulePreview(
        ruleKind: String,
        ruleExpr: String?,
        timeLocal: String?,
        timezone: String
    ) async throws -> ApiSchedulePreview {
        var query = [URLQueryItem(name: "rule_kind", value: ruleKind)]
        if let ruleExpr, !ruleExpr.isEmpty {
            query.append(URLQueryItem(name: "rule_expr", value: ruleExpr))
        }
        if let timeLocal, !timeLocal.isEmpty {
            query.append(URLQueryItem(name: "time_local", value: timeLocal))
        }
        query.append(URLQueryItem(name: "timezone", value: timezone))
        return try await request(.get, "/schedules/preview", query: query)
    }
}

struct ApiSchedulesResponse: Decodable {
    let schedules: [ApiSchedule]
}

struct ApiScheduleRunsResponse: Decodable {
    let runs: [ApiScheduleRun]
}
