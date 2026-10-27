import Foundation
import SwiftUI
import Observation

/// Выбор модели в окне ввода чата (владелец 19.10.2026): пилюля рядом с
/// режимом «Работа / Планирование». Модели — у единственного агента чата
/// (`GET /api/roles/:role/models`): у внешнего агента его каталог, у роли —
/// модели Pi. Выбор хранится на устройстве для каждого чата, как режим, и
/// уходит с сообщением полем `model`; `nil` — модель роли по умолчанию.
@MainActor
@Observable
final class ChatModelChoice {
    private(set) var options: [RoleModelOption] = []
    /// Чем агент работает сейчас (для подписи «По умолчанию»).
    private(set) var current: String?
    var selected: String? {
        didSet { if let key { UserDefaults.standard.set(selected, forKey: key) } }
    }
    private var key: String?
    private let api = APIClient()

    /// Пилюля видна, когда в чате ровно один агент и у него есть выбор.
    var isAvailable: Bool { !options.isEmpty }

    /// Модель, которой агент работает на деле: выбранная, иначе текущая.
    var effectiveTitle: String? {
        if let selected, let option = options.first(where: { $0.id == selected }) { return option.title }
        guard let current else { return nil }
        return options.first(where: { $0.id == current })?.title ?? current
    }

    var title: String {
        if let selected, let option = options.first(where: { $0.id == selected }) {
            return option.title
        }
        return "Модель"
    }

    func load(chat: RoleChat) async {
        let agents = chat.members.compactMap(\.roleKey)
        guard agents.count == 1, let role = agents.first else { options = []; return }
        key = "roleChat.model." + chat.createdBy + "." + chat.id
        selected = key.flatMap { UserDefaults.standard.string(forKey: $0) }
        do {
            let result = try await api.roleModels(role: role)
            options = result.models
            current = result.current
            self.selected = RoleModelOption.resolveSelection(selected, in: options)
        } catch {
            options = []
        }
    }
}

/// Меню выбора модели: «По умолчанию» и модели агента.
struct ChatModelMenu<MenuLabel: View>: View {
    @Bindable var choice: ChatModelChoice
    @ViewBuilder let label: () -> MenuLabel

    var body: some View {
        Menu {
            Button { choice.selected = nil } label: {
                if choice.selected == nil {
                    Label(choice.current.map { "По умолчанию · " + $0 } ?? "По умолчанию", systemImage: "checkmark")
                } else {
                    Text(choice.current.map { "По умолчанию · " + $0 } ?? "По умолчанию")
                }
            }
            // Как меню инструментов: все модели сразу, разделы по провайдерам.
            ForEach(RoleModelOption.grouped(choice.options)) { group in
                Section(group.provider) {
                    ForEach(group.models) { option in
                        Button { choice.selected = option.id } label: {
                            if choice.selected == option.id { Label(option.title, systemImage: "checkmark") }
                            else { Text(option.title) }
                        }
                    }
                }
            }
        } label: { label() }
        .accessibilityIdentifier("chat.model")
        .accessibilityLabel("Модель: " + choice.title)
    }
}
