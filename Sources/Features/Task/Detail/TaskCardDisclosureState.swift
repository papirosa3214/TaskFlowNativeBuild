import Foundation

/// Только выбранное владельцем представление; данные задачи не меняются.
enum TaskCardDisclosureState {
    static func sections(_ taskID: String?) -> Set<TaskDetailSection>? {
        guard let taskID, let values = UserDefaults.standard.stringArray(forKey: "task.card.sections.\(taskID)") else { return nil }
        return Set(values.compactMap(TaskDetailSection.init(rawValue:)))
    }
    static func saveSections(_ sections: Set<TaskDetailSection>, taskID: String?) {
        guard let taskID else { return }
        UserDefaults.standard.set(sections.map(\.rawValue).sorted(), forKey: "task.card.sections.\(taskID)")
    }
    static func flag(_ key: String, default value: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? value
    }
    static func saveFlag(_ value: Bool, key: String) { UserDefaults.standard.set(value, forKey: key) }
}
