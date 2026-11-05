import SwiftUI

/// Чат проекта (владелец 05.11.2026): сразу открывается общее обсуждение, а над
/// полем ввода листаются топики задач — как вкладки, без отдельного экрана тем.
struct ProjectChatScreen: View {
    let groupID: String
    @State private var selected: RoleChat
    @State private var group: RoleChat?
    @State private var topics: [RoleChat] = []
    @State private var tasks: [ApiTask] = []
    @State private var showsClosed = false
    @State private var showingTasks = false
    @State private var errorMessage: String?
    @State private var sheetErrorMessage: String?
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
            .task(id: "\(selected.id):\(showsClosed)") { await loadTopics() }
            .sheet(isPresented: $showingTasks) { taskPicker }
    }

    private var strip: some View {
        HStack(spacing: TFSpacing.xs) {
            ScrollView(.horizontal) {
                HStack(spacing: TFSpacing.xs) {
                    tab(id: groupID, title: "Общее", unread: 0, closed: false) { openGeneral() }
                        .accessibilityIdentifier("projectChat.general")
                    ForEach(topics) { topic in
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
            menu
                .padding(.trailing, TFSpacing.screenHorizontal)
        }
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

    private var menu: some View {
        Menu {
            Button { Task { await openTaskPicker() } } label: {
                Label("Добавить тему задачи", systemImage: "plus")
            }
            .accessibilityIdentifier("projectChat.addTopic")
            Button { showsClosed.toggle() } label: {
                Label("Показать закрытые", systemImage: showsClosed ? "checkmark" : "archivebox")
            }
        } label: {
            Image(systemName: "ellipsis")
                .frame(minWidth: 32, minHeight: 32)
                .contentShape(Rectangle())
        }
        .tint(Color.tfText)
        .accessibilityLabel("Темы проекта")
        .accessibilityIdentifier("projectChat.menu")
    }

    private var taskPicker: some View {
        NavigationStack {
            List {
                TFErrorBanner(sheetErrorMessage.map { _ in "Не удалось добавить тему" }, variant: .block)
                ForEach(tasks.filter { $0.projectId == selected.projectID }) { task in
                    Button(task.title) { Task { await addTopic(task) } }
                }
            }
            .tint(Color.tfText)
            .navigationTitle("Выберите задачу")
            .toolbar { Button("Закрыть") { showingTasks = false } }
        }
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
        if let fresh = try? await api.chatTopics(chatID: groupID, includeClosed: showsClosed), !Task.isCancelled {
            topics = fresh
        }
    }

    private func openTaskPicker() async {
        sheetErrorMessage = nil
        showingTasks = true
        do { tasks = try await api.tasks(includeChildren: true) }
        catch { sheetErrorMessage = error.localizedDescription }
    }

    private func addTopic(_ task: ApiTask) async {
        do {
            let topic = try await api.taskTopic(taskID: task.id)
            showingTasks = false
            await loadTopics()
            selected = topic
            stripPosition = topic.id
        } catch {
            sheetErrorMessage = error.localizedDescription
        }
    }
}
