import Foundation

/// Internal document references are handled by app navigation, never by iOS openURL.
enum ChatMaterialDestination: Equatable {
    case note(String)
    case task(String)
    case web(URL)

    static func resolve(_ reference: String, kind: String = "document") -> Self? {
        let value = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        // Compatibility with documents sent before roles returned note:// links.
        if ["document", "artifact"].contains(kind), UUID(uuidString: value) != nil { return .note(value) }
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased() else { return nil }
        if ["http", "https"].contains(scheme), let host = url.host, !host.isEmpty { return .web(url) }
        guard ["note", "task"].contains(scheme), let id = url.host,
              UUID(uuidString: id) != nil, url.path.isEmpty || url.path == "/",
              url.query == nil, url.fragment == nil, url.user == nil, url.port == nil else { return nil }
        return scheme == "note" ? .note(id) : .task(id)
    }
}
