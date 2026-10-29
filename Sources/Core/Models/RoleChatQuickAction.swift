import Foundation

/// Правка быстрого действия, сделанная владельцем (владелец 29.10.2026:
/// «у меня появляется возможность редактировать эти четыре квадратика и
/// прописывать первичный промпт под свои задачи»).
///
/// Владелец правит две вещи: название (видно на карточке) и сам промпт
/// (подставляется в поле ввода). Текст промпта на карточке не показывается —
/// карточка показывает только название.
public struct RoleChatQuickActionOverride: Codable, Equatable, Sendable {
    /// Своё название карточки. nil — остаётся штатное.
    public var name: String?
    /// Свой промпт. nil — остаётся штатный.
    public var prompt: String?

    public init(name: String? = nil, prompt: String? = nil) {
        self.name = name
        self.prompt = prompt
    }

    /// Есть ли что сохранять: пустые строки — это «вернуть штатное».
    public var isEmpty: Bool {
        let nameEmpty = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let promptEmpty = (prompt ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return nameEmpty && promptEmpty
    }
}

/// Правки быстрых действий по роли: индекс карточки → правка.
public typealias RoleChatQuickActionOverrides = [Int: RoleChatQuickActionOverride]

public enum RoleChatQuickActions {
    /// Ключ хранения правок для роли в `UserDefaults`.
    public static func storageKey(roleKey: String) -> String {
        "taskflow_quick_actions." + roleKey
    }

    /// Штатная карточка с учётом правки владельца.
    ///
    /// Название берётся из правки, если она непустая; промпт — тоже. Текст
    /// промпта в карточке не показывается: видно только название.
    public static func effectiveCommand(
        _ command: RoleChatStarterCommand,
        override: RoleChatQuickActionOverride?
    ) -> RoleChatStarterCommand {
        guard let override else { return command }
        let name = (override.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = (override.prompt ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return RoleChatStarterCommand(
            title: name.isEmpty ? command.title : name,
            hint: command.hint,
            prompt: prompt.isEmpty ? command.prompt : prompt,
            icon: command.icon)
    }

    /// Все карточки роли с учётом правок.
    public static func effectiveCommands(
        for starter: RoleChatStarter,
        overrides: RoleChatQuickActionOverrides
    ) -> [RoleChatStarterCommand] {
        starter.commands.enumerated().map { index, command in
            effectiveCommand(command, override: overrides[index])
        }
    }

    /// Правка, которую показываем в редакторе: пустые поля — «вернуть штатное».
    public static func override(
        for index: Int,
        in starter: RoleChatStarter,
        overrides: RoleChatQuickActionOverrides
    ) -> RoleChatQuickActionOverride {
        guard starter.commands.indices.contains(index) else {
            return RoleChatQuickActionOverride()
        }
        let command = starter.commands[index]
        let saved = overrides[index]
        return RoleChatQuickActionOverride(
            name: saved?.name ?? command.title,
            prompt: saved?.prompt ?? command.prompt)
    }
}
