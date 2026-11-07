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
    @State private var showsDetails = false
    @State private var contextDetent: PresentationDetent = .medium

    var body: some View {
        contextRingButton
            .tfSheet(isPresented: $showsDetails) { contextSheet }
    }

    /// Кольцо в ряду ярлычков (владелец 26.10.2026): заполняется по мере
    /// расхода окна — белое, жёлтое, красное; нажатие — расшифровка листом.
    ///
    /// Кнопка и шторка вынесены в отдельные свойства намеренно: единая цепочка
    /// модификаторов не успевала type-check'иться на CI («the compiler is unable
    /// to type-check this expression in reasonable time», `ChatComposerControlsView.swift:60`).
    /// Вид не меняется — те же элементы, тот же порядок.
    private var contextRingButton: some View {
        Button { contextDetent = .medium; showsDetails = true } label: {
            ChatContextRing(fraction: snapshot?.fraction ?? 0)
                .frame(width: 20, height: 20)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Контекст" + (roleName.map { ", " + $0 } ?? "") + ". " + (snapshot?.summary ?? "Нет замера"))
        .accessibilityHint("Показать, из чего состоит контекст")
        .accessibilityIdentifier("chat.context-window")
        .hintAnchor(HintAnchorID.chatContextWindow)
    }

    /// Содержимое шторки с расшифровкой окна контекста.
    private var contextSheet: some View {
        ChatContextSheet(snapshot: snapshot, roleName: roleName, loadError: loadError, onRefresh: onRefresh)
            .presentationDetents([.medium, .large], selection: $contextDetent)
            .presentationDragIndicator(.visible)
    }
}

/// Кольцо заполнения окна: дорожка и дуга по доле; цвет — по порогам.
struct ChatContextRing: View {
    let fraction: Double

    private var color: Color {
        fraction >= 0.85 ? .red : fraction >= 0.6 ? .yellow : .primary
    }

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.2), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: min(1, max(0, fraction)))
                .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .accessibilityHidden(true)
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
    var roleName: String? = nil
    let loadError: String?
    let onRefresh: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: TFSpacing.sm) {
                        Text(snapshot?.summary ?? "Контекст пока недоступен")
                            .tfText(.body).monospacedDigit()
                            .foregroundStyle(Color.tfText)
                        if let snapshot, snapshot.fraction != nil {
                            ChatContextBar(snapshot: snapshot).frame(height: 12)
                        }
                        if let snapshot, snapshot.shouldConsiderReset {
                            Text("Окно заполнено на 85% или больше: можно сжать или начать новую сессию.")
                                .tfText(.meta).foregroundStyle(Color.tfOrange)
                        }
                    }
                    .padding(.vertical, TFSpacing.xs)
                    .tfSettingsListRow()
                }
                if let snapshot, let breakdown = snapshot.breakdown, let window = snapshot.contextWindow, window > 0 {
                    Section {
                        ForEach(breakdown.parts.filter { $0.tokens > 0 }) { part in
                            row(color: ChatContextPalette.color(part.id), title: part.title, tokens: part.tokens, window: window)
                        }
                        row(color: Color.tfStroke, title: "Свободно",
                            tokens: max(0, window - (snapshot.tokens ?? 0)), window: window)
                    } header: {
                        Text("Из чего состоит")
                            .tfText(.title)
                            .foregroundStyle(Color.tfSub)
                    }
                }
                if let snapshot {
                    Section {
                        if let model = snapshot.model { detailRow("Модель", value: model) }
                        if let provider = snapshot.provider {
                            detailRow("Провайдер", value: RoleModelOption.providerNames[provider.lowercased()] ?? provider)
                        }
                        if let measuredAt = snapshot.measuredAt {
                            detailRow("Замер", value: RoleChatTime.date(measuredAt)?.formatted(date: .omitted, time: .shortened) ?? measuredAt)
                        }
                    } footer: {
                        Text(snapshot.isEstimate ? "Части — оценка по тексту; итог — по последнему ответу модели." : "Итог — по последнему ответу модели.")
                            .tfText(.caption)
                            .foregroundStyle(Color.tfSub)
                    }
                }
                if let loadError {
                    Section {
                        Text(loadError)
                            .tfText(.body)
                            .foregroundStyle(Color.tfSub)
                            .tfSettingsListRow()
                    }
                }
                Section {
                    Button("Обновить", systemImage: "arrow.clockwise", action: onRefresh)
                        .tfText(.body)
                        .foregroundStyle(Color.tfText)
                        .frame(minHeight: 40)
                        .buttonStyle(.plain)
                        .tfSettingsListRow()
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .listSectionSpacing(TFSpacing.sm)
            .environment(\.defaultMinListRowHeight, 40)
            .tfScreenBackground()
            .navigationTitle(roleName.map { "Контекст · " + $0 } ?? "Контекст")
            .navigationBarTitleDisplayMode(.inline)
        }
        .environment(\.tfTypeSettingsEnabled, true)
    }

    private func row(color: Color, title: String, tokens: Int, window: Int) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.xs) {
            HStack(spacing: TFSpacing.sm) {
                Text(title).foregroundStyle(Color.tfText)
                Spacer()
                Text(ChatContextSnapshot.compact(tokens) + " · " + (Double(tokens) / Double(window)).formatted(.percent.precision(.fractionLength(0...1))))
                    .monospacedDigit()
                    .foregroundStyle(Color.tfSub)
            }
            // Полоска доли вместо точки (владелец 26.10.2026).
            ProgressView(value: min(1, Double(tokens) / Double(window)))
                .tint(color)
                .accessibilityHidden(true)
        }
        .tfText(.body)
        .padding(.vertical, TFSpacing.xs)
        .tfSettingsListRow()
        .accessibilityElement(children: .combine)
    }

    private func detailRow(_ title: String, value: String) -> some View {
        HStack(spacing: TFSpacing.sm) {
            Text(title).foregroundStyle(Color.tfText)
            Spacer(minLength: TFSpacing.sm)
            Text(value)
                .foregroundStyle(Color.tfSub)
                .multilineTextAlignment(.trailing)
        }
        .tfText(.body)
        .frame(minHeight: 40)
        .tfSettingsListRow()
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
                        ChatCommandCard(command: command)
                            .padding(.horizontal, TFSpacing.md)
                            .padding(.vertical, TFSpacing.sm)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxHeight: 220)
        .tfScreenBackground()
        .accessibilityIdentifier("chat.slash-suggestions")
    }
}

/// Карточка навыка или инструмента (владелец 27.10.2026): значок, понятное
/// название белым и что делает в двух словах. Без `/skill:` и английских
/// имён — подробности на экране «Подробнее».
struct ChatCommandCard: View {
    let command: ChatSlashCommand

    var body: some View {
        HStack(spacing: TFSpacing.md) {
            Image(systemName: command.cardIcon)
                .tfTypeFont(size: 16, weight: .medium)
                .foregroundStyle(Color.tfText)
                .frame(width: 34, height: 34)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(command.title)
                    .tfText(.row)
                    .foregroundStyle(Color.tfText)
                    .lineLimit(1)
                Text(command.cardSummary)
                    .tfText(.caption)
                    .foregroundStyle(Color.tfSub)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// «Подробнее»: полное описание и кнопка «Использовать».
private struct ChatCommandDetailScreen: View {
    let command: ChatSlashCommand
    let onUse: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TFSpacing.lg) {
                HStack(spacing: TFSpacing.md) {
                    Image(systemName: command.cardIcon)
                        .tfTypeFont(size: 24, weight: .medium)
                        .foregroundStyle(Color.tfText)
                        .frame(width: 52, height: 52)
                        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(command.title).tfText(.taskTitle).foregroundStyle(Color.tfText)
                        Text(command.kind == "skill" ? "Навык" : "Инструмент")
                            .tfText(.meta)
                            .foregroundStyle(Color.tfSub)
                    }
                }
                Text(command.description)
                    .tfText(.body)
                    .foregroundStyle(Color.tfText)
                    .textSelection(.enabled)
                TFButton("Использовать", icon: "text.insert", variant: .secondary, action: onUse)
            }
            .padding(TFSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .tfNativeHeader("Подробнее", displayMode: .inline)
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
        commands.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.cardSummary.localizedCaseInsensitiveContains(query) || $0.invocation.localizedCaseInsensitiveContains(query) || $0.description.localizedCaseInsensitiveContains(query) }
    }
    private var skills: [ChatSlashCommand] { filtered.filter { $0.kind == "skill" } }
    private var tools: [ChatSlashCommand] { filtered.filter { $0.kind != "skill" } }

    var body: some View {
        NavigationStack {
            Group {
                if commands.isEmpty {
                    TFEmptyState(
                        icon: "slash.circle",
                        text: "Команды недоступны",
                        description: errorText ?? "Выберите личный чат агента с доступными навыками и инструментами.",
                        actionTitle: "Обновить",
                        action: onRefresh
                    )
                } else if filtered.isEmpty {
                    TFEmptyState(search: query)
                } else {
                    List {
                        if !skills.isEmpty { section("Навыки", skills) }
                        if !tools.isEmpty { section("Инструменты", tools) }
                    }
                }
            }
            .navigationTitle("Навыки и инструменты")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Название команды")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
    }

    private func section(_ title: String, _ items: [ChatSlashCommand]) -> some View {
        Section(title) {
            ForEach(items) { command in
                NavigationLink {
                    ChatCommandDetailScreen(command: command) {
                        onSelect(command)
                        dismiss()
                    }
                } label: {
                    ChatCommandCard(command: command)
                }
            }
        }
    }
}
