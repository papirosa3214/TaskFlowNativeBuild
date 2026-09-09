import Foundation
import Observation

/// Вид экрана «Сегодня» — persist в `taskLayout.today` (spec §4.4).
enum TodayLayout: String, CaseIterable {
    case list, board, hours
}

/// Вью-модель «Сегодня» — собирает данные из общих сторов (`TaskStore`/
/// `ProjectStore`/`SessionStore`, инъекция через `@Environment` в App/)
/// и локальное состояние экрана (фильтры, вид, офсет дня в «часах»).
///
/// Список агентов НЕ приходит ни из одного общего стора (в Core нет
/// `AgentStore` — только сырой метод `APIClient.agents()`), а нужен для
/// `isAgentAssignedTask` (задачи агентов исключаются из «часов», spec §5.1)
/// и для `isWaitingForUser`. Здесь заведён свой `APIClient()` — он
/// `Sendable` и без состояния (токен читает из Keychain на каждый запрос,
/// см. комментарий в `Core/Networking/APIClient.swift`), поэтому второй
/// экземпляр безопасен и не конфликтует с тем, что держит `TaskFlowApp`.
@MainActor
@Observable
final class TodayViewModel {
    private let apiClient = APIClient()

    var agents: [ApiUser] = []
    var filters = TodayTaskFilters.empty
    var layout: TodayLayout {
        didSet { UserDefaults.standard.set(layout.rawValue, forKey: Self.layoutKey) }
    }
    var hourDateOffset = 0

    private static let layoutKey = "taskflow_today_layout"

    init() {
        layout = TodayLayout(rawValue: UserDefaults.standard.string(forKey: Self.layoutKey) ?? "") ?? .list
    }

    func loadAgentsIfNeeded() async {
        guard agents.isEmpty else { return }
        agents = (try? await apiClient.agents()) ?? []
    }
}
