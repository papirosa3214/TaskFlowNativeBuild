import SwiftUI

/// Невидимое наблюдение за подготовкой по событиям WebSocket. Самой подготовки в карточке больше нет
/// (владелец 07.10.2026: «занимает место и отвлекает») — она открывается из «Ещё».
/// При открытии, восстановлении связи и событии перечитывается снимок подготовки.
struct TaskPreparationPoller: View {
    let taskID: String
    let onChange: () async -> Void
    /// Чего автомат ждёт от владельца (`nil` — ничего): по этому «Ещё» в шапке
    /// получает отметку, а пункт «Подготовка» — подпись (владелец 07.10.2026).
    let onWaiting: (String?) -> Void
    @State private var signature: String?
    @Environment(RealtimeClient.self) private var realtime
    @Environment(\.scenePhase) private var scenePhase
    private let api = APIClient()

    var body: some View {
        Color.clear
            .task(id: "\(taskID):\(scenePhase):\(realtime.revision(for: taskID))") {
            guard scenePhase == .active else { return }
                await load()
            }
    }

    private func load() async {
        // Ошибки молча пропускаем: старый сервер этого маршрута не знает,
        // а показать их здесь негде — всё видимое живёт в шторке.
        guard let fresh = try? await api.taskPreparation(taskId: taskID) else { return }
        let next = "\(fresh.id)|\(fresh.status)|\(fresh.planID ?? "")|\(fresh.planStatus ?? "")"
        guard next != signature else { return }
        signature = next
        if fresh.canApproveStructure {
            onWaiting("Жду решения по разделению карточки")
        } else if fresh.status == "needs_clarification" || fresh.status == "structure_review" {
            onWaiting("Жду уточнения по задаче")
        } else {
            onWaiting(nil)
        }
        await onChange()
    }
}

/// Подготовка — текущий вопрос, готовые ответы и следующий шаг.
struct TaskPreparationView: View {
    let taskID: String
    let allowsExecution: Bool
    let onChange: () async -> Void
    @Environment(SessionStore.self) private var session
    @Environment(RealtimeClient.self) private var realtime
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @State private var preparation: ApiTaskPreparation?
    @State private var roles: [RoleProfile] = []
    @State private var errorMessage: String?
    @State private var actionError: String?
    @State private var isApplying = false
    @State private var isLoading = true
    @State private var selectedChoiceID: String?
    @State private var confirmingStructure = false
    @State private var confirmationInputVersion: Int?
    private let api = APIClient()
    private var isOwner: Bool { session.currentUser?.role == .owner }
    private var question: String? { preparation?.question }
    private var choices: [TaskPreparationReply.Choice] {
        guard let question else { return [] }
        let options = roles.filter(\.isEnabled).sorted {
            if $0.role == "builder" { return $1.role != "builder" }
            if $1.role == "builder" { return false }
            return $0.title < $1.title
        }.map { role in
            TaskPreparationReply.Choice(id: role.role, title: role.title,
                answer: "Исполнитель результата — \(role.title) (\(role.role)). Подготовить этап этой роли с результатом и критериями из описания задачи.")
        }
        return TaskPreparationReply.choices(for: question, roles: options)
    }
    private var selectedChoice: TaskPreparationReply.Choice? { choices.first { $0.id == selectedChoiceID } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TFSpacing.lg) {
                if isLoading {
                    ProgressView("Загружаю подготовку…")
                } else if let errorMessage {
                    // 16.10.2026 (LOCK-UI-DRIFT-KNOWN): системная кнопка в потоке
                    // экрана всегда синяя, а кнопки приложения серые. Заголовок и
                    // текст ошибки оставлены как есть — это не баннер ошибки, а
                    // состояние экрана; меняется только действие.
                    Text("Не удалось загрузить подготовку").tfText(.title)
                    Text(errorMessage).foregroundStyle(Color.tfSub)
                    TFButton("Повторить загрузку", icon: "arrow.clockwise", variant: .secondary) {
                        Task { await load() }
                    }
                    .accessibilityIdentifier("preparation.retry")
                } else {
                    current
                }
                if let actionError {
                    Text(actionError).foregroundStyle(Color.tfRed)
                        .accessibilityIdentifier("preparation.error")
                }
                if isApplying { ProgressView("Сохраняю решение…") }
                Divider()
                DisclosureGroup("Как работает подготовка") {
                    VStack(alignment: .leading, spacing: TFSpacing.sm) {
                        Text("Подготовка читает постановку и предлагает, кто выполнит работу и в каком порядке. Если нужен ваш выбор, он появится здесь.")
                        Text("Ответ продолжает подготовку. Исполнители начнут работу только после утверждения плана. Для дочерней карточки общий план утверждается в родительской задаче.")
                    }
                    .tfText(.body).foregroundStyle(Color.tfSub).padding(.top, TFSpacing.sm)
                }
                .accessibilityIdentifier("preparation.help")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(TFSpacing.lg)
        }
        .accessibilityIdentifier("preparation.content")
        .safeAreaInset(edge: .bottom) {
            if isOwner, question != nil, !choices.isEmpty,
               preparation?.status == "needs_clarification" || preparation?.status == "structure_review" {
                VStack(alignment: .leading, spacing: TFSpacing.sm) {
                    Text(selectedChoice.map { "Выбрано: \($0.title)" } ?? "Выберите один вариант")
                        .tfText(.body)
                        .accessibilityIdentifier("preparation.selection")
                    Button {
                        guard let preparation else { return }
                        Task { await sendReply(preparation) }
                    } label: {
                        Text("Продолжить подготовку").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedChoice == nil || isApplying)
                    .accessibilityIdentifier("preparation.continue")
                }
                .padding(TFSpacing.lg)
                .background(Color.tfSheetBackground)
            }
        }
        .disabled(isApplying)
        .interactiveDismissDisabled(isApplying)
        .task(id: "\(taskID):\(scenePhase):\(realtime.revision(for: taskID))") {
            guard scenePhase == .active else { return }
            do { roles = try await api.roles() }
            catch { roles = [] }
            await load()
        }
        .onChange(of: question) { _, _ in selectedChoiceID = nil }
        .onChange(of: preparation?.id) { _, _ in selectedChoiceID = nil }
        .onChange(of: preparation?.inputVersion) { _, _ in selectedChoiceID = nil }
        .confirmationDialog("Создать дочерние задачи?", isPresented: $confirmingStructure, titleVisibility: .visible) {
            Button("Создать согласованные задачи") {
                guard let version = confirmationInputVersion else { return }
                Task { await apply { try await api.approveTaskStructure(taskId: taskID, inputVersion: version) } }
            }
        }
    }

    @ViewBuilder private var current: some View {
        Text(statusTitle).font(.title2.weight(.semibold))
            .accessibilityIdentifier("preparation.status")
        if let preparation, preparation.status == "needs_clarification" || (preparation.status == "structure_review" && question != nil) {
            if let question {
                Text(question).tfText(.title)
                    .accessibilityIdentifier("preparation.question")
                Text("Выберите подходящий вариант.")
                    .tfText(.body).foregroundStyle(Color.tfSub)
                if isOwner {
                    if choices.isEmpty {
                        Text("Для этого вопроса готовые варианты пока не получены.").foregroundStyle(Color.tfSub)
                        // 16.10.2026 (LOCK-UI-DRIFT-KNOWN): кнопка приложения
                        // вместо системной синей.
                        TFButton("Повторить подготовку", icon: "arrow.clockwise", variant: .secondary) {
                            Task { await apply { try await api.retryTaskPreparation(taskId: taskID) } }
                        }
                        .accessibilityIdentifier("preparation.retryQuestion")
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: TFSpacing.sm) {
                            ForEach(choices) { choice in
                                Button {
                                    selectedChoiceID = choice.id
                                    actionError = nil
                                } label: {
                                    HStack(alignment: .center) {
                                        Text(choice.title).multilineTextAlignment(.leading)
                                        Spacer(minLength: 4)
                                        Image(systemName: selectedChoiceID == choice.id ? "checkmark.circle.fill" : "circle")
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                }
                                .buttonStyle(.bordered)
                                .accessibilityIdentifier("preparation.choice." + choice.id)
                                .accessibilityValue(selectedChoiceID == choice.id ? "Выбрано" : "Не выбрано")
                            }
                        }
                    }
                } else {
                    Text("Решение принимает владелец задачи.").foregroundStyle(Color.tfSub)
                }
            } else {
                Text("Подготовка ждёт уточнения, но конкретный вопрос не получен. Повторите подготовку, чтобы получить варианты решения.")
                if isOwner {
                    TFButton("Повторить подготовку", icon: "arrow.clockwise", variant: .secondary) {
                        Task { await apply { try await api.retryTaskPreparation(taskId: taskID) } }
                    }
                    .accessibilityIdentifier("preparation.retryNoQuestion")
                }
            }
        } else if let preparation, preparation.canApproveStructure {
            Text("Предложены дочерние задачи. Проверьте их результаты перед созданием.").foregroundStyle(Color.tfSub)
            if let proposal = preparation.result?.card?.preparation {
                ForEach(proposal.workstreams) { stream in
                    VStack(alignment: .leading, spacing: TFSpacing.xs) {
                        Text(stream.title).tfText(.title)
                        Text(stream.result).tfText(.body)
                        if let role = stream.role { Text(roles.first { $0.role == role }?.title ?? role).foregroundStyle(Color.tfSub) }
                    }
                }
            }
            if isOwner && allowsExecution {
                Button("Создать дочерние задачи") {
                    confirmationInputVersion = preparation.inputVersion
                    confirmingStructure = true
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("preparation.approveStructure")
            }
        } else {
            Text(statusDetail).foregroundStyle(Color.tfSub)
            if preparation?.isPending == true { ProgressView() }
            if preparation?.status == "failed", let error = preparation?.error {
                DisclosureGroup("Причина ошибки") { Text(error).tfText(.action) }
            }
            if isOwner && (preparation == nil || preparation?.status == "failed") {
                Button("Подготовить план") { Task { await apply { try await api.retryTaskPreparation(taskId: taskID) } } }
                    .buttonStyle(.borderedProminent)
            }
            if preparation?.status == "ready" || preparation?.planStatus == "approved" {
                Button("Вернуться к задаче") { dismiss() }.buttonStyle(.borderedProminent)
            }
        }
    }

    private var statusTitle: String {
        if preparation?.planStatus == "approved" { return "План согласован" }
        switch preparation?.status {
        case "queued", "running": return "Готовится"
        case "needs_clarification": return "Нужно уточнение"
        case "structure_review": return "Проверьте разделение задачи"
        case "ready": return "План подготовлен"
        case "failed": return "Не удалось подготовить план"
        case "skipped": return "Автоматическая подготовка не требуется"
        case "superseded": return "Подготовка устарела"
        default: return "План ещё не подготовлен"
        }
    }
    private var statusDetail: String {
        if preparation?.planStatus == "approved" { return "План уже утверждён. Состояние этапов доступно в карточке задачи." }
        switch preparation?.status {
        case "queued", "running": return "Подготовка определяет этапы и исполнителей. Результат появится здесь автоматически."
        case "ready": return "Черновик готов. Проверьте участников и связи в разделе «План совместной работы». Общий план дочерних задач утверждается в родительской карточке."
        case "failed": return "Подготовка завершилась с ошибкой. Её можно повторить; уже выполняющаяся работа продолжится."
        case "skipped": return "В карточке уже есть назначение, план или работа. Откройте её план, чтобы проверить состав команды."
        case "superseded": return "После подготовки постановку изменили. Этот результат больше не используется."
        default: return "Подготовьте черновик: он покажет участников, результаты и порядок работы."
        }
    }
    private func sendReply(_ expected: ApiTaskPreparation) async {
        guard let question = expected.question, let selectedChoice else { return }
        await apply {
            try await api.answerTaskPreparation(taskId: taskID, preparationID: expected.id,
                inputVersion: expected.inputVersion, question: question, answer: selectedChoice.answer)
        }
    }
    private func load() async {
        defer { isLoading = false }
        do {
            let fresh = try await api.taskPreparation(taskId: taskID)
            let changed = fresh?.id != preparation?.id || fresh?.status != preparation?.status || fresh?.question != preparation?.question
            preparation = fresh
            errorMessage = nil
            if changed { await onChange() }
        } catch { errorMessage = error.localizedDescription }
    }
    private func apply(_ action: () async throws -> Void) async {
        guard !isApplying else { return }
        isApplying = true
        actionError = nil
        defer { isApplying = false }
        do {
            try await action()
            selectedChoiceID = nil
            await onChange()
            await load()
        } catch {
            await load()
            actionError = error.localizedDescription
        }
    }
}
