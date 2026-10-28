import Foundation

/// Очередь автослияния на сервере (`GET /api/merges/queue`, владелец).
///
/// Сервер сам переносит ветку роли в `main` после сдачи шага интеграции:
/// слияние идёт во временной копии, `main` двигается только после зелёных
/// тестов. Карточке нужен только её собственная строка — что с ней
/// случилось и можно ли откатывать.
public struct ApiMergeQueue: Decodable, Sendable, Equatable {
    public let mode: String
    public let testTimeoutMin: Int?
    public let rows: [Row]

    enum CodingKeys: String, CodingKey {
        case mode, rows
        case testTimeoutMin = "test_timeout_min"
    }

    public struct Row: Decodable, Sendable, Equatable, Identifiable {
        public let taskID: String
        public let trigger: String
        public let state: ApiMergeState
        public let mainShaBefore: String?
        public let resultSha: String?
        public let error: String?
        public let createdAt: String?
        /// PR на GitHub, через который вливается ветка роли (режим `pr`
        /// очереди; старый сервер полей не шлёт — тогда nil).
        public let prNumber: Int?
        public let prURL: URL?

        public var id: String { taskID }

        enum CodingKeys: String, CodingKey {
            case state, error
            case taskID = "task_id"
            case trigger
            case mainShaBefore = "main_sha_before"
            case resultSha = "result_sha"
            case createdAt = "created_at"
            case prNumber = "pr_number"
            case prURL = "pr_url"
        }

        /// Короткий SHA для показа — полный не влезает в строку и не нужен.
        public var shortSHA: String? {
            guard let resultSha, !resultSha.isEmpty else { return nil }
            return String(resultSha.prefix(9))
        }
    }

    /// Строка этой карточки в общей очереди.
    public func row(forTask taskID: String) -> Row? {
        rows.first { $0.taskID == taskID }
    }
}

/// Состояние переноса ветки роли в `main`.
///
/// Сервер может прислать состояние, которого клиент ещё не знает: очередь
/// живёт своей жизнью, и новый её исход не должен ронять разбор всего
/// ответа — строка «Автослияние» тогда просто покажет то, что пришло.
public enum ApiMergeState: Decodable, Sendable, Equatable, Hashable {
    case queued
    case running
    /// PR на GitHub открыт: идут проверки, зелёный без конфликтов вольётся сам.
    case prOpen
    case merged
    case dryRun
    case conflict
    case testFailed
    case blockedDirtyMain
    case dirtyWorktree
    case nothingToMerge
    case missingBranch
    /// Состояние, которого клиент ещё не знает (строка с сервера как есть).
    case unknown(String)

    private static let byRaw: [String: ApiMergeState] = [
        "queued": .queued,
        "running": .running,
        "pr_open": .prOpen,
        "merged": .merged,
        "dry_run": .dryRun,
        "conflict": .conflict,
        "test_failed": .testFailed,
        "blocked_dirty_main": .blockedDirtyMain,
        "dirty_worktree": .dirtyWorktree,
        "nothing_to_merge": .nothingToMerge,
        "missing_branch": .missingBranch,
    ]

    public init(rawValue: String) {
        self = ApiMergeState.byRaw[rawValue] ?? .unknown(rawValue)
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self.init(rawValue: raw)
    }

    public var rawValue: String {
        switch self {
        case .queued: return "queued"
        case .running: return "running"
        case .prOpen: return "pr_open"
        case .merged: return "merged"
        case .dryRun: return "dry_run"
        case .conflict: return "conflict"
        case .testFailed: return "test_failed"
        case .blockedDirtyMain: return "blocked_dirty_main"
        case .dirtyWorktree: return "dirty_worktree"
        case .nothingToMerge: return "nothing_to_merge"
        case .missingBranch: return "missing_branch"
        case .unknown(let raw): return raw
        }
    }

    public static let allCases: [ApiMergeState] = [
        .queued, .running, .prOpen, .merged, .dryRun, .conflict, .testFailed,
        .blockedDirtyMain, .dirtyWorktree, .nothingToMerge, .missingBranch,
    ]

    /// Подпись для владельца в «Итоге» карточки.
    public var title: String {
        switch self {
        case .queued: return "В очереди на слияние"
        case .running: return "Сливается"
        case .prOpen: return "PR открыт — вливается"
        case .merged: return "Влито в основную ветку"
        case .dryRun: return "Проверено, main не тронут"
        case .conflict: return "Конфликт — ждёт интегратора"
        case .testFailed: return "Тесты красные — ждёт интегратора"
        case .blockedDirtyMain: return "Ждёт чистого main"
        case .dirtyWorktree: return "В копии есть незакоммиченное"
        case .nothingToMerge: return "Сливать нечего"
        case .missingBranch: return "Ветка роли исчезла"
        case .unknown(let raw): return raw
        }
    }

    /// Откат предлагаем только после настоящего слияния: до него откатывать
    /// нечего, а после «проверено вхолостую» — тем более.
    public var canRollBack: Bool { self == .merged }

    /// Символ состояния — тот же язык, что и в остальном «Итоге».
    public var symbol: String {
        switch self {
        case .queued, .running: return "clock.arrow.circlepath"
        case .prOpen: return "arrow.triangle.pull"
        case .merged: return "checkmark.circle.fill"
        case .dryRun: return "eye.circle"
        case .conflict, .testFailed, .blockedDirtyMain, .dirtyWorktree: return "exclamationmark.triangle.fill"
        case .nothingToMerge, .missingBranch: return "minus.circle"
        case .unknown: return "questionmark.circle"
        }
    }
}
