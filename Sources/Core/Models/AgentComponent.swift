import Foundation

/// Интерфейс от агента одним форматом (AG-UI generative UI, 27.10.2026):
/// роль шлёт имя компонента и данные, телефон рисует по имени свой нативный
/// компонент. Сервер (`server/src/lib/agentComponents.ts`) кладёт
/// `component` в блок ```widget и `components` в блок ```tf-json.
public struct AgentComponent: Decodable, Sendable, Equatable {
    public let name: String
    public let props: JSONValue

    public var kind: AgentComponentKind? { AgentComponentRegistry.kind(for: name) }

    /// Данные компонента строкой JSON — в том виде, что читают виджеты.
    public var propsJSON: String? {
        guard let data = try? JSONEncoder().encode(props) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// Все компоненты, которые умеет рисовать телефон. Одно имя — одна запись,
/// даже если имя приходит и из ```widget, и из ```tf-json (`progress`, `chart`).
public enum AgentComponentKind: String, CaseIterable, Sendable {
    // ```widget
    case weather, metrics, checklist, card
    case statusBoard = "status_board"
    case barsList = "bars_list"
    case chain, ladder, timeline
    case calendarGrid = "calendar_grid"
    case heatmap, compare
    // ```widget и ```tf-json
    case progress, chart
    // ```tf-json
    case text, heading, list, table, status, diagram, report, handoff, command, link, widget, html
}

/// Реестр «имя → компонент». Добавить компонент — запись в `AgentComponentKind`
/// и ветка в виде, который его рисует.
public enum AgentComponentRegistry {
    public static func kind(for name: String) -> AgentComponentKind? {
        AgentComponentKind(rawValue: name)
    }
}
