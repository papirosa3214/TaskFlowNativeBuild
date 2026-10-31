import Foundation
import Observation

/// Стор уведомлений — загрузка + приём `notification:new` по WS (spec §4.1).
@MainActor
@Observable
public final class NotificationStore {
    public private(set) var notifications: [ApiNotification] = []
    public private(set) var isLoading = false
    public var errorMessage: String?

    public var unreadCount: Int { notifications.count(where: { !$0.read }) }

    private let apiClient: APIClient

    public init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    /// `unreadOnly` — взять только непрочитанные. На старте приложения и при
    /// переподключении хватает счётчика непрочитанных: вся лента — это
    /// ~463 КБ (61 КБ в gzip) ради числа на плашке. Полную ленту грузит
    /// экран уведомлений обычным `load()`.
    public func load(unreadOnly: Bool = false) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        // Локальная база: лента видна сразу, без сети. На пустой базе —
        // скелет, дальше данные приходят из сети.
        if notifications.isEmpty, let local = try? LocalStore.shared.notifications(), !local.isEmpty {
            notifications = local
        }
        do {
            // Сырое тело: его и в базу, и в модель. Отдельно — чтобы в базе
            // лежал ответ сервера как есть.
            let data = try await apiClient.rawNotifications(unreadOnly: unreadOnly)
            notifications = try apiClient.decode([ApiNotification].self, from: data)
            try? LocalStore.shared.upsertNotifications(data)
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func markRead(id: String) async {
        guard notifications.contains(where: { $0.id == id }) else { return }
        do {
            try await apiClient.markNotificationRead(id: id)
            // `PATCH .../read` возвращает только `{ ok: true }`, поэтому
            // перечитываем полный серверный снимок вместо локальной имитации
            // неизменяемой `ApiNotification`.
            await load()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func apply(_ event: RealtimeEvent) {
        if case .notificationNew(let notification) = event {
            // Дедуп по id — страховка на случай дублирующего события с WS
            // (напр. короткое окно двойного реконнекта), не должно давать
            // одно и то же уведомление в списке дважды.
            guard !notifications.contains(where: { $0.id == notification.id }) else { return }
            notifications.insert(notification, at: 0)
        }
    }
}
