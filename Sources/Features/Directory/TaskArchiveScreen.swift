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
        // Тот же каркас, что у списков проекта и меток: `ScrollView` +
        // `LazyVStack` с разделителями между рядами. Штатный `List` давал
        // карточный контейнер и разделители — это и был неровный вид.
        ScrollView {
            LazyVStack(alignment: .leading, spacing: TFSpacing.md) {
                TFErrorBanner(taskStore.archiveErrorMessage, variant: .inline)

                if taskStore.isLoadingArchive && tasks.isEmpty {
                    TFLoading(.block)
                } else if tasks.isEmpty && taskStore.archiveErrorMessage == nil {
                    TFEmptyState(
                        icon: "archivebox",
                        text: "Задачи, отправленные в архив, можно восстановить или удалить окончательно."
                    )
                    .padding(.horizontal, TFSpacing.xs)
                } else if !tasks.isEmpty {
                    VStack(spacing: 2) {
                        ForEach(tasks.indices, id: \.self) { rowIndex in
                            if rowIndex > 0 { TFDivider() }
                            archiveRow(tasks[rowIndex])
                        }
                    }
                }
            }
            .padding(.top, TFSpacing.sm)
            .padding(.bottom, TFSpacing.xl)
        }
        .accessibilityIdentifier("taskArchiveList")
        .tfNativeHeader("Архив", displayMode: .inline)
        .task { await loadArchive() }
        .refreshable { await loadArchive() }
        // Фон экрана — тот же токен, что у списков проекта и меток. Без этой
        // строки SwiftUI подставлял системный фон, и в тёмной теме раздел
        // был чисто чёрным вместо общей серой подложки.
        .background(Color.tfBackground)
        .confirmationDialog(pendingProjectDelete == nil ? "Удалить задачу окончательно?" : "Удалить проект окончательно?", isPresented: Binding(
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
                        Text(task.title).tfText(.title).foregroundStyle(Color.tfText)
                        if let description = task.description, !description.isEmpty {
                            Text(.init(description)).tfText(.row).foregroundStyle(Color.tfText).textSelection(.enabled)
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

    /// Ряд архивной задачи — каноничный `DirectoryTaskRow` на `HorizontalPan`,
    /// тот же, что в списках проекта и меток. Свайп вправо — безвозвратное
    /// удаление, свайп влево — «Вернуть в работу».
    private func archiveRow(_ task: ApiTask) -> some View {
        DirectoryTaskRow(
            index: nil,
            task: task,
            isOwner: true,
            onOpen: { selectedTask = task },
            onDelete: { pendingDelete = task },
            swipeAction: .restore,
            onSwipeAction: { restore(task) },
            deleteConfirmTitle: "Удалить окончательно?",
            deleteConfirmMessage: { title in
                "«\(title)» и её история будут удалены без возможности восстановления."
            }
        )
        .disabled(busyID != nil)
        .contextMenu {
            Button("Восстановить", systemImage: "arrow.uturn.backward") { restore(task) }
            Button("Удалить окончательно", systemImage: "trash", role: .destructive) {
                pendingDelete = task
            }
        }
    }

    @ViewBuilder
    private var projectArchiveSection: some View {
        if !projectStore.archivedProjects.isEmpty {
            VStack(alignment: .leading, spacing: TFSpacing.xs) {
                Text("Проекты")
                    .tfText(.meta)
                    .foregroundStyle(Color.tfSub)
                    .padding(.horizontal, TFSpacing.screenHorizontal)

                VStack(spacing: 2) {
                    ForEach(projectStore.archivedProjects.indices, id: \.self) { i in
                        if i > 0 { TFDivider() }
                        projectRow(projectStore.archivedProjects[i])
                    }
                }
            }
        }
    }

    /// Ряд архивного проекта — `DirectorySwipeRow`, как в списке проектов:
    /// свайп вправо — удалить окончательно, влево — восстановить.
    private func projectRow(_ project: ApiProject) -> some View {
        DirectorySwipeRow(
            onEdit: { restoreProject(project) },
            onDelete: { pendingProjectDelete = project }
        ) {
            HStack(spacing: TFSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .tfText(.row)
                        .foregroundStyle(Color.tfText)
                    Text("Задач: \(project.taskCount ?? 0)")
                        .tfText(.meta)
                        .foregroundStyle(Color.tfSub)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, TFSpacing.md)
            .padding(.vertical, TFSpacing.sm)
            .background(Color.tfBackground)
        }
        .disabled(busyID != nil)
        .contextMenu {
            Button("Восстановить", systemImage: "arrow.uturn.backward") { restoreProject(project) }
            Button("Удалить окончательно", systemImage: "trash", role: .destructive) { pendingProjectDelete = project }
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
