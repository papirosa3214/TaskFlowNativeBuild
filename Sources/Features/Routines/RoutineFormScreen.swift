import SwiftUI

// Форма рутины — отдельный экран (не шторка): полей много, и на телефоне
// шторка оставила бы половину формы под большим пальцем (дизайн, п. 2.6).
//
// Дата, время, длительность и повтор — тот же редактор срока, что в карточке
// задачи (`ExistingTaskDueEditor`); часовой пояс — строкой с выбором.
struct RoutineFormScreen: View {
    @State private var model = RoutineFormViewModel()
    @Environment(\.dismiss) private var dismiss

    init(schedule: ApiSchedule? = nil) {
        _model = State(initialValue: RoutineFormViewModel(schedule: schedule))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TFSpacing.lg) {
                titleBlock
                taskBlock
                scheduleBlock
                policyBlock
                previewBlock
                saveButton
                if let schedule = model.editingSchedule {
                    NavigationLink {
                        RoutineRunsScreen(schedule: schedule)
                    } label: {
                        Label("История запусков", systemImage: "clock.arrow.circlepath")
                    }
                    .hintAnchor(HintAnchorID.routineHistory)
                    .accessibilityIdentifier("routines.form.history")
                }
            }
            .padding(.horizontal, TFSpacing.screenHorizontal)
            .padding(.bottom, TFSpacing.sm)
        }
        .background(Color.tfBackground)
        .tfNativeHeader(model.editingSchedule == nil ? "Новая рутина" : "Рутина", displayMode: .inline)
        .task {
            await model.loadRoles()
            await model.refreshPreview()
        }
        .onChange(of: model.ruleKind) { _, _ in Task { await model.refreshPreview() } }
        .onChange(of: model.weeklyDay) { _, _ in Task { await model.refreshPreview() } }
        .onChange(of: model.monthlyDay) { _, _ in Task { await model.refreshPreview() } }
        .onChange(of: model.onceDate) { _, _ in Task { await model.refreshPreview() } }
        .onChange(of: model.weekdays) { _, _ in Task { await model.refreshPreview() } }
        .onChange(of: model.intervalMinutes) { _, _ in Task { await model.refreshPreview() } }
        .onChange(of: model.timeMinutes) { _, _ in Task { await model.refreshPreview() } }
        .onChange(of: model.timezone) { _, _ in Task { await model.refreshPreview() } }
    }

    // MARK: - Название

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            Text("Название рутины")
                .tfText(.action)
                .foregroundStyle(Color.tfSub)
            TFTextField("Например, Ежедневный отчёт продаж", text: $model.title)
                .accessibilityIdentifier("routines.form.title")
        }
    }

    // MARK: - Срок, повтор и зона

    private var scheduleBlock: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            Text("Расписание")
                .tfText(.action)
                .foregroundStyle(Color.tfSub)
            ExistingTaskDueEditor(
                dueDate: $model.startDate,
                startMinutes: $model.startMinutes,
                durationMin: $model.durationMin,
                runRepeat: $model.repeatChoice,
                repeatUntil: .constant(nil)
            )
            .accessibilityIdentifier("routines.form.schedule")
            Menu {
                ForEach(RoutineFormat.timezones, id: \.self) { zone in
                    Button {
                        model.timezone = zone
                    } label: {
                        if model.timezone == zone {
                            Label(RoutineFormat.timezoneTitle(zone), systemImage: "checkmark")
                        } else {
                            Text(RoutineFormat.timezoneTitle(zone))
                        }
                    }
                }
            } label: {
                HStack(spacing: TFSpacing.md) {
                    Image(systemName: "clock")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.tfDim)
                    Text(RoutineFormat.timezoneTitle(model.timezone))
                        .tfText(.row)
                        .foregroundStyle(Color.tfText)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: TFHitTarget.min)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("routines.form.timezone")
        }
    }

    // MARK: - Что создаст задачу

    private var taskBlock: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            Text("Задание рутины")
                .tfText(.action)
                .foregroundStyle(Color.tfSub)
            TFTextField("Название задачи", text: $model.taskTitle)
                .accessibilityIdentifier("routines.form.taskTitle")
            Text("Задание агенту").tfText(.action).foregroundStyle(Color.tfSub)
            instructionsEditor
            Text("В «Итоге» должен быть сам материал: дайджест, урок или отчёт. Укажите содержание и нужный формат.")
                .tfText(.caption).foregroundStyle(Color.tfSub)
            Menu {
                Button("Без роли") { model.assigneeRoleKey = nil }
                ForEach(model.roles, id: \.role) { role in
                    Button {
                        model.assigneeRoleKey = role.role
                    } label: {
                        if model.assigneeRoleKey == role.role {
                            Label(role.title, systemImage: "checkmark")
                        } else {
                            Text(role.title)
                        }
                    }
                }
            } label: {
                pickerRow(icon: "person.crop.circle", title: "Роль-исполнитель", value: roleTitle)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var instructionsEditor: some View {
        let editor = TextEditor(text: $model.instructions)
            .frame(minHeight: 120)
            .accessibilityIdentifier("routines.form.instructions")
        if model.editingSchedule != nil {
            editor.hintAnchor(HintAnchorID.routineInstructions)
        } else {
            editor
        }
    }

    // MARK: - Пропуски и наложения

    private var policyBlock: some View {
        VStack(alignment: .leading, spacing: TFSpacing.md) {
            Text("Пропуски и наложения")
                .tfText(.action)
                .foregroundStyle(Color.tfSub)
            HStack(spacing: TFSpacing.md) {
                Text("Пропускать запуск, пока прошлый не закрыт")
                    .tfText(.row)
                    .foregroundStyle(Color.tfText)
                Spacer(minLength: 0)
                TFToggle(isOn: $model.skipOverlapping)
            }
            .frame(minHeight: TFHitTarget.min)
            HStack(spacing: TFSpacing.md) {
                Text("Догонять пропущенный запуск")
                    .tfText(.row)
                    .foregroundStyle(Color.tfText)
                Spacer(minLength: 0)
                TFToggle(isOn: $model.catchUp)
            }
            .frame(minHeight: TFHitTarget.min)
        }
    }

    // MARK: - Превью и кнопка

    private var previewBlock: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            Text("Превью")
                .tfText(.action)
                .foregroundStyle(Color.tfSub)
            VStack(alignment: .leading, spacing: TFSpacing.xs) {
                Text(previewText)
                    .tfText(.action)
                    .foregroundStyle(Color.tfText)
                if let next = model.previewNextRun {
                    Text("Ближайший запуск — \(next)")
                        .tfText(.action)
                        .foregroundStyle(Color.tfSub)
                }
            }
            .padding(TFSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.tfCard2)
            .clipShape(RoundedRectangle(cornerRadius: TFRadius.md))
        }
    }

    private var saveButton: some View {
        VStack(spacing: TFSpacing.sm) {
            TFButton(model.editingSchedule == nil ? "Создать рутину" : "Сохранить изменения", variant: .secondary, isEnabled: model.canSave && !model.isSaving) {
                Task {
                    if await model.create() {
                        dismiss()
                    }
                }
            }
            .accessibilityIdentifier("routines.form.save")
            if let error = model.errorMessage {
                TFErrorBanner(error, variant: .block)
            }
        }
    }

    // MARK: - Подписи

    private var previewText: String {
        let label = model.previewLabel ?? RoutineFormat.ruleKindTitle(model.ruleKind)
        let taskName = model.taskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? model.title.trimmingCharacters(in: .whitespacesAndNewlines)
            : model.taskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let when = model.ruleKind == "interval"
            ? label
            : "\(label) в \(model.timeLocal)"
        return "Создаст задачу «\(taskName)» \(when)."
    }

    private var roleTitle: String {
        guard let key = model.assigneeRoleKey else { return "Без роли" }
        return model.roles.first { $0.role == key }?.title ?? key
    }

    private func pickerRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: TFSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(Color.tfDim)
            Text(title)
                .tfText(.row)
                .foregroundStyle(Color.tfText)
            Spacer(minLength: 0)
            Text(value)
                .tfText(.action)
                .foregroundStyle(Color.tfSub)
                .lineLimit(1)
        }
        .frame(minHeight: TFHitTarget.min)
        .contentShape(Rectangle())
    }
}
