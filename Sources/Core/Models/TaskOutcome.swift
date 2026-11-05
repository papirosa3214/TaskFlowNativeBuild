import Foundation

/// Итог карточки (`GET /api/tasks/:id/outcome`, владелец 01.10.2026): вердикт
/// проверяющего, что сдала каждая роль, документы по карточке, ветка с кодом.
public struct ApiTaskOutcome: Decodable, Sendable, Equatable {
    public struct Verdict: Decodable, Sendable, Equatable {
        public let verdict: String
        public let findings: String
        public let reviewerID: String
        public let createdAt: String
        /// Замечания, уже разобранные сервером (26.10.2026); nil — старый сервер.
        public var findingsBlocks: [ChatServerBlock]? = nil

        enum CodingKeys: String, CodingKey {
            case verdict, findings
            case findingsBlocks = "findings_blocks"
            case reviewerID = "reviewer_id"
            case createdAt = "created_at"
        }

        public var isApproved: Bool { verdict == "approved" }

        /// `created_at` из SQLite — «2026-09-30 10:12:34», UTC.
        public var createdDate: Date? {
            DateFormats.sqliteUTC(createdAt)
        }

        public var title: String {
            switch verdict {
            case "approved": return "принято"
            case "changes_requested": return "вернуть на доработку"
            case "blocked": return "остановить"
            default: return verdict
            }
        }
    }

    public struct Node: Decodable, Sendable, Equatable, Identifiable {
        public let slotKey: String?
        public let role: String?
        public let title: String
        public let result: String?
        public let done: Bool
        /// То же, что сдала роль, человеческим языком для владельца
        /// (сервер, `lib/stepResults.ts`). nil — сервер пересказа не дал.
        public let humanTitle: String?
        public let humanResult: String?
        /// `displayResult`, уже разобранный сервером (26.10.2026); nil — старый сервер.
        public let displayResultBlocks: [ChatServerBlock]?

        public var id: String { (slotKey ?? "") + "|" + title }

        /// Что показывать владельцу: пересказ, а без него — исходный текст роли.
        public var displayTitle: String {
            if let humanTitle, !humanTitle.isEmpty { return humanTitle }
            return title
        }

        public var displayResult: String? {
            let raw: String?
            if let h = humanResult?.trimmingCharacters(in: .whitespacesAndNewlines), !h.isEmpty {
                raw = h
            } else {
                raw = result
            }
            return raw.map(AgentTextSanitizer.sanitizeForOwner)
        }

        enum CodingKeys: String, CodingKey {
            case role, title, result, done
            case slotKey = "slot_key"
            case humanTitle = "human_title"
            case humanResult = "human_result"
            case displayResultBlocks = "display_result_blocks"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            slotKey = try c.decodeIfPresent(String.self, forKey: .slotKey)
            role = try c.decodeIfPresent(String.self, forKey: .role)
            title = try c.decode(String.self, forKey: .title)
            result = try c.decodeIfPresent(String.self, forKey: .result)
            humanTitle = try c.decodeIfPresent(String.self, forKey: .humanTitle)
            humanResult = try c.decodeIfPresent(String.self, forKey: .humanResult)
            displayResultBlocks = try? c.decodeIfPresent([ChatServerBlock].self, forKey: .displayResultBlocks)
            // Сервер шлёт true/false, SQLite-ответы — 0/1: принимаем оба.
            if let flag = try? c.decode(Bool.self, forKey: .done) {
                done = flag
            } else {
                done = (try c.decodeIfPresent(Int.self, forKey: .done) ?? 0) != 0
            }
        }
    }

    public struct Document: Decodable, Sendable, Equatable, Identifiable {
        public let id: String
        public let title: String
        public let updatedAt: String?
        public let isOutcome: Bool
        /// `result` — сам документ, `outcome` — сводка, `report` — отчёт роли; nil — старый сервер.
        public var kind: String? = nil

        enum CodingKeys: String, CodingKey {
            case id, title, kind
            case updatedAt = "updated_at"
            case isOutcome = "is_outcome"
        }
    }

    public struct Branch: Decodable, Sendable, Equatable {
        public let name: String
        public let commit: String
        public let subject: String
        public let ahead: Int
    }

    public let verdict: Verdict?
    public let nodes: [Node]
    public let documents: [Document]
    public let branch: Branch?

    /// Ответы шагов читаются под подзадачами и не создают отдельную секцию итога.
    public var isEmpty: Bool {
        verdict == nil && documents.isEmpty && branch == nil
    }
}
