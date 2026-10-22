import Foundation

/// Контракт канала команд устройству `device_op` (сервер → телефон).
///
/// Источник истины — заметка «Контракт канала команд устройству device_op»
/// (ffaf800d-19ad-40e7-8616-9482019f432e) и `server/src/device/protocol.ts`.
/// Сервер шлёт команду, телефон отвечает `device_op_result` ровно один раз
/// на `opId` и никогда не начинает диалог сам.
public enum DeviceOpProtocol {
    /// Версия контракта. Команда с версией выше — ответ `version_unsupported`.
    public static let version = 1

    /// Операции устройства (§3 контракта). Удаления здесь нет намеренно:
    /// стирать напоминания Помощнику недоступно.
    public static let knownOps: Set<String> = [
        "reminder.list",
        "reminder.create",
        "reminder.complete",
        "reminder.reschedule",
        "calendar.events",
        "calendar.event.create",
        "calendar.event.update",
    ]
}

/// Коды ошибок контракта, которые выбирает телефон (§4).
public enum DeviceOpErrorCode: String, Sendable {
    case opUnknown = "op_unknown"
    case invalidArguments = "invalid_arguments"
    case accessDenied = "access_denied"
    case notFound = "not_found"
    case versionUnsupported = "version_unsupported"
    case internalError = "internal"
}

/// Команда сервера: одна операция устройства с аргументами.
public struct DeviceOpRequest: Decodable, Sendable {
    public let v: Int?
    public let opId: String
    public let op: String
    public let arguments: [String: JSONValue]

    public init(v: Int?, opId: String, op: String, arguments: [String: JSONValue] = [:]) {
        self.v = v
        self.opId = opId
        self.op = op
        self.arguments = arguments
    }

    private enum CodingKeys: String, CodingKey {
        case v, opId, op, arguments
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        v = try c.decodeIfPresent(Int.self, forKey: .v)
        opId = try c.decode(String.self, forKey: .opId)
        op = try c.decode(String.self, forKey: .op)
        arguments = try c.decodeIfPresent([String: JSONValue].self, forKey: .arguments) ?? [:]
    }
}

/// Тело ошибки в ответе устройства.
public struct DeviceOpErrorPayload: Encodable, Sendable {
    public let code: String
    public let message: String
}

/// Ответ телефона: успех — `data`, отказ — код и текст.
public struct DeviceOpResultMessage: Encodable, Sendable {
    public let type = "device_op_result"
    public let v = DeviceOpProtocol.version
    public let opId: String
    public let ok: Bool
    public let data: JSONValue?
    public let error: DeviceOpErrorPayload?

    public init(opId: String, outcome: DeviceOpOutcome) {
        self.opId = opId
        switch outcome {
        case .success(let value):
            ok = true
            data = value
            error = nil
        case .failure(let code, let message):
            ok = false
            data = nil
            error = DeviceOpErrorPayload(code: code.rawValue, message: message)
        }
    }

    /// Текст кадра для отправки по сокету.
    public func encoded() -> String {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(self), let text = String(data: data, encoding: .utf8) else {
            return "{\"type\":\"device_op_result\",\"v\":1,\"opId\":\"\(opId)\",\"ok\":false,\"error\":{\"code\":\"internal\",\"message\":\"не удалось собрать ответ\"}}"
        }
        return text
    }
}

/// Итог операции устройства: успех с данными или отказ с кодом контракта.
public enum DeviceOpOutcome: Sendable {
    case success(JSONValue)
    case failure(code: DeviceOpErrorCode, message: String)
}

extension JSONValue {
    /// Текстовое значение поля (nil, если поле не строка).
    public var text: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    /// Числовое значение поля (nil, если поле не число).
    public var double: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    /// Логическое значение поля (nil, если поле не логическое).
    public var flag: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }
}
