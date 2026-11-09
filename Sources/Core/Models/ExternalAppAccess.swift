import Foundation

/// Ответ существующей операции хоста; содержимое дел остаётся за пределами UI.
struct ThingsAccessProbe: Decodable {
    struct Data: Decodable {
        let ok: Bool?
        let result: String?
    }
    let ok: Bool
    let data: Data?
    let error: String?

    var readAvailable: Bool {
        guard ok, data?.ok == true,
              let result = data?.result, let bytes = result.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: bytes),
              value is [Any] else { return false }
        return true
    }
}

/// Ответ `/api/integrations/wealthfolio`: отвечает ли финансовый трекер на .110
/// и сколько действий он даёт Помощнику владельца. Адрес и токен сервер наружу
/// отдаёт только для диагностики — в интерфейсе он не нужен.
struct WealthfolioAccessProbe: Decodable {
    let connected: Bool
    let url: String?
    let toolCount: Int?
    let error: String?
}

/// Ответ `/api/integrations/changedetection`: отвечает ли MCP слежения за
/// страницами на .110 и сколько действий он даёт ролям. Адрес нужен только
/// диагностике — в интерфейсе не показывается.
struct ChangedetectionAccessProbe: Decodable {
    let connected: Bool
    let url: String?
    let toolCount: Int?
    let error: String?
}
