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

    var title: String {
        if let selected { return options.first { $0.id == selected }?.title ?? selected }
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
            if let selected, !options.contains(where: { $0.id == selected }) { self.selected = nil }
        } catch {
            options = []
        }
    }
}

/// Меню выбора модели: «По умолчанию» и модели агента.
struct ChatModelMenu<Label: View>: View {
    @Bindable var choice: ChatModelChoice
    @ViewBuilder let label: () -> Label

    var body: some View {
        Menu {
            Picker("Модель", selection: $choice.selected) {
                Text(choice.current.map { "По умолчанию · " + $0 } ?? "По умолчанию").tag(String?.none)
                ForEach(choice.options) { option in
                    Text(option.title).tag(Optional(option.id))
                }
            }
        } label: { label() }
        .accessibilityIdentifier("chat.model")
        .accessibilityLabel("Модель: " + choice.title)
    }
}
