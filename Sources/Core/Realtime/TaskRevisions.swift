import Foundation

/// Счётчики, по которым экраны карточки решают, идти ли в сеть.
///
/// Переподключение сокета само по себе карточку не будит: после него
/// `TaskStore.refreshAfterReconnect()` берёт дельту `/api/tasks/changes`, и
/// будятся только названные в ней карточки (`catchUp`). Если дельты нет
/// (полный список или ошибка) — неизвестно, что изменилось, растёт `stale`,
/// и обновляются все открытые карточки, как раньше на каждый реконнект.
/// Раньше каждый из ~30 тыс. разрывов связи перекачивал открытую карточку.
struct TaskRevisions {
    private(set) var tasks: [String: Int] = [:]
    private(set) var activity: [String: Int] = [:]
    private(set) var stale = 0
    private(set) var connection = 0

    func revision(for taskID: String) -> Int {
        stale + (tasks[taskID] ?? 0)
    }

    mutating func connected() {
        connection += 1
    }

    mutating func taskChanged(_ id: String, parent: String? = nil) {
        tasks[id, default: 0] += 1
        if let parent { tasks[parent, default: 0] += 1 }
    }

    mutating func activityChanged(_ id: String) {
        activity[id, default: 0] += 1
    }

    /// `nil` — дельты не было, будим всех.
    mutating func catchUp(changedTaskIDs: Set<String>?) {
        guard let changedTaskIDs else {
            stale += 1
            return
        }
        for id in changedTaskIDs {
            taskChanged(id)
            activityChanged(id)
        }
    }
}
