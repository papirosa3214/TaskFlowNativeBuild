import Foundation

/// Общий каталог явного выбора в карточке и рутине; профиль — контракт сервера.
enum CollaborationPlanTemplate {
    static let all: [(profile: String, title: String, icon: String)] = [
        ("single_executor", "Один исполнитель", "person.fill"),
        ("research", "Исследование: исследователь → аналитик", "magnifyingglass"),
        ("delivery", "Доставка: архитектор → исполнитель → QA → критик", "shippingbox"),
        ("full_cycle", "Полный цикл: все роли", "person.3.fill"),
        ("orchestrated", "Оркестратор: раздаёт работу команде", "point.3.filled.connected.trianglepath.dotted"),
        ("product_feature", "Продуктовая фича", "sparkles"),
        ("bug_regression", "Баг или регрессия", "ladybug"),
        ("ux_concept", "UX-концепция", "pencil.and.outline"),
        ("api_integration", "API-интеграция", "arrow.left.arrow.right"),
        ("audit", "Аудит", "checkmark.shield"),
    ]

    static func title(for profile: String) -> String {
        all.first { $0.profile == profile }?.title ?? profile
    }

    /// Маршрут шаблона: этапы сверху вниз; несколько ролей в одном этапе —
    /// параллельная ветка. Состав сверен с
    /// `docs/2026-10-16-team-plan-template-catalog.md`.
    static func stages(for profile: String) -> [[String]] {
        switch profile {
        case "single_executor": return [["Исполнитель"]]
        case "research": return [["Исследователь"], ["Аналитик"]]
        case "delivery": return [["Архитектор"], ["Разработчик"], ["QA"], ["Критик"]]
        case "full_cycle": return [["Исследователь"], ["Аналитик"],
                                   ["Архитектор", "Дизайнер"],
                                   ["Разработчик"], ["QA"], ["Критик"]]
        case "orchestrated": return [["Оркестратор"], ["Роли по заданию"], ["Оркестратор"]]
        case "product_feature": return [["Аналитик"], ["Архитектор"], ["Дизайнер"],
                                        ["Разработчик"], ["QA"]]
        case "bug_regression": return [["Аналитик"], ["Архитектор"], ["Разработчик"], ["QA"]]
        case "ux_concept": return [["Дизайнер"], ["Критик"]]
        case "api_integration": return [["Исследователь"], ["Архитектор"],
                                        ["Разработчик", "QA: подготовка"], ["QA: проверка"]]
        case "audit": return [["Аналитик"], ["Проверяющий"], ["Критик"]]
        default: return []
        }
    }
}
