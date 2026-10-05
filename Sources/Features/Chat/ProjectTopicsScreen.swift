import SwiftUI

struct ProjectTopicsScreen: View {
    let group: RoleChat
    @State private var topics: [RoleChat] = []
    @State private var tasks: [ApiTask] = []
    @State private var showingTasks = false
    @State private var errorMessage: String?
    private let api = APIClient()

    var body: some View {
        List {
            NavigationLink {
                RoleChatRoomScreen(chat: group)
            } label: {
                Label { Text("Общее обсуждение").foregroundStyle(Color.tfText) } icon: { Image(systemName: "bubble.left.and.bubble.right").foregroundStyle(Color.tfRed) }
            }
            .accessibilityIdentifier("projectChat.general")
            Section("Задачи") {
                if topics.isEmpty { Text("Тем пока нет").foregroundStyle(Color.tfReadableSecondary) }
                ForEach(topics) { topic in
                    NavigationLink(value: AppRoute.roleChat(id: topic.id)) {
                        HStack {
                            Label { Text(topic.title ?? "Задача").foregroundStyle(Color.tfText) } icon: { Image(systemName: "number").foregroundStyle(Color.tfRed) }
                            Spacer()
                            if topic.unread > 0 { Text("\(topic.unread)").foregroundStyle(Color.tfReadableSecondary) }
                        }
                    }
                    .accessibilityIdentifier("projectChat.topic.\(topic.id)")
                }
                Button("Добавить тему задачи") { showingTasks = true }
                    .accessibilityIdentifier("projectChat.addTopic")
            }
        }
         .tint(Color.tfText)
        .navigationTitle(group.title ?? "Проект")
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: TFSpacing.sm) {
                    TFGroupAvatar(identity: group.projectID ?? group.id, size: .md)
                    Text(group.title ?? "Проект").font(.headline).foregroundStyle(Color.tfText).lineLimit(1)
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showingTasks) {
            NavigationStack {
                List(tasks.filter { $0.projectId == group.projectID }) { task in
                    Button(task.title) {
                        Task {
                            do {
                                _ = try await api.taskTopic(taskID: task.id)
                                showingTasks = false
                                await load()
                            } catch { errorMessage = error.localizedDescription }
                        }
                    }
                }
                .tint(Color.tfText)
                .navigationTitle("Выберите задачу")
                .toolbar { Button("Закрыть") { showingTasks = false } }
            }
        }
        .alert("Не удалось загрузить темы", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("ОК") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func load() async {
        do {
            topics = try await api.chatTopics(chatID: group.id)
            tasks = try await api.tasks(includeChildren: true)
        } catch { errorMessage = error.localizedDescription }
    }
}

struct ProjectChatPicker: View {
    let onCreated: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var projects: [ApiProject] = []
    @State private var errorMessage: String?
    private let api = APIClient()
    var body: some View {
        NavigationStack {
            List(projects) { project in
                Button(project.name) {
                    Task {
                        do {
                            _ = try await api.projectChat(projectID: project.id)
                            onCreated()
                            dismiss()
                        } catch { errorMessage = error.localizedDescription }
                    }
                }
            }
            .tint(Color.tfText)
            .navigationTitle("Группа проекта")
            .toolbar { Button("Закрыть") { dismiss() } }
            .task {
                do { projects = try await api.projects() }
                catch { errorMessage = error.localizedDescription }
            }
            .alert("Не удалось открыть группу", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("ОК") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }
}
