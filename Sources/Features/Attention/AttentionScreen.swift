import SwiftUI
import Observation

@MainActor
@Observable
final class AttentionViewModel {
    var data: ApiAttention?
    var isLoading = false
    var errorMessage: String?
    private let api: APIClient
    init(api: APIClient = APIClient()) { self.api = api }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            data = try await api.request(.get, APIEndpoint.attention.list)
        } catch is CancellationError {
            // Leaving the tab does not turn cancellation into a failed request.
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Only actionable owner requests. Opening a ticket never approves its action.
struct AttentionScreen: View {
    @State private var model = AttentionViewModel()
    @State private var answeringTicket: ApiAttentionTicket?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: TFSpacing.md) {
                if let error = model.errorMessage {
                    TFErrorBanner(error, variant: .block)
                    Button("Повторить") { Task { await model.load() } }
                }
                if let data = model.data {
                    if let tickets = data.tickets {
                        if tickets.isEmpty && model.errorMessage == nil {
                            TFEmptyState(
                                icon: "tray",
                                text: "Нет обращений",
                                description: "Агенты не ждут вашего ответа или решения."
                            )
                        }
                        ForEach(tickets) { ticket in
                            ticketLink(ticket)
                        }
                    } else {
                        TFEmptyState(
                            icon: "arrow.triangle.2.circlepath",
                            text: "Нужно обновление сервера",
                            description: "Этот сервер ещё не поддерживает обращения во входящих."
                        )
                    }
                } else if model.isLoading {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, TFSpacing.screenHorizontal)
            .padding(.vertical, TFSpacing.md)
        }
        .tfNativeHeader("Входящие", displayMode: .large)
        .background(Color.tfBackground)
        .hintAnchor(HintAnchorID.inboxTickets)
        .refreshable { await model.load() }
        .onAppear { Task { await model.load() } }
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { break }
                if scenePhase == .active { await model.load() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.load() } }
        }
        .sheet(item: $answeringTicket, onDismiss: { Task { await model.load() } }) { ticket in
            if let question = ticket.question, let chatID = ticket.chat_id {
                NavigationStack {
                    ScrollView {
                        RoleQuestionCard(question: question) { answers, note in
                            _ = try await APIClient().answerChatQuestion(
                                chatID: chatID, questionID: question.id, answers: answers, note: note
                            )
                            answeringTicket = nil
                            await model.load()
                        }
                        .padding(TFSpacing.screenHorizontal)
                    }
                    .background(Color.tfBackground)
                    .navigationTitle("Ответ агенту")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Закрыть") { answeringTicket = nil }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func ticketLink(_ ticket: ApiAttentionTicket) -> some View {
        switch ticket.action {
        case .answer:
            Button { answeringTicket = ticket } label: { ticketCard(ticket) }
                .buttonStyle(TFTapRowStyle())
        case .task(let id):
            NavigationLink(value: AppRoute.taskDetail(taskID: id)) { ticketCard(ticket) }
                .buttonStyle(.plain)
        case .chat(let id):
            NavigationLink(value: AppRoute.roleChat(id: id)) { ticketCard(ticket) }
                .buttonStyle(.plain)
        case nil:
            ticketCard(ticket)
        }
    }

    private func ticketCard(_ ticket: ApiAttentionTicket) -> some View {
        TFCard {
            VStack(alignment: .leading, spacing: TFSpacing.md) {
                HStack(alignment: .top, spacing: TFSpacing.sm) {
                    Image(systemName: ticket.kind == "question" ? "questionmark.bubble" :
                            ticket.kind == "approval" ? "checkmark.shield" : "hand.raised")
                        .tfText(.body)
                        .foregroundStyle(Color.tfBlue)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: TFSpacing.xs) {
                        Text(ticket.role ?? "Команда")
                            .tfText(.action)
                            .foregroundStyle(Color.tfText)
                        Text(ticket.kindTitle)
                            .tfText(.meta)
                            .foregroundStyle(Color.tfSub)
                    }
                    Spacer(minLength: TFSpacing.xs)
                    if let date = ticket.createdDate {
                        Text(date, style: .relative)
                            .tfText(.meta)
                            .foregroundStyle(Color.tfDim)
                            .multilineTextAlignment(.trailing)
                    }
                }
                Text(ticket.title)
                    .tfText(.taskTitle)
                    .foregroundStyle(Color.tfText)
                    .fixedSize(horizontal: false, vertical: true)
                if !ticket.body.isEmpty {
                    Text(ticket.body)
                        .tfText(.body)
                        .foregroundStyle(Color.tfSub)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let context = ticket.context_title {
                    Text(context)
                        .tfText(.meta)
                        .foregroundStyle(Color.tfDim)
                        .lineLimit(2)
                }
                if let project = ticket.project, !project.isEmpty {
                    Text(project)
                        .tfText(.meta)
                        .foregroundStyle(Color.tfDim)
                        .lineLimit(1)
                }
                HStack {
                    Text(ticket.actionTitle)
                        .tfText(.action)
                    Spacer()
                    if ticket.action != nil {
                        Image(systemName: "arrow.up.right")
                            .tfText(.action)
                            .accessibilityHidden(true)
                    }
                }
                .foregroundStyle(Color.tfBlue)
                .frame(minHeight: 44)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("inbox.ticket." + ticket.id)
    }
}
