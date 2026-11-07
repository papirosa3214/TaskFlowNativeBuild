import SwiftUI

struct BashCommandBlock: View {
    let command: String
    @State private var confirming = false
    @State private var running = false
    @State private var result: OwnerCommandResult?
    @State private var error: String?

    var body: some View {
        // Тёмная подложка и тёмно-красная рамка, как у виджетов (владелец 06.11.2026).
        TFCard(padding: TFSpacing.md, surface: .dark, radius: TFRadius.md) {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            ScrollView(.horizontal) {
                Text(command).tfChatText(.mono).textSelection(.enabled)
            }
            if running {
                TFLoading(.inline)
            } else {
                Button { confirming = true } label: {
                    Label(result == nil ? "Запустить на .110" : "Запустить ещё раз", systemImage: "play.fill")
                }
                .accessibilityIdentifier("chat-command-play")
            }
            if let result {
                Text(result.outcome == "timeout" ? "Время ожидания истекло" : "Код завершения: \(result.exitCode.map(String.init) ?? "—")")
                    .tfText(.meta)
                    .accessibilityIdentifier("chat-command-result")
                if !result.stdout.isEmpty { output(result.stdout) }
                if !result.stderr.isEmpty { output(result.stderr) }
                if let message = result.error { Text(message).foregroundStyle(Color.tfCoral) }
            }
            if let error { Text(error).foregroundStyle(Color.tfCoral) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Вывод прошлого запуска возвращается после повторного открытия чата.
        .onAppear { if result == nil && !running { result = OwnerCommandResultStore.load(command) } }
        .tfSheet(isPresented: $confirming) {
            NavigationStack {
                Form {
                    Section("Команда на сервере .110") {
                        Text(command).tfChatText(.mono).textSelection(.enabled)
                    }
                    Section {
                        Button("Выполнить на .110") {
                            confirming = false
                            guard !running else { return }
                            running = true
                            result = nil
                            error = nil
                            Task {
                                defer { running = false }
                                do {
                                    let fresh = try await APIClient().runOwnerCommand(command)
                                    result = fresh
                                    OwnerCommandResultStore.save(fresh, for: command)
                                }
                                catch { self.error = error.localizedDescription }
                            }
                        }
                        .accessibilityIdentifier("chat-command-confirm")
                        .disabled(running)
                    }
                }
                .navigationTitle("Запуск команды")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Отмена") { confirming = false } } }
            }
        }
    }
    private func output(_ text: String) -> some View {
        ScrollView(.horizontal) {
            Text(text).tfChatText(.mono, scale: TFChatTypeGroup.meta.baseSize / TFChatTypeGroup.mono.baseSize).textSelection(.enabled)
        }
    }
}

/// Последний вывод каждой команды на устройстве. Блок в ленте знает только
/// текст команды, поэтому ключ — он: одна и та же команда в двух сообщениях
/// показывает один и тот же последний результат.
enum OwnerCommandResultStore {
    private struct Entry: Codable {
        let command: String
        let result: OwnerCommandResult
    }

    private static let key = "chat.commandResults"
    private static let limit = 40
    private static let outputLimit = 20_000

    static func load(_ command: String) -> OwnerCommandResult? {
        entries().last { $0.command == command }?.result
    }

    static func save(_ result: OwnerCommandResult, for command: String) {
        let stored = OwnerCommandResult(
            outcome: result.outcome,
            exitCode: result.exitCode,
            stdout: String(result.stdout.prefix(outputLimit)),
            stderr: String(result.stderr.prefix(outputLimit)),
            durationMs: result.durationMs,
            requestId: result.requestId,
            error: result.error
        )
        var all = entries().filter { $0.command != command }
        all.append(Entry(command: command, result: stored))
        if all.count > limit { all.removeFirst(all.count - limit) }
        guard let data = try? JSONEncoder().encode(all) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func entries() -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }
}
