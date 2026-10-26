import Foundation

/// Кусок ответа в чате, уже разобранный сервером (`server/src/lib/chatBlocks.ts`,
/// 26.10.2026): клиент рисует его, а текст ответа сам не раскладывает.
///
/// • `doc` — обычный текст как документ TipTap (тот же формат, что у заметок);
/// • `table` — таблица: заголовок и строки ячеек TipTap, выравнивание колонок;
/// • `widget`, `structuredJSON`, `html` — блоки ```widget, ```tf-json, ```html;
/// • `structuredJSONStreaming`, `pending` — такой блок ещё дописывается;
/// • `unknown` — тип, которого этот клиент не знает (новый сервер): пропускаем.
public enum ChatServerBlock: Decodable, Sendable, Equatable {
    case doc(JSONValue, chars: Int)
    case table(header: [JSONValue], align: [String], rows: [[JSONValue]], chars: Int)
    case widget(String)
    case structuredJSON(String)
    case structuredJSONStreaming(String)
    case html(String)
    case pending(String)
    case unknown

    private enum CodingKeys: String, CodingKey {
        case type, doc, chars, header, align, rows, json, html, kind
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decodeIfPresent(String.self, forKey: .type) {
        case "doc":
            self = .doc(try c.decode(JSONValue.self, forKey: .doc),
                        chars: try c.decodeIfPresent(Int.self, forKey: .chars) ?? 0)
        case "table":
            self = .table(header: try c.decode([JSONValue].self, forKey: .header),
                          align: try c.decodeIfPresent([String].self, forKey: .align) ?? [],
                          rows: try c.decode([[JSONValue]].self, forKey: .rows),
                          chars: try c.decodeIfPresent(Int.self, forKey: .chars) ?? 0)
        case "widget": self = .widget(try c.decode(String.self, forKey: .json))
        case "structured_json": self = .structuredJSON(try c.decode(String.self, forKey: .json))
        case "structured_json_streaming": self = .structuredJSONStreaming(try c.decode(String.self, forKey: .json))
        case "html": self = .html(try c.decode(String.self, forKey: .html))
        case "pending": self = .pending(try c.decode(String.self, forKey: .kind))
        default: self = .unknown
        }
    }
}
