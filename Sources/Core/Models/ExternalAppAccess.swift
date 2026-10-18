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
