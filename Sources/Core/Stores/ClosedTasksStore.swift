import Foundation
import Observation

/// Архив закрытых задач и статистика по дням на телефоне (владелец
/// 13.11.2026). Держит у себя снимок (`ClosedTasksSnapshot`) в файле и при
/// каждом обновлении спрашивает у сервера только изменения с прошлого раза:
/// мини-карточки — по журналу изменений, дни статистики — по версии снимка.
/// Полная карточка задачи сюда не приходит никогда — только при
/// восстановлении, через `TaskStore.restore`.
@MainActor
@Observable
final class ClosedTasksStore {
    static let shared = ClosedTasksStore()

    private(set) var snapshot: ClosedTasksSnapshot
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let api = APIClient()
    @ObservationIgnored private let fileURL: URL

    init(fileURL: URL? = nil) {
        let url = fileURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("closed-tasks.json")
        self.fileURL = url
        if let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode(ClosedTasksSnapshot.self, from: data) {
            var restored = saved
            restored.prune()
            snapshot = restored
        } else {
            snapshot = ClosedTasksSnapshot()
        }
    }

    /// Только изменения с прошлого раза; первый раз — полный снимок.
    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            async let closed: ClosedTasksResponse = api.request(.get, "/tasks/closed", query: query(snapshot.closedCursor))
            async let daily: DailyStatsResponse = api.request(.get, "/stats/completed-daily", query: query(snapshot.statsCursor))
            let (closedResponse, dailyResponse) = try await (closed, daily)
            var next = snapshot
            next.apply(closedResponse)
            next.apply(dailyResponse)
            if next != snapshot {
                snapshot = next
                save()
            }
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// «Убрать с телефона» — из архива телефона; в статистике и на сервере остаётся.
    func hide(_ id: String) {
        snapshot.hide(id)
        save()
    }

    /// Восстановленная задача уходит из архива сразу.
    func removeRestored(_ id: String) {
        snapshot.remove(id)
        save()
    }

    private func query(_ cursor: String?) -> [URLQueryItem] {
        cursor.map { [URLQueryItem(name: "since", value: $0)] } ?? []
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
