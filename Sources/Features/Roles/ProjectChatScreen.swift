import SwiftUI

/// Чат проекта (владелец 05.11.2026): сразу открывается общее обсуждение, а над
/// полем ввода листаются топики задач — как вкладки, без отдельного экрана тем.
struct ProjectChatScreen: View {
    let groupID: String
    @State private var selected: RoleChat
    @State private var group: RoleChat?
    @State private var topics: [RoleChat] = []
    @State private var stripPosition: String?
    private let api = APIClient()

    init(groupID: String, opened: RoleChat) {
        self.groupID = groupID
        _selected = State(initialValue: opened)
        _group = State(initialValue: opened.id == groupID ? opened : nil)
        _stripPosition = State(initialValue: opened.id)
    }

    var body: some View {
        // Каждая вкладка — свой экран чата: лента, черновик и сокет не должны
        // переходить из топика в топик.
        RoleChatRoomScreen(chat: selected, topicStrip: AnyView(strip))
            .id(selected.id)
            .task { await loadGroup() }
            .task(id: selected.id) { await loadTopics() }
    }

    /// Открытые топики. Если открыт топик вне этого списка (например закрытый,
    /// из карточки задачи), он тоже виден: иначе не понять, где находишься.
    private var visibleTopics: [RoleChat] {
        guard selected.id != groupID, !topics.contains(where: { $0.id == selected.id }) else { return topics }
        return [selected] + topics
    }

    private var strip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: TFSpacing.xs) {
                tab(id: groupID, title: "Общее", unread: 0, closed: false) { openGeneral() }
                    .accessibilityIdentifier("projectChat.general")
                ForEach(visibleTopics) { topic in
                    tab(id: topic.id, title: topic.title ?? "Задача", unread: topic.unread, closed: topic.closedAt != nil) {
                        selected = topic
                        stripPosition = topic.id
                    }
                    .accessibilityIdentifier("projectChat.topic.\(topic.id)")
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, TFSpacing.screenHorizontal)
        }
        .scrollIndicators(.hidden)
        .scrollPosition(id: $stripPosition, anchor: .center)
        .padding(.vertical, TFSpacing.xs)
    }

    private func tab(id: String, title: String, unread: Int, closed: Bool, action: @escaping () -> Void) -> some View {
        let isSelected = selected.id == id
        return Button(action: action) {
            Text(unread > 0 ? "\(title) · \(unread)" : title)
                .tfText(.action)
                .lineLimit(1)
                .foregroundStyle(isSelected ? Color.tfBackground : closed ? Color.tfDim : Color.tfText)
                .padding(.horizontal, TFSpacing.sm)
                .frame(minHeight: 32)
                .frame(maxWidth: 220)
                .background(Capsule().fill(isSelected ? Color.tfText : Color.clear))
                .overlay(Capsule().stroke(isSelected ? Color.clear : Color.tfDim.opacity(0.5), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .id(id)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func openGeneral() {
        stripPosition = groupID
        if let group {
            selected = group
        } else {
            Task {
                await loadGroup()
                if let group { selected = group }
            }
        }
    }

    private func loadGroup() async {
        guard group == nil else { return }
        group = try? await api.roleChat(id: groupID)
    }

    private func loadTopics() async {
        if let fresh = try? await api.chatTopics(chatID: groupID), !Task.isCancelled {
            topics = fresh
        }
    }
}
