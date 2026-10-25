import Foundation

struct ServerSetting: Decodable, Identifiable, Sendable {
    let key: String
    let label: String
    let group: String
    let kind: String
    let defaultValue: JSONValue
    let min: Double?
    let max: Double?
    let options: [String]?
    let explanation: String?
    var id: String { key }
    enum CodingKeys: String, CodingKey {
        case key, label, group, kind, min, max, options
        case defaultValue = "default"
        case explanation = "description"
    }
    var unit: String {
        switch kind {
        case "duration_min": "мин"
        case "duration_sec": "с"
        case "duration_ms", "interval_ms": displayDivisor == 60_000 ? "мин" : "с"
        default: ""
        }
    }
    var displayDivisor: Double {
        guard kind == "duration_ms" || kind == "interval_ms" else { return 1 }
        if case .number(let value) = defaultValue, value >= 60_000, value.truncatingRemainder(dividingBy: 60_000) == 0 { return 60_000 }
        return 1_000
    }
    func displayNumber(_ value: Double) -> String {
        (value / displayDivisor).formatted(.number.grouping(.never).precision(.fractionLength(0...6)))
    }
    func displayText(_ value: JSONValue) -> String {
        if case .number(let number) = value {
            return displayNumber(number) + (unit.isEmpty ? "" : " " + unit)
        }
        return value.serverSettingText
    }
    func validatedNumber(_ text: String) throws -> JSONValue {
        guard let number = Double(text.replacingOccurrences(of: ",", with: ".")),
              number.isFinite else {
            throw SettingValidationError(message: "Введите число")
        }
        let storedNumber = number * displayDivisor
        guard storedNumber.isFinite else { throw SettingValidationError(message: "Введите число") }
        if kind == "int" && number.rounded() != number { throw SettingValidationError(message: "Введите целое число") }
        if let min, storedNumber < min { throw SettingValidationError(message: "Минимум: " + displayNumber(min) + (unit.isEmpty ? "" : " " + unit)) }
        if let max, storedNumber > max { throw SettingValidationError(message: "Максимум: " + displayNumber(max) + (unit.isEmpty ? "" : " " + unit)) }
        return .number(storedNumber)
    }
}
struct SettingValidationError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
struct ServerSettingsSnapshot: Decodable, Sendable {
    let settings: [ServerSetting]
    let values: [String: JSONValue]
    let updatedAt: [String: String]
    enum CodingKeys: String, CodingKey { case settings, values; case updatedAt = "updated_at" }
    var groups: [String] {
        let order = ["тишина", "перезапуски", "расписания", "снимки", "автоимпорт", "linear", "таймауты", "лимиты", "режим_приёма"]
        let actual = Set(settings.map(\.group))
        return order.filter(actual.contains) + actual.subtracting(order).sorted()
    }
}
struct ServerSettingLog: Decodable, Identifiable, Sendable {
    let id: Int
    let key: String
    let oldValue: String?
    let newValue: String
    let reason: String?
    let createdAt: String
    enum CodingKeys: String, CodingKey {
        case id, key, reason
        case oldValue = "old_value", newValue = "new_value", createdAt = "created_at"
    }
}
extension APIClient {
    func serverSettings() async throws -> ServerSettingsSnapshot {
        try await request(.get, "/admin/server-settings")
    }
    func updateServerSetting(key: String, value: JSONValue) async throws {
        struct Body: Encodable { let value: JSONValue; let reason: String }
        try await requestVoid(.put, "/admin/server-settings/\(key)", body: Body(value: value, reason: "Из настроек iPhone"))
    }
    func resetServerSetting(key: String) async throws {
        try await requestVoid(.post, "/admin/server-settings/\(key)/reset", body: ["reason": "Сброс из настроек iPhone"])
    }
    func serverSettingsLog() async throws -> [ServerSettingLog] {
        struct Envelope: Decodable { let log: [ServerSettingLog] }
        let result: Envelope = try await request(.get, "/admin/server-settings/log")
        return result.log
    }
}
extension JSONValue {
    var serverSettingText: String {
        switch self {
        case .bool(let value): value ? "Включено" : "Выключено"
        case .number(let value): value.formatted(.number.grouping(.never))
        case .string(let value):
            switch value { case "manual": "Вручную"; case "auto", "automatic": "Автоматически"; default: value }
        default: "—"
        }
    }
}
