import SwiftUI

/// Карточка назначения слота в личной комнате роли (владелец 08.11.2026).
///
/// Личная комната — родитель, назначение — её дочерняя сессия; разговор идёт
/// в общей комнате задачи, и карточка ведёт именно туда. Сервер держит
/// карточку вне переписки (`chat_child_sessions`), поэтому она не попадает в
/// контекст модели — здесь она только отображается.
struct ChatChildAssignment: Decodable, Identifiable, Sendable {
    let id: String
    let status: String
    let talkChatID: String
    let taskID: String?
    let taskTitle: String?
    let slotTitle: String?
    let attemptNo: Int
    let roleKey: String?

    enum CodingKeys: String, CodingKey {
        case id, status
        case talkChatID = "talk_chat_id"
        case taskID = "task_id"
        case taskTitle = "task_title"
        case slotTitle = "slot_title"
        case attemptNo = "attempt_no"
        case roleKey = "role_key"
    }

    /// Короткая подпись состояния — то же слово, что на сервере.
    var statusTitle: String {
        switch status {
        case "assigned": return "Назначено"
        case "delivered": return "Передано сессии"
        case "answered": return "Ответ получен"
        case "waiting": return "Ждёт решения"
        case "failed": return "Ошибка"
        default: return status
        }
    }

    var roomTitle: String {
        let task = taskTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (task?.isEmpty == false) ? task! : "Задача"
    }

    var slotLine: String? {
        let slot = slotTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (slot?.isEmpty == false) ? slot : nil
    }

    var subtitle: String {
        [slotLine, statusTitle].compactMap { $0 }.joined(separator: " · ")
    }
}

private struct ChatChildAssignmentsEnvelope: Decodable {
    let children: [ChatChildAssignment]
}

extension APIClient {
    /// Карточки назначений комнаты: `GET /api/chats/:id/children`.
    func chatChildAssignments(chatID: String) async throws -> [ChatChildAssignment] {
        let response: ChatChildAssignmentsEnvelope = try await request(.get, "/chats/\(chatID)/children")
        return response.children
    }
}

/// Полоса назначений над лентой личной комнаты: без подложки, строками — как
/// «Задача чата» в комнате задачи (владелец 08.11.2026).
struct ChatChildAssignmentsStrip: View {
    let chatID: String
    let onOpen: (String) -> Void

    @State private var items: [ChatChildAssignment] = []

    var body: some View {
        Group {
            if items.isEmpty {
                EmptyView()
            } else {
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        TFListRow(
                            icon: "square.stack.3d.up",
                            title: item.roomTitle,
                            subtitle: item.subtitle,
                            trailing: nil,
                            chevron: .shown,
                            action: { onOpen(item.talkChatID) }
                        )
                        .accessibilityIdentifier("chat.assignment." + item.id)
                    }
                    TFDivider(inset: TFSpacing.screenHorizontal)
                }
            }
        }
        .task(id: chatID) { await load() }
    }

    private func load() async {
        let api = APIClient()
        items = (try? await api.chatChildAssignments(chatID: chatID)) ?? []
    }
}
