import SwiftUI

struct BashCommandBlock: View {
    let command: String
    @State private var confirming = false
    @State private var running = false
    @State private var result: OwnerCommandResult?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            ScrollView(.horizontal) {
                Text(command).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
            }
            if running {
                HStack { ProgressView(); Text("Выполняется на .110…") }
            } else {
                Button { confirming = true } label: {
                    Label(result == nil ? "Запустить на .110" : "Запустить ещё раз", systemImage: "play.fill")
                }
                .accessibilityIdentifier("chat-command-play")
            }
            if let result {
                Text(result.outcome == "timeout" ? "Время ожидания истекло" : "Код завершения: \(result.exitCode.map(String.init) ?? "—")")
                    .font(.caption)
                    .accessibilityIdentifier("chat-command-result")
                if !result.stdout.isEmpty { output(result.stdout) }
                if !result.stderr.isEmpty { output(result.stderr) }
                if let message = result.error { Text(message).foregroundStyle(Color.tfCoral) }
            }
            if let error { Text(error).foregroundStyle(Color.tfCoral) }
        }
        .padding(TFSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tfCard, in: RoundedRectangle(cornerRadius: TFRadius.md))
        .sheet(isPresented: $confirming) {
            NavigationStack {
                Form {
                    Section("Команда на сервере .110") {
                        Text(command).font(.system(.body, design: .monospaced)).textSelection(.enabled)
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
                                do { result = try await APIClient().runOwnerCommand(command) }
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
            Text(text).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
        }
    }
}
