import Foundation

/// JSON произвольной формы. Сессия Pi приходит деревом без схемы, поэтому
/// клиент хранит её как есть и разбирает те части, которые показывает.
///
/// 30.11.2026: разбор больше не идёт через \`Codable\`. Причина — падение при
/// открытии сессии: дерево Pi это цепочка \`children\`, по два контейнера на
/// запись, и \`JSONDecoder\` тратит ~4 КБ стека на уровень. На 222 уровнях это
/// ~900 КБ при 512 КБ у потока Swift Concurrency — SIGBUS в \`JSONValue.init(from:)\`.
/// Вдобавок \`JSONSerialization\` (и \`JSONDecoder\` на Darwin) отказывается
/// разбирать глубже 512 вложенных контейнеров, то есть сессия переставала
/// открываться уже на ~256 записях. Поэтому ниже — свой разбор на явном стеке:
/// глубина ограничена только памятью, рекурсии нет.
public enum JSONValue: Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public static func parse(_ data: Data) throws -> JSONValue {
        var parser = JSONValueParser(data)
        return try parser.parseDocument()
    }

    public static func parse(_ text: String) throws -> JSONValue {
        try parse(Data(text.utf8))
    }
}

// MARK: - Доступ к содержимому

public extension JSONValue {
    /// Значение по ключу объекта. Для остальных ветвей — nil.
    subscript(key: String) -> JSONValue? {
        guard case let .object(object) = self else { return nil }
        return object[key]
    }

    var objectValue: [String: JSONValue]? {
        guard case let .object(value) = self else { return nil }
        return value
    }

    var arrayValue: [JSONValue]? {
        guard case let .array(value) = self else { return nil }
        return value
    }

    var stringValue: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }

    var boolValue: Bool? {
        guard case let .bool(value) = self else { return nil }
        return value
    }

    var doubleValue: Double? {
        guard case let .number(value) = self else { return nil }
        return value
    }

    var intValue: Int? {
        guard case let .number(value) = self, value.rounded() == value,
              value >= Double(Int.min), value <= Double(Int.max) else { return nil }
        return Int(value)
    }

    var isNull: Bool {
        if case .null = self { return true }
        return false
    }
}

// MARK: - Разбор

public enum JSONValueParseError: Error, Equatable, CustomStringConvertible {
    case unexpectedEnd
    case unexpectedByte(UInt8, offset: Int)
    case invalidString(offset: Int)
    case invalidNumber(String)
    case invalidLiteral(offset: Int)
    case trailingData(offset: Int)

    public var description: String {
        switch self {
        case .unexpectedEnd: "JSON закончился неожиданно."
        case let .unexpectedByte(byte, offset): "Неожиданный байт \(byte) в позиции \(offset)."
        case let .invalidString(offset): "Повреждённая строка в позиции \(offset)."
        case let .invalidNumber(text): "Повреждённое число: \(text)."
        case let .invalidLiteral(offset): "Неизвестный литерал в позиции \(offset)."
        case let .trailingData(offset): "Лишние данные после JSON в позиции \(offset)."
        }
    }
}

/// Разбор JSON на явном стеке контейнеров. Рекурсии нет, поэтому вложенность
/// дерева сессии (по два контейнера на запись) не ограничена глубиной стека.
struct JSONValueParser {
    private enum Frame {
        case array([JSONValue])
        case object([String: JSONValue], key: String?)
    }

    private let bytes: [UInt8]
    private var index = 0

    init(_ data: Data) {
        bytes = [UInt8](data)
    }

    mutating func parseDocument() throws -> JSONValue {
        var stack: [Frame] = []
        var pending: JSONValue?

        while true {
            if let value = pending {
                pending = nil
                if stack.isEmpty {
                    skipWhitespace()
                    guard index == bytes.count else { throw JSONValueParseError.trailingData(offset: index) }
                    return value
                }
                try attach(value, to: &stack)
                skipWhitespace()
                guard index < bytes.count else { throw JSONValueParseError.unexpectedEnd }
                switch bytes[index] {
                case UInt8(ascii: ","):
                    index += 1
                    try prepareNextElement(in: &stack)
                case UInt8(ascii: "]"):
                    guard case let .array(items) = stack[stack.count - 1] else {
                        throw JSONValueParseError.unexpectedByte(bytes[index], offset: index)
                    }
                    index += 1
                    stack.removeLast()
                    pending = .array(items)
                case UInt8(ascii: "}"):
                    guard case let .object(object, key) = stack[stack.count - 1], key == nil else {
                        throw JSONValueParseError.unexpectedByte(bytes[index], offset: index)
                    }
                    index += 1
                    stack.removeLast()
                    pending = .object(object)
                default:
                    throw JSONValueParseError.unexpectedByte(bytes[index], offset: index)
                }
                continue
            }

            skipWhitespace()
            guard index < bytes.count else { throw JSONValueParseError.unexpectedEnd }
            switch bytes[index] {
            case UInt8(ascii: "{"):
                index += 1
                skipWhitespace()
                if index < bytes.count, bytes[index] == UInt8(ascii: "}") {
                    index += 1
                    pending = .object([:])
                    continue
                }
                let key = try parseString()
                skipWhitespace()
                guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else {
                    throw JSONValueParseError.unexpectedEnd
                }
                index += 1
                stack.append(.object([:], key: key))
            case UInt8(ascii: "["):
                index += 1
                skipWhitespace()
                if index < bytes.count, bytes[index] == UInt8(ascii: "]") {
                    index += 1
                    pending = .array([])
                    continue
                }
                stack.append(.array([]))
            case UInt8(ascii: "\""):
                pending = .string(try parseString())
            case UInt8(ascii: "t"):
                try expectLiteral("true")
                pending = .bool(true)
            case UInt8(ascii: "f"):
                try expectLiteral("false")
                pending = .bool(false)
            case UInt8(ascii: "n"):
                try expectLiteral("null")
                pending = .null
            default:
                pending = .number(try parseNumber())
            }
        }
    }

    private mutating func attach(_ value: JSONValue, to stack: inout [Frame]) throws {
        switch stack[stack.count - 1] {
        case var .array(items):
            items.append(value)
            stack[stack.count - 1] = .array(items)
        case let .object(object, key):
            guard let key else { throw JSONValueParseError.invalidString(offset: index) }
            var updated = object
            updated[key] = value
            stack[stack.count - 1] = .object(updated, key: nil)
        }
    }

    /// После запятой: внутри объекта читаем ключ, внутри массива — ничего.
    private mutating func prepareNextElement(in stack: inout [Frame]) throws {
        guard case let .object(object, key) = stack[stack.count - 1], key == nil else { return }
        skipWhitespace()
        let name = try parseString()
        skipWhitespace()
        guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else {
            throw JSONValueParseError.unexpectedEnd
        }
        index += 1
        stack[stack.count - 1] = .object(object, key: name)
    }

    private mutating func skipWhitespace() {
        while index < bytes.count {
            switch bytes[index] {
            case 0x20, 0x09, 0x0A, 0x0D: index += 1
            default: return
            }
        }
    }

    private mutating func expectLiteral(_ literal: StaticString) throws {
        let literalBytes = Array(String(describing: literal).utf8)
        guard index + literalBytes.count <= bytes.count else { throw JSONValueParseError.unexpectedEnd }
        for (offset, byte) in literalBytes.enumerated() where bytes[index + offset] != byte {
            throw JSONValueParseError.invalidLiteral(offset: index + offset)
        }
        index += literalBytes.count
    }

    private mutating func parseNumber() throws -> Double {
        let start = index
        while index < bytes.count, Self.isNumberByte(bytes[index]) { index += 1 }
        let text = String(decoding: bytes[start..<index], as: UTF8.self)
        guard !text.isEmpty, let value = Double(text) else {
            throw JSONValueParseError.invalidNumber(text)
        }
        return value
    }

    private static func isNumberByte(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "-"), UInt8(ascii: "+"), UInt8(ascii: "."),
             UInt8(ascii: "e"), UInt8(ascii: "E"),
             UInt8(ascii: "0")...UInt8(ascii: "9"):
            true
        default:
            false
        }
    }

    private mutating func parseString() throws -> String {
        guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else {
            throw JSONValueParseError.invalidString(offset: index)
        }
        index += 1
        var buffer: [UInt8] = []
        var highSurrogate: UInt32?

        func flushSurrogate() {
            if highSurrogate != nil {
                buffer.append(contentsOf: Array("\u{FFFD}".utf8))
                highSurrogate = nil
            }
        }

        while index < bytes.count {
            let byte = bytes[index]
            if byte == UInt8(ascii: "\"") {
                flushSurrogate()
                index += 1
                return String(decoding: buffer, as: UTF8.self)
            }
            if byte == UInt8(ascii: "\\") {
                index += 1
                guard index < bytes.count else { throw JSONValueParseError.unexpectedEnd }
                let escape = bytes[index]
                index += 1
                switch escape {
                case UInt8(ascii: "\""): flushSurrogate(); buffer.append(0x22)
                case UInt8(ascii: "\\"): flushSurrogate(); buffer.append(0x5C)
                case UInt8(ascii: "/"): flushSurrogate(); buffer.append(0x2F)
                case UInt8(ascii: "b"): flushSurrogate(); buffer.append(0x08)
                case UInt8(ascii: "f"): flushSurrogate(); buffer.append(0x0C)
                case UInt8(ascii: "n"): flushSurrogate(); buffer.append(0x0A)
                case UInt8(ascii: "r"): flushSurrogate(); buffer.append(0x0D)
                case UInt8(ascii: "t"): flushSurrogate(); buffer.append(0x09)
                case UInt8(ascii: "u"):
                    let unit = try parseHexQuad()
                    if (0xD800...0xDBFF).contains(unit) {
                        flushSurrogate()
                        highSurrogate = unit
                    } else if (0xDC00...0xDFFF).contains(unit), let high = highSurrogate {
                        let scalar = 0x10000 + ((high - 0xD800) << 10) + (unit - 0xDC00)
                        highSurrogate = nil
                        if let unicode = UnicodeScalar(scalar) {
                            buffer.append(contentsOf: Array(String(Character(unicode)).utf8))
                        }
                    } else {
                        flushSurrogate()
                        if let unicode = UnicodeScalar(unit) {
                            buffer.append(contentsOf: Array(String(Character(unicode)).utf8))
                        }
                    }
                default:
                    throw JSONValueParseError.invalidString(offset: index)
                }
                continue
            }
            if byte < 0x20 { throw JSONValueParseError.invalidString(offset: index) }
            flushSurrogate()
            buffer.append(byte)
            index += 1
        }
        throw JSONValueParseError.unexpectedEnd
    }

    private mutating func parseHexQuad() throws -> UInt32 {
        guard index + 4 <= bytes.count else { throw JSONValueParseError.unexpectedEnd }
        var value: UInt32 = 0
        for _ in 0..<4 {
            let byte = bytes[index]
            let digit: UInt32
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): digit = UInt32(byte - UInt8(ascii: "0"))
            case UInt8(ascii: "a")...UInt8(ascii: "f"): digit = UInt32(byte - UInt8(ascii: "a") + 10)
            case UInt8(ascii: "A")...UInt8(ascii: "F"): digit = UInt32(byte - UInt8(ascii: "A") + 10)
            default: throw JSONValueParseError.invalidString(offset: index)
            }
            value = value << 4 | digit
            index += 1
        }
        return value
    }
}
