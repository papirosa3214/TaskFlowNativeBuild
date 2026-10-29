import Foundation
import Observation

// Список рутин: загрузка, пауза/возобновление, запуск сейчас, удаление.
// Отдельный `@Observable`-объект без SwiftUI в самой модели — так же, как
// остальные вью-модели приложения (`TaskFormViewModel`).
@MainActor
@Observable
final class RoutinesViewModel {
    var schedules: [ApiSchedule] = []
    var isLoading = false
    var errorMessage: String?
    /// Короткое сообщение о результате действия («Задача создана», «Рутина на паузе»).
    var notice: String?

    /// Роли — чтобы в строке рутины показывать имя роли, а не её ключ
    /// (`assignee_id` сервера — это ключ роли, «builder», а не «Разработчик»).
    private var roles: [RoleProfile] = []

    private let api: APIClient

    init(api: APIClient = APIClient()) {
        self.api = api
    }

    /// Имя роли по её ключу. Если каталог ролей не пришёл — показываем ключ,
    /// не выдумывая подпись.
    func roleTitle(for key: String?) -> String? {
        guard let key, !key.isEmpty else { return nil }
        return roles.first { $0.role == key }?.title ?? key
    }

    /// Сколько рутин активны — это значение показывает строка «Мои рутины» на «Обзоре».
    var activeCount: Int {
        schedules.filter { $0.status == "active" }.count
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            schedules = try await api.schedules()
        } catch is CancellationError {
            return
        } catch {
            errorMessage = Self.message(error)
        }
        // Каталог нужен только для подписи исполнителя. Список (или ошибка)
        // уже готов: не держим его за загрузкой вспомогательных данных.
        isLoading = false
        if roles.isEmpty {
            roles = (try? await api.roles()) ?? []
        }
    }

    /// Пауза/возобновление: сервер пересчитывает следующий запуск сам.
    func setPaused(_ schedule: ApiSchedule, paused: Bool) async {
        do {
            let updated = try await api.patchSchedule(id: schedule.id, fields: ["status": .string(paused ? "paused" : "active")])
            replace(updated)
            notice = paused ? "Рутина на паузе" : "Рутина возобновлена"
        } catch is CancellationError {
            return
        } catch {
            errorMessage = Self.message(error)
        }
    }

    /// Запуск вне расписания — карточка создаётся сейчас.
    func runNow(_ schedule: ApiSchedule) async {
        do {
            let result = try await api.runScheduleNow(id: schedule.id)
            replace(result.schedule)
            if let run = result.run {
                // Причину от сервера показываем: без неё «Пропущено» ничего
                // не объясняет (например, «прошлый экземпляр не закрыт»).
                notice = run.status == "created"
                    ? "Задача создана"
                    : RoutineFormat.runNotice(status: run.status, detail: run.detail)
            } else {
                notice = "Запуск выполнен"
            }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = Self.message(error)
        }
    }

    /// Удаление рутины: созданные ею карточки остаются (инвариант из спеки).
    func delete(_ schedule: ApiSchedule) async {
        do {
            try await api.deleteSchedule(id: schedule.id)
            schedules.removeAll { $0.id == schedule.id }
            notice = "Рутина удалена"
        } catch is CancellationError {
            return
        } catch {
            errorMessage = Self.message(error)
        }
    }

    private func replace(_ schedule: ApiSchedule) {
        if let index = schedules.firstIndex(where: { $0.id == schedule.id }) {
            schedules[index] = schedule
        } else {
            schedules.insert(schedule, at: 0)
        }
    }

    static func message(_ error: Error) -> String {
        (error as? APIError)?.errorDescription ?? error.localizedDescription
    }
}
