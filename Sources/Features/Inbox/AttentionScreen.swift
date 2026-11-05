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
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
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
                        ForEach(AttentionTicketSection.grouping(tickets)) { section in
                            Section {
                                ForEach(section.tickets) { ticket in
                                    ticketLink(ticket)
                                        .padding(.vertical, TFSpacing.sm)
                                    if ticket.id != section.tickets.last?.id {
                                        Divider()
                                    }
                                }
                            } header: {
                                HStack(alignment: .firstTextBaseline, spacing: TFSpacing.sm) {
                                    Image(systemName: section.symbol)
                                        .imageScale(.large)
                                        .foregroundStyle(ticketAccent(section.tickets[0]))
                                        .accessibilityHidden(true)
                                    Text(section.title)
                                        .foregroundStyle(Color.tfText)
                                }
                                .tfText(.taskTitle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, TFSpacing.md)
                                .tfScreenBackground()
                                .accessibilityAddTraits(.isHeader)
                            }
                        }
                    } else {
                        TFEmptyState(
                            icon: "arrow.triangle.2.circlepath",
                            text: "Нужно обновление сервера",
                            description: "Этот сервер ещё не поддерживает обращения во входящих."
                        )
                    }
                } else if model.isLoading {
                    TFLoading(.block)
                }
            }
            .padding(.horizontal, TFSpacing.screenHorizontal)
            .padding(.vertical, TFSpacing.md)
        }
        .tfNativeHeader("Входящие", displayMode: .large)
        .tfScreenBackground()
        .tint(Color.tfText)
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
        .tfSheet(item: $answeringTicket, onDismiss: { Task { await model.load() } }) { ticket in
            if let question = ticket.question, let chatID = ticket.chat_id {
                NavigationStack {
                    ScrollView {
                        RoleQuestionCard(question: question, nativePresentation: true) { answers, note in
                            _ = try await APIClient().answerChatQuestion(
                                chatID: chatID, questionID: question.id, answers: answers, note: note
                            )
                            answeringTicket = nil
                            await model.load()
                        }
                        .padding(TFSpacing.screenHorizontal)
                    }
                    .navigationTitle("Ответ агенту")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Закрыть") { answeringTicket = nil }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
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
            TaskCardLink(taskID: id) { ticketCard(ticket) }
                .buttonStyle(.plain)
        case .chat(let id):
            NavigationLink(value: AppRoute.roleChat(id: id)) { ticketCard(ticket) }
                .buttonStyle(.plain)
        case nil:
            ticketCard(ticket)
        }
    }

    private func ticketCard(_ ticket: ApiAttentionTicket) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.xs) {
            if let summary = ticket.cardSummary {
                Text(summary)
                    .tfText(.body)
                    .foregroundStyle(Color.tfText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .bottom, spacing: TFSpacing.sm) {
                VStack(alignment: .leading, spacing: TFSpacing.xs) {
                    Text(ticket.role ?? "Команда")
                        .lineLimit(1)
                    Text(ticket.sourceTitle)
                }
                .tfText(.meta)
                .foregroundStyle(Color.tfDim)
                .frame(maxWidth: .infinity, alignment: .leading)

            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .multilineTextAlignment(.leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("inbox.ticket." + ticket.id)
    }

    private func ticketAccent(_ ticket: ApiAttentionTicket) -> Color {
        switch ticket.kind {
        case "question": .tfPurple
        case "approval": .tfTeal
        case "decision": .tfOrange
        default: .tfSub
        }
    }
}
