import SwiftUI

/// Невидимый опрос подготовки. Самой подготовки в карточке больше нет
/// (владелец 07.10.2026: «занимает место и отвлекает») — она открывается из «Ещё».
/// Опрос остался: по смене его результата обновляется план на карточке.
struct TaskPreparationPoller: View {
    let taskID: String
    let onChange: () async -> Void
    /// Чего автомат ждёт от владельца (`nil` — ничего): по этому «Ещё» в шапке
    /// получает отметку, а пункт «Подготовка» — подпись (владелец 07.10.2026).
    let onWaiting: (String?) -> Void
    @State private var signature: String?
    private let api = APIClient()

    var body: some View {
        Color.clear
            .task(id: taskID) {
                signature = nil
                onWaiting(nil)
                await load()
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(3)) } catch { return }
                    await load()
                }
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

/// Раздел «Подготовка» — шторка из меню «Ещё» карточки: что это такое,
/// текущий статус с действием и расшифровка всех статусов.
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
    @State private var confirmingStructure = false
    @State private var confirmationInputVersion: Int?
    private let api = APIClient()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TFSpacing.lg) {
                Text("Автомат читает название и описание карточки и сам собирает черновик плана совместной работы: кто участвует и в каком порядке. Запускается при создании карточки и после правки названия, описания или проекта. Работу он не начинает — запуск только после вашего согласования плана.")
                    .tfText(.action).foregroundStyle(Color.tfDim)

                block("Сейчас") {
                    if isLoading {
                        ProgressView()
                    } else if let errorMessage {
                        Text(errorMessage).tfText(.action).foregroundStyle(Color.tfRed)
                        TFButton("Повторить загрузку", variant: .secondary) { Task { await load() } }
                    } else {
                        current
                    }
                }

                block("Что значат статусы") {
                    ForEach(Self.legend, id: \.key) { item in
                        VStack(alignment: .leading, spacing: TFSpacing.xs) {
                            Text(item.title).tfText(.action)
                                .foregroundStyle(item.key == currentKey ? Color.tfText : Color.tfSub)
                            Text(item.meaning).tfText(.meta).foregroundStyle(Color.tfDim)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(TFSpacing.lg)
        }
        .disabled(isApplying)
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
        .confirmationDialog("Создать дочерние задачи?", isPresented: $confirmingStructure, titleVisibility: .visible) {
            Button("Создать согласованные задачи") {
                guard let version = confirmationInputVersion else { return }
                Task { await apply { try await api.approveTaskStructure(taskId: taskID, inputVersion: version) } }
            }
        }
    }

    /// Текущий статус: название, что он значит, и то, что по нему можно сделать.
    @ViewBuilder
    private var current: some View {
        let item = Self.legend.first { $0.key == currentKey }
        Text(preparation.map(statusTitle) ?? item?.title ?? "").tfText(.taskTitle).foregroundStyle(Color.tfText)
        if let item { Text(item.meaning).tfText(.action).foregroundStyle(Color.tfSub) }
        if let preparation {
            if let question = preparation.question {
                Text(question).tfText(.action).foregroundStyle(Color.tfText)
            }
            if preparation.status == "failed", let error = preparation.error {
                Text("Причина: \(error)").tfText(.action).foregroundStyle(Color.tfSub)
            }
            if preparation.status == "structure_review", let proposal = preparation.result?.card?.preparation {
                Text(proposal.reason).tfText(.meta).foregroundStyle(Color.tfDim)
                ForEach(proposal.workstreams) { stream in
                    HStack(alignment: .top, spacing: TFSpacing.sm) {
                        if let role = stream.role {
                            TFAvatar(size: .lg, initials: String((roleTitles[role] ?? role).prefix(2)).uppercased(),
                                     tint: Color.tfCard2, accessibilityLabel: "Роль: \(roleTitles[role] ?? role)", userID: "role_\(role)")
                        }
                        VStack(alignment: .leading, spacing: TFSpacing.xs) {
                            Text(stream.title).tfText(.action).foregroundStyle(Color.tfText)
                            if let role = stream.role {
                                Text(roleTitles[role] ?? role).tfText(.meta).foregroundStyle(Color.tfDim)
                            }
                            Text("Результат: \(stream.result)").tfText(.meta).foregroundStyle(Color.tfSub)
                            if !stream.dependsOn.isEmpty {
                                Text("После: " + stream.dependsOn.map { key in
                                    proposal.workstreams.first { $0.key == key }?.title ?? key
                                }.joined(separator: ", "))
                                    .tfText(.meta).foregroundStyle(Color.tfDim)
                            }
                        }
                    }
                }
            }
            if isOwner, preparation.status == "failed" {
                TFButton("Повторить подготовку", variant: .secondary) {
                    Task { await apply { try await api.retryTaskPreparation(taskId: taskID) } }
                }
            }
            if isOwner, allowsExecution, preparation.canApproveStructure {
                TFButton("Согласовать дочерние задачи", variant: .secondary) {
                    confirmationInputVersion = preparation.inputVersion
                    confirmingStructure = true
                }
                .accessibilityIdentifier("preparation.approveStructure")
            }
        }
        if let actionError { Text(actionError).tfText(.action).foregroundStyle(Color.tfRed) }
    }

    private func block<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            Text(title).tfText(.meta).foregroundStyle(Color.tfDim)
            content()
        }
    }

    private struct LegendItem { let key: String; let title: String; let meaning: String }
    /// Статусы — как их выставляет сервер (`runtime/autoPreparation.ts`).
    private static let legend: [LegendItem] = [
        .init(key: "none", title: "Не запускалась",
              meaning: "Автомат берёт только активные карточки, лежащие в проекте. Плана от него нет."),
        .init(key: "pending", title: "Готовится",
              meaning: "Автомат читает карточку. Делать ничего не нужно, обычно это меньше минуты."),
        .init(key: "ready", title: "План подготовлен",
              meaning: "Черновик плана собран и лежит в «Плане совместной работы». Работа не начнётся, пока вы его не согласуете."),
        .init(key: "needs_clarification", title: "Нужно уточнение",
              meaning: "Постановки не хватило, плана нет. Дополните название или описание — подготовка запустится заново сама."),
        .init(key: "structure_review", title: "Предложено разделение",
              meaning: "Автомат считает, что задачу лучше разбить на дочерние карточки. Согласуете — создадутся карточки и зависимости между ними, работа при этом не начнётся."),
        .init(key: "failed", title: "Ошибка подготовки",
              meaning: "Автомат три раза не смог собрать план. Это сбой автомата, а не задачи: на уже идущую работу не влияет. Плана от него нет — можно повторить или собрать план через «Работа»."),
        .init(key: "skipped", title: "Пропущена",
              meaning: "У карточки уже есть свой план, исполнитель или идущая работа — автомат её не трогает."),
        .init(key: "superseded", title: "Устарела",
              meaning: "После этого прогона карточку изменили или план уже согласован. Результат прогона не используется."),
    ]

    private var currentKey: String {
        guard let preparation else { return "none" }
        return preparation.isPending ? "pending" : preparation.status
    }
    private var isOwner: Bool { session.currentUser?.role == .owner }
    private func statusTitle(_ preparation: ApiTaskPreparation) -> String {
        if preparation.planStatus == "approved" { return "План согласован" }
        if preparation.result?.approvedChildren != nil { return "Дочерние задачи созданы" }
        return Self.legend.first { $0.key == currentKey }?.title ?? preparation.status
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
