import Foundation

/// Журнал телефона на сервере (владелец 06.11.2026: «почему ты до сих пор
/// этих журналов не насоздавал»). Строки о том, что чат получил по сокету и
/// как показал, копятся и раз в 2 с уходят на `POST /api/client-log`; сервер
/// пишет их рядом со своими `[ws-out]`, и обрыв видно по одному журналу.
@MainActor
final class ClientLog {
    static let shared = ClientLog()
    private var lines: [String] = []
    private var flushTask: Task<Void, Never>?
    private let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    func add(_ line: String) {
        guard lines.count < 400 else { return }
        lines.append(formatter.string(from: Date()) + " " + line)
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            await self?.flush()
        }
    }

    private func flush() async {
        let batch = lines
        lines.removeAll()
        flushTask = nil
        guard !batch.isEmpty else { return }
        struct Body: Encodable { let lines: [String] }
        struct Ok: Decodable { let ok: Bool }
        do {
            let _: Ok = try await APIClient().request(.post, "/client-log", body: Body(lines: batch))
        } catch {
            // Не дошло — строки не выбрасываем: вернуть в начало и дослать
            // следующей пачкой (с пометкой о сбое), а не молчать.
            lines = Array((batch + ["sendfail \(error.localizedDescription)"] + lines).suffix(400))
            if flushTask == nil {
                flushTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(5))
                    await self?.flush()
                }
            }
        }
    }
}
