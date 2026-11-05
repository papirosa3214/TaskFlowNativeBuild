import Foundation

/// Фоновая синхронизация: сеть догоняет локальную базу, а не наоборот.
///
/// Порядок работы на старте приложения:
/// 1. Экран рисует то, что уже лежит в базе (мгновенно, без сети).
/// 2. Синхронизация в фоне догружает изменившееся и пишет в базу.
/// 3. Экран перечитывает из базы.
///
/// Что где хранится:
/// - **Отпечатки и курсоры** — в `sync_state` (таблица `LocalStore`).
///   Именно из-за этого повторный запуск не качает список заново: ETag
///   переживает перезапуск приложения, а не живёт в памяти до перезапуска.
/// - **Данные** — в таблицах `chat`, `message`, `task`, `notification`.
@MainActor
public final class SyncEngine {
    public static let shared = SyncEngine()

    /// Сеть недоступна — экраны показывают базу и плашку «нет связи».
    public private(set) var isOffline = false
    /// Последняя ошибка синхронизации (для плашки; детали — в логе).
    public private(set) var lastErrorMessage: String?

    private let store = LocalStore.shared
    private let api = APIClient()

    private init() {}

    // MARK: - Чаты

    /// Список чатов: спрашиваем с отпечатком, сервер отвечает 304, если
    /// список не менялся, — тогда тело не качаем вовсе.
    public func syncChats(includeClosed: Bool = false) async {
        do {
            let result = try await attempt {
                try await self.api.roleChatsSync(
                    includeClosed: includeClosed,
                    etag: self.store.syncState(SyncStateKeys.chatsETag)
                )
            }
            if result.notModified { return }
            try store.upsertChats(result.data)
            // Отпечаток без тела (сервер его не шлёт) — не храним: иначе
            // следующий раз пошлём If-None-Match, на который сервер не ответит.
            if let etag = result.etag { store.setSyncState(SyncStateKeys.chatsETag, etag) }
            isOffline = false
        } catch is CancellationError {
            return
        } catch {
            fail(error)
        }
    }

    // MARK: - Сообщения чата

    /// Догрузить сообщения чата.
    ///
    /// Курсор — максимальный `sequence` из базы. Если сервер умеет
    /// постраничную выдачу, спрашиваем только новое; если нет (старый
    /// сервер) — придёт весь чат, и мы просто перезапишем те же записи.
    public func syncMessages(chatID: String) async {
        // Сервер без постраничной выдачи отдаёт чат целиком. Тогда качать
        // его на КАЖДОЕ событие сокета — лишний трафик: событие и так
        // применяется к ленте на экране. Догружаем только там, где сервер
        // умеет отдать новое (`after`).
        guard store.syncState(SyncStateKeys.chatsPaging) == "1" else { return }
        let cursor = try? store.maxSequence(chatID: chatID)
        do {
            let page = try await attempt {
                try await self.api.roleChatMessagesPage(
                    id: chatID,
                    after: cursor,
                    limit: cursor.map { _ in Self.pageSize }
                )
            }
            try store.upsertMessages(chatID: chatID, payload: page.data)
            if page.hasMore != nil {
                // Сервер отдал признак «есть ещё» — значит умеет постранично.
                store.setSyncState(SyncStateKeys.chatsPaging, "1")
            }
            if let max = try? store.maxSequence(chatID: chatID) {
                store.setSyncState(SyncStateKeys.messagesCursor(chatID: chatID), String(max))
            }
            isOffline = false
        } catch is CancellationError {
            return
        } catch {
            fail(error)
        }
    }

    /// Догрузить сообщения ВВЕРХ (прокрутка к началу).
    ///
    /// Возвращает `true`, если ещё есть что догружать. На сервере без
    /// постраничной выдачи — `false`: там history и так приходит целиком.
    @discardableResult
    public func syncOlderMessages(chatID: String) async -> Bool {
        guard store.syncState(SyncStateKeys.chatsPaging) == "1" else { return false }
        guard let oldest = try? store.minSequence(chatID: chatID) else { return false }
        do {
            let page = try await attempt {
                try await self.api.roleChatMessagesPage(
                    id: chatID,
                    before: oldest,
                    limit: Self.pageSize
                )
            }
            try store.upsertMessages(chatID: chatID, payload: page.data)
            return page.hasMore ?? false
        } catch is CancellationError {
            return false
        } catch {
            fail(error)
            return false
        }
    }

    // MARK: - Уведомления

    /// Лента уведомлений. На старте и при переподключении — только
    /// непрочитанные: полная лента весит ~463 КБ (61 КБ в gzip) ради
    /// числа на плашке.
    public func syncNotifications(unreadOnly: Bool = false) async {
        do {
            let data = try await attempt {
                try await self.api.rawNotifications(unreadOnly: unreadOnly)
            }
            try store.upsertNotifications(data)
            isOffline = false
        } catch is CancellationError {
            return
        } catch {
            fail(error)
        }
    }

    // MARK: - Реалтайм

    /// Событие сокета. Сообщение пришло — догружаем его в базу: сервер
    /// отдаст только новое (`after` курсора), это один короткий запрос.
    public func ingest(_ event: RealtimeEvent) {
        switch event {
        case .roleChatMessage(let chatID, _):
            Task { await syncMessages(chatID: chatID) }
        case .unknown("chat:withdrawn", .object(let payload)):
            // Отозванное сообщение уходит и из базы: лента чата читает базу.
            if let chatID = payload["chat_id"]?.stringValue, let id = payload["message_id"]?.stringValue {
                try? store.deleteMessages(chatID: chatID, ids: [id])
            }
        case .notificationNew(_):
            Task { await syncNotifications(unreadOnly: true) }
        default:
            break
        }
    }

    // MARK: - Общее

    /// Полный проход по всем спискам. Вызывается после первой отрисовки.
    public func syncAll(includeClosed: Bool = false) async {
        async let chats: Void = syncChats(includeClosed: includeClosed)
        async let notifications: Void = syncNotifications(unreadOnly: true)
        _ = await (chats, notifications)
    }

    /// Повтор с задержкой: сеть моргнула — ждём и пробуем ещё раз.
    private func attempt<T>(_ operation: () async throws -> T, retries: Int = 1) async throws -> T {
        var lastError: Error?
        for attempt in 0...retries {
            do {
                return try await operation()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                if attempt < retries {
                    try? await Task.sleep(nanoseconds: 700_000_000)
                }
            }
        }
        guard let lastError else { throw CancellationError() }
        throw lastError
    }

    private func fail(_ error: Error) {
        lastErrorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        // Сеть недоступна — не «сломалось», а «связи нет». Различаем по
        // коду транспорта: остальное — реальная ошибка, её видно плашкой.
        if let apiError = error as? APIError, case .transport = apiError {
            isOffline = true
        }
    }

    /// Сколько сообщений брать за раз — как в плане синхронизации.
    private static let pageSize = 50
}
