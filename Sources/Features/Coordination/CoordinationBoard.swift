import Foundation

/// Логика полотна «Координации»: уровни этапов, видимые связи, раскладка и то,
/// какую правку плана собирает каждый плюс. Без интерфейса, чтобы проверяться
/// без симулятора (`Tests/CoordinationBoardTests.swift`).
enum CoordinationBoard {
    struct Metrics: Equatable {
        var cardWidth: CGFloat
        var cardHeight: CGFloat
        var columnGap: CGFloat
        var levelGap: CGFloat
        var plusSize: CGFloat
    }

    struct Link: Hashable {
        let from: String
        let to: String
    }

    /// Заготовка нового этапа: куда его поставил плюс. Владелец может её
    /// поменять в редакторе до сохранения.
    struct StepPreset: Hashable {
        var roleKey: String? = nil
        var after: [String] = []
        var before: [String] = []
    }

    struct Layout: Equatable {
        var size: CGSize = .zero
        var centers: [String: CGPoint] = [:]
        /// По одному плюсу на уровень, в том же порядке, что уровни.
        var besidePlus: [CGPoint] = []
        var endPlus: CGPoint? = nil
    }

    /// Потолок сервера, `MAX_PLAN_NODES` в `planMutations.ts`.
    static let maxStages = 16

    private static let orchestratorRoles: Set<String> = ["code_orchestrator", "orchestrator"]

    /// План из одного оркестратора: на карточке вместо «Координации» открывается
    /// Mission Control. Профиль решает и после того, как оркестратор позвал роли.
    static func isOrchestratorOnly(_ plan: ApiCollaborationPlan) -> Bool {
        if plan.profile == "orchestrated" { return true }
        return !plan.nodes.isEmpty && plan.nodes.allSatisfy { orchestratorRoles.contains($0.roleKey) }
    }

    /// Этапы по уровням сверху вниз: этап стоит ниже самой длинной цепочки,
    /// которую ждёт; этапы одного уровня идут параллельно.
    static func levels(of plan: ApiCollaborationPlan) -> [[String]] {
        let slots = plan.nodes.map(\.slotKey)
        let known = Set(slots)
        var level = Dictionary(uniqueKeysWithValues: slots.map { ($0, 0) })
        // Проходов не больше числа этапов: сломанный цикл не зациклит экран.
        for _ in slots.indices {
            var changed = false
            for edge in plan.edges where known.contains(edge.fromSlotKey) && known.contains(edge.toSlotKey) {
                let next = (level[edge.fromSlotKey] ?? 0) + 1
                if (next < slots.count) && (next > (level[edge.toSlotKey] ?? 0)) {
                    level[edge.toSlotKey] = next
                    changed = true
                }
            }
            if !changed { break }
        }
        let grouped = Dictionary(grouping: slots) { level[$0] ?? 0 }
        return grouped.keys.sorted().compactMap { grouped[$0] }
    }

    /// Связи для рисования. Связь, которую уже выражает цепочка через другие
    /// этапы, не рисуется: вставка этапа оставляет на сервере и прямую связь.
    static func visibleLinks(of plan: ApiCollaborationPlan) -> [Link] {
        let known = Set(plan.nodes.map(\.slotKey))
        var links: [Link] = []
        for edge in plan.edges where known.contains(edge.fromSlotKey) && known.contains(edge.toSlotKey) {
            let link = Link(from: edge.fromSlotKey, to: edge.toSlotKey)
            if !links.contains(link) { links.append(link) }
        }
        return links.filter { !reaches($0.from, $0.to, in: links, skipping: $0) }
    }

    private static func reaches(_ start: String, _ target: String, in links: [Link], skipping: Link) -> Bool {
        var seen: Set<String> = [start]
        var stack = [start]
        while let current = stack.popLast() {
            for link in links where link.from == current && link != skipping {
                if link.to == target { return true }
                if seen.insert(link.to).inserted { stack.append(link.to) }
            }
        }
        return false
    }

    static func insert(between from: String, and to: String) -> StepPreset {
        StepPreset(after: [from], before: [to])
    }

    /// Ещё один этап на этом уровне: ждёт то же, что уровень, а следующие
    /// этапы ждут и его. Начатый этап ждать новый заставить нельзя.
    static func beside(level: [String], in plan: ApiCollaborationPlan, pending: Set<String>) -> StepPreset {
        let own = Set(level)
        let order = plan.nodes.map(\.slotKey)
        let preds = Set(plan.edges.filter { own.contains($0.toSlotKey) }.map(\.fromSlotKey)).subtracting(own)
        let next = Set(plan.edges.filter { own.contains($0.fromSlotKey) }.map(\.toSlotKey))
            .subtracting(own).intersection(pending)
        return StepPreset(after: order.filter { preds.contains($0) }, before: order.filter { next.contains($0) })
    }

    /// Новый этап в конец: ждёт всё, что сейчас замыкает цепочки.
    static func atEnd(of plan: ApiCollaborationPlan) -> StepPreset {
        let alive = plan.nodes.filter { !$0.isSkipped }.map(\.slotKey)
        let hasNext = Set(plan.edges.filter { alive.contains($0.toSlotKey) }.map(\.fromSlotKey))
        return StepPreset(after: alive.filter { !hasNext.contains($0) })
    }

    /// Распараллелить этап: та же роль на том же месте цепочки.
    static func split(_ node: ApiCollaborationPlanNode, in plan: ApiCollaborationPlan, pending: Set<String>) -> StepPreset {
        var preset = beside(level: [node.slotKey], in: plan, pending: pending)
        preset.roleKey = node.roleKey
        return preset
    }

    /// Дописать задачу: написанное раньше остаётся.
    static func appended(_ text: String, to existing: String?) -> String {
        let addition = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = (existing ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return current.isEmpty ? addition : current + "\n\n" + addition
    }

    static func canGrow(_ plan: ApiCollaborationPlan) -> Bool {
        plan.nodes.count < maxStages
    }

    /// Раскладка считается сама: владелец не двигает карточки, он меняет план.
    static func layout(levels: [[String]], metrics: Metrics, editable: Bool, minWidth: CGFloat) -> Layout {
        let side = editable ? metrics.columnGap + metrics.plusSize : 0
        func rowWidth(_ level: [String]) -> CGFloat {
            CGFloat(level.count) * metrics.cardWidth + CGFloat(max(0, level.count - 1)) * metrics.columnGap + side
        }
        let width = max(levels.map(rowWidth).max() ?? 0, minWidth)
        var layout = Layout()
        var top: CGFloat = 0
        for level in levels {
            var x = (width - rowWidth(level)) / 2
            for slot in level {
                layout.centers[slot] = CGPoint(x: x + metrics.cardWidth / 2, y: top + metrics.cardHeight / 2)
                x += metrics.cardWidth + metrics.columnGap
            }
            if editable {
                layout.besidePlus.append(CGPoint(x: x + metrics.plusSize / 2, y: top + metrics.cardHeight / 2))
            }
            top += metrics.cardHeight + metrics.levelGap
        }
        let bottom = levels.isEmpty ? 0 : top - metrics.levelGap
        var height = bottom
        if editable {
            let plus = CGPoint(x: width / 2, y: bottom + metrics.levelGap / 2)
            layout.endPlus = plus
            height = plus.y + metrics.plusSize / 2
        }
        layout.size = CGSize(width: width, height: height)
        return layout
    }
}

/// Что показывает шапка Mission Control. Оркестратор на экране — одна сессия, хотя в плане
/// у него два шага: разложить работу и собрать итог.
enum MissionProgress {
    struct Slot: Equatable {
        let key: String
        let roleKey: String
        let isDone: Bool
        let isActive: Bool
        let needsOwner: Bool
        let isSkipped: Bool
    }

    private static let orchestratorRoles: Set<String> = ["code_orchestrator", "orchestrator"]
    /// Ключи шагов оркестратора: сервер, `orchestratedPlan.ts`.
    private static let assembleSlot = "assemble"

    static func status(slots: [Slot], paused: Bool) -> String {
        let alive = slots.filter { !$0.isSkipped }
        if paused { return "На паузе" }
        if !alive.isEmpty, alive.allSatisfy(\.isDone) { return "Завершена" }
        if alive.contains(where: \.needsOwner) { return "Ждёт вас" }
        let active = alive.filter(\.isActive)
        if active.isEmpty { return "Ждёт запуска" }
        if active.contains(where: { $0.key == assembleSlot }) { return "Оркестратор собирает итог" }
        if active.allSatisfy({ orchestratorRoles.contains($0.roleKey) }) { return "Оркестратор раскладывает работу" }
        return "Команда работает"
    }

    static func progress(slots: [Slot]) -> (done: Int, total: Int) {
        let alive = slots.filter { !$0.isSkipped }
        return (alive.filter(\.isDone).count, alive.count)
    }

    /// Сессии по порядку: сначала оркестратор на текущем шаге, потом команда.
    static func sessions(slots: [Slot]) -> [String] {
        let own = slots.filter { orchestratorRoles.contains($0.roleKey) }
        let team = slots.filter { !orchestratorRoles.contains($0.roleKey) }.map(\.key)
        guard let current = currentOrchestratorStep(own) else { return team }
        return [current] + team
    }

    private static func currentOrchestratorStep(_ own: [Slot]) -> String? {
        if let assemble = own.first(where: { $0.key == assembleSlot && ($0.isActive || $0.isDone || $0.needsOwner) }) {
            return assemble.key
        }
        return own.first(where: { !$0.isSkipped })?.key
    }

    /// Какую сессию открыть сразу: где работа идёт, иначе где ждут владельца, иначе оркестратора.
    static func defaultSession(slots: [Slot]) -> String? {
        let order = sessions(slots: slots)
        let bySlot = Dictionary(uniqueKeysWithValues: slots.map { ($0.key, $0) })
        return order.first { bySlot[$0]?.isActive == true }
            ?? order.first { bySlot[$0]?.needsOwner == true }
            ?? order.first
    }

    /// Паузить есть что, пока работа не закончена; снять паузу можно всегда.
    static func canPause(slots: [Slot], paused: Bool) -> Bool {
        if paused { return true }
        return slots.contains { !$0.isSkipped && !$0.isDone }
    }

    static func duration(seconds: Int) -> String {
        let total = max(0, seconds)
        return String(format: "%d:%02d:%02d", total / 3600, total % 3600 / 60, total % 60)
    }

    static func tokens(_ count: Int) -> String {
        if count <= 0 { return "—" }
        if count < 1000 { return "\(count)" }
        if count < 1_000_000 { return "\(Int((Double(count) / 1000).rounded())) тыс." }
        let millions = (Double(count) / 1_000_000 * 10).rounded() / 10
        return String(format: "%.1f млн", millions).replacingOccurrences(of: ".", with: ",")
    }
}
