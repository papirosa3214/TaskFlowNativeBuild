import Foundation
import Observation

/// Правила напоминаний о просрочке владельца (`/api/escalation/rules`).
/// Каждое изменение сразу уходит на сервер: экран без кнопки «Сохранить»,
/// как системные настройки.
@MainActor @Observable
final class EscalationSettingsViewModel {
    var rule: EscalationRule?
    var preview: EscalationPreview?
    var recent: [EscalationEvent] = []
    var loading = false
    var saving = false
    var error: String?
    var warning: String?
    private let api = APIClient()

    func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            rule = try await api.escalationRule()
            error = nil
            await refreshSummary()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Применить правку локально и сохранить. При ошибке сервера правило
    /// возвращается к сохранённому, чтобы экран не показывал несохранённое.
    func update(_ change: (inout EscalationRule) -> Void) async {
        guard var draft = rule else { return }
        let previous = draft
        change(&draft)
        draft.steps.sort { $0.afterHours < $1.afterHours }
        // Сервер не принимает правило без шагов — последний шаг не удаляется.
        guard draft != previous, !draft.steps.isEmpty else { return }
        rule = draft
        saving = true
        defer { saving = false }
        do {
            let result = try await api.saveEscalationRule(draft)
            warning = result.warning == nil ? nil : "Ни один шаг не охватывает приоритет 1 — самые срочные задачи без напоминаний."
            error = nil
            await refreshSummary()
        } catch {
            rule = previous
            self.error = error.localizedDescription
        }
    }

    func toggleWeekday(_ day: Int) async {
        await update { rule in
            if rule.weekdays.contains(day) {
                guard rule.weekdays.count > 1 else { return }
                rule.weekdays.removeAll { $0 == day }
            } else {
                rule.weekdays.append(day)
                rule.weekdays.sort()
            }
        }
    }

    /// Часы шага уже заняты другим шагом. Сервер различает шаги по часам,
    /// два шага с одинаковыми часами смешали бы каналы.
    func hoursTaken(_ hours: Int, except index: Int?) -> Bool {
        guard let rule else { return false }
        return rule.steps.indices.contains { $0 != index && rule.steps[$0].afterHours == hours }
    }

    private func refreshSummary() async {
        preview = try? await api.escalationPreview()
        recent = (try? await api.escalationRecent()) ?? recent
    }
}
