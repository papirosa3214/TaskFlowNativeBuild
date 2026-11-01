import Foundation

/// Контракт миссии — сервер TaskFlow (.110, миграции 189–191).
///
/// Эндпоинты появились вместе с контрактом ассерций, поэтому на старом
/// сервере они отдают 404 «маршрута нет» (`APIError.routeMissing`) — экран
/// обязан отличать это от поломки и не пугать владельца ошибкой.
extension APIClient {
    /// Контракт ассерций карточки и итог по нему.
    func missionContract(taskID: String) async throws -> (assertions: [MissionAssertion], outcome: MissionOutcome) {
        struct Envelope: Decodable {
            let assertions: [MissionAssertion]
            let outcome: MissionOutcome
        }
        let result: Envelope = try await request(.get, "/tasks/\(taskID)/mission-assertions")
        return (result.assertions, result.outcome)
    }

    /// Журнал миссии: кто какие ассерции проверял, что упало, какая доработка
    /// открылась.
    func missionEvents(taskID: String, limit: Int = 200) async throws -> [MissionEvent] {
        struct Envelope: Decodable { let events: [MissionEvent] }
        let result: Envelope = try await request(
            .get,
            "/tasks/\(taskID)/mission-events",
            query: [URLQueryItem(name: "limit", value: String(limit))]
        )
        return result.events
    }

    /// Навыки, написанные под миссию.
    func missionSkills(taskID: String) async throws -> [MissionSkill] {
        struct Envelope: Decodable { let skills: [MissionSkill] }
        let result: Envelope = try await request(.get, "/tasks/\(taskID)/mission-skills")
        return result.skills
    }

    /// Покрытие контракта планом: какие ассерции не заявлены ни одной работой.
    func assertionCoverage(taskID: String, planID: String) async throws -> AssertionCoverage {
        try await request(.get, "/tasks/\(taskID)/collaboration-plans/\(planID)/assertion-coverage")
    }
}
