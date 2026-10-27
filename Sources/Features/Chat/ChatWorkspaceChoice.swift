import Foundation
import SwiftUI
import Observation

/// Рабочая папка в окне ввода чата с Помощником владельца (владелец
/// 27.10.2026: «как во всех других системах»). Выбор хранится на сервере за
/// чатом и действует со следующего хода роли.
@MainActor
@Observable
final class ChatWorkspaceChoice {
    private(set) var state: ChatWorkspaceState?
    private var chatID: String?
    private let api = APIClient()

    var isAvailable: Bool { !(state?.options.isEmpty ?? true) }
    var title: String { state?.title ?? "Папка" }
    var selected: String? { state?.selected }

    /// Только чат с Помощником владельца; в остальных чатах чипа нет.
    func load(chat: RoleChat) async {
        guard chat.members.contains(where: { $0.id == "u-secretary" || $0.roleKey == "secretary" }) else {
            state = nil
            return
        }
        chatID = chat.id
        state = try? await api.request(.get, "/chats/\(chat.id)/workspace")
    }

    func select(_ name: String?) async {
        guard let chatID else { return }
        if let updated: ChatWorkspaceState = try? await api.request(
            .put, "/chats/\(chatID)/workspace", body: ["name": name ?? ""]
        ) {
            state = updated
        }
    }
}

/// Меню: «По умолчанию» и папки проектов; как меню модели рядом.
struct ChatWorkspaceMenu<MenuLabel: View>: View {
    @Bindable var choice: ChatWorkspaceChoice
    @ViewBuilder let label: () -> MenuLabel

    var body: some View {
        Menu {
            Button { Task { await choice.select(nil) } } label: {
                if choice.selected == nil { Label("По умолчанию", systemImage: "checkmark") }
                else { Text("По умолчанию") }
            }
            Section("Проекты") {
                ForEach(choice.state?.options ?? []) { option in
                    Button { Task { await choice.select(option.name) } } label: {
                        if choice.selected == option.name {
                            Label(option.name, systemImage: "checkmark")
                        } else {
                            Text(option.name)
                        }
                        if let subtitle = option.subtitle { Text(subtitle) }
                    }
                }
            }
        } label: { label() }
        .accessibilityIdentifier("chat.workspace")
        .accessibilityLabel("Рабочая папка: " + choice.title)
    }
}
