import SwiftUI
import Observation

// «Входящие» (владелец 28.10.2026, переделка 29.10.2026): это не лента событий,
// а три статуса, на которые владелец обязан смотреть — «Заблокировано»,
// «В работе», «На проверке». Строка списка — карточка задачи; тап открывает
// ту же стандартную карточку задачи (`AppRoute.taskDetail`), без боковых панелей.

struct ApiAttentionTask: Decodable, Identifiable {
    let id: String
    let title: String
    let project: String?
    let role: String?
    let age_seconds: Int?
    let overdue: Bool?
}

struct ApiAttentionGroup: Decodable, Identifiable {
    let key: String
    let title: String
    let count: Int
    let tasks: [ApiAttentionTask]
    /// Идентификатор для `ForEach` — ключ группы. Без него структура не
    /// соответствует `Identifiable`, и проект не собирается (внесено
    /// коммитом b5cce4a6 29.10.2026).
    var id: String { key }
}

struct ApiAttention: Decodable {
    let ok: Bool
    let groups: [ApiAttentionGroup]
}

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
                            ForEach(group.tasks) { task in
                                NavigationLink(value: AppRoute.taskDetail(taskID: task.id)) {
                                    taskRow(task, tint: AttentionViewModel.tint(for: group.key))
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

    private func taskRow(_ task: ApiAttentionTask, tint: Color) -> some View {
        HStack(spacing: TFSpacing.md) {
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .tfText(.body)
                    .foregroundStyle(Color.tfText)
                    .lineLimit(2)
                HStack(spacing: TFSpacing.xs) {
                    if let project = task.project, !project.isEmpty {
                        Text(project).tfText(.caption).foregroundStyle(Color.tfSub).lineLimit(1)
                    }
                    if let role = task.role, !role.isEmpty {
                        Text(role).tfText(.caption).foregroundStyle(Color.tfDim)
                    }
                    if task.overdue == true {
                        Text("просрочено").tfText(.caption).foregroundStyle(Color.tfRed)
                    }
                    if let s = task.age_seconds {
                        Text(Self.ago(s)).tfText(.caption).foregroundStyle(Color.tfDim)
                    }
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
        }
        .padding(.vertical, TFSpacing.xs)
        .contentShape(Rectangle())
    }

    static func ago(_ seconds: Int) -> String {
        if seconds < 60 { return "только что" }
        if seconds < 3600 { return "\(seconds / 60) мин" }
        if seconds < 86_400 { return "\(seconds / 3600) ч" }
        return "\(seconds / 86_400) дн"
    }
}
