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
    let area: String
    let message: String
    let kind: Kind
    let taskID: String?

    static func compose(checks: [ServiceTicketCheck], incidents: [SystemState.Incident]) -> [Self] {
        var represented = Set<String>()
        var rows: [Self] = []
        for (index, check) in checks.enumerated() {
            let incident = incidents.first {
                $0.key == check.incidentKey || check.diagnosticTaskIDs?.contains($0.id) == true
            }
            if let incident, !represented.insert(incident.id).inserted { continue }
            let kind: Kind
            if let incident { kind = incident.fixed ? .repaired : .broken }
            else if check.status == "error" { kind = .broken }
            else if check.status != "ok" { kind = .warning }
            else { kind = check.recovered == true ? .repaired : .normal }
            let status = incident.map { "\($0.statusLine)" + ($0.workLine.map { "\n" + $0 } ?? "") }
            rows.append(Self(id: incident?.id ?? "check-\(index)", title: check.name,
                             area: check.area, message: [check.message, status].compactMap { $0 }.joined(separator: "\n"),
                             kind: kind, taskID: incident?.id ?? check.diagnosticTaskIDs?.first))
        }
        for incident in incidents where !represented.contains(incident.id) {
            rows.append(Self(id: incident.id, title: incident.title, area: "Работа по устранению неисправности",
                             message: [incident.statusLine, incident.workLine].compactMap { $0 }.joined(separator: "\n"),
                             kind: incident.fixed ? .repaired : .broken, taskID: incident.id))
        }
        return rows
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
                Text(item.area).tfText(.caption).foregroundStyle(Color.tfDim)
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
