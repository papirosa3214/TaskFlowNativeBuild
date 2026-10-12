import Foundation

public struct ApiTaskPreparation: Decodable, Sendable {
    public let id: Int
    public let inputVersion: Int
    public let status: String
    public let planID: String?
    public let planStatus: String?
    public let branchSnapshot: String?
    public let error: String?
    public let result: Recommendation?
    /// Старые результаты автомата не включают вопрос, записанный в самой карточке.
    var taskQuestion: String? = nil

    enum CodingKeys: String, CodingKey {
        case id, status, error, result
        case branchSnapshot = "branch_snapshot"
        case inputVersion = "input_version", planID = "plan_id", planStatus = "plan_status"
    }
    public struct Recommendation: Decodable, Sendable {
        public let question: String?
        public let card: Card?
        public let approvedChildren: [String]?
        enum CodingKeys: String, CodingKey { case question, card; case approvedChildren = "approved_children" }
    }
    public struct Card: Decodable, Sendable { public let preparation: Proposal? }
    public struct Proposal: Decodable, Sendable {
        public let representation: String
        public let reason: String
        public let question: String?
        public let workstreams: [Workstream]
    }
    public struct Workstream: Decodable, Identifiable, Sendable {
        public let key: String
        public let title: String
        public let result: String
        public let role: String?
        public let dependsOn: [String]
        public var id: String { key }
        enum CodingKeys: String, CodingKey { case key, title, result, role; case dependsOn = "depends_on" }
    }
    public var isPending: Bool { status == "queued" || status == "running" }
    public var canApprovePlan: Bool { status == "ready" && planID != nil && planStatus == "draft" }
    public var canApproveStructure: Bool {
        status == "structure_review" && result?.question == nil && result?.card?.preparation?.question == nil
    }
    public var question: String? {
        [result?.question, result?.card?.preparation?.question, taskQuestion]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}
