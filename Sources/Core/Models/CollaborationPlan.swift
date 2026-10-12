import Foundation

/// Версионируемый граф совместной работы над задачей — LOCK-246.
///
/// Источник — `server/src/routes/task-collaboration-plans.ts` (`GET
/// /api/tasks/:id/collaboration-plans`). Клиент только читает: создание и
/// утверждение плана делает оркестратор/владелец через API напрямую,
/// графового редактора на телефоне нет и не планируется (docs/
/// 2026-09-28-parent-child-execution-context, этап 10, «вне первого этапа»).
///
/// Runtime-состояние узлов (кто в работе, кто закрыт) — с 29.09.2026 НЕ
/// отдельная сущность (`task_role_slots` выведена из употребления, см.
/// docs/2026-09-29-role-slot-execution-integration/DESIGN.md), а обычные
/// `ApiSubtask` с `collaborationPlanId`/`planNodeKey` — читай их напрямую
/// вместо `ApiRoleSlot` (убран).
public struct ApiCollaborationPlanNode: Codable, Sendable, Hashable, Identifiable {
    public let slotKey: String
    public let roleKey: String
    public let required: Bool
    public let expectedResult: String
    /// Живой план (01.10.2026) — поля необязательные: сервер до этой правки их
    /// не слал. Задание шага, откуда он взялся (template | owner | role |
    /// rework), кто и зачем добавил, круг доработки, пропуск с причиной.
    public let instructions: String?
    public let origin: String?
    public let addedBy: String?
    public let addedReason: String?
    public let iteration: Int?
    public let reworkOfKey: String?
    public let skippedAt: String?
    public let skipReason: String?
    public let taskId: String?
    public let taskTitle: String?
    public let executionState: String?
    public let sourcePlanStatus: String?
    public let sourcePlanVersion: Int?
    public let sourcePlanId: String?
    public let sourceSlotKey: String?
    public let sourceSubtaskId: String?
    public let workChoice: String?
    public let originalTitle: String?
    public let plannedWork: String?
    public let requiresChoice: Bool?
    public let responsible: Bool?
    /// Чего ждёт ещё не начатый шаг: от кого и почему (сервер, 07.10.2026).
    public let waitingFor: [PlanWaitingFor]?
    /// Человекочитаемый отчёт этапа — заметка в папке документов задачи.
    public let resultDocument: PlanResultDocument?
    public let submissionReceipt: PlanSubmissionReceipt?

    public var id: String { slotKey }
    public var isSkipped: Bool { skippedAt != nil }

    enum CodingKeys: String, CodingKey {
        case slotKey = "slot_key"
        case roleKey = "role_key"
        case required
        case expectedResult = "expected_result"
        case instructions, origin, iteration
        case addedBy = "added_by"
        case addedReason = "added_reason"
        case reworkOfKey = "rework_of_key"
        case skippedAt = "skipped_at"
        case skipReason = "skip_reason"
        case taskId = "task_id", taskTitle = "task_title", executionState = "execution_state"
        case sourcePlanStatus = "source_plan_status"
        case sourceSubtaskId = "source_subtask_id", workChoice = "work_choice", originalTitle = "original_title", plannedWork = "planned_work", requiresChoice = "requires_choice"
        case sourcePlanVersion = "source_plan_version"
        case sourcePlanId = "source_plan_id", sourceSlotKey = "source_slot_key", responsible
        case waitingFor = "waiting_for"
        case resultDocument = "result_document"
        case submissionReceipt = "submission_receipt"
    }
}

public struct PlanResultDocument: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
}

/// Одна причина ожидания шага: от какого шага, какой результат и что с ним не так.
public struct PlanWaitingFor: Codable, Sendable, Hashable {
    public let fromSlotKey: String
    public let artifactKey: String?
    public let reason: String

    enum CodingKeys: String, CodingKey {
        case fromSlotKey = "from_slot_key", artifactKey = "artifact_key", reason
    }
}

/// Операция правки живого плана — `POST .../collaboration-plans/:planId/ops`
/// (сервер: runtime/planMutations.ts). Одна структура на все виды: лишние
/// поля пустые и в JSON не уходят.
public struct ApiPlanOp: Codable, Sendable, Hashable {
    public var op: String
    public var slotKey: String?
    public var roleKey: String?
    public var expectedResult: String?
    public var instructions: String?
    public var after: [String]?
    public var before: [String]?
    public var reason: String?
    public var fromSlot: String?
    public var defects: String?

    public init(op: String, slotKey: String? = nil, roleKey: String? = nil, expectedResult: String? = nil,
                instructions: String? = nil, after: [String]? = nil, before: [String]? = nil,
                reason: String? = nil, fromSlot: String? = nil, defects: String? = nil) {
        self.op = op
        self.slotKey = slotKey
        self.roleKey = roleKey
        self.expectedResult = expectedResult
        self.instructions = instructions
        self.after = after
        self.before = before
        self.reason = reason
        self.fromSlot = fromSlot
        self.defects = defects
    }

    enum CodingKeys: String, CodingKey {
        case op, instructions, after, before, reason, defects
        case slotKey = "slot_key"
        case roleKey = "role_key"
        case expectedResult = "expected_result"
        case fromSlot = "from_slot"
    }
}

/// Предложение роли сверх лимита — ждёт решения владельца.
public struct ApiPlanProposal: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let actorName: String?
    public let reason: String?
    public let ops: [ApiPlanOp]

    enum CodingKeys: String, CodingKey {
        case id, reason, ops
        case actorName = "actor_name"
    }
}

public struct ApiCollaborationPlanEdge: Codable, Sendable, Hashable {
    public let fromSlotKey: String
    public let toSlotKey: String
    public let startCondition: String

    enum CodingKeys: String, CodingKey {
        case fromSlotKey = "from_slot_key"
        case toSlotKey = "to_slot_key"
        case startCondition = "start_condition"
    }
}

public struct ApiBranchTeamMember: Codable, Sendable, Hashable {
    public let roleKey: String
    public let slotKeys: [String]
    public let taskNumbers: [Int]
    public let executionState: String
    enum CodingKeys: String, CodingKey {
        case roleKey = "role_key", slotKeys = "slot_keys", taskNumbers = "task_numbers", executionState = "execution_state"
    }
}
public struct ApiBranchCard: Codable, Sendable, Hashable {
    public let id: String
    public let tabNumber: Int
    public var responsibleRole: String? = nil
    enum CodingKeys: String, CodingKey { case id, tabNumber = "tab_number", responsibleRole = "responsible_role" }
}

public struct ApiCollaborationPlan: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let taskId: String
    public let revision: Int
    public let status: String
    public let profile: String
    public let rationale: String
    public let nodes: [ApiCollaborationPlanNode]
    public let edges: [ApiCollaborationPlanEdge]
    /// Версия живого плана — для проверки конкурентных правок.
    public let version: Int?
    public let pendingProposals: [ApiPlanProposal]?
    public let branchSnapshot: String?
    public let branchRootTaskId: String?
    public var branchTeam: [ApiBranchTeamMember]? = nil
    public var branchCards: [ApiBranchCard]? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case taskId = "task_id"
        case revision, status, profile, rationale, nodes, edges, version
        case pendingProposals = "pending_proposals"
        case branchSnapshot = "branch_snapshot", branchRootTaskId = "branch_root_task_id"
        case branchTeam = "branch_team", branchCards = "branch_cards"
    }
}

public extension ApiCollaborationPlan {
    /// Ноль — только этап этой роли в родительской вкладке, не участие в ветке вообще.
    func tabNumbers(forRole role: String) -> [Int] {
        let root = branchRootTaskId ?? taskId
        let work = nodes.filter { $0.roleKey == role && !$0.isSkipped && $0.executionState != "skipped" }
        if let cards = branchCards {
            let numbers = Dictionary(cards.map { ($0.id, $0.tabNumber) }, uniquingKeysWith: { first, _ in first })
            return Set(work.compactMap { node -> Int? in
                guard let id = node.taskId else { return nil }
                if id == root { return 0 }
                guard let number = numbers[id], number > 0 else { return nil }
                return number
            }).sorted()
        }
        let children = branchTeam?.first { $0.roleKey == role }?.taskNumbers.filter { $0 > 0 } ?? []
        return Set((work.contains { $0.taskId == root } ? [0] : []) + children).sorted()
    }

    func tabStates(forRole role: String) -> [Int: String] {
        let root = branchRootTaskId ?? taskId
        return Dictionary(tabNumbers(forRole: role).map { number in
            let id = number == 0 ? root : branchCards?.first { $0.tabNumber == number }?.id
            let states = nodes.filter { id != nil && $0.roleKey == role && $0.taskId == id && !$0.isSkipped && $0.executionState != "skipped" }
                .map { $0.executionState ?? "waiting" }
            let priority = ["blocked", "returned", "active", "review", "ready", "waiting", "accepted"]
            return (number, priority.first { states.contains($0) } ?? "waiting")
        }, uniquingKeysWith: { first, _ in first })
    }

    var activeChildTaskIDs: Set<String> {
        let root = branchRootTaskId ?? taskId
        return Set(nodes.filter { !$0.isSkipped && $0.executionState == "active" }.compactMap(\.taskId).filter { $0 != root })
    }

    var branchExecutionState: String {
        let states = nodes.filter { !$0.isSkipped && $0.executionState != "skipped" }.map { $0.executionState ?? "waiting" }
        if states.contains("active") { return "active" }
        if states.contains("blocked") || states.contains("returned") { return "blocked" }
        if states.contains("review") { return "review" }
        if !states.isEmpty && states.allSatisfy({ $0 == "accepted" }) { return "accepted" }
        return "waiting"
    }

    var branchResponsibleRole: String? {
        let root = branchRootTaskId ?? taskId
        return branchCards?.first { $0.id == root }?.responsibleRole
            ?? nodes.first { $0.taskId == root && $0.responsible == true && !$0.isSkipped }?.roleKey
    }
}


public struct PlanSubmissionReceipt: Codable, Sendable, Hashable {
    public let confirmed: Bool
    public let authority: String
    public let artifactId: String?
    public let documentId: String?
    public let confirmedAt: String?
    enum CodingKeys: String, CodingKey {
        case confirmed, authority
        case artifactId = "artifact_id", documentId = "document_id", confirmedAt = "confirmed_at"
    }
}
