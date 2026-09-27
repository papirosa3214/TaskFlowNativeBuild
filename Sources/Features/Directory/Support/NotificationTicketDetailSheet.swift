import SwiftUI

/// Полный разбор карточки-тикета — нативное окно снизу на всю высоту
/// (`.tfBottomSheet` в `NotificationTicketCard`), владелец 27.09.2026: «как
/// в карточку задачи должен проваливаться», нормальный размер шрифта
/// (`.body`/`.row`, не `.meta`/`.caption`, тут ничего мельче остального
/// приложения). Показывает: когда/от кого/уровень/тревога, полный текст
/// сводки, кто и когда создал карточку диагностики (живой запрос задачи),
/// когда она выполнена — если готова, и строки «Итог по устранению».
struct NotificationTicketDetailSheet: View {
    let summary: ServiceTicketSummary
    let detail: ServiceTicketDetail?
    let onOpenTask: (String) -> Void
    let onTapResolutionItem: (ServiceTicketResolutionItem) -> Void

    @State private var diagnosticTask: ApiTask?
    @State private var diagnosticTaskError: String?
    private let apiClient = APIClient()

    private var isAlarm: Bool { detail?.isAlarm ?? (summary.level == "error") }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TFSpacing.lg) {
                metaSection

                if let summaryText = detail?.summaryText, !summaryText.isEmpty {
                    NotificationTicketStyle.markdownText(summaryText)
                        .tfText(.body).foregroundStyle(Color.tfText)
                } else {
                    NotificationTicketStyle.markdownText(summary.snippet)
                        .tfText(.body).foregroundStyle(Color.tfText)
                }

                if let taskId = detail?.diagnosticTaskId {
                    diagnosticSection(taskId: taskId)
                }

                if let items = detail?.resolutionItems, !items.isEmpty {
                    resolutionSection(items)
                }
            }
            .padding(TFSpacing.lg)
        }
        .task(id: detail?.diagnosticTaskId) {
            guard let taskId = detail?.diagnosticTaskId else { return }
            do {
                diagnosticTask = try await apiClient.task(id: taskId)
            } catch {
                diagnosticTaskError = "Не удалось загрузить карточку диагностики"
            }
        }
    }

    private var metaSection: some View {
        VStack(alignment: .leading, spacing: TFSpacing.xs) {
            if isAlarm {
                Label("Тревога", systemImage: "exclamationmark.triangle.fill")
                    .tfText(.body).foregroundStyle(Color.tfRed)
            }
            metaLine("Когда", NotificationTicketStyle.parseTicketDate(summary.ts).map { DirectoryDate.absolute($0) } ?? (detail?.when ?? summary.ts))
            metaLine("От кого", detail?.from ?? summary.source)
            metaLine("Уровень", detail?.level ?? summary.level)
        }
    }

    private func metaLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: TFSpacing.sm) {
            Text(label).tfText(.row).foregroundStyle(Color.tfDim).frame(width: 90, alignment: .leading)
            Text(value).tfText(.row).foregroundStyle(Color.tfSub)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func diagnosticSection(taskId: String) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            Label("Карточка диагностики", systemImage: "wrench.and.screwdriver")
                .tfText(.title).foregroundStyle(Color.tfText)

            if let task = diagnosticTask {
                metaLine("Исполнитель", task.assigneeName ?? "не назначен")
                if let created = task.createdAtDate {
                    metaLine("Создана", DirectoryDate.absolute(created))
                }
                if task.status == .completed, let completed = task.completedAtDate {
                    metaLine("Выполнена", DirectoryDate.absolute(completed))
                } else {
                    metaLine("Статус", statusLabel(task))
                }
            } else if let error = diagnosticTaskError {
                TFErrorBanner(error, variant: .inline)
            } else {
                TFLoading(.inline)
            }

            Button {
                onOpenTask(taskId)
            } label: {
                HStack(spacing: 4) {
                    Text("Открыть карточку").tfText(.row).foregroundStyle(Color.tfSub)
                    Spacer()
                    Image(systemName: "chevron.right").imageScale(.small).foregroundStyle(Color.tfDim)
                }
            }
            .buttonStyle(TFTapScaleStyle())
        }
    }

    /// `status` (active/completed) и `agent_state` (in_progress/blocked/review)
    /// — независимые поля (spec §7), не один enum.
    private func statusLabel(_ task: ApiTask) -> String {
        switch task.agentState {
        case .review: return "на проверке"
        case .blocked: return "заблокирована"
        case .inProgress: return "в работе"
        case .todo: return "в очереди"
        case nil: return task.status == .completed ? "выполнена" : "не в работе"
        }
    }

    private func resolutionSection(_ items: [ServiceTicketResolutionItem]) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            Label("Итог по устранению", systemImage: "checkmark.seal")
                .tfText(.title).foregroundStyle(Color.tfText)
            ForEach(items) { item in
                resolutionRow(item)
            }
        }
    }

    @ViewBuilder
    private func resolutionRow(_ item: ServiceTicketResolutionItem) -> some View {
        switch item.status {
        case .fixed:
            Button {
                if let taskId = item.taskId { onOpenTask(taskId) }
            } label: {
                Text("\(item.problem) — (исправлено)").tfText(.row).foregroundStyle(Color.tfDim)
            }
            .buttonStyle(TFTapScaleStyle())
            .disabled(item.taskId == nil)
        case .unresolved, .needsDecision:
            // Симметрично ветке `.fixed`: тап реально открывает модалку
            // (комментарий уйдёт в задачу `taskId`) — если ни у пункта, ни у
            // тикета (fallback `detail?.diagnosticTaskId`) нет ссылки на
            // задачу, строка дизейблится и гаснет, а не остаётся тапабельной
            // без эффекта.
            let canResolve = item.taskId != nil || detail?.diagnosticTaskId != nil
            Button {
                onTapResolutionItem(item)
            } label: {
                Text(resolutionRowText(item)).tfText(.row)
                    .foregroundStyle(canResolve ? Color.tfRed : Color.tfDim)
                    .underline(canResolve)
            }
            .buttonStyle(TFTapScaleStyle())
            .disabled(!canResolve)
        }
    }

    private func resolutionRowText(_ item: ServiceTicketResolutionItem) -> String {
        switch item.status {
        case .fixed: return "\(item.problem) — (исправлено)"
        case .unresolved(let reason): return "\(item.problem) — (не исправлено: \(reason))"
        case .needsDecision: return "\(item.problem) — (не исправлено, нужно ваше решение)"
        }
    }
}
