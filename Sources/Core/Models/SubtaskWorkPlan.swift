import Foundation

struct SubtaskWorkPlan: Decodable, Sendable, Equatable {
    let subtaskID: String
    let revision: Int
    let items: [Item]
    let updatedAt: String
    struct Item: Decodable, Identifiable, Sendable, Equatable {
        let id: String
        let title: String
        let state: State
        /// Итог, который сервер принял при сдаче пункта (карточка b504958a).
        /// Ставит только сервер — клиент его лишь показывает.
        let result: String?
        /// Почему пункт заблокирован: причина от сервера (`block_reason`).
        let blockReason: String?

        init(id: String, title: String, state: State, result: String? = nil, blockReason: String? = nil) {
            self.id = id
            self.title = title
            self.state = state
            self.result = result
            self.blockReason = blockReason
        }

        enum State: String, Decodable, Sendable, Equatable {
            case pending, inProgress = "in_progress", done
            /// Пункт заблокирован и ждёт ответа или доступа: следующий за ним
            /// не начинается (контракт §7).
            case blocked
            /// План остановлен, и это был его текущий пункт.
            case stopped

            var label: String {
                switch self {
                case .pending: "Ожидает"
                case .inProgress: "Сейчас"
                case .done: "Выполнено"
                case .blocked: "Заблокировано"
                case .stopped: "Остановлено"
                }
            }
            var symbol: String {
                switch self {
                case .pending: "square"
                case .inProgress: "play.square"
                case .done: "checkmark.square.fill"
                case .blocked: "exclamationmark.square.fill"
                case .stopped: "stop.square.fill"
                }
            }
        }

        enum CodingKeys: String, CodingKey {
            case id, title, state, result
            case blockReason = "block_reason"
        }

        /// Подпись под пунктом: то, что сервер говорит о пункте помимо названия.
        var statusNote: String? {
            switch state {
            case .inProgress: "Сейчас"
            case .blocked: blockReason.map { "Ждёт: \($0)" } ?? "Заблокировано"
            case .stopped: "Остановлено"
            case .done: result.map { "Результат: \($0)" }
            case .pending: nil
            }
        }
    }
    enum CodingKeys: String, CodingKey {
        case subtaskID = "subtask_id", revision, items
        case updatedAt = "updated_at"
    }
    var doneCount: Int { items.filter { $0.state == .done }.count }
}
struct SubtaskWorkPlanResponse: Decodable { let plan: SubtaskWorkPlan? }
