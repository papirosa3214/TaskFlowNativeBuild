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
    var scrolls = true

    @State private var diagnosticTasks: [String: ApiTask] = [:]
    @State private var diagnosticTaskErrors: [String: String] = [:]
    /// Карточек, которых сервер не знает (404) — не «не загрузилось», а
    /// именно нет. Владелец 11.10.2026: ссылка в сводке осталась, а задача
    /// не создана — тап по такой ведёл на экран, из которого нельзя было
    /// выйти. Такую ссылку не показываем вовсе, а другие сбои (сеть и пр.)
    /// оставляем как были, с баннером и рабочей кнопкой.
    @State private var missingTaskIDs: Set<String> = []
    private let apiClient = APIClient()


    var body: some View {
        Group {
            if scrolls { ScrollView { summaryContent } }
            else { summaryContent }
        }
        .task(id: diagnosticTaskIDs.joined(separator: ",")) {
            for taskId in diagnosticTaskIDs {
                do { diagnosticTasks[taskId] = try await apiClient.task(id: taskId) }
                catch {
                    if case .notFound = (error as? APIError) {
                        missingTaskIDs.insert(taskId)
                    } else {
                        diagnosticTaskErrors[taskId] = "Не удалось загрузить карточку диагностики"
                    }
                }
            }
        }
    }

    private var summaryContent: some View {
            VStack(alignment: .leading, spacing: TFSpacing.lg) {
                ServiceTicketStatusCounts(summary: summary)

                if let checks = summary.checks, !checks.isEmpty {
                    checkSection("Не отработали в штатном режиме", checks: checks.filter { $0.status != "ok" })
                    checkSection("Работают в штатном режиме", checks: checks.filter { $0.status == "ok" })
                } else if let summaryText = detail?.summaryText, !summaryText.isEmpty {
                    // Сводку сторожа пишет роль — рисуется общим рендером
                    // ответов (карточка 19f57bc9), а не своим разборщиком.
                    RoleReplyMarkdown(text: summaryText)
                } else {
                    RoleReplyMarkdown(text: summary.snippet)
                }

                metaSection

                ForEach(diagnosticTaskIDs, id: \.self) { taskId in
                    diagnosticSection(taskId: taskId)
                }

                if let items = detail?.resolutionItems, !items.isEmpty {
                    resolutionSection(items)
                }
            }
            .padding(TFSpacing.lg)
        }

    private var diagnosticTaskIDs: [String] {
        var ids = summary.links.compactMap { link -> String? in
            guard link.hasPrefix("tf://task/") else { return nil }
            return String(link.dropFirst("tf://task/".count))
        }
        if let id = detail?.diagnosticTaskId, !ids.contains(id) { ids.append(id) }
        return Array(NSOrderedSet(array: ids)) as? [String] ?? ids
    }

    private func checkSection(_ title: String, checks: [ServiceTicketCheck]) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.md) {
            HStack {
                Text(title).tfText(.title).foregroundStyle(Color.tfText)
                Spacer()
                Text("\(checks.count)").tfText(.row).foregroundStyle(Color.tfSub)
            }
            if checks.isEmpty {
                Text("Нет").tfText(.row).foregroundStyle(Color.tfDim)
            }
            ForEach(Array(checks.enumerated()), id: \.offset) { _, check in
                HStack(alignment: .top, spacing: TFSpacing.sm) {
                    Image(systemName: check.status == "ok" ? "checkmark.circle" : check.status == "error" ? "xmark.circle" : "clock")
                        .foregroundStyle(check.status == "ok" ? Color.tfGreen : check.status == "error" ? Color.tfRed : Color.tfOrange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(check.name).tfText(.body).foregroundStyle(Color.tfText)
                        Text(check.area).tfText(.caption).foregroundStyle(Color.tfDim)
                        Text(check.message).tfText(.row).foregroundStyle(Color.tfSub)
                    }
                }
            }
        }
    }

    private var metaSection: some View {
        VStack(alignment: .leading, spacing: TFSpacing.xs) {
            metaLine("Когда", NotificationTicketStyle.parseTicketDate(summary.ts).map { DirectoryDate.absolute($0) } ?? (detail?.when ?? summary.ts))
            metaLine("От кого", "Сервисы и приложение")
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

            if let task = diagnosticTasks[taskId] {
                metaLine("Исполнитель", task.assigneeName ?? "не назначен")
                if let created = task.createdAtDate {
                    metaLine("Создана", DirectoryDate.absolute(created))
                }
                if task.status == .completed, let completed = task.completedAtDate {
                    metaLine("Выполнена", DirectoryDate.absolute(completed))
                } else {
                    metaLine("Статус", statusLabel(task))
                }
            } else if let error = diagnosticTaskErrors[taskId] {
                TFErrorBanner(error, variant: .inline)
            } else if !missingTaskIDs.contains(taskId) {
                TFLoading(.inline)
            }

            if missingTaskIDs.contains(taskId) {
                // Ссылка в сводке есть, а задачи нет — говорим об этом прямо,
                // вместо тапа в пустоту.
                Text("Карточка не создана")
                    .tfText(.row).foregroundStyle(Color.tfDim)
            } else {
                Button {
                    onOpenTask(taskId)
                } label: {
                    TFListRow(
                        title: "Открыть карточку",
                        titleStyle: .row,
                        titleColor: Color.tfSub,
                        horizontalPadding: 0,
                        chevron: .shown
                    )
                }
                .buttonStyle(TFTapScaleStyle())
            }
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
