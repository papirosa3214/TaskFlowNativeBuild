import Foundation
import Observation

@MainActor @Observable
final class RoutinePlanner {
    var occurrences: [RoutineOccurrence] = []
    var error: String?
    private var generation = 0

    func load(from: Date, until: Date) async {
        generation += 1
        let requestGeneration = generation
        do {
            let formatter = ISO8601DateFormatter()
            struct Response: Decodable { let occurrences: [RoutineOccurrence] }
            let response: Response = try await APIClient().request(.get, "/schedules/occurrences", query: [
                URLQueryItem(name: "from", value: formatter.string(from: from)),
                URLQueryItem(name: "until", value: formatter.string(from: until))
            ])
            guard requestGeneration == generation else { return }
            occurrences = response.occurrences
            error = nil
        } catch is CancellationError { return }
        catch {
            guard requestGeneration == generation else { return }
            // Do not show the previous month as if this request had succeeded.
            occurrences = []
            self.error = "Расписание автоматизаций не загрузилось: \(error.localizedDescription)"
        }
    }
}
