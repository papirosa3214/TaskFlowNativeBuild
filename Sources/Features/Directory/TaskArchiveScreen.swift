import SwiftUI

/// Системный архив задач; принадлежность исходному проекту сохраняется.
struct TaskArchiveScreen: View {
    @Environment(TaskStore.self) private var taskStore
    @Environment(ProjectStore.self) private var projectStore
    @State private var pendingProjectDelete: ApiProject?
    @State private var pendingDelete: ApiTask?
    @State private var selectedTask: ApiTask?
    @State private var busyID: String?

    private var tasks: [ApiTask] {
        taskStore.archivedTasks.sorted {
            ($0.archivedAt ?? "") > ($1.archivedAt ?? "")
        }
    }

    var body: some View {
        List {
            projectArchiveSection
            if let error = taskStore.archiveErrorMessage {
                Section {
                    Text(error).foregroundStyle(.red)
                    Button("Повторить") { Task { await taskStore.loadArchive() } }
                }
            }
            if taskStore.isLoadingArchive && tasks.isEmpty {
                ProgressView("Загрузка архива")
            } else if tasks.isEmpty && projectStore.archivedProjects.isEmpty && taskStore.archiveErrorMessage == nil && projectStore.archiveErrorMessage == nil {
                ContentUnavailableView("Архив пуст", systemImage: "archivebox",
                    description: Text("Задачи, отправленные в архив, можно восстановить или удалить окончательно."))
            }
            ForEach(tasks) { task in
                Button { selectedTask = task } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(task.title).foregroundStyle(.primary)
                        Text(task.projectName ?? "Без проекта")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("archiveTask-\(task.id)")
                .disabled(busyID != nil)
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button("Восстановить", systemImage: "arrow.uturn.backward") {
                        restore(task)
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("Удалить окончательно", systemImage: "trash", role: .destructive) {
                        pendingDelete = task
                    }
                }
                .contextMenu {
                    Button("Восстановить", systemImage: "arrow.uturn.backward") { restore(task) }
                    Button("Удалить окончательно", systemImage: "trash", role: .destructive) {
                        pendingDelete = task
                    }
                }
            }
        }
        .accessibilityIdentifier("taskArchiveList")
        .navigationTitle("Архив")
        .task { await loadArchive() }
        .refreshable { await loadArchive() }
        .confirmationDialog("Удалить задачу окончательно?", isPresented: Binding(
            get: { pendingDelete != nil || pendingProjectDelete != nil },
            set: { if !$0 { pendingDelete = nil; pendingProjectDelete = nil } }
        ), titleVisibility: .visible) {
            if let task = pendingDelete {
                Button("Удалить окончательно", role: .destructive) {
                    permanentlyDelete(task)
                }
            }
            if let project = pendingProjectDelete {
                Button("Удалить проект окончательно", role: .destructive) { purgeProject(project) }
            }
            Button("Отмена", role: .cancel) { pendingDelete = nil; pendingProjectDelete = nil }
        } message: {
            Text(pendingProjectDelete != nil
                ? "Проект, его задачи, чаты и память будут удалены без возможности восстановления. Документы сохранятся."
                : "Карточка и её история будут удалены без возможности восстановления. Если у задачи есть дочерние карточки, сначала удалите их из архива.")
        }
        .sheet(item: $selectedTask) { task in
            NavigationStack {
                List {
                    Section {
                        Text(task.title).font(.headline)
                        if let description = task.description, !description.isEmpty {
                            Text(.init(description)).textSelection(.enabled)
                        }
                        LabeledContent("Проект", value: task.projectName ?? "Без проекта")
                        LabeledContent("Состояние", value: task.status == .completed ? "Выполнена" : "Открыта")
                        if let date = task.archivedAt {
                            LabeledContent("В архиве с", value: date)
                        }
                    }
                    Section {
                        Button("Восстановить", systemImage: "arrow.uturn.backward") {
                            selectedTask = nil
                            restore(task)
                        }
                        Button("Удалить окончательно", systemImage: "trash", role: .destructive) {
                            selectedTask = nil
                            pendingDelete = task
                        }
                    }
                    .disabled(busyID != nil)
                }
                .navigationTitle("Задача в архиве")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Готово") { selectedTask = nil }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var projectArchiveSection: some View {
        if let error = projectStore.archiveErrorMessage {
            Section("Проекты") {
                Text(error).foregroundStyle(.red)
                Button("Повторить") { Task { await projectStore.loadArchive() } }
            }
        }
        if !projectStore.archivedProjects.isEmpty {
            Section("Проекты") {
                ForEach(projectStore.archivedProjects) { project in
                    VStack(alignment: .leading) {
                        Text(project.name)
                        Text("Задач: \(project.taskCount ?? 0)").font(.caption).foregroundStyle(.secondary)
                    }
                    .disabled(busyID != nil)
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button("Восстановить", systemImage: "arrow.uturn.backward") { restoreProject(project) }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Удалить окончательно", systemImage: "trash", role: .destructive) { pendingProjectDelete = project }
                    }
                    .contextMenu {
                        Button("Восстановить", systemImage: "arrow.uturn.backward") { restoreProject(project) }
                        Button("Удалить окончательно", systemImage: "trash", role: .destructive) { pendingProjectDelete = project }
                    }
                }
            }
        }
    }

    private func loadArchive() async {
        await taskStore.loadArchive()
        await projectStore.loadArchive()
    }

    private func restoreProject(_ project: ApiProject) {
        guard busyID == nil else { return }
        busyID = project.id
        Task { _ = await projectStore.restoreArchived(projectId: project.id); busyID = nil }
    }

    private func purgeProject(_ project: ApiProject) {
        guard busyID == nil else { return }
        pendingProjectDelete = nil
        busyID = project.id
        Task { _ = await projectStore.purgeArchived(projectId: project.id); busyID = nil }
    }

    private func restore(_ task: ApiTask) {
        guard busyID == nil else { return }
        busyID = task.id
        Task {
            _ = await taskStore.restore(taskId: task.id)
            busyID = nil
        }
    }

    private func permanentlyDelete(_ task: ApiTask) {
        guard busyID == nil else { return }
        pendingDelete = nil
        busyID = task.id
        Task {
            _ = await taskStore.permanentlyDelete(taskId: task.id)
            busyID = nil
        }
    }
}
