import SwiftUI

// Форма рутины — отдельный экран (не шторка): полей много, и на телефоне
// шторка оставила бы половину формы под большим пальцем (дизайн, п. 2.6).
//
// Правило и время — барабанными пикерами, как в существующем редакторе срока
// (`ExistingTaskDueEditor`); дни недели — кнопками; часовой пояс — строкой с
// переходом к выбору.
struct RoutineFormScreen: View {
    @State private var model = RoutineFormViewModel()
    @State private var timeDate = Date()
    @Environment(\.dismiss) private var dismiss
    @Environment(ProjectStore.self) private var projectStore

    init(schedule: ApiSchedule? = nil) {
        let model = RoutineFormViewModel(schedule: schedule)
        _model = State(initialValue: model)
        _timeDate = State(initialValue: Calendar.current.date(bySettingHour: model.timeMinutes / 60, minute: model.timeMinutes % 60, second: 0, of: Date()) ?? Date())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TFSpacing.xl) {
                titleBlock
                ruleBlock
                timeBlock
                taskBlock
                policyBlock
                previewBlock
                saveButton
            }
            .padding(.horizontal, TFSpacing.screenHorizontal)
            .padding(.bottom, TFSpacing.xl)
        }
        .background(Color.tfBackground)
        .tfNativeHeader(model.editingSchedule == nil ? "Новая автоматизация" : "Автоматизация", displayMode: .inline)
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
        .onChange(of: timeDate) { _, newValue in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            model.timeMinutes = (parts.hour ?? 9) * 60 + (parts.minute ?? 0)
        }
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

    // MARK: - Правило

    private var ruleBlock: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            Text("Правило")
                .tfText(.action)
                .foregroundStyle(Color.tfSub)
            VStack(spacing: 0) {
                ForEach(RoutineFormat.ruleKinds, id: \.self) { kind in
                    Button {
                        model.ruleKind = kind
                    } label: {
                        HStack(spacing: TFSpacing.md) {
                            Image(systemName: model.ruleKind == kind ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: 18))
                                .foregroundStyle(Color.tfDim)
                            Text(RoutineFormat.ruleKindTitle(kind))
                                .tfText(.row)
                                .foregroundStyle(Color.tfText)
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: TFHitTarget.min)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("routines.form.rule.\(kind)")
                }
            }
            if model.ruleKind == "weekly_days" {
                weekdaysPicker
            }
            if model.ruleKind == "weekly" {
                weeklyDayPicker
            }
            if model.ruleKind == "monthly" {
                monthlyDayPicker
            }
            if model.ruleKind == "once" {
                DatePicker("Дата запуска", selection: $model.onceDate, displayedComponents: .date)
                    .environment(\.timeZone, TimeZone(identifier: model.timezone) ?? .current)
            }
            if model.ruleKind == "interval" {
                intervalPicker
            }
        }
    }

    private var weekdaysPicker: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            Text("Дни недели")
                .tfText(.action)
                .foregroundStyle(Color.tfSub)
            HStack(spacing: TFSpacing.xs) {
                ForEach(1...7, id: \.self) { day in
                    let names = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
                    Button {
                        if model.weekdays.contains(day) {
                            model.weekdays.remove(day)
                        } else {
                            model.weekdays.insert(day)
                        }
                    } label: {
                        Text(names[day - 1])
                            .tfText(.action)
                            .foregroundStyle(model.weekdays.contains(day) ? Color.tfText : Color.tfSub)
                            .frame(width: TFHitTarget.min, height: TFHitTarget.min)
                            .background(model.weekdays.contains(day) ? Color.tfCard2 : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: TFRadius.pill))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(names[day - 1])
                    .accessibilityIdentifier("routines.form.day.\(day)")
                }
            }
            if model.weekdays.isEmpty {
                Text("Выберите хотя бы один день")
                    .tfText(.action)
                    .foregroundStyle(Color.tfCoral)
            }
        }
    }

    /// День недели для правила «Еженедельно» — как в вебе.
    private var weeklyDayPicker: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            Text("День недели")
                .tfText(.action)
                .foregroundStyle(Color.tfSub)
            HStack(spacing: TFSpacing.xs) {
                ForEach(1...7, id: \.self) { day in
                    let names = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
                    Button {
                        model.weeklyDay = day
                    } label: {
                        Text(names[day - 1])
                            .tfText(.action)
                            .foregroundStyle(model.weeklyDay == day ? Color.tfText : Color.tfSub)
                            .frame(width: TFHitTarget.min, height: TFHitTarget.min)
                            .background(model.weeklyDay == day ? Color.tfCard2 : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: TFRadius.pill))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(names[day - 1])
                    .accessibilityIdentifier("routines.form.weekday.\(day)")
                }
            }
        }
    }

    /// День месяца для правила «Ежемесячно» — как в вебе.
    private var monthlyDayPicker: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            Text("День месяца")
                .tfText(.action)
                .foregroundStyle(Color.tfSub)
            Menu {
                ForEach(1...31, id: \.self) { day in
                    Button {
                        model.monthlyDay = day
                    } label: {
                        if model.monthlyDay == day {
                            Label("\(day)-е число", systemImage: "checkmark")
                        } else {
                            Text("\(day)-е число")
                        }
                    }
                }
            } label: {
                Text("\(model.monthlyDay)-е число")
                    .tfText(.row)
                    .foregroundStyle(Color.tfText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: TFHitTarget.min)
                    .padding(.horizontal, TFSpacing.lg)
                    .background(Color.tfCard)
                    .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
            }
            .accessibilityIdentifier("routines.form.monthday")
        }
    }

    private var intervalPicker: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            Text("Интервал")
                .tfText(.action)
                .foregroundStyle(Color.tfSub)
            Menu {
                ForEach(RoutineFormViewModel.intervalOptions, id: \.self) { minutes in
                    Button {
                        model.intervalMinutes = minutes
                    } label: {
                        if model.intervalMinutes == minutes {
                            Label(RoutineFormat.intervalText(RoutineFormat.intervalExpr(minutes: minutes)), systemImage: "checkmark")
                        } else {
                            Text(RoutineFormat.intervalText(RoutineFormat.intervalExpr(minutes: minutes)))
                        }
                    }
                }
            } label: {
                Text(RoutineFormat.intervalText(RoutineFormat.intervalExpr(minutes: model.intervalMinutes)))
                    .tfText(.row)
                    .foregroundStyle(Color.tfText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: TFHitTarget.min)
                    .padding(.horizontal, TFSpacing.lg)
                    .background(Color.tfCard)
                    .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
            }
            .accessibilityIdentifier("routines.form.interval")
        }
    }

    // MARK: - Время запуска и зона

    @ViewBuilder
    private var timeBlock: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            Text("Время запуска")
                .tfText(.action)
                .foregroundStyle(Color.tfSub)
            if model.ruleKind == "interval" {
                Text("Для интервала время запуска не нужно — рутина срабатывает каждые выбранные минуты.")
                    .tfText(.action)
                    .foregroundStyle(Color.tfSub)
            } else {
                DatePicker("", selection: $timeDate, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.wheel)
                    .frame(width: 300, height: 180)
                    .clipped()
                    .environment(\.locale, Locale(identifier: "ru_RU"))
                    .accessibilityIdentifier("routines.form.time")
            }
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
            Text("Что создаст задачу")
                .tfText(.action)
                .foregroundStyle(Color.tfSub)
            TFTextField("Название задачи", text: $model.taskTitle)
                .accessibilityIdentifier("routines.form.taskTitle")
            Text("Задание агенту").tfText(.action).foregroundStyle(Color.tfSub)
            TextEditor(text: $model.instructions)
                .frame(minHeight: 120)
                .accessibilityIdentifier("routines.form.instructions")
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
            Menu {
                Button("Без проекта") { model.projectId = nil }
                ForEach(projectStore.projects) { project in
                    Button {
                        model.projectId = project.id
                    } label: {
                        if model.projectId == project.id {
                            Label(project.name, systemImage: "checkmark")
                        } else {
                            Text(project.name)
                        }
                    }
                }
            } label: {
                pickerRow(icon: "folder", title: "Проект", value: projectTitle)
            }
            .buttonStyle(.plain)
            Menu {
                ForEach(TaskPriority.allCases, id: \.rawValue) { priority in
                    Button {
                        model.priority = priority
                    } label: {
                        if model.priority == priority {
                            Label(priority.label, systemImage: "checkmark")
                        } else {
                            Text(priority.label)
                        }
                    }
                }
            } label: {
                pickerRow(icon: "flag", title: "Приоритет", value: model.priority.label)
            }
            .buttonStyle(.plain)
            Menu {
                Button("Без длительности") { model.durationMin = nil }
                ForEach([15, 30, 45, 60, 120, 180], id: \.self) { minutes in
                    Button {
                        model.durationMin = minutes
                    } label: {
                        if model.durationMin == minutes {
                            Label("\(minutes) мин", systemImage: "checkmark")
                        } else {
                            Text("\(minutes) мин")
                        }
                    }
                }
            } label: {
                pickerRow(icon: "hourglass", title: "Длительность", value: durationTitle)
            }
            .buttonStyle(.plain)
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
            TFButton(model.editingSchedule == nil ? "Создать автоматизацию" : "Сохранить автоматизацию", variant: .secondary, isEnabled: model.canSave && !model.isSaving) {
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

    private var projectTitle: String {
        guard let id = model.projectId else { return "Без проекта" }
        return projectStore.projects.first { $0.id == id }?.name ?? "Без проекта"
    }

    private var durationTitle: String {
        guard let minutes = model.durationMin else { return "Без длительности" }
        return "\(minutes) мин"
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
