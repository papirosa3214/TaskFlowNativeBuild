import SwiftUI

struct TaskPreparationView: View {
    let taskID: String
    let allowsExecution: Bool
    let onChange: () async -> Void
    @Environment(SessionStore.self) private var session
    @State private var preparation: ApiTaskPreparation?
    @State private var errorMessage: String?
    @State private var actionError: String?
    @State private var roleTitles: [String: String] = [:]
    @State private var isApplying = false
    @State private var isLoading = true
    @State private var confirmingPlan = false
    @State private var confirmingStructure = false
    @State private var confirmationPlanID: String?
    @State private var confirmationBranchSnapshot: String?
    @State private var confirmationInputVersion: Int?
    private let api = APIClient()

    var body: some View {
        Group {
            // Секция «Подготовка» больше не показывает статус «готова» и не дублирует
            // согласование плана (оно в меню «Ещё»): владелец 06.10.2026. Остаётся только то,
            // где нужно действие или что-то сломалось. Опрос состояния ниже работает по-прежнему —
            // по нему обновляется план на карточке.
            if let preparation, ["failed", "needs_clarification", "structure_review"].contains(preparation.status) {
                preparationSection {
                    Group {
                        if preparation.isPending {
                            ProgressView(preparation.status == "queued" ? "Ожидает подготовки" : "Подготавливаем план…")
                        } else {
                            TFPill(statusTitle(preparation), color: Color.tfSub)
                        }
                        if let question = preparation.question {
                            Text(question).tfText(.action).foregroundStyle(Color.tfSub)
                        }
                        if let proposal = preparation.result?.card?.preparation {
                            Text(proposal.reason).tfText(.meta).foregroundStyle(Color.tfDim)
                            ForEach(proposal.workstreams) { stream in
                                DisclosureGroup {
                                    Label("Результат: \(stream.result)", systemImage: "doc.text")
                                        .tfText(.action).foregroundStyle(Color.tfSub)
                                    if !stream.dependsOn.isEmpty {
                                        Label("После: " + stream.dependsOn.map { key in
                                            proposal.workstreams.first { $0.key == key }?.title ?? key
                                        }.joined(separator: ", "), systemImage: "arrow.turn.down.right")
                                            .tfText(.meta).foregroundStyle(Color.tfDim)
                                    }
                                } label: {
                                    HStack(spacing: TFSpacing.sm) {
                                        if let role = stream.role {
                                            TFAvatar(size: .lg, initials: String((roleTitles[role] ?? role).prefix(2)).uppercased(),
                                                     tint: Color.tfCard2, accessibilityLabel: "Роль: \(roleTitles[role] ?? role)", userID: "role_\(role)")
                                        }
                                        VStack(alignment: .leading, spacing: TFSpacing.xs) {
                                            Text(stream.title).tfText(.action).foregroundStyle(Color.tfSub)
                                            if let role = stream.role {
                                                TFPill(roleTitles[role] ?? role, color: Color.tfDim)
                                            }
                                        }
                                    }
                                }
                                .tfText(.action)
                            }
                        }
                        if preparation.status == "failed" {
                            Text(preparation.error ?? "Подготовка не завершена").tfText(.action)
                            if isOwner { Button("Повторить подготовку") { Task { await apply { try await api.retryTaskPreparation(taskId: taskID) } } } }
                        }
                        if isOwner, allowsExecution, preparation.canApproveStructure {
                            Button("Согласовать дочерние задачи") {
                                confirmationInputVersion = preparation.inputVersion
                                confirmingStructure = true
                            }
                                .foregroundStyle(Color.tfDim)
                                .accessibilityIdentifier("preparation.approveStructure")
                            Text("Создадим карточки и зависимости. Работа пока не начнётся.")
                                .tfText(.action).foregroundStyle(Color.tfDim)
                        }
                        if preparation.status == "needs_clarification" || (preparation.status == "structure_review" && preparation.question != nil) {
                            Text("Дополните название или описание задачи. Подготовка повторится после сохранения.")
                                .tfText(.action).foregroundStyle(Color.tfDim)
                        }
                        if let message = actionError ?? errorMessage { Text(message).tfText(.action).foregroundStyle(Color.tfRed) }
                    }
                    .tfText(.action)
                    .foregroundStyle(Color.tfSub)
                    .buttonStyle(.borderless)
                    .disabled(isApplying)
                }
            } else if isLoading {
                preparationSection { ProgressView("Проверяем подготовку…") }
            } else if let errorMessage {
                preparationSection {
                    Text(errorMessage).tfText(.action)
                    Button("Повторить загрузку") { Task { await load() } }
                        .foregroundStyle(Color.tfDim)
                }
            }
        }
        .tfText(.action)
        .tint(Color.tfDim)
        .task(id: taskID) {
            if let roles = try? await api.roles() {
                roleTitles = Dictionary(roles.map { ($0.role, $0.title) }, uniquingKeysWith: { first, _ in first })
            }
            await load()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                if isApplying { continue }
                await load()
            }
        }
        .confirmationDialog("Согласовать и запустить план?", isPresented: $confirmingPlan, titleVisibility: .visible) {
            Button("Запустить согласованный план") {
                guard let planID = confirmationPlanID else { return }
                Task { await apply { _ = try await api.approveCollaborationPlan(taskId: taskID, planId: planID, branchSnapshot: confirmationBranchSnapshot) } }
            }
        } message: { Text("Исполнители начнут работу по показанному графу. Процессные подзадачи создадутся автоматически.") }
        .confirmationDialog("Создать дочерние задачи?", isPresented: $confirmingStructure, titleVisibility: .visible) {
            Button("Создать согласованные задачи") {
                guard let version = confirmationInputVersion else { return }
                Task { await apply { try await api.approveTaskStructure(taskId: taskID, inputVersion: version) } }
            }
        }
    }
    private func preparationSection<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        Section {
            content()
        } header: {
            Text("Подготовка")
                .tfText(.taskTitle)
                .fontWeight(.semibold)
                .foregroundStyle(Color.tfText)
                .textCase(nil)
        }
        .listRowBackground(Color.tfBackground)
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
    }

    private var isOwner: Bool { session.currentUser?.role == .owner }
    private func statusTitle(_ preparation: ApiTaskPreparation) -> String {
        if preparation.planStatus == "approved" { return "План согласован" }
        if preparation.result?.approvedChildren != nil { return "Дочерние задачи созданы" }
        switch preparation.status {
        case "ready": return "Подготовка готова"
        case "structure_review": return "Предложена структура дочерних задач"
        case "needs_clarification": return "Нужно уточнение"
        case "failed": return "Ошибка подготовки"
        default: return preparation.status
        }
    }
    private func load() async {
        defer { isLoading = false }
        do {
            let fresh = try await api.taskPreparation(taskId: taskID)
            let changed = preparation?.id != fresh?.id || preparation?.status != fresh?.status || preparation?.planID != fresh?.planID || preparation?.planStatus != fresh?.planStatus
            preparation = fresh
            errorMessage = nil
            if changed { await onChange() }
        } catch {
            // Старый сервер ещё не предоставляет этот маршрут.
            if case APIError.server(let status, _) = error, status == 404 { preparation = nil; return }
            errorMessage = error.localizedDescription
        }
    }
    private func apply(_ action: () async throws -> Void) async {
        isApplying = true
        actionError = nil
        defer { isApplying = false }
        do { try await action(); await onChange(); await load() }
        catch {
            await load()
            actionError = error.localizedDescription
        }
    }
}
