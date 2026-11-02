import Foundation

/// Дельта синхронизации сущностей вне карточек: `GET /api/sync/changes`.
///
/// Зачем. Журнал карточек (`/api/tasks/changes`) покрывает только задачи и их
/// дочерние таблицы. Проекты, метки, заметки, дневник, рутины и вложения в
/// него не пишутся, а события сокета в разрыв связи не доходят: правка
/// рутины или заметки на сервере оставалась на телефоне до перезагрузки
/// экрана (разбор 02.11.2026, заметка Архитектора «Техническое решение и
/// риски»).
///
/// Формы ответа и правила разбора — в `EntitySyncPolicy.swift`: там нет ни
/// БД, ни сети, поэтому их проверяют без симулятора.
public extension APIClient {

    /// `GET /api/sync/changes?since=<курсор>` — что изменилось с курсора.
    ///
    /// Старый сервер такой ручки не знает и отвечает 404 — клиент на это
    /// возвращается к прежнему пути (перечитывание списков целиком), чтобы
    /// не сломаться против сервера без дельты.
    func entityChanges(since: String?) async throws -> EntitySyncDelta {
        var query: [URLQueryItem] = []
        if let since { query.append(URLQueryItem(name: "since", value: since)) }
        return try await request(
            .get,
            "/sync/changes",
            query: query,
            timeout: Self.localSyncTimeout
        )
    }
}
