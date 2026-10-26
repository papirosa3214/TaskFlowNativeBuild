import Foundation

/// Compatibility at the display boundary; stored workflow prefixes remain unchanged.
enum TaskRoleContent {
    private final class Entry: NSObject {
        let json: String?
        init(_ json: String?) { self.json = json }
    }
    private static let cache: NSCache<NSString, Entry> = {
        let cache = NSCache<NSString, Entry>()
        cache.countLimit = 128
        return cache
    }()
    static func json(in text: String) -> String? {
        if let value = cache.object(forKey: text as NSString) { return value.json }
        let value = decode(text)
        cache.setObject(Entry(value), forKey: text as NSString)
        return value
    }
    private static func decode(_ text: String) -> String? {
        var source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if source.hasPrefix("```tf-json\n"), source.hasSuffix("```") {
            source = String(source.dropFirst(11).dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if source.hasPrefix("{"), let data = source.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           object["schema_version"] as? Int == 1,
           object["ok"] is Bool, object["output"] is [[String: Any]] { return source }
        let prefixes = ["changes_requested:", "Ревьюер вернул на доработку:"]
        guard let prefix = prefixes.first(where: { source.hasPrefix($0) }) else { return nil }
        let body = source.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = body.data(using: .utf8),
              let defects = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              !defects.isEmpty,
              defects.allSatisfy({ ($0["observation"] as? String)?.isEmpty == false }) else { return nil }
        let blocks: [[String: Any]] = [["type":"heading", "text":"Нужна доработка", "level":2]] + defects.map { defect in
            let title = [defect["id"], defect["priority"]].compactMap { $0 as? String }.joined(separator: " · ")
            let text = [title, defect["observation"] as? String, defect["location"] as? String]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
            return ["type":"text", "text":text]
        }
        let envelope: [String: Any] = ["schema_version":1, "ok":true, "output":blocks,
            "artifacts":[], "plan_artifact":NSNull(), "error":NSNull(), "next_hint":NSNull()]
        guard let encoded = try? JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys]) else { return nil }
        return String(data: encoded, encoding: .utf8)
    }
}
