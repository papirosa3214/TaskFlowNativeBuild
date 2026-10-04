import SwiftUI
import Observation

@MainActor @Observable
final class LinearImportViewModel {
    var workspace: LinearWorkspace?
    var issues: [LinearSourceIssue] = []
    var projects: [ApiProject] = []
    var selected = Set<String>()
    var projectID: String?
    var cursor: String?
    var search = ""
    var loading = false
    var error: String?
    var preview: LinearImportPreview?
    var result: LinearImportResult?
    var importedPreview: LinearImportPreview?
    private let api: any LinearImportServing
    init(api: any LinearImportServing = APIClient()) { self.api = api }

    var filteredIssues: [LinearSourceIssue] {
        let text = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? issues : issues.filter { "\($0.identifier) \($0.title)".localizedCaseInsensitiveContains(text) }
    }
    var selectedProjectName: String { projects.first { $0.id == projectID }?.name ?? "Без проекта" }

    func load(next: Bool = false) async {
        guard !loading else { return }
        loading = true; error = nil
        defer { loading = false }
        do {
            let page = try await api.linearIssues(cursor: next ? cursor : nil)
            if next && workspace?.id != page.workspace.id { throw LinearImportClientError.workspaceChanged }
            if !next { issues = []; selected = []; preview = nil; result = nil }
            workspace = page.workspace
            var known = Set(issues.map(\.id))
            issues += page.issues.filter { known.insert($0.id).inserted }
            cursor = page.cursor
            if !next { projects = try await api.projects() }
        } catch { self.error = error.localizedDescription }
    }
    func toggle(_ id: String) {
        guard !loading else { return }
        if selected.contains(id) { selected.remove(id) }
        else if selected.count < 50 { selected.insert(id) }
        else { error = "За один раз можно выбрать до 50 задач."; return }
        preview = nil; result = nil; error = nil
    }
    func prepare() async {
        guard !loading, !selected.isEmpty else { return }
        loading = true; error = nil
        defer { loading = false }
        do { preview = try await api.linearPreview(issueIDs: selected.sorted(), projectID: projectID); result = nil }
        catch { self.error = error.localizedDescription }
    }
    func commit() async -> Bool {
        guard !loading, let preview else { return false }
        loading = true; error = nil
        defer { loading = false }
        do { result = try await api.importLinear(previewID: preview.previewID); importedPreview = preview; self.preview = nil; return true }
        catch { self.error = error.localizedDescription; return false }
    }
}
enum LinearImportClientError: LocalizedError {
    case workspaceChanged
    case preparation(String)
    var errorDescription: String? {
        switch self {
        case .workspaceChanged: "Рабочее пространство Linear изменилось. Загрузите список заново."
        case .preparation(let message): message
        }
    }
}

struct LinearImportScreen: View {
    @State private var model: LinearImportViewModel
    @Environment(TaskStore.self) private var taskStore
    @Environment(ProjectStore.self) private var projectStore
    @State private var detail: LinearPreviewItem?
    @State private var showsDetail = false
    let embedded: Bool
    let onOpenConnection: (() -> Void)?
    init(api: any LinearImportServing = APIClient(), embedded: Bool = false, onOpenConnection: (() -> Void)? = nil) {
        self.onOpenConnection = onOpenConnection
        self.embedded = embedded
        _model = State(initialValue: LinearImportViewModel(api: api))
    }

    var body: some View {
        Group {
            if embedded {
                VStack(alignment: .leading, spacing: TFSpacing.md) { content; actions }
            } else {
                ScrollView { content.padding(TFSpacing.lg) }
                    .background(Color.tfBackground)
                    .tfNativeHeader("Linear", displayMode: .inline)
                    .safeAreaInset(edge: .bottom) { actions.padding(TFSpacing.lg).background(Color.tfBackground) }
            }
        }
        .tfBottomSheet(isPresented: $showsDetail, title: detail?.identifier) {
            if let detail {
                ScrollView {
                    VStack(alignment: .leading, spacing: TFSpacing.lg) {
                        Text(detail.title).tfText(.title)
                        Text(detail.description ?? "Без описания").tfText(.body).textSelection(.enabled)
                        Text("Linear: \(detail.sourceState)\nИсполнитель: \(detail.sourceAssignee ?? "Не назначен")\nКомментарии: \(detail.comments) · История: \(detail.history)\nМетки: \(detail.labels) · Вложения: \(detail.attachments) · Документы: \(detail.documents ?? 0)").tfText(.action).foregroundStyle(Color.tfSub)
                        if let url = URL(string: detail.url) { Link("Открыть оригинал в Linear", destination: url).tfText(.body) }
                    }.padding(TFSpacing.lg)
                }
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: TFSpacing.md) {
            Text(model.workspace?.name ?? "Выборочный перенос задач и структуры")
                .tfText(.caption).foregroundStyle(Color.tfSub)
            TFErrorBanner(model.error, variant: .block)
            if let result = model.result { resultSection(result) }
            else if let preview = model.preview { previewSection(preview) }
            else { selectionSection }
            if model.loading { TFLoading(.inline) }
        }
    }

    private var connectionRow: some View {
        TFListRow(icon: "link", iconStyle: .plain, title: "Подключение аккаунта Linear",
            subtitle: "Сервер MCP → Composio",
            trailing: AnyView(Image(systemName: "chevron.right").foregroundStyle(Color.tfDim)),
            titleStyle: .action, verticalPadding: TFSpacing.xs)
    }

    @ViewBuilder private var selectionSection: some View {
        Text("Выберите задачи для переноса. Родители и дочерние карточки будут показаны перед импортом.")
            .tfText(.action).foregroundStyle(Color.tfSub)
        TFButton(model.workspace == nil ? "Синхронизация" : "Обновить список", icon: "arrow.clockwise", variant: .secondary, isEnabled: !model.loading) {
            Task { await model.load() }
        }.accessibilityIdentifier("linear.load")
        if model.workspace == nil {
            if let onOpenConnection {
                Button(action: onOpenConnection) { connectionRow }
                    .buttonStyle(.plain)
            } else {
                NavigationLink { ServiceAccountsScreen(composioExpanded: true) } label: { connectionRow }
                    .buttonStyle(.plain)
            }
        } else {
            Menu {
                Button("Без проекта") { model.projectID = nil }
                ForEach(model.projects) { project in Button(project.name) { model.projectID = project.id } }
            } label: {
                TFCard(padding: 0) { TFListRow(icon: "folder", iconStyle: .plain, title: "Проект TaskFlow", subtitle: model.selectedProjectName,
                    trailing: AnyView(Image(systemName: "chevron.up.chevron.down").foregroundStyle(Color.tfDim))) }
            }
                .accessibilityIdentifier("linear.project")
                .disabled(model.loading)
            TFTextField("Найти среди загруженных задач", text: $model.search, icon: "magnifyingglass")
            TFSectionHeader("Задачи Linear · выбрано \(model.selected.count)")
            TFCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(model.filteredIssues.enumerated()), id: \.element.id) { index, issue in
                        if index > 0 { TFDivider(inset: TFSpacing.lg) }
                        HStack(spacing: 0) {
                            Button { model.toggle(issue.id) } label: {
                                Image(systemName: model.selected.contains(issue.id) ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(model.selected.contains(issue.id) ? Color.tfText : Color.tfDim)
                                    .frame(width: TFHitTarget.min, height: TFHitTarget.min)
                            }.buttonStyle(TFTapRowStyle()).accessibilityLabel("Выбрать \(issue.identifier)")
                                .accessibilityIdentifier("linear.select.\(issue.id)")
                                .accessibilityValue(model.selected.contains(issue.id) ? "Выбрана" : "Не выбрана")
                            TFTaskRow(TFTaskRowModel(projectName: issue.project?.name, title: "\(issue.identifier) · \(issue.title)",
                                                    description: issue.description, agentStatus: issue.state.name, agentStatusColor: .tfSub, dueText: issue.dueDate)) {
                                model.toggle(issue.id)
                            }
                        }.padding(.leading, TFSpacing.sm).disabled(model.loading)
                    }
                }
            }
            if model.filteredIssues.isEmpty { TFEmptyState(text: "Задачи не найдены") }
            if model.cursor != nil {
                TFButton("Загрузить ещё", icon: "arrow.down", variant: .secondary, isEnabled: !model.loading) { Task { await model.load(next: true) } }
                    .accessibilityIdentifier("linear.more")
            }
        }
    }

    private func previewSection(_ preview: LinearImportPreview) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.lg) {
            TFSectionHeader("Предварительный просмотр")
            TFCard {
                Text("Новых карточек: \(preview.createCount)\nУже в TaskFlow: \(preview.updateCount)\nВключено для структуры: \(preview.items.filter { $0.reason == "hierarchy" }.count)")
                    .tfText(.body).accessibilityIdentifier("linear.preview.summary")
            }
            Text("Уже перенесённые задачи будут обновлены в существующих карточках — копии не создаются. Дочерние задачи находятся внутри родительской. Локальные правки сохраняются.")
                .tfText(.action).foregroundStyle(Color.tfSub)
            ForEach(preview.warnings, id: \.self) { Text($0).tfText(.caption).foregroundStyle(Color.tfSub) }
            TFCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(preview.rows) { row in
                        VStack(alignment: .leading, spacing: TFSpacing.xs) {
                            TFTaskRow(TFTaskRowModel(title: "\(row.item.identifier) · \(row.item.title)",
                                                    description: row.item.description,
                                                    agentStatus: "\(row.item.action == "create" ? "Новая карточка" : "Уже в TaskFlow")\(row.item.reason == "hierarchy" ? " · Для структуры" : "")",
                                                    agentStatusColor: .tfSub,
                                                    childrenCount: preview.items.filter { $0.parentID == row.id }.count)) {
                                detail = row.item; showsDetail = true
                            }.accessibilityIdentifier("linear.preview.\(row.id)")
                                .padding(.leading, CGFloat(min(row.depth, 5)) * TFSpacing.md)
                            Text(previewRelation(row.item, in: preview))
                                .tfText(.caption).foregroundStyle(Color.tfSub)
                                .padding(.horizontal, TFSpacing.lg)
                                .accessibilityIdentifier("linear.preview.relation.\(row.id)")
                            if row.item.action == "update", let taskID = row.item.taskID {
                                NavigationLink(value: AppRoute.taskDetail(taskID: taskID)) {
                                    Label("Открыть в TaskFlow", systemImage: "doc.text")
                                        .tfText(.action).foregroundStyle(Color.tfSub)
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, TFSpacing.lg)
                                .accessibilityIdentifier("linear.preview.existing.\(row.id)")
                            }
                            if !row.item.conflicts.isEmpty {
                                Text("Сохранятся локальные правки: \(row.item.conflicts.map(fieldName).joined(separator: ", "))")
                                    .tfText(.caption).foregroundStyle(Color.tfText).padding(.horizontal, TFSpacing.lg)
                            }
                            TFDivider(inset: TFSpacing.lg)
                        }
                    }
                }
            }
            TFButton("Обновить просмотр", icon: "arrow.clockwise", variant: .secondary, isEnabled: !model.loading) { Task { await model.prepare() } }
        }
    }

    private func resultSection(_ result: LinearImportResult) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.lg) {
            Text("Перенос завершён").tfText(.title).accessibilityIdentifier("linear.import.done")
            Text("Создано: \(result.created) · Обновлено: \(result.updated)").tfText(.body)
            if !result.conflicts.isEmpty { Text("Локальные правки сохранены у \(result.conflicts.count) карточек.").tfText(.action).foregroundStyle(Color.tfSub) }
            TFCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(result.taskIDs) { task in
                        let source = model.importedPreview?.items.first { $0.id == task.sourceID }
                        NavigationLink(value: AppRoute.taskDetail(taskID: task.taskID)) {
                            TFListRow(icon: "doc.text", iconStyle: .plain,
                                      title: source.map { "\($0.identifier) · \(task.title)" } ?? task.title,
                                      subtitle: source.map { item in
                                          let action = item.action == "create" ? "Создана" : "Обновлена существующая"
                                          let relation = model.importedPreview.map { previewRelation(item, in: $0) } ?? ""
                                          return "\(action) · \(relation)"
                                      })
                        }.buttonStyle(.plain)
                        TFDivider(inset: TFSpacing.lg)
                    }
                }
            }
        }
    }

    @ViewBuilder private var actions: some View {
        if model.result != nil {
            TFButton("Выбрать другие задачи", variant: .secondary, isEnabled: !model.loading) { model.result = nil; model.selected = [] }
        } else if let preview = model.preview {
            HStack(spacing: TFSpacing.md) {
                TFButton("Назад", variant: .secondary, isEnabled: !model.loading) { model.preview = nil }
                TFButton(preview.createCount == 0 ? "Обновить существующие (\(preview.updateCount))" : preview.updateCount == 0 ? "Создать карточки (\(preview.createCount))" : "Создать \(preview.createCount) · обновить \(preview.updateCount)", icon: "arrow.down", variant: .secondary, isEnabled: !model.loading) {
                    Task { if await model.commit() { await taskStore.load(silent: true); await projectStore.load() } }
                }.accessibilityIdentifier("linear.import.confirm")
            }
        } else {
            TFButton("Предварительный просмотр (\(model.selected.count))", icon: "list.bullet.indent", variant: .secondary, isEnabled: !model.loading && !model.selected.isEmpty) {
                Task { await model.prepare() }
            }.accessibilityIdentifier("linear.preview")
            Text("Покажет выбранные задачи, их родителей и подзадачи, связи и изменения перед переносом в TaskFlow. На этом этапе ничего не переносится.")
                .tfText(.caption).foregroundStyle(Color.tfSub)
                .accessibilityIdentifier("linear.preview.explanation")
        }
    }
    private func previewRelation(_ item: LinearPreviewItem, in preview: LinearImportPreview) -> String {
        if let parentID = item.parentID {
            if let parent = preview.items.first(where: { $0.id == parentID }) {
                return "В Linear дочерняя: \(parent.identifier) · \(parent.title)"
            }
            return "В Linear дочерняя задача"
        }
        return preview.items.contains(where: { $0.parentID == item.id }) ? "Родительская задача" : "Самостоятельная задача"
    }

    private func fieldName(_ value: String) -> String {
        ["title":"название", "description":"описание", "priority":"приоритет", "due_date":"срок", "status":"статус", "parent_id":"родитель" ][value] ?? (value.hasPrefix("comment:") ? "комментарий" : value.hasPrefix("history:") ? "история" : value)
    }
}
