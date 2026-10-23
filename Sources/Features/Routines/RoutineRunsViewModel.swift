import Foundation
import Observation

// История запусков рутины (`GET /api/schedules/:id/runs`).
@MainActor
@Observable
final class RoutineRunsViewModel {
    var runs: [ApiScheduleRun] = []
    var isLoading = false
    var errorMessage: String?

    private let api: APIClient

    init(api: APIClient = APIClient()) {
        self.api = api
    }

    func load(scheduleID: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            runs = try await api.scheduleRuns(id: scheduleID)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = RoutinesViewModel.message(error)
        }
    }
}
