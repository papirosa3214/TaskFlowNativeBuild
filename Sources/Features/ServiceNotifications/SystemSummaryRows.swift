import SwiftUI

/// One visible row per problem/check. Explicit incident keys and task IDs join
/// the two sources; a coincidentally equal count or similar title is not a link.
struct SystemSummaryItem: Identifiable {
    enum Kind: Int, CaseIterable {
        case broken, warning, repaired, normal
        var title: String {
            switch self {
            case .broken: "Поломки"
            case .warning: "Тревоги"
            case .repaired: "Починено"
            case .normal: "Работает в штатном режиме"
            }
        }
        var icon: String {
            switch self {
            case .broken: "xmark.circle"
            case .warning: "exclamationmark.circle"
            case .repaired: "checkmark.circle.fill"
            case .normal: "checkmark.circle"
            }
        }
        var color: Color {
            switch self {
            case .broken: .tfRed
            case .warning: .tfOrange
            case .repaired, .normal: .tfGreen
            }
        }
    }
    let id: String
    let title: String
    /// `nil` — подпись нечего рисовать: её не было или она была заглушкой
    /// («Сервер» у трёх проверок из шестнадцати). Пустой подписью строка
    /// выглядит полнее, но содержательно не добавляет ничего.
    let area: String?
    let message: String
    let kind: Kind
    let taskID: String?

    /// `closedIncidents` — поломки, закрытые архивом карточки починки
    /// (сервер отдаёт их в `GET /api/system-state` отдельным списком).
    /// Строка проверки, привязанная только к закрытой поломке, не рисуется:
    /// починка не нужна, показывать нечего (владелец 20.10.2026).
    static func compose(checks: [ServiceTicketCheck],
                        incidents: [SystemState.Incident],
                        closedIncidents: [SystemState.Closed] = []) -> [Self] {
        var represented = Set<String>()
        var rows: [Self] = []
        for (index, check) in checks.enumerated() {
            let incident = incidents.first {
                $0.key == check.incidentKey || check.diagnosticTaskIDs?.contains($0.id) == true
            }
            if let incident, !represented.insert(incident.id).inserted { continue }
            // Живая поломка важнее закрытой: если та же поломка возникла
            // снова, у неё новая карточка — строка возвращается. Закрытая
            // поломка без живой — строку убираем.
            if incident == nil, isClosed(check: check, closedIncidents: closedIncidents) { continue }
            // Свою карточку поломки проверка уже представлена — её состояние
            // и есть факт, статус проверки вторичен.
            let kind: Kind
            if let incident { kind = incident.fixed ? .repaired : .broken }
            else if check.status == "error" { kind = .broken }
            else if check.status != "ok" { kind = .warning }
            // `status: ok` с текстом об отказе (за 12–16.10 это «Проверка
            // сервиса»: вчера error, сегодня ok при том же тексте). Помещать
            // в «Работает в штатном режиме» значит показать зелёную галочку на
            // противоречии; в «Тревоги» — потому что формально прошла, а
            // фактически нет, и почему пока не ясно.
            else if ServiceTicketPresentation.contradictsSuccess(check.message) { kind = .warning }
            else { kind = check.recovered == true ? .repaired : .normal }
            let status = incident.map { "\($0.statusLine)" + ($0.workLine.map { "\n" + $0 } ?? "") }
            let message = ([ServiceTicketPresentation.readable(check), status].compactMap { $0 }
                .joined(separator: "\n"))
            rows.append(Self(id: incident?.id ?? "check-\(index)", title: check.name,
                             area: ServiceTicketPresentation.readableArea(check), message: message,
                             kind: kind, taskID: incident?.id ?? check.diagnosticTaskIDs?.first))
        }
        for incident in incidents where !represented.contains(incident.id) {
            rows.append(Self(id: incident.id, title: incident.title, area: "Работа по устранению неисправности",
                             message: [incident.statusLine, incident.workLine].compactMap { $0 }.joined(separator: "\n"),
                             kind: incident.fixed ? .repaired : .broken, taskID: incident.id))
        }
        return rows
    }

    /// Привязана ли проверка к поломке, которая уже закрыта архивом карточки
    /// починки. Связь — по ключу поломки (`incident_key`) или по id карточки
    /// в `diagnostic_task_ids`.
    private static func isClosed(check: ServiceTicketCheck, closedIncidents: [SystemState.Closed]) -> Bool {
        guard !closedIncidents.isEmpty else { return false }
        if let key = check.incidentKey, closedIncidents.contains(where: { $0.key == key }) { return true }
        if let ids = check.diagnosticTaskIDs,
           closedIncidents.contains(where: { ids.contains($0.id) }) { return true }
        return false
    }
}

struct SystemSummaryRows: View {
    let items: [SystemSummaryItem]
    let openTask: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.lg) {
            HStack(spacing: TFSpacing.lg) {
                ForEach(SystemSummaryItem.Kind.allCases, id: \.self) { kind in
                    Label("\(items.filter { $0.kind == kind }.count)", systemImage: kind.icon)
                        .foregroundStyle(kind.color)
                        .accessibilityLabel("\(kind.title): \(items.filter { $0.kind == kind }.count)")
                }
            }.tfText(.row)
            ForEach(SystemSummaryItem.Kind.allCases, id: \.self) { kind in
                VStack(alignment: .leading, spacing: TFSpacing.md) {
                    Text(kind.title).tfText(.title).foregroundStyle(Color.tfText)
                    let matching = items.filter { $0.kind == kind }
                    if matching.isEmpty { Text("Нет").tfText(.row).foregroundStyle(Color.tfDim) }
                    ForEach(matching) { item in
                        if let taskID = item.taskID {
                            Button { openTask(taskID) } label: { SystemSummaryInformationRow(item: item, showsLink: true) }
                                .buttonStyle(TFTapRowStyle())
                                .accessibilityIdentifier("system-summary-task-\(taskID)")
                        } else { SystemSummaryInformationRow(item: item, showsLink: false) }
                    }
                }
            }
        }
        .padding(TFSpacing.lg)
    }
}

struct SystemSummaryInformationRow: View {
    let item: SystemSummaryItem
    var showsLink = true

    var body: some View {
        HStack(alignment: .top, spacing: TFSpacing.sm) {
            Image(systemName: item.kind.icon).foregroundStyle(item.kind.color)
            VStack(alignment: .leading, spacing: TFSpacing.xs) {
                Text(item.title).tfText(.body).foregroundStyle(Color.tfText)
                // Подпись рисуется, только когда несёт смысл: заглушка «Сервер»
                // — это шум без содержания (владелец 16.10.2026).
                if let area = item.area {
                    Text(area).tfText(.caption).foregroundStyle(Color.tfDim)
                }
                Text(item.message).tfText(.row).foregroundStyle(Color.tfSub)
            }
            Spacer(minLength: 0)
            if showsLink { Image(systemName: "chevron.right").foregroundStyle(Color.tfDim) }
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
