import SwiftUI

struct ProjectTopicsScreen: View {
    let group: RoleChat
    @State private var topics: [RoleChat] = []
    @State private var tasks: [ApiTask] = []
    @State private var showingTasks = false
    @State private var errorMessage: String?
    /// Ошибка внутри шторки «Выберите задачу» — своя: баннер в списке под
    /// шторкой не видно, а раньше её показывал системный диалог поверх шторки.
    @State private var sheetErrorMessage: String?
    /// Фильтры тем (владелец 21.10.2026): закрытые и участник.
    @State private var showsClosed = false
    @State private var memberFilter: String?
    private let api = APIClient()

    /// Участники тем проекта — для фильтра, без повторов и по имени.
    private var topicMembers: [RoleChatMember] {
        var seen = Set<String>()
        return topics.flatMap(\.members)
            .filter { $0.roleKey != nil && seen.insert($0.id).inserted }
            .sorted { $0.name < $1.name }
    }

    private var visibleTopics: [RoleChat] {
        guard let memberFilter else { return topics }
        return topics.filter { topic in topic.members.contains { $0.id == memberFilter } }
    }

    var body: some View {
        List {
            TFErrorBanner(errorMessage.map { _ in "Не удалось загрузить темы" }, variant: .block)
            // Маршрутом, как и темы ниже: смесь `NavigationLink { }` и
            // маршрутов в одном стеке ломала переходы и «назад» (20.10.2026).
            NavigationLink(value: AppRoute.projectGroupRoom(id: group.id)) {
                Label { Text("Общее обсуждение").foregroundStyle(Color.tfText) } icon: { Image(systemName: "bubble.left.and.bubble.right").foregroundStyle(Color.tfRed) }
            }
            .accessibilityIdentifier("projectChat.general")
            Section("Задачи") {
                if visibleTopics.isEmpty { Text(memberFilter == nil ? "Тем пока нет" : "У этого участника тем нет").foregroundStyle(Color.tfReadableSecondary) }
                ForEach(visibleTopics) { topic in
                    NavigationLink(value: AppRoute.roleChat(id: topic.id)) {
                        HStack {
                            Label { Text(topic.title ?? "Задача").foregroundStyle(topic.closedAt == nil ? Color.tfText : Color.tfDim) } icon: { Image(systemName: "number").foregroundStyle(Color.tfRed) }
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
        // 16.10.2026 (LOCK-UI-DRIFT-KNOWN): корневой `List` рисует свой
        // системный фон, а не фон приложения — на тёмной теме это более
        // чёрное поле, чем `tfBackground`. Тот же дефект, что был у
        // «Параметров сервера» и «Диагностики», закрыт 16.10.2026 общим
        // модификатором `TFScreenBackground`.
        .tfScreenBackground()
        .navigationTitle(group.title ?? "Проект")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { filterMenu }
            ToolbarItem(placement: .principal) {
                HStack(spacing: TFSpacing.sm) {
                    TFGroupAvatar(identity: group.projectID ?? group.id, size: .md)
                    Text(group.title ?? "Проект").tfText(.title).foregroundStyle(Color.tfText).lineLimit(1)
                }
            }
        }
        .task { await load() }
        .onChange(of: showsClosed) { Task { await load() } }
        .refreshable { await load() }
        .sheet(isPresented: $showingTasks) {
            NavigationStack {
                List {
                    TFErrorBanner(sheetErrorMessage.map { _ in "Не удалось загрузить темы" }, variant: .block)
                    ForEach(tasks.filter { $0.projectId == group.projectID }) { task in
                        Button(task.title) {
                            Task {
                                do {
                                    _ = try await api.taskTopic(taskID: task.id)
                                    showingTasks = false
                                    await load()
                                } catch {
                                    sheetErrorMessage = error.localizedDescription
                                }
                            }
                        }
                    }
                }
                .tint(Color.tfText)
                .navigationTitle("Выберите задачу")
                .toolbar { Button("Закрыть") { showingTasks = false } }
            }
        }
    }

    private var filterMenu: some View {
        Menu {
            Button { showsClosed.toggle() } label: {
                Label("Показать закрытые", systemImage: showsClosed ? "checkmark" : "archivebox")
            }
            Divider()
            Button { memberFilter = nil } label: {
                Label("Все участники", systemImage: memberFilter == nil ? "checkmark" : "person.2")
            }
            ForEach(topicMembers) { member in
                Button { memberFilter = member.id } label: {
                    Label(member.name, systemImage: memberFilter == member.id ? "checkmark" : "person")
                }
            }
        } label: {
            Image(systemName: showsClosed || memberFilter != nil
                  ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("Фильтр тем")
        .accessibilityIdentifier("projectChat.filter")
    }

    private func load() async {
        do {
            topics = try await api.chatTopics(chatID: group.id, includeClosed: showsClosed)
            tasks = try await api.tasks(includeChildren: true)
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }
}
