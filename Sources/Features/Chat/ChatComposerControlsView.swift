import SwiftUI
import Observation

@MainActor
@Observable
final class ChatComposerControlStore {
    private(set) var contexts: [String: ChatContextSnapshot] = [:]
    private(set) var commands: [ChatSlashCommand] = []
    private(set) var errorText: String?
    private let api = APIClient()
    private var requestRevision = 0

    func load(chat: RoleChat) async {
        requestRevision += 1
        let revision = requestRevision
        contexts = [:]
        commands = []
        errorText = nil
        let roles = chat.members.filter { $0.roleKey != nil || $0.id == "u-secretary" || $0.id.hasPrefix("role_") }
        var next: [String: ChatContextSnapshot] = [:]
        var nextCommands: [ChatSlashCommand] = []
        var failure: String?
        for role in roles {
            do {
                let value = try await api.chatComposerControls(chatID: chat.id, roleID: role.id)
                next[role.id] = value.context
                if roles.count == 1 { nextCommands = value.commands }
            } catch {
                failure = error.localizedDescription
            }
        }
        guard revision == requestRevision else { return }
        contexts = next
        commands = nextCommands
        errorText = failure
    }
}

struct ChatContextControl: View {
    let snapshot: ChatContextSnapshot?
    let roleName: String?
    let loadError: String?
    let onRefresh: () -> Void
    let onNewSession: (() -> Void)?
    let onCompact: (() -> Void)?

    var body: some View {
        Menu {
            Text(snapshot?.summary ?? "Контекст пока недоступен")
            if let snapshot {
                if let provider = snapshot.provider { Text("Провайдер: " + provider) }
                if let model = snapshot.model { Text("Модель: " + model) }
                if let measuredAt = snapshot.measuredAt {
                    Text("Последний замер: " + (RoleChatTime.date(measuredAt)?.formatted(date: .abbreviated, time: .standard) ?? measuredAt))
                }
                Text(snapshot.isEstimate ? "Размер окна оценён Pi; новый текст ещё не учтён." : "Размер на последнем запросе; новый текст ещё не учтён.")
                if snapshot.shouldConsiderReset { Text("Окно заполнено на 85% или больше. Можно сжать или начать новую сессию.") }
            }
            if let loadError { Text(loadError) }
            Button("Обновить", systemImage: "arrow.clockwise", action: onRefresh)
            if let onCompact { Button("Сжать контекст", systemImage: "arrow.down.right.and.arrow.up.left", action: onCompact) }
            if let onNewSession { Button("Новая сессия", systemImage: "arrow.counterclockwise", action: onNewSession) }
        } label: {
            HStack(spacing: TFSpacing.xs) {
                if let roleName { Text(roleName).lineLimit(1) }
                Text(snapshot?.summary ?? "Контекст пока недоступен")
                    .monospacedDigit().lineLimit(1)
                Image(systemName: "chevron.down")
            }
            .tfText(.caption)
            .foregroundStyle(Color.tfSub)
        }
        .accessibilityLabel("Контекст. " + (snapshot?.summary ?? "Нет замера"))
        .accessibilityIdentifier("chat.context-window")
        .hintAnchor(HintAnchorID.chatContextWindow)
    }
}

struct ChatSlashSuggestions: View {
    let commands: [ChatSlashCommand]
    let onSelect: (ChatSlashCommand) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(commands) { command in
                    Button { onSelect(command) } label: {
                        VStack(alignment: .leading, spacing: TFSpacing.xs) {
                            HStack {
                                Text(command.invocation.trimmingCharacters(in: .whitespacesAndNewlines))
                                Spacer()
                                Text(command.kindTitle).foregroundStyle(Color.tfSub)
                            }
                            Text(command.description).tfText(.caption).foregroundStyle(Color.tfSub).lineLimit(2)
                        }
                        .tfText(.body)
                        .foregroundStyle(Color.tfText)
                        .padding(TFSpacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxHeight: 220)
        .background(Color.tfBackground)
        .accessibilityIdentifier("chat.slash-suggestions")
    }
}

struct ChatCommandPicker: View {
    let commands: [ChatSlashCommand]
    let errorText: String?
    let onRefresh: () -> Void
    let onSelect: (ChatSlashCommand) -> Void
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    private var filtered: [ChatSlashCommand] {
        commands.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.invocation.localizedCaseInsensitiveContains(query) || $0.description.localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        NavigationStack {
            Group {
                if commands.isEmpty {
                    ContentUnavailableView {
                        Label("Команды недоступны", systemImage: "slash.circle")
                    } description: {
                        Text(errorText ?? "Выберите личный чат агента с доступными навыками и инструментами.")
                    } actions: { Button("Обновить", action: onRefresh) }
                } else if filtered.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List(filtered) { command in
                        Button {
                            onSelect(command)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: TFSpacing.xs) {
                                Text(command.invocation).tfText(.body)
                                Text(command.description).tfText(.caption).foregroundStyle(Color.tfSub)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Навыки и инструменты")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Название команды")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
    }
}
