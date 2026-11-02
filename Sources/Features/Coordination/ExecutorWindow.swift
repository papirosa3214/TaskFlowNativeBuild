import SwiftUI
import Observation

/// Окно исполнителя: сводка по роли, которая делает шаг, и управление ею
/// прямо из окна координации.
///
/// Зачем: владелец открыл «Координацию» и по факту ничего не мог — узлы
/// показывали состояние, но не отвечали на вопрос «кто это делает, чего ждёт
/// и что ему сказать» (владелец, 02.11.2026). Здесь ответ на все три: кто
/// делает, чего ждёт, и кнопка «написать исполнителю» — сообщение уходит
/// в тему задачи, адресованное его слоту, и сервер подмешивает его в работу
/// роли, если та сейчас занята этим шагом.
@MainActor @Observable
final class ExecutorWindowModel {
    var summary: TaskExecutorSummary?
    var loading = false
    var loaded = false
    var error: String?
    /// Сервер без этого маршрута (старая выкладка .110) — не поломка.
    var unsupported = false
    var sending = false
    var answering = false
    /// Отправленные ответы на вопросы (id вопроса).
    var answered: Set<String> = []
    /// Выбранные варианты: ключ — «id вопроса:номер вопроса».
    var picked: [String: Set<String>] = [:]
    var sentText = ""

    private let api = APIClient()

    func load(taskID: String) async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            summary = try await api.taskExecutorSummary(taskId: taskID)
            error = nil
        } catch {
            if case APIError.routeMissing = error {
                unsupported = true
            } else {
                self.error = error.localizedDescription
            }
        }
        loaded = true
    }

    /// Исполнитель по слоту.
    func executor(subtaskID: String) -> TaskExecutor? {
        summary?.executors.first { $0.subtaskId == subtaskID }
    }

    /// Написать исполнителю: сообщение в тему задачи, адресованное его
    /// слоту. Упоминание роли не нужно: адресата определяет сам слот
    /// (сервер, `dispatchRoleReplies`), поэтому текст остаётся владельческим.
    func send(taskID: String, subtaskID: String, text: String, executorID: String?) async {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, !sending else { return }
        sending = true
        defer { sending = false }
        do {
            // Тема задачи — обычный путь. У задачи без проекта темы нет:
            // тогда открываем личную комнату роли и привязываем её к задаче.
            let chat: RoleChat
            if let topic = try? await api.taskTopic(taskID: taskID) {
                chat = topic
            } else if let executorID {
                chat = try await api.createRoleChat(
                    title: "Шаг задачи",
                    memberIDs: [executorID],
                    taskID: taskID
                )
            } else {
                throw APIError.routeMissing(message: "Нет темы задачи и не назначен исполнитель")
            }
            _ = try await api.sendRoleChatMessage(
                chatID: chat.id,
                text: body,
                executionMode: .card,
                recipientSubtaskID: subtaskID
            )
            sentText = body
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Ответить на вопрос роли: варианты по номерам вопросов.
    func answer(question: TaskExecutorQuestion) async {
        guard let payload = question.payload, !answering else { return }
        answering = true
        defer { answering = false }
        do {
            let entries = payload.questions.enumerated().map { index, _ in
                ChatQuestionAnswerEntry(
                    questionIndex: index,
                    selected: Array(picked[pickKey(question.id, index)] ?? []),
                    custom: nil
                )
            }
            _ = try await api.answerChatQuestion(
                chatID: question.chatId,
                questionID: question.id,
                answers: entries
            )
            answered.insert(question.id)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func pickKey(_ questionID: String, _ index: Int) -> String { "\(questionID):\(index)" }

    func toggle(questionID: String, index: Int, label: String, multi: Bool) {
        let key = pickKey(questionID, index)
        var current = picked[key] ?? []
        if multi {
            if current.contains(label) { current.remove(label) } else { current.insert(label) }
        } else {
            current = [label]
        }
        picked[key] = current
    }

    func selection(questionID: String, index: Int) -> Set<String> {
        picked[pickKey(questionID, index)] ?? []
    }
}

/// Окно исполнителя — шторка из окна координации по тапу на узел графа.
struct ExecutorWindow: View {
    let taskID: String
    let subtaskID: String
    @State private var model = ExecutorWindowModel()
    @State private var draft = ""
    @State private var taskChatID: String?
    @Environment(\.dismiss) private var dismiss

    private var executor: TaskExecutor? { model.executor(subtaskID: subtaskID) }

    var body: some View {
        NavigationStack {
            List {
                if model.loading && !model.loaded {
                    Section { TFLoading(.inline) }
                }
                if model.unsupported {
                    Section {
                        Text("Сервер пока не знает про сводку исполнителей").tfText(.body)
                        Text("Обновите TaskFlow на .110 — после выкладки окно покажет, кто чем занимается.").tfText(.meta)
                    }
                }
                if let error = model.error {
                    Section { TFErrorBanner(error, variant: .block) }
                }
                if let executor {
                    stepSection(executor)
                    roleSection(executor)
                    if !executor.questions.isEmpty { questionsSection(executor) }
                    if !executor.messages.isEmpty { messagesSection(executor) }
                    composeSection(executor)
                    taskChatSection
                } else if model.loaded && !model.unsupported {
                    Section {
                        TFEmptyState(
                            icon: "person.crop.circle.badge.questionmark",
                            text: "Исполнитель не найден",
                            description: "Шаг не входит в план карточки — обновите данные."
                        )
                    }
                }
            }
            .listStyle(.plain)
            .tfScreenBackground()
            .navigationTitle(executor?.roleTitle ?? "Исполнитель")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } }
            }
            .task { await model.load(taskID: taskID) }
            .refreshable { await model.load(taskID: taskID) }
            .sheet(isPresented: Binding(
                get: { taskChatID != nil },
                set: { if !$0 { taskChatID = nil } }
            )) {
                if let taskChatID { TaskChatSheet(chatID: taskChatID) }
            }
        }
    }

    // MARK: - Секции

    private func stepSection(_ executor: TaskExecutor) -> some View {
        Section("Шаг") {
            Text(executor.title).tfText(.body)
            HStack(spacing: TFSpacing.sm) {
                TFPill(executor.stateTitle, color: executor.stateTint)
                if executor.pendingMessages > 0 {
                    TFPill("Ждёт прочтения: \(executor.pendingMessages)", color: .tfOrange)
                }
                if executor.discussionId != nil {
                    TFPill("Идёт обсуждение", color: .tfPurple)
                }
            }
            Text(executor.statusText).tfText(.meta)
            if !executor.waitingFor.isEmpty {
                Text("Ожидает: " + executor.waitingFor.joined(separator: ", ")).tfText(.meta)
            }
            if let notes = executor.notes, !notes.isEmpty {
                Text(notes).tfText(.meta).textSelection(.enabled)
            }
        }
    }

    private func roleSection(_ executor: TaskExecutor) -> some View {
        Section("Исполнитель") {
            LabeledContent("Роль", value: executor.roleTitle ?? "Не назначена")
            LabeledContent("Состояние", value: executor.stateTitle)
            if let started = executor.attempt.startedAt {
                LabeledContent("Попытка началась", value: started)
            }
            if let outcome = executor.attempt.outcome {
                LabeledContent("Итог попытки", value: outcome)
            }
            if executor.metrics.attemptsInWindow > 0 {
                LabeledContent("Попыток за окно", value: "\(executor.metrics.attemptsInWindow)")
            }
            if executor.addressBlockReason != nil {
                Text("Написать сейчас нельзя: " + (executor.addressBlockReason ?? "")).tfText(.meta)
            }
        }
    }

    private func questionsSection(_ executor: TaskExecutor) -> some View {
        Section("Ждёт вашего ответа") {
            ForEach(executor.questions) { question in
                VStack(alignment: .leading, spacing: TFSpacing.sm) {
                    Text(question.roleTitle ?? "Роль").tfText(.meta).foregroundStyle(Color.tfDim)
                    if model.answered.contains(question.id) {
                        TFPill("Отвечено", color: .tfGreen)
                    } else if let payload = question.payload {
                        ForEach(Array(payload.questions.enumerated()), id: \.offset) { index, item in
                            questionItem(question: question, index: index, item: item)
                        }
                    } else {
                        Text("Вопрос без вариантов ответа").tfText(.meta)
                    }
                }
                .padding(.vertical, TFSpacing.xs)
            }
        }
    }

    @ViewBuilder
    private func questionItem(
        question: TaskExecutorQuestion,
        index: Int,
        item: TaskExecutorQuestionItem
    ) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.xs) {
            Text(item.question).tfText(.body)
            ForEach(item.options, id: \.label) { option in
                let chosen = model.selection(questionID: question.id, index: index).contains(option.label)
                Button {
                    model.toggle(questionID: question.id, index: index, label: option.label, multi: item.multiSelect)
                    if !item.multiSelect {
                        Task { await model.answer(question: question) }
                    }
                } label: {
                    HStack(spacing: TFSpacing.sm) {
                        Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(chosen ? Color.tfGreen : Color.tfDim)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.label).tfText(.body)
                            if let description = option.description, !description.isEmpty {
                                Text(description).tfText(.meta).foregroundStyle(Color.tfDim)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(TFTapRowStyle())
            }
            if item.multiSelect {
                TFButton("Ответить", icon: "checkmark", variant: .secondary) {
                    Task { await model.answer(question: question) }
                }
            }
        }
    }

    private func messagesSection(_ executor: TaskExecutor) -> some View {
        Section("Переписка по шагу") {
            ForEach(executor.messages) { message in
                VStack(alignment: .leading, spacing: 2) {
                    Text(message.isFromOwner ? "Вы" : (executor.roleTitle ?? "Роль"))
                        .tfText(.meta)
                        .foregroundStyle(Color.tfDim)
                    Text(message.text).tfText(.body)
                }
                .padding(.vertical, TFSpacing.xs)
            }
        }
    }

    private func composeSection(_ executor: TaskExecutor) -> some View {
        Section("Написать исполнителю") {
            TFTextField("Что сказать исполнителю", text: $draft, icon: "bubble.left.and.bubble.right")
            Text("Сообщение уходит в тему задачи и адресуется этому шагу — роль увидит его в своей работе.").tfText(.meta)
            TFButton(
                model.sentText.isEmpty ? "Отправить" : "Отправить ещё",
                icon: "paperplane.fill",
                variant: .primary,
                isEnabled: !model.sending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ) {
                let text = draft
                draft = ""
                Task {
                    await model.send(
                        taskID: taskID,
                        subtaskID: subtaskID,
                        text: text,
                        executorID: executor.executorId
                    )
                }
            }
        }
    }

    private var taskChatSection: some View {
        Section {
            Button("Открыть переписку по задаче") {
                Task {
                    if let chat = try? await APIClient().taskTopic(taskID: taskID) {
                        taskChatID = chat.id
                    }
                }
            }
        }
    }

}

/// Цвет состояния исполнителя — тот же язык, что у координации: «идёт работа»
/// синяя, «ждёт вас» оранжевая, «готово» зелёная.
extension TaskExecutor {
    var stateTint: Color {
        switch state {
        case "working": return .tfBlue
        case "waiting": return .tfTeal
        case "ready": return .tfGreen
        case "queued": return .tfYellow
        case "blocked": return .tfOrange
        case "review": return .tfPurple
        case "done": return .tfGreen
        case "skipped": return .tfDim
        default: return .tfDim
        }
    }
}
