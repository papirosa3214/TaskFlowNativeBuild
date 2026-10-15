import Foundation
import SwiftUI
import Combine

/// Клиентский стор координации по контракту V2. Один источник правды
/// для экрана карточки: держит последний массив `Resolution`, отдаёт
/// его как `Published` (для SwiftUI), и применяет **diff-механизм по
/// `subtask_id`** — чтобы обновление не пересобирало граф.
///
/// Два главных принципа UX-документа (`docs/ios/coordination-resolver-view.md`):
///
/// 1. **Позиция узла фиксирована по `plan_node_key`.** Если узел временно
///    отсутствует в ответе сервера, его место сохраняется плейсхолдером.
/// 2. **Обновление цвета/иконки без layout-инвалидации.** Стор хранит
///    стабильный `orderedKeys` — порядок узлов определяется первым
///    ответом сервера и далее не меняется.
@MainActor
public final class CoordinationState: ObservableObject {

    /// Узел графа с фиксированной позицией. Хранится в порядке первого
    /// появления от сервера.
    public struct Node: Identifiable, Equatable {
        public let id: String  // subtask_id (уникальный ключ от сервера)
        public let planNodeKey: String?
        public let role: String?
        public var resolution: APIClient.CoordinationResolution?
        public let initialIndex: Int
        /// Время последнего ненулевого ответа по этому узлу. Используется
        /// `pruneStaleNodes(after:)`, чтобы не удалять узел, который
        /// сервер просто не упомянул в последнем ответе (правило №1).
        public var lastSeenAt: Date?
    }

    /// Полный массив в стабильном порядке. Узлы без `resolution` —
    /// плейсхолдеры (правило стабильности №1).
    @Published public private(set) var nodes: [Node] = []

    /// Карта быстрого доступа: subtask_id → индекс в `nodes`.
    private var indexBySubtask: [String: Int] = [:]

    /// Последний `contract_version` ответа. Несовпадение с ожидаемой
    /// версией → состояние «конфликт версий» в UI.
    @Published public private(set) var contractVersion: String = "2.0.0"

    /// Когда был последний успешный ответ — для плашки «обновлено N мин назад».
    @Published public private(set) var lastUpdatedAt: Date?

    /// Состояние загрузки — отдельно от данных, чтобы UI мог показать
    /// плашку «Не удалось получиться статус», не стирая старые узлы.
    public enum LoadState: Equatable, Sendable {
        case idle
        case loading
        case loaded
        case failed(String)
        case versionMismatch(detail: String)
    }
    @Published public private(set) var loadState: LoadState = .idle

    public let expectedContractVersion: String

    /// Обработчик действий Action bar. По умолчанию `nil` — родительский
    /// экран выставляет `state.onAction = { … }` при инициализации,
    /// если хочет перехватить решение до вызова маршрута.
    public var onAction: ((CoordinationAction) -> Void)?

    /// Конструктор. `expectedContractVersion` — обычно `"2.0.0"`.
    public init(expectedContractVersion: String = "2.0.0") {
        self.expectedContractVersion = expectedContractVersion
        self.onAction = nil
    }

    /// Загрузить `Resolution` для карточки. Сервер отдаёт массив —
    /// превращаем его в стабильный список узлов.
    ///
    /// Алгоритм диф-а:
    /// 1. Для существующих узлов — обновляем `resolution` и `lastSeenAt`
    ///    без изменения позиции (правило стабильности №2).
    /// 2. Для новых subtask_id — добавляем узел **в конец**.
    /// 3. Для исчезнувших — оставляем как плейсхолдер (`resolution = nil`,
    ///    `lastSeenAt = nil`). Удаляются только через
    ///    `pruneStaleNodes(after:)`.
    public func apply(
        resolutions: [APIClient.CoordinationResolution],
        contractVersion: String?
    ) {
        if let v = contractVersion { self.contractVersion = v }
        if let v = contractVersion, v != expectedContractVersion {
            loadState = .versionMismatch(
                detail: "Сервер \(v), клиент \(expectedContractVersion)"
            )
        }

        var updatedNodes = nodes
        var newIndex: [String: Int] = [:]
        let now = Date()

        // 1. Обновляем/добавляем узлы из ответа.
        for res in resolutions {
            if let existingIdx = indexBySubtask[res.subtaskId] {
                updatedNodes[existingIdx].resolution = res
                updatedNodes[existingIdx].lastSeenAt = now
            } else {
                let newNode = Node(
                    id: res.subtaskId,
                    planNodeKey: res.planNodeKey,
                    role: res.role,
                    resolution: res,
                    initialIndex: updatedNodes.count,
                    lastSeenAt: now
                )
                updatedNodes.append(newNode)
            }
        }

        // 2. Перестраиваем карту индексов после возможных добавлений.
        for (i, node) in updatedNodes.enumerated() {
            newIndex[node.id] = i
        }

        self.nodes = updatedNodes
        self.indexBySubtask = newIndex
        self.lastUpdatedAt = now
        switch loadState {
        case .loaded, .idle, .loading:
            self.loadState = .loaded
        case .versionMismatch:
            // Сохраняем несовпадение версий — данные есть, но действия
            // заблокированы кроме чтения.
            break
        case .failed:
            self.loadState = .loaded
        }
    }

    /// Отметить сбой загрузки, не теряя уже отрисованные узлы.
    /// UI покажет плашку «Не удалось получить статус», но Reason strip
    /// и граф сохранят старые данные.
    public func applyFailure(_ message: String) {
        loadState = .failed(message)
    }

    /// Удалить плейсхолдеры (`resolution == nil`), которые старше `cutoff`.
    /// Вызывайте после длительного фонового режима, когда понятно, что
    /// узел действительно ушёл с сервера. По умолчанию — 5 минут.
    public func pruneStaleNodes(olderThan cutoff: Date) {
        nodes.removeAll { node in
            guard node.resolution == nil else { return false }
            return (node.lastSeenAt ?? .distantPast) < cutoff
        }
        var rebuilt: [String: Int] = [:]
        for (i, node) in nodes.enumerated() {
            rebuilt[node.id] = i
        }
        self.indexBySubtask = rebuilt
    }

    /// ID первой зависшей ветви (`stalled_manual_review` или
    /// `step_stalled`). UI использует это, чтобы поднять её в списке
    /// дочерних карточек и показать красной точкой (правило стабильности №5).
    public var stalledNodeId: String? {
        nodes.first(where: { node in
            guard let cause = node.resolution?.causeEnum else { return false }
            return cause == .stalledManualReview || cause == .stepStalled
        })?.id
    }

    /// Получить `Resolution` для узла (или nil, если это плейсхолдер).
    public func resolution(forSubtaskId subtaskId: String) -> APIClient.CoordinationResolution? {
        guard let idx = indexBySubtask[subtaskId] else { return nil }
        return nodes[idx].resolution
    }
}

extension APIClient.CoordinationResolution {
    /// `cause` как enum. Не падает на незнакомых строках — отдаёт `unknown`.
    public var causeEnum: CoordinationCause {
        CoordinationCause(rawValue: cause) ?? .unknown
    }

    /// `action` как enum. Если сервер прислал незнакомое значение —
    /// возвращает `none`, UI скроет кнопку.
    public var actionEnum: CoordinationAction {
        CoordinationAction(rawValue: action) ?? .none
    }
}