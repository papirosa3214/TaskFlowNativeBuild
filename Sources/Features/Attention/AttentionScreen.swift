import SwiftUI
import Observation

// «Входящие» (владелец 28.10.2026, переделка 29.10.2026): это не лента событий,
// а три статуса, на которые владелец обязан смотреть — «Заблокировано»,
// «В работе», «На проверке». Строка списка — карточка задачи; тап открывает
// ту же стандартную карточку задачи (`AppRoute.taskDetail`), без боковых панелей.
//
// Наводящая строка (владелец 29.10.2026): под названием задачи — строка о том,
// что с ней делать, чтобы не открывать карточку и вникать заново. Строку
// собирает сервер (`Sources/Core/Models/AttentionFeed.swift`), телефон её
// только рисует.

@MainActor
@Observable
final class AttentionViewModel {
    var data: ApiAttention?
    var isLoading = false
    var errorMessage: String?

    private let api: APIClient

    init(api: APIClient = APIClient()) { self.api = api }

    var isEmpty: Bool {
        guard let data else { return false }
        return data.groups.allSatisfy { $0.tasks.isEmpty }
    }

    func load() async {
        if data == nil { isLoading = true }
        errorMessage = nil
        do {
            data = try await api.request(.get, APIEndpoint.attention.list)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Цвет маркера группы — смысл тот же, что у статусов на доске.
    static func tint(for key: String) -> Color {
        switch key {
        case "blocked": Color.tfRed
        case "in_progress": Color.tfTeal
        case "review": Color.tfBlue
        default: Color.tfDim
        }
    }
}

struct AttentionScreen: View {
    @State private var model = AttentionViewModel()

    var body: some View {
        List {
            if let error = model.errorMessage {
                Section {
                    TFErrorBanner(error, variant: .block)
                    Button("Повторить") { Task { await model.load() } }
                        .tfText(.action)
                        .foregroundStyle(Color.tfText)
                }
                .listRowSeparator(.hidden)
            }

            if let data = model.data {
                if model.isEmpty {
                    Section {
                        TFEmptyState(
                            icon: "checkmark.circle",
                            text: "Всё чисто",
                            description: "Ни одной задачи в работе, на проверке или в блоке."
                        )
                    }
                    .listRowSeparator(.hidden)
                }
                ForEach(data.groups) { group in
                    if !group.tasks.isEmpty {
                        Section {
                            groupHeader(group)
                                .listRowBackground(Color.tfCard)
                                .listRowSeparator(.hidden)
                            ForEach(group.tasks) { task in
                                NavigationLink(value: AppRoute.taskDetail(taskID: task.id)) {
                                    taskRow(task)
                                }
                                .buttonStyle(.plain)
                                .listRowBackground(Color.tfCard)
                            }
                        }
                    }
                }
            } else if model.isLoading {
                Section { ProgressView().frame(maxWidth: .infinity) }
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .tfNativeHeader("Входящие", displayMode: .large)
        .background(Color.tfBackground)
        .refreshable { await model.load() }
        .task { await model.load() }
    }

    /// Подзаголовок раздела — тот же вход, что у разделов «Обзора» и «Настроек»
    /// (`tfSectionDisplay(.taskTitle)`), плюс счётчик и цветная точка статуса.
    private func groupHeader(_ group: ApiAttentionGroup) -> some View {
        HStack(spacing: TFSpacing.sm) {
            Circle()
                .fill(AttentionViewModel.tint(for: group.key))
                .frame(width: 8, height: 8)
            Text(group.title)
                .tfSectionDisplay(style: .taskTitle)
            Spacer()
            Text("\(group.count)")
                .tfText(.action)
                .foregroundStyle(Color.tfDim)
        }
    }

    /// Строка задачи — та же геометрия, что строки задач в остальных списках
    /// (`TFTaskRowContent`): аватар роли слева, название, наводящая строка и
    /// ряд меток. Свой шеврон у строки не рисуется: у `NavigationLink` он
    /// свой, и вместе они давали два шеврона подряд.
    private func taskRow(_ task: ApiAttentionTask) -> some View {
        TFTaskRowContent(
            title: task.title,
            description: task.hintLine,
            isDone: false,
            descriptionLines: 2
        ) {
            if let initials = task.roleInitials {
                TFAvatar(
                    size: .taskList,
                    initials: initials,
                    tint: Color(hex: TFHexDefault.unassigned),
                    userID: task.role_id
                )
            }
        } metadata: {
            if let project = task.project, !project.isEmpty {
                Text("#\(project)")
                    .foregroundStyle(Color.tfSub)
                    .lineLimit(1)
                    .layoutPriority(-1)
            }
            TFTaskStructureIndicators(
                priority: task.priority.flatMap { TaskPriority(rawValue: $0) },
                subtasksDone: task.subtask_done,
                subtasksTotal: task.subtask_total,
                childrenCount: 0,
                hasCollaborationPlan: false
            )
            if let role = task.role, !role.isEmpty {
                Text(role)
                    .foregroundStyle(Color.tfDim)
                    .lineLimit(1)
                    .layoutPriority(-1)
            }
            if task.overdue == true {
                Text("просрочено")
                    .foregroundStyle(Color.tfRed)
                    .layoutPriority(-1)
            }
            if let s = task.age_seconds {
                Text(Self.ago(s))
                    .foregroundStyle(Color.tfDim)
                    .layoutPriority(-1)
            }
        }
    }

    static func ago(_ seconds: Int) -> String {
        if seconds < 60 { return "только что" }
        if seconds < 3600 { return "\(seconds / 60) мин" }
        if seconds < 86_400 { return "\(seconds / 3600) ч" }
        return "\(seconds / 86_400) дн"
    }
}
