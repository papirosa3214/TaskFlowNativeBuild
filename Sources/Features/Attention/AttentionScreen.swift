import SwiftUI
import Observation

// «Входящие» (владелец 28.10.2026): один экран со всем, что требует внимания —
// решения по шагам и карточкам, вопросы ролей с кнопками, сбои и зависшие ходы,
// сроки на сегодня, кто работает сейчас и что ближайшее. Данные — одним ответом
// GET /api/attention, сервер собирает сам.

struct ApiAttentionItem: Decodable, Identifiable {
    let kind: String
    let id: String
    let title: String
    let context: String?
    let role: String?
    let age_seconds: Int?
    let actions: [String]?
    /// Карточка, к которой относится событие: тап открывает её.
    let task_id: String?
}

struct ApiAttentionToday: Decodable, Identifiable {
    let id: String
    let title: String
    let due_date: String?
    let project: String?
}

struct ApiAttentionRunning: Decodable, Identifiable {
    let id: String
    let task_id: String?
    let title: String
    let role: String?
    let since_seconds: Int?
}

struct ApiAttentionUpcoming: Decodable, Identifiable {
    let id: String
    let kind: String
    let title: String
    let at: String?
}

struct ApiAttention: Decodable {
    let ok: Bool
    let decisions: [ApiAttentionItem]
    let failures: [ApiAttentionItem]
    let today: [ApiAttentionToday]
    let running: [ApiAttentionRunning]
    let upcoming: [ApiAttentionUpcoming]
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
        return data.decisions.isEmpty && data.failures.isEmpty && data.today.isEmpty
            && data.running.isEmpty && data.upcoming.isEmpty
    }

    func load() async {
        if data == nil { isLoading = true }
        errorMessage = nil
        do {
            data = try await api.request(.get, "/attention")
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
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
                            description: "Ничего не ждёт решения, ничего не сломалось."
                        )
                    }
                    .listRowSeparator(.hidden)
                }
                if !data.decisions.isEmpty {
                    attentionSection("Нужно твоё решение", tint: Color.tfRed, items: data.decisions)
                }
                if !data.failures.isEmpty {
                    attentionSection("Сломалось", tint: Color.tfOrange, items: data.failures)
                }
                if !data.today.isEmpty {
                    Section {
                        header("Сроки сегодня", tint: Color.tfBlue)
                        ForEach(data.today) { item in
                            NavigationLink(value: AppRoute.taskDetail(taskID: item.id)) {
                                HStack(spacing: TFSpacing.sm) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title).tfText(.body).foregroundStyle(Color.tfText)
                                        if let project = item.project, !project.isEmpty {
                                            Text(project).tfText(.caption).foregroundStyle(Color.tfSub)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(Color.tfDim)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if !data.running.isEmpty {
                    Section {
                        header("Идёт сейчас", tint: Color.tfTeal)
                        ForEach(data.running) { run in
                            NavigationLink(value: run.task_id.map { AppRoute.taskDetail(taskID: $0) } ?? .agentWork(focus: nil)) {
                                HStack(spacing: TFSpacing.sm) {
                                    Text(run.role ?? "Роль").tfText(.action).foregroundStyle(Color.tfText)
                                    Text(run.title).tfText(.caption).foregroundStyle(Color.tfSub).lineLimit(1)
                                    Spacer()
                                    if let s = run.since_seconds {
                                        Text(Self.ago(s)).tfText(.caption).foregroundStyle(Color.tfDim)
                                    }
                                    Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(Color.tfDim)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if !data.upcoming.isEmpty {
                    Section {
                        header("Ближайшее", tint: Color.tfDim)
                        ForEach(data.upcoming) { item in
                            HStack(spacing: TFSpacing.sm) {
                                Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(Color.tfDim)
                                Text(item.title).tfText(.action).foregroundStyle(Color.tfText).lineLimit(1)
                                Spacer()
                                if let at = item.at {
                                    Text(Self.when(at)).tfText(.caption).foregroundStyle(Color.tfDim)
                                }
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

    @ViewBuilder
    private func attentionSection(_ title: String, tint: Color, items: [ApiAttentionItem]) -> some View {
        Section {
            header(title, tint: tint)
            ForEach(items) { item in
                NavigationLink(value: Self.route(for: item)) {
                    HStack(spacing: TFSpacing.sm) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).tfText(.body).foregroundStyle(Color.tfText).lineLimit(2)
                            HStack(spacing: TFSpacing.xs) {
                                if let role = item.role {
                                    Text(role).tfText(.caption).foregroundStyle(Color.tfSub)
                                }
                                if let context = item.context, !context.isEmpty {
                                    Text(context).tfText(.caption).foregroundStyle(Color.tfDim).lineLimit(1)
                                }
                                Spacer()
                                if let s = item.age_seconds {
                                    Text(Self.ago(s)).tfText(.caption).foregroundStyle(Color.tfDim)
                                }
                            }
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.tfDim)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func header(_ title: String, tint: Color) -> some View {
        HStack(spacing: TFSpacing.sm) {
            Circle().fill(tint).frame(width: 8, height: 8)
            Text(title).tfText(.action).foregroundStyle(Color.tfText)
        }
    }

    /// Куда ведёт строка: вопрос роли — в чат с этой ролью, всё остальное —
    /// в карточку задачи, где владелец отвечает, принимает или перезапускает шаг.
    /// Владелец 28.10.2026: «нажимаю — и меня перекидывает на само событие».
    static func route(for item: ApiAttentionItem) -> AppRoute {
        if item.kind == "chat" { return .roleChat(id: item.id) }
        if let taskId = item.task_id { return .taskDetail(taskID: taskId) }
        return .roleChat(id: item.id)
    }

    static func ago(_ seconds: Int) -> String {
        if seconds < 60 { return "только что" }
        if seconds < 3600 { return "\(seconds / 60) мин" }
        if seconds < 86_400 { return "\(seconds / 3600) ч" }
        return "\(seconds / 86_400) дн"
    }

    static func when(_ iso: String) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = parser.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMM, HH:mm"
        return formatter.string(from: date)
    }
}
