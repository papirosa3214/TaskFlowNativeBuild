import Foundation

/// Адрес эндпоинта API.
///
/// Префикс `/api` добавляет клиент — в вызовах путь пишется без него
/// («/attention», а не «/api/attention»). С префиксом в вызове получалось
/// `/api/api/attention`, и сервер отвечал «не знаю такого запроса»
/// (владелец 29.10.2026).
public enum APIEndpoint {
    /// Адрес эндпоинта: база плюс `/api` плюс путь.
    public static func url(_ path: String, base: URL) -> URL {
        base.appendingPathComponent("/api" + path)
    }

    /// «Входящие» — три статуса на доске владельца.
    public enum attention {
        public static let list = "/attention"
    }
}
