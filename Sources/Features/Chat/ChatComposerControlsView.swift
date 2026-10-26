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
    @State private var showsDetails = false

    var body: some View {
        // Строка над полем ввода: итог и тонкая полоска; нажатие — расшифровка.
        Button { showsDetails = true } label: {
            HStack(spacing: TFSpacing.sm) {
                if let roleName { Text(roleName).lineLimit(1) }
                Text(snapshot?.summary ?? "Контекст пока недоступен")
                    .monospacedDigit().lineLimit(1)
                if let snapshot, snapshot.fraction != nil {
                    ChatContextBar(snapshot: snapshot).frame(width: 48, height: 4)
                }
                Image(systemName: "chevron.up")
            }
            .tfText(.caption)
            .foregroundStyle(Color.tfSub)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Контекст. " + (snapshot?.summary ?? "Нет замера"))
        .accessibilityHint("Показать, из чего состоит контекст")
        .accessibilityIdentifier("chat.context-window")
        .hintAnchor(HintAnchorID.chatContextWindow)
        // Как было: прозрачное всплывающее окно у самой строки, не отдельный лист.
        .popover(isPresented: $showsDetails, arrowEdge: .bottom) {
            ChatContextSheet(snapshot: snapshot, loadError: loadError, onRefresh: onRefresh,
                             onNewSession: onNewSession, onCompact: onCompact)
                .frame(minWidth: 300, idealWidth: 340, minHeight: 360, idealHeight: 460)
                .presentationCompactAdaptation(.popover)
                .presentationBackground(.ultraThinMaterial)
        }
    }
}

/// Цвет части контекста — один и тот же в полосе и в расшифровке.
enum ChatContextPalette {
    static func color(_ id: String) -> Color {
        switch id {
        case "system": Color.tfBlue
        case "tools": Color.tfPurple
        case "user": Color.tfGreen
        case "assistant": Color.tfOrange
        case "toolResults": Color.tfTeal
        default: Color.tfDim
        }
    }
}

/// Полоса заполнения окна: части по цветам, остаток — свободно.
struct ChatContextBar: View {
    let snapshot: ChatContextSnapshot

    var body: some View {
        GeometryReader { geo in
            let window = Double(max(snapshot.contextWindow ?? 1, 1))
            HStack(spacing: 0) {
                if let breakdown = snapshot.breakdown {
                    ForEach(breakdown.parts.filter { $0.tokens > 0 }) { part in
                        ChatContextPalette.color(part.id)
                            .frame(width: geo.size.width * min(1, Double(part.tokens) / window))
                    }
                } else if let fraction = snapshot.fraction {
                    Color.tfBlue.frame(width: geo.size.width * min(1, fraction))
                }
                Spacer(minLength: 0)
            }
            .background(Color.tfStroke)
            .clipShape(Capsule())
        }
    }
}

/// Расшифровка контекста (владелец 26.10.2026): из чего состоит окно и что с
/// ним можно сделать — сжать, начать новую сессию, обновить замер.
struct ChatContextSheet: View {
    let snapshot: ChatContextSnapshot?
    let loadError: String?
    let onRefresh: () -> Void
    let onNewSession: (() -> Void)?
    let onCompact: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: TFSpacing.sm) {
                        Text(snapshot?.summary ?? "Контекст пока недоступен")
                            .tfText(.title).monospacedDigit()
                        if let snapshot, snapshot.fraction != nil {
                            ChatContextBar(snapshot: snapshot).frame(height: 12)
                        }
                        if let snapshot, snapshot.shouldConsiderReset {
                            Text("Окно заполнено на 85% или больше: можно сжать или начать новую сессию.")
                                .tfText(.meta).foregroundStyle(Color.tfOrange)
                        }
                    }
                    .padding(.vertical, TFSpacing.xs)
                }
                if let snapshot, let breakdown = snapshot.breakdown, let window = snapshot.contextWindow, window > 0 {
                    Section("Из чего состоит") {
                        ForEach(breakdown.parts.filter { $0.tokens > 0 }) { part in
                            row(color: ChatContextPalette.color(part.id), title: part.title, tokens: part.tokens, window: window)
                        }
                        row(color: Color.tfStroke, title: "Свободно",
                            tokens: max(0, window - (snapshot.tokens ?? 0)), window: window)
                    }
                }
                if let snapshot {
                    Section {
                        if let model = snapshot.model { LabeledContent("Модель", value: model) }
                        if let provider = snapshot.provider {
                            LabeledContent("Провайдер", value: RoleModelOption.providerNames[provider.lowercased()] ?? provider)
                        }
                        if let measuredAt = snapshot.measuredAt {
                            LabeledContent("Замер", value: RoleChatTime.date(measuredAt)?.formatted(date: .omitted, time: .shortened) ?? measuredAt)
                        }
                    } footer: {
                        Text(snapshot.isEstimate ? "Части — оценка по тексту; итог — по последнему ответу модели." : "Итог — по последнему ответу модели.")
                    }
                }
                if let loadError { Section { Text(loadError).foregroundStyle(Color.tfSub) } }
                Section {
                    if let onCompact {
                        Button("Сжать контекст", systemImage: "arrow.down.right.and.arrow.up.left") { onCompact(); dismiss() }
                    }
                    if let onNewSession {
                        Button("Новая сессия", systemImage: "arrow.counterclockwise") { onNewSession(); dismiss() }
                    }
                    Button("Обновить", systemImage: "arrow.clockwise", action: onRefresh)
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Контекст")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func row(color: Color, title: String, tokens: Int, window: Int) -> some View {
        HStack(spacing: TFSpacing.sm) {
            Circle().fill(color).frame(width: 10, height: 10).accessibilityHidden(true)
            Text(title)
            Spacer()
            Text(ChatContextSnapshot.compact(tokens) + " · " + (Double(tokens) / Double(window)).formatted(.percent.precision(.fractionLength(0...1))))
                .monospacedDigit()
                .foregroundStyle(Color.tfSub)
        }
        .tfText(.body)
        .accessibilityElement(children: .combine)
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
