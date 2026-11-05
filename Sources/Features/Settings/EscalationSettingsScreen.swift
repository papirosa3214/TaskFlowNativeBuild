import SwiftUI

/// Настройки → «Напоминания о просрочке». Правила сервера
/// `/api/escalation/*`: общий выключатель, тихие часы, дни недели, шаги
/// напоминаний, прогноз на неделю и последние отправленные.
struct EscalationSettingsScreen: View {
    @State private var model = EscalationSettingsViewModel()
    @State private var editing: EscalationStepDraft?

    var body: some View {
        List {
            if let error = model.error {
                Section {
                    Text(error).foregroundStyle(Color.tfSub)
                        .accessibilityIdentifier("escalation-error")
                    Button("Обновить") { Task { await model.load() } }
                }
            }
            if model.loading && model.rule == nil { TFLoading(.inline) }
            if let rule = model.rule {
                EscalationMainSection(model: model, rule: rule)
                if rule.enabled {
                    EscalationScheduleSection(model: model, rule: rule)
                    EscalationStepsSection(model: model, rule: rule, editing: $editing)
                    EscalationSummarySection(model: model)
                }
            }
        }
        .tfSettingsListChrome()
        .tfScreenBackground()
        .tfNativeHeader("Напоминания о просрочке")
        .tint(Color.tfText)
        .accessibilityIdentifier("escalation-settings-screen")
        .task { await model.load() }
        .refreshable { await model.load() }
        .tfSheet(item: $editing) { draft in
            EscalationStepEditor(draft: draft, model: model)
        }
    }
}

private struct EscalationMainSection: View {
    let model: EscalationSettingsViewModel
    let rule: EscalationRule

    var body: some View {
        Section {
            HStack {
                Text("Напоминать о просроченных задачах")
                    .tfText(.body)
                    .foregroundStyle(Color.tfText)
                Spacer()
                TFToggle(isOn: Binding(
                    get: { rule.enabled },
                    set: { value in Task { await model.update { $0.enabled = value } } }
                ))
                .accessibilityLabel("Напоминания о просрочке")
                .accessibilityIdentifier("escalation-enabled")
            }
            .tfSettingsListRow()
        } footer: {
            Text("Касается ваших активных задач со сроком, который уже прошёл.")
        }
    }
}

private struct EscalationScheduleSection: View {
    let model: EscalationSettingsViewModel
    let rule: EscalationRule
    private static let dayTitles = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]

    var body: some View {
        Section {
            DatePicker("Не беспокоить с", selection: timeBinding(\.quietFrom), displayedComponents: .hourAndMinute)
                .tfSettingsListRow()
                .accessibilityIdentifier("escalation-quiet-from")
            DatePicker("до", selection: timeBinding(\.quietTo), displayedComponents: .hourAndMinute)
                .tfSettingsListRow()
                .accessibilityIdentifier("escalation-quiet-to")
            HStack(spacing: TFSpacing.xs) {
                ForEach(1...7, id: \.self) { day in
                    dayButton(day)
                }
            }
            .tfSettingsListRow()
        } header: {
            Text("Когда можно присылать")
        } footer: {
            Text("В тихие часы и в выключенные дни напоминания не приходят.")
        }
    }

    private func dayButton(_ day: Int) -> some View {
        let isOn = rule.weekdays.contains(day)
        return Button { Task { await model.toggleWeekday(day) } } label: {
            Text(Self.dayTitles[day - 1])
                .tfText(.body)
                .foregroundStyle(isOn ? Color.tfText : Color.tfDim)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 32)
                .padding(.vertical, TFSpacing.xs)
                .tfSelectTile(selected: isOn)
        }
            .buttonStyle(.plain)
            .frame(minHeight: 44)
            .accessibilityValue(isOn ? "Включён" : "Выключен")
            .accessibilityIdentifier("escalation-day-\(day)")
    }

    private func timeBinding(_ key: WritableKeyPath<EscalationRule, String>) -> Binding<Date> {
        Binding(
            get: { EscalationTime.date(from: rule[keyPath: key]) },
            set: { date in
                let text = EscalationTime.text(from: date)
                Task { await model.update { $0[keyPath: key] = text } }
            }
        )
    }
}

private struct EscalationStepsSection: View {
    let model: EscalationSettingsViewModel
    let rule: EscalationRule
    @Binding var editing: EscalationStepDraft?

    var body: some View {
        Section {
            ForEach(Array(rule.steps.enumerated()), id: \.offset) { index, step in
                Button { editing = EscalationStepDraft(index: index, step: step) } label: {
                    EscalationStepRow(step: step)
                }
                .buttonStyle(.plain)
                .tfSettingsListRow()
                .accessibilityIdentifier("escalation-step-\(index)")
            }
            .onDelete { offsets in
                Task { await model.update { $0.steps.remove(atOffsets: offsets) } }
            }
            Button("Добавить шаг") {
                editing = EscalationStepDraft(index: nil, step: EscalationStep(afterHours: nextFreeHours, priorityMax: 4, channels: ["inapp"]))
            }
            .tfText(.body)
            .tfSettingsListRow()
            .accessibilityIdentifier("escalation-add-step")
        } header: {
            Text("Когда напоминать")
        } footer: {
            if let warning = model.warning { Text(warning).foregroundStyle(Color.tfCoral) }
            else { Text("Одно и то же напоминание по задаче приходит не чаще раза в день.") }
        }
    }

    private var nextFreeHours: Int {
        var hours = (rule.steps.map(\.afterHours).max() ?? 0) + 24
        while model.hoursTaken(hours, except: nil) { hours += 1 }
        return min(hours, EscalationStepDraft.maxHours)
    }
}

struct EscalationStepRow: View {
    let step: EscalationStep

    var body: some View {
        TFListRow(
            content: AnyView(
                VStack(alignment: .leading, spacing: TFSpacing.xs) {
                    Text("Через \(EscalationStepDraft.hoursText(step.afterHours)) после срока")
                        .foregroundStyle(Color.tfText)
                    Text(EscalationStepDraft.priorityText(step.priorityMax) + " · " + (step.sendsPush ? "пуш и в приложении" : "только в приложении"))
                        .tfText(.meta)
                        .foregroundStyle(Color.tfSub)
                }
            ),
            horizontalPadding: 0,
            chevron: .shown
        )
    }
}

private struct EscalationSummarySection: View {
    let model: EscalationSettingsViewModel

    var body: some View {
        Section("Прогноз и история") {
            if let preview = model.preview {
                Text("За \(preview.days) дн. придёт напоминаний: \(preview.count)")
                    .accessibilityIdentifier("escalation-preview")
            }
            if model.recent.isEmpty {
                Text("За неделю напоминаний не было").foregroundStyle(Color.tfSub)
            }
            ForEach(model.recent.prefix(10)) { event in
                VStack(alignment: .leading, spacing: TFSpacing.xs) {
                    Text(event.taskTitle ?? "Задача удалена")
                    Text(event.sentAt).tfText(.meta).foregroundStyle(Color.tfSub)
                }
            }
        }
    }
}

/// Перевод «ЧЧ:ММ» сервера в `Date` для `DatePicker` и обратно.
enum EscalationTime {
    static func date(from text: String) -> Date {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        var components = DateComponents()
        components.hour = parts.first ?? 0
        components.minute = parts.count > 1 ? parts[1] : 0
        return Calendar.current.date(from: components) ?? Date()
    }
    static func text(from date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}
