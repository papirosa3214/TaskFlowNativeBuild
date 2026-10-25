import Foundation

/// Диагностика окна чата: короткие строки пишутся в файл рядом с данными
/// приложения, чтобы их можно было забрать с телефона без root и без Xcode:
///
///     xcrun devicectl device copy from --device <udid> \
///         --domain-type appDataContainer \
///         --domain-identifier com.maksim.taskflow.native \
///         --source "Library/Application Support/chat-feed.log" \
///         --destination /tmp/
///
/// Пишется только в отладочной сборке: в обычной приложении файл не нужен.
enum ChatFeedDiagnostics {
    private static let fileName = "chat-feed.log"
    private static let sizeLimit = 256 * 1024

    /// Записать строку в лог и в системный лог устройства.
    static func log(_ message: String) {
        #if DEBUG
        NSLog("[TaskFlow] %@", message)
        let line = message + "\n"
        guard let data = line.data(using: .utf8) else { return }
        let url = fileURL()
        do {
            let manager = FileManager.default
            if !manager.fileExists(atPath: url.path) {
                try manager.createDirectory(at: url.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
                manager.createFile(atPath: url.path, contents: nil)
            }
            if let size = try? manager.attributesOfItem(atPath: url.path)[.size] as? Int,
               size > sizeLimit {
                // Старое стираем — файл нужен только для последнего разбора.
                try? manager.removeItem(at: url)
                manager.createFile(atPath: url.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } catch {
            // Диагностика не должна ломать чат.
        }
        #else
        _ = message
        #endif
    }

    private static func fileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent(fileName)
    }
}
