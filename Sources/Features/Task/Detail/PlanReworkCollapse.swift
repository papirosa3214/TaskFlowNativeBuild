import Foundation

/// Свёртка кругов доработки в исходные места графа (владелец 27.10.2026).
///
/// Сервер на каждый возврат заводит новый узел-доработку (`rework_of_key`
/// может означать прошлую попытку ИЛИ источник межролевого возврата).
/// Сворачиваем только точную ссылку на попытку той же роли; новый исполнитель
/// сохраняет собственный slot, даже когда эта роль уже есть в плане. Все его
/// попытки сводятся к исходному узлу, состояние берётся у последней попытки,
/// а сам возврат рисуется отдельной стрелкой снизу вверх — от того, кто
/// вернул, к тому, кого вернули. Цвет — по номеру круга: 1 жёлтый,
/// 2 оранжевый, 3 красный (третий отказ: лимит `MAX_REWORK_ROUNDS = 2`
/// исчерпан, ход за владельцем).
enum PlanReworkCollapse {
    struct Node: Equatable {
        let slotKey: String
        let iteration: Int
        let reworkOfKey: String?
        let roleKey: String
    }

    struct Edge: Hashable {
        let from: String
        let to: String
    }

    struct Return: Hashable {
        let from: String
        let to: String
        /// 1, 2 — круги доработки; 3 — отказ после последнего круга.
        let round: Int
    }

    struct Result: Equatable {
        /// Исходные места графа в порядке плана.
        let slots: [String]
        /// Исходное место → узел последней попытки (по нему состояние).
        let latest: [String: String]
        /// Обычные связи между исходными местами, без петель и повторов.
        let edges: [Edge]
        /// Стрелки возврата: одна на пару «кто вернул → кому», с последним кругом.
        let returns: [Return]
    }

    static func collapse(nodes: [Node], edges: [Edge], limitExhausted: Bool) -> Result {
        let byKey = Dictionary(nodes.map { ($0.slotKey, $0) }, uniquingKeysWith: { first, _ in first })
        func root(_ slot: String) -> String {
            var current = slot
            var seen: Set<String> = []
            while let node = byKey[current], let next = node.reworkOfKey,
                  let previous = byKey[next], node.roleKey == previous.roleKey,
                  seen.insert(current).inserted {
                current = next
            }
            return current
        }
        let rootOf = Dictionary(uniqueKeysWithValues: byKey.keys.map { ($0, root($0)) })
        let slots = nodes.map(\.slotKey).filter { rootOf[$0] == $0 }

        var latest: [String: String] = [:]
        for node in nodes {
            let r = rootOf[node.slotKey] ?? node.slotKey
            if let current = latest[r], (byKey[current]?.iteration ?? 0) >= node.iteration { continue }
            latest[r] = node.slotKey
        }

        // Связи первого круга задают порядок работы: возврат — это связь в
        // доработку от того, кто по этому порядку стоит НИЖЕ исполнителя.
        var baseNext: [String: Set<String>] = [:]
        for edge in edges {
            guard let a = rootOf[edge.from], let b = rootOf[edge.to], a != b,
                  (byKey[edge.from]?.iteration ?? 0) == 0, (byKey[edge.to]?.iteration ?? 0) == 0 else { continue }
            baseNext[a, default: []].insert(b)
        }
        func reaches(_ from: String, _ target: String) -> Bool {
            var stack = [from]
            var seen: Set<String> = []
            while let slot = stack.popLast() {
                if slot == target { return true }
                guard seen.insert(slot).inserted else { continue }
                stack.append(contentsOf: baseNext[slot] ?? [])
            }
            return false
        }

        var plain: [Edge] = []
        var plainSeen: Set<Edge> = []
        var rounds: [Edge: Int] = [:]
        for edge in edges {
            guard let a = rootOf[edge.from], let b = rootOf[edge.to], a != b,
                  let source = byKey[edge.from], let target = byKey[edge.to] else { continue }
            let pair = Edge(from: a, to: b)
            // op rework у QA/критика: ссылка ведёт к проверяющему,
            // а исправление другой роли — отдельное место. Оно ещё не
            // имеет пути в исходном графе, но ребро точно задаёт возврат.
            let crossRoleReturn = target.reworkOfKey == source.slotKey && a != b
            if target.iteration > source.iteration, reaches(b, a) || crossRoleReturn {
                rounds[pair] = max(rounds[pair] ?? 0, target.iteration)
            } else if !reaches(b, a), plainSeen.insert(pair).inserted {
                plain.append(pair)
            }
        }
        // Третий отказ новых узлов не создаёт: сервер останавливается и
        // отдаёт ход владельцу. Красим возвраты последнего круга в красный.
        if limitExhausted, let last = rounds.values.max() {
            for (pair, round) in rounds where round == last { rounds[pair] = last + 1 }
        }
        let returns = rounds.map { Return(from: $0.key.from, to: $0.key.to, round: $0.value) }
            .sorted { ($0.from, $0.to) < ($1.from, $1.to) }
        return Result(slots: slots, latest: latest, edges: plain, returns: returns)
    }
}
