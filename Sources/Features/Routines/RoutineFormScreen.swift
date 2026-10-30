import SwiftUI

// Форма рутины — отдельный экран (не шторка): полей много, и на телефоне
// шторка оставила бы половину формы под большим пальцем (дизайн, п. 2.6).
//
// Дата, время, длительность и повтор — тот же редактор срока, что в карточке
// задачи (`ExistingTaskDueEditor`). Часовой пояс не выбирается: рутина живёт
// по времени телефона.
struct RoutineFormScreen: View {
    @State private var model = RoutineFormViewModel()
    @State private var isDescriptionEditorPresented = false
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
                planBlock
            }
            .padding(.horizontal, TFSpacing.screenHorizontal)
            .padding(.bottom, TFSpacing.sm)
        }
        .background(Color.tfBackground)
        .tfNativeHeader(model.editingSchedule == nil ? "Новая рутина" : "Рутина", displayMode: .inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if showsSaveAction {
                    Button {
                        Task {
                            if await model.create() {
                                dismiss()
                            }
                        }
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .disabled(!model.canSave || model.isSaving)
                    .accessibilityLabel("Сохранить")
                    .accessibilityIdentifier("routines.form.save")
                }
            }
        }
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
        .sheet(isPresented: $isDescriptionEditorPresented) {
            NavigationStack {
                TextEditor(text: $model.instructions)
                    .scrollContentBackground(.hidden)
                    .padding(TFSpacing.md)
                    .background(Color.tfBackground)
                    .navigationTitle("Описание задачи")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Готово") { isDescriptionEditorPresented = false }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
        .alert("Не сохранено", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("Понятно", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    /// Новая рутина — галочка появляется, когда форма готова к созданию.
    /// Существующая — только когда в карточке реально что-то поменяли.
    private var showsSaveAction: Bool {
        model.editingSchedule == nil ? model.canSave : model.isDirty
    }

    // MARK: - Название рутины

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            Text("Название рутины")
                .tfText(.title)
                .foregroundStyle(Color.tfText)
            TFTextField("Например, Ежедневный отчёт продаж", text: $model.title, surface: .dark)
                .accessibilityIdentifier("routines.form.title")
        }
    }

    // MARK: - Задача

    private var taskBlock: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            Text("Название задачи")
                .tfText(.title)
                .foregroundStyle(Color.tfText)
            TFTextField("Название задачи", text: $model.taskTitle, surface: .dark)
                .accessibilityIdentifier("routines.form.taskTitle")
            Text("Описание задачи")
                .tfText(.title)
                .foregroundStyle(Color.tfText)
            // Компактная карточка описания: три строки с многоточием.
            // Полный текст правится на отдельном листе снизу — так поле
            // не растягивает форму (владелец 31.10.2026).
            Button {
                isDescriptionEditorPresented = true
            } label: {
                Text(model.instructions.isEmpty ? "Описание задачи" : model.instructions)
                    .tfText(.body)
                    .foregroundStyle(model.instructions.isEmpty ? Color.tfDim : Color.tfText)
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
                    .padding(TFSpacing.md)
                    .background(Color.tfFieldDark)
                    .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
                    .overlay {
                        RoundedRectangle(cornerRadius: TFRadius.lg)
                            .stroke(Color.tfFieldBorder, lineWidth: 1)
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("routines.form.instructions")
        }
    }

    // MARK: - Расписание

    private var scheduleBlock: some View {
        VStack(alignment: .leading, spacing: TFSpacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: TFSpacing.xs) {
                Text("Расписание")
                    .tfText(.title)
                    .foregroundStyle(Color.tfText)
                if let next = model.previewNextRun {
                    Text("(ближайший запуск — \(next))")
                        .tfText(.caption)
                        .foregroundStyle(Color.tfSub)
                }
            }
            ExistingTaskDueEditor(
                dueDate: $model.startDate,
                startMinutes: $model.startMinutes,
                durationMin: $model.durationMin,
                runRepeat: $model.repeatChoice,
                repeatUntil: .constant(nil),
                showsDateField: model.ruleUsesDate
            )
            .accessibilityIdentifier("routines.form.schedule")

            // «Пропуски и наложения» — часть расписания, не отдельный раздел.
            HStack(spacing: TFSpacing.xs) {
                Text("Пропускать запуск, пока прошлый не закрыт")
                    .tfText(.row)
                    .foregroundStyle(Color.tfText)
                TFInfoHint("Если предыдущий экземпляр рутины ещё выполняется, новый не создаётся — запуск пропускается.")
                Spacer(minLength: 0)
                TFToggle(isOn: $model.skipOverlapping)
            }
            .frame(minHeight: TFHitTarget.min)
            HStack(spacing: TFSpacing.xs) {
                Text("Догонять пропущенный запуск")
                    .tfText(.row)
                    .foregroundStyle(Color.tfText)
                TFInfoHint("Пропущенный по расписанию запуск будет создан при следующей возможности, а не потерян.")
                Spacer(minLength: 0)
                TFToggle(isOn: $model.catchUp)
            }
            .frame(minHeight: TFHitTarget.min)
        }
    }

    // MARK: - План

    private var planBlock: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            HStack(spacing: TFSpacing.xs) {
                Text("План")
                    .tfText(.title)
                    .foregroundStyle(Color.tfText)
                TFInfoHint(planCaption)
            }

            Menu {
                Button("Автоматически") { model.selectPlanTemplate(nil) }
                CollaborationPlanTemplateOptions { model.selectPlanTemplate($0) }
            } label: {
                HStack(spacing: TFSpacing.md) {
                    Image(systemName: selectedTemplate?.icon ?? "wand.and.stars")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.tfDim)
                    Text(selectedTemplate?.title ?? "Автоматически")
                        .tfText(.row)
                        .foregroundStyle(Color.tfText)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.tfDim)
                }
                .frame(minHeight: TFHitTarget.min)
                .contentShape(Rectangle())
            }
            .hintAnchor(HintAnchorID.routinePlanTemplate)
            .buttonStyle(.plain)
            .accessibilityIdentifier("routines.form.plan")

            if let template = selectedTemplate {
                PlanFlowView(stages: CollaborationPlanTemplate.stages(for: template.profile))
            }
        }
    }

    private var planCaption: String {
        selectedTemplate == nil
            ? "План соберётся по задаче автоматически."
            : "Сервер собирает план по этому шаблону; состав шагов можно донастроить в карточке задачи после создания."
    }

    private var selectedTemplate: (profile: String, title: String, icon: String)? {
        guard let profile = model.planProfile else { return nil }
        return CollaborationPlanTemplate.all.first { $0.profile == profile }
    }

}

/// Последовательность плана: этапы сверху вниз, параллельные роли — в одной
/// строке. Это не живой граф задачи (`CollaborationPlanView`), а превью
/// маршрута выбранного шаблона до создания карточки.
private struct PlanFlowView: View {
    let stages: [[String]]

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.xs) {
            ForEach(Array(stages.enumerated()), id: \.offset) { index, roles in
                HStack(spacing: TFSpacing.xs) {
                    ForEach(Array(roles.enumerated()), id: \.offset) { roleIndex, role in
                        if roleIndex > 0 {
                            Text("∥")
                                .tfText(.caption)
                                .foregroundStyle(Color.tfSub)
                        }
                        Text(role)
                            .tfText(.row)
                            .foregroundStyle(Color.tfText)
                            .padding(.horizontal, TFSpacing.sm)
                            .padding(.vertical, TFSpacing.xs)
                            .background(Color.tfCard)
                            .clipShape(Capsule())
                    }
                    Spacer(minLength: 0)
                }
                if index < stages.count - 1 {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.tfDim)
                        .padding(.leading, TFSpacing.md)
                }
            }
        }
        .padding(TFSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tfCard2)
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.md))
        .accessibilityIdentifier("routines.form.planFlow")
    }
}
