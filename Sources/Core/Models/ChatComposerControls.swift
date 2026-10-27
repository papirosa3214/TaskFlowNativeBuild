import Foundation

public struct RoleModelOption: Decodable, Identifiable, Hashable {
    public let id: String
    public let title: String
    public let provider: String?
    public let modelID: String?
    public let contextWindow: Int?

    /// Провайдер: из ответа сервера, а у старого ответа — из id вида
    /// «провайдер/модель». Имя — как его пишет сам провайдер.
    var providerTitle: String {
        let raw = (provider?.isEmpty == false ? provider : nil)
            ?? (id.contains("/") ? String(id.split(separator: "/", maxSplits: 1)[0]) : nil)
        guard let raw else { return "Другие" }
        return Self.providerNames[raw.lowercased()] ?? raw
    }
    static let providerNames: [String: String] = [
        "opencode-go": "OpenCode Go", "opencode": "OpenCode", "anthropic": "Anthropic",
        "openai": "OpenAI", "openai-codex": "OpenAI Codex", "minimax": "MiniMax",
        "google": "Google", "deepseek": "DeepSeek", "openrouter": "OpenRouter", "ollama": "Ollama",
    ]
    struct ProviderGroup: Identifiable {
        var id: String { provider }
        let provider: String
        let models: [RoleModelOption]
    }
    static func grouped(_ options: [Self]) -> [ProviderGroup] {
        Dictionary(grouping: options, by: \.providerTitle)
            .map { ProviderGroup(provider: $0.key, models: $0.value.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }) }
            .sorted { $0.provider.localizedStandardCompare($1.provider) == .orderedAscending }
    }
    static func resolveSelection(_ selected: String?, in options: [Self]) -> String? {
        guard let selected else { return nil }
        if options.contains(where: { $0.id == selected }) { return selected }
        let matches = options.filter { $0.modelID == selected }
        return matches.count == 1 ? matches[0].id : nil
    }
}

public enum RoleChatWorkMode: String, CaseIterable, Codable {
    case work, plan, goal, deepResearch = "deep_research"
    var title: String {
        switch self { case .work: "Работа"; case .plan: "Планирование"; case .goal: "Цель"; case .deepResearch: "Исследование" }
    }
    var symbol: String {
        switch self { case .work: "bolt"; case .plan: "list.bullet.clipboard"; case .goal: "scope"; case .deepResearch: "magnifyingglass" }
    }
    static func available(for roles: [String]) -> [Self] {
        roles.contains("researcher") || roles.contains("secretary")
            ? [.work, .plan, .goal, .deepResearch] : [.work, .plan, .goal]
    }
}

enum ChatComposerPolicy {
    static func isAssistantOnly(_ roles: [String]) -> Bool {
        !roles.isEmpty && roles.allSatisfy { $0 == "secretary" }
    }
}

struct ChatComposerControls: Decodable {
    let context: ChatContextSnapshot
    let commands: [ChatSlashCommand]
}

/// Из чего состоит занятое окно (сервер, 26.10.2026): оценка по частям,
/// в сумме — настоящий итог `tokens`.
struct ChatContextBreakdown: Decodable, Equatable {
    let system: Int
    let tools: Int
    let user: Int
    let assistant: Int
    let toolResults: Int
    let other: Int

    struct Part: Identifiable {
        let id: String
        let title: String
        let tokens: Int
    }
    var parts: [Part] {
        [Part(id: "system", title: "Инструкция", tokens: system),
         Part(id: "tools", title: "Инструменты", tokens: tools),
         Part(id: "user", title: "Ваши сообщения", tokens: user),
         Part(id: "assistant", title: "Ответы модели", tokens: assistant),
         Part(id: "toolResults", title: "Результаты инструментов", tokens: toolResults),
         Part(id: "other", title: "Прочее", tokens: other)]
    }
}

struct ChatContextSnapshot: Decodable, Equatable {
    let roleID: String
    let sessionID: String?
    let model: String?
    let provider: String?
    let tokens: Int?
    let contextWindow: Int?
    let measuredAt: String?
    let status: String
    let isEstimate: Bool
    var breakdown: ChatContextBreakdown? = nil

    var fraction: Double? {
        guard status == "measured", let tokens, tokens >= 0,
              let contextWindow, contextWindow > 0 else { return nil }
        return Double(tokens) / Double(contextWindow)
    }
    // Advisory threshold, not a claim that the model must be reset here.
    var shouldConsiderReset: Bool { (fraction ?? 0) >= 0.85 }
    var summary: String {
        if status == "no_session" { return "Новая сессия · замера ещё нет" }
        if status == "after_compaction" { return "После сжатия · ждём новый замер" }
        guard let fraction, let tokens, let contextWindow else { return "Контекст пока недоступен" }
        return "Контекст \(Self.compact(tokens)) из \(Self.compact(contextWindow)) · \(Int((fraction * 100).rounded()))%"
    }

    /// 36 900 → «36,9 тыс», 1 000 000 → «1 млн».
    static func compact(_ value: Int) -> String {
        if value >= 1_000_000 { return (Double(value) / 1_000_000).formatted(.number.precision(.fractionLength(0...1))) + " млн" }
        if value >= 1_000 { return (Double(value) / 1_000).formatted(.number.precision(.fractionLength(0...1))) + " тыс" }
        return String(value)
    }
}

struct ChatSlashCommand: Decodable, Identifiable, Equatable {
    let id: String
    let title: String
    let kind: String
    let description: String
    let invocation: String
    /// Карточка (сервер с 27.10.2026): что делает в двух словах и значок SF Symbol.
    var summary: String? = nil
    var icon: String? = nil
    var kindTitle: String { kind == "skill" ? "Навык" : "Инструмент / MCP" }

    /// Подпись карточки; у старого сервера — первая фраза описания.
    var cardSummary: String {
        if let summary, !summary.isEmpty { return summary }
        let first = description.components(separatedBy: CharacterSet(charactersIn: ".:;—")).first ?? description
        return first.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    var cardIcon: String { icon ?? (kind == "skill" ? "sparkles" : "wrench.and.screwdriver") }

    static func suggestions(for draft: String, from commands: [Self]) -> [Self] {
        guard draft.hasPrefix("/"), !draft.dropFirst().contains(where: \.isWhitespace) else { return [] }
        let query = draft.dropFirst().lowercased()
        return commands.filter {
            query.isEmpty || $0.title.lowercased().contains(query)
                || $0.invocation.dropFirst().lowercased().contains(query)
        }
    }
    func inserting(into draft: String) -> String {
        let suffix: String
        if draft.hasPrefix("/"), let end = draft.firstIndex(where: \.isWhitespace) {
            suffix = String(draft[end...]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if draft.hasPrefix("/") { suffix = "" }
        else { suffix = draft }
        return invocation.trimmingCharacters(in: .whitespacesAndNewlines) + " " + suffix
    }
}
