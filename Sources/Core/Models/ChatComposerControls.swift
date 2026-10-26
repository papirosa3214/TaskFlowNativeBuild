import Foundation

public struct RoleModelOption: Decodable, Identifiable, Hashable {
    public let id: String
    public let title: String
    public let provider: String?
    public let modelID: String?
    public let contextWindow: Int?

    var providerTitle: String {
        guard let provider, !provider.isEmpty else { return "Провайдер не указан" }
        return provider
    }
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
        return "\(isEstimate ? "≈ " : "")\(tokens) / \(contextWindow) токенов · \(Int((fraction * 100).rounded()))%"
    }
}

struct ChatSlashCommand: Decodable, Identifiable, Equatable {
    let id: String
    let title: String
    let kind: String
    let description: String
    let invocation: String
    var kindTitle: String { kind == "skill" ? "Навык" : "Инструмент / MCP" }

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
