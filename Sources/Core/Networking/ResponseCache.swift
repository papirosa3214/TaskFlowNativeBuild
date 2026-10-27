import CryptoKit
import Foundation

/// Последние ответы GET-запросов — в памяти и на диске (папка Caches).
///
/// Экран открывается сразу с прошлыми данными (`APIClient.cached`), а
/// свежие подставляет, когда придёт сеть. Пишет сюда сам `APIClient` на
/// каждый успешный GET; любой запрос записи и 401 кэш очищают — устаревшее
/// после правки не показывается. Система может сама почистить Caches при
/// нехватке места — это нормально, тогда экран просто ждёт сеть, как раньше.
final class ResponseCache: @unchecked Sendable {
    static let shared = ResponseCache(
        directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("api-responses", isDirectory: true)
    )

    private let directory: URL
    private var memory: [String: Data] = [:]
    private let lock = NSLock()

    init(directory: URL) {
        self.directory = directory
    }

    /// Ключ не зависит от порядка параметров запроса.
    static func key(path: String, query: [URLQueryItem]) -> String {
        let items = query
            .map { "\($0.name)=\($0.value ?? "")" }
            .sorted()
            .joined(separator: "&")
        return items.isEmpty ? path : "\(path)?\(items)"
    }

    func data(for key: String) -> Data? {
        lock.withLock {
            if let data = memory[key] { return data }
            guard let data = try? Data(contentsOf: fileURL(for: key)) else { return nil }
            memory[key] = data
            return data
        }
    }

    func store(_ data: Data, for key: String) {
        lock.withLock {
            memory[key] = data
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? data.write(to: fileURL(for: key), options: .atomic)
        }
    }

    func removeAll() {
        lock.withLock {
            memory.removeAll()
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private func fileURL(for key: String) -> URL {
        let name = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name)
    }
}
