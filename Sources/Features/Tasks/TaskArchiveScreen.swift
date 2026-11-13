import SwiftUI

/// Системный архив задач; принадлежность исходному проекту сохраняется.
struct TaskArchiveScreen: View {
    @Environment(TaskStore.self) private var taskStore
    @Environment(ProjectStore.self) private var projectStore
    @State private var pendingProjectDelete: ApiProject?
    @State private var selectedItem: ClosedTaskItem?
    @State private var busyID: String?
    /// Архив на телефоне — мини-карточки закрытых задач за месяц, только
    /// изменения с сервера (владелец 13.11.2026). Полная карточка приходит
    /// только при восстановлении.
    @State private var closedStore = ClosedTasksStore.shared

    private var tasks: [ClosedTaskItem] { closedStore.snapshot.items }

    var body: some View {
        // List owns the row surface and native swipe presentation.
        List {
            Group {
                historySection

                TFErrorBanner(closedStore.errorMessage ?? taskStore.archiveErrorMessage, variant: .inline)

                if closedStore.isLoading && tasks.isEmpty {
                    TFLoading(.block)
                } else if tasks.isEmpty && closedStore.errorMessage == nil {
                    TFEmptyState(
                        icon: "archivebox",
                        text: "Закрытые за последний месяц задачи появятся здесь. Их можно вернуть в работу."
                    )
                    .padding(.horizontal, TFSpacing.xs)
                } else if !tasks.isEmpty {
                    Group {
                        Text("Задачи")
                            .tfText(.action)
                            .foregroundStyle(Color.tfSub)
                            .padding(.horizontal, TFSpacing.screenHorizontal)
                        Group {
                            ForEach(tasks) { item in
                                archiveRow(item)
                            }
                        }
                    }
                }

            }
            .listRowInsets(EdgeInsets())
        }
        .listStyle(.plain)
        // Фон экрана — тот же токен, что у списков проекта и меток. Без этой
        // строки SwiftUI подставлял системный фон, и в тёмной теме раздел
        // был чисто чёрным вместо общей серой подложки.
        .tfScreenBackground()
        .accessibilityIdentifier("taskArchiveList")
        .tfNativeHeader("Архив", displayMode: .inline)
        .task { await loadArchive() }
        .refreshable { await loadArchive() }
        .confirmationDialog("Удалить проект окончательно?", isPresented: Binding(
            get: { pendingProjectDelete != nil },
            set: { if !$0 { pendingProjectDelete = nil } }
        ), titleVisibility: .visible) {
            if let project = pendingProjectDelete {
                Button("Удалить проект окончательно", role: .destructive) { purgeProject(project) }
            }
            Button("Отмена", role: .cancel) { pendingProjectDelete = nil }
        } message: {
            Text("Проект, его задачи, чаты и память будут удалены без возможности восстановления. Документы сохранятся.")
        }
        .tfSheet(item: $selectedItem) { item in
            // Мини-карточка: только то, что пришло в архив. Полная задача
            // грузится, лишь когда её возвращают в работу.
            ClosedMiniCardSheet(
                item: item,
                isBusy: busyID != nil,
                onRestore: { restore(item); selectedItem = nil },
                onHide: { closedStore.hide(item.id); selectedItem = nil }
            )
        }
    }

    /// Ряд закрытой задачи: название, проект и дата, итог одной строкой.
    /// Свайп влево — вернуть в работу, вправо — убрать с телефона (в
    /// статистике и на сервере остаётся).
    private func archiveRow(_ item: ClosedTaskItem) -> some View {
        Button { selectedItem = item } label: {
            ClosedMiniCardRow(item: item)
        }
        .buttonStyle(.plain)
        .disabled(busyID != nil)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button { restore(item) } label: { Label("Вернуть", systemImage: "arrow.uturn.backward") }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button { closedStore.hide(item.id) } label: { Label("Убрать с телефона", systemImage: "iphone.slash") }
        }
        .contextMenu {
            Button("Вернуть в работу", systemImage: "arrow.uturn.backward") { restore(item) }
            Button("Убрать с телефона", systemImage: "iphone.slash") { closedStore.hide(item.id) }
        }
        .accessibilityIdentifier("archive.closed.\(item.id)")
    }

    /// Ссылка на историю выполнения — тем же видом, что ряды остальных
    /// разделов архива: подпись секции 13 pt `tfSub`, строка на подложке,
    /// разделитель, шеврон справа. Было голое `Label` прямо в списке: оно
    /// читалось как случайно брошенная строка (владелец 24.10.2026 —
    /// «в разнобой, вообще неадекватный вид»).
    private var historySection: some View {
        VStack(alignment: .leading, spacing: TFSpacing.xs) {
            TFSectionHeader("История")

            NavigationLink {
                ActivityScreen()
            } label: {
                TFListRow(
                    title: "Выполненные задачи",
                    subtitle: "График выполнения и закрытые задачи",
                    subtitleStyle: .meta,
                    titleStyle: .row,
                    verticalPadding: TFSpacing.sm,
                    horizontalPadding: TFSpacing.md,
                    minHeight: 44,
                    chevron: .shown
                )
                .tfScreenBackground()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("archive.completed-history")
        }
    }

    @ViewBuilder
    private var projectArchiveSection: some View {
        if !projectStore.archivedProjects.isEmpty {
            Group {
                // Единый заголовок секции — `TFSectionHeader` (13 pt `tfSub`,
                // LOCK-TYPOGRAPHY-UNIFY): было `.meta` 12.
                TFSectionHeader("Проекты")

                Group {
                    ForEach(projectStore.archivedProjects.indices, id: \.self) { i in
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
            .tfScreenBackground()
        }
        .disabled(busyID != nil)
        .contextMenu {
            Button("Восстановить", systemImage: "arrow.uturn.backward") { restoreProject(project) }
            Button("Удалить окончательно", systemImage: "trash", role: .destructive) { pendingProjectDelete = project }
        }
    }

    private func archiveDate(_ raw: String) -> String {
        DateFormats.sqliteUTC(raw)?.formatted(date: .abbreviated, time: .shortened) ?? raw
    }

    private func loadArchive() async {
        await closedStore.refresh()
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

    /// Вернуть в работу: только здесь полная карточка приходит на телефон.
    private func restore(_ item: ClosedTaskItem) {
        guard busyID == nil else { return }
        busyID = item.id
        Task {
            if await taskStore.restore(taskId: item.id) { closedStore.removeRestored(item.id) }
            busyID = nil
        }
    }
}

/// Ряд мини-карточки закрытой задачи.
private struct ClosedMiniCardRow: View {
    let item: ClosedTaskItem

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.title)
                .tfText(.row)
                .foregroundStyle(Color.tfText)
                .lineLimit(2)
            Text(ClosedMiniCard.meta(item))
                .tfText(.meta)
                .foregroundStyle(Color.tfSub)
                .lineLimit(1)
            if let outcome = item.outcome {
                Text(outcome)
                    .tfText(.meta)
                    .foregroundStyle(Color.tfSub)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, TFSpacing.screenHorizontal)
        .padding(.vertical, TFSpacing.sm)
        .contentShape(Rectangle())
    }
}

/// Мини-карточка закрытой задачи шторкой: название, проект, дата, пометка,
/// итог; «Вернуть в работу» и «Убрать с телефона».
private struct ClosedMiniCardSheet: View {
    let item: ClosedTaskItem
    let isBusy: Bool
    let onRestore: () -> Void
    let onHide: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.md) {
            Text(item.title)
                .tfText(.title)
                .foregroundStyle(Color.tfText)
            Text(ClosedMiniCard.meta(item))
                .tfText(.meta)
                .foregroundStyle(Color.tfSub)
            if let outcome = item.outcome {
                VStack(alignment: .leading, spacing: TFSpacing.xs) {
                    Text("Итог")
                        .tfText(.meta)
                        .foregroundStyle(Color.tfSub)
                    Text(outcome)
                        .tfText(.body)
                        .foregroundStyle(Color.tfText)
                        .textSelection(.enabled)
                }
            }
            TFButton("Вернуть в работу", icon: "arrow.uturn.backward", variant: .primary, isEnabled: !isBusy, action: onRestore)
            TFButton("Убрать с телефона", icon: "iphone.slash", variant: .secondary, action: onHide)
            Text("В статистике и на сервере задача останется.")
                .tfText(.meta)
                .foregroundStyle(Color.tfDim)
        }
        .padding(TFSpacing.screenHorizontal)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum ClosedMiniCard {
    /// «Проект · 12 нояб., 14:30 · выполнена».
    static func meta(_ item: ClosedTaskItem) -> String {
        var parts: [String] = []
        if let project = item.projectName, !project.isEmpty { parts.append(project) }
        if let date = ClosedTasksSnapshot.date(item.closedAt) {
            parts.append(date.formatted(date: .abbreviated, time: .shortened))
        }
        parts.append(item.kind == .completed ? "выполнена" : "в архиве")
        return parts.joined(separator: " · ")
    }
}
