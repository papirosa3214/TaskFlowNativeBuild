import SwiftUI

/// Черновик шага в окне правки: `index == nil` — новый шаг.
struct EscalationStepDraft: Identifiable {
    let index: Int?
    var step: EscalationStep
    var id: String { index.map(String.init) ?? "new" }

    static let maxHours = 720

    static func hoursText(_ hours: Int) -> String {
        if hours >= 24, hours % 24 == 0 { return "\(hours / 24) дн." }
        return "\(hours) ч"
    }

    static func priorityText(_ priorityMax: Int) -> String {
        priorityMax == 1 ? "Приоритет 1" : (priorityMax >= 4 ? "Любой приоритет" : "Приоритет 1–\(priorityMax)")
    }
}

/// Окно правки одного шага напоминания.
struct EscalationStepEditor: View {
    let model: EscalationSettingsViewModel
    @State private var step: EscalationStep
    private let index: Int?
    @Environment(\.dismiss) private var dismiss

    init(draft: EscalationStepDraft, model: EscalationSettingsViewModel) {
        self.model = model
        self.index = draft.index
        _step = State(initialValue: draft.step)
    }

    private var hoursTaken: Bool { model.hoursTaken(step.afterHours, except: index) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $step.afterHours, in: 1...EscalationStepDraft.maxHours) {
                        Text("Через \(EscalationStepDraft.hoursText(step.afterHours)) после срока")
                    }
                    .accessibilityIdentifier("escalation-step-hours")
                } footer: {
                    if hoursTaken { Text("Шаг с таким временем уже есть").foregroundStyle(Color.tfCoral) }
                }
                Section {
                    Picker("Для задач", selection: $step.priorityMax) {
                        ForEach(1...4, id: \.self) { value in
                            Text(EscalationStepDraft.priorityText(value)).tag(value)
                        }
                    }
                    .accessibilityIdentifier("escalation-step-priority")
                    HStack {
                        Text("Пуш на телефон")
                        Spacer()
                        TFToggle(isOn: pushBinding)
                            .accessibilityLabel("Пуш на телефон")
                            .accessibilityIdentifier("escalation-step-push")
                    }
                } footer: {
                    Text("В приложении напоминание приходит всегда.")
                }
                if index != nil {
                    Section {
                        Button("Удалить шаг", role: .destructive) { save { $0.steps.remove(at: index!) } }
                            .accessibilityIdentifier("escalation-step-delete")
                    }
                }
            }
            .navigationTitle(index == nil ? "Новый шаг" : "Шаг")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        save { rule in
                            if let index { rule.steps[index] = step } else { rule.steps.append(step) }
                        }
                    }
                    .disabled(hoursTaken)
                    .accessibilityIdentifier("escalation-step-save")
                }
            }
        }
    }

    private var pushBinding: Binding<Bool> {
        Binding(
            get: { step.sendsPush },
            set: { step.channels = $0 ? ["inapp", "apns"] : ["inapp"] }
        )
    }

    private func save(_ change: @escaping (inout EscalationRule) -> Void) {
        Task {
            await model.update(change)
            dismiss()
        }
    }
}
