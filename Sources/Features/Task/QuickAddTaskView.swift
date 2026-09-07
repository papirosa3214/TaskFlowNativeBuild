import SwiftUI
import UniformTypeIdentifiers

/// Быстрое создание задачи построено только на системных `Form`, `Section`,
/// `Picker` и `sheet`: без чипов, собственных фонов, обводок и анимаций.
struct QuickAddTaskView: View {
    @Bindable var viewModel: TaskFormViewModel
    var onSaved: () -> Void
    var onExpand: () -> Void

    @Environment(TaskStore.self) private var taskStore
    @Environment(ProjectStore.self) private var projectStore
    @Environment(LabelStore.self) private var labelStore
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTitleFocused: Bool
    @State private var activePicker: QuickAddPicker?
    @State private var isAttachmentImporterPresented = false
    @State private var dictation = DictationEngine.shared

    private enum QuickAddPicker: String, Identifiable {
        case project, dueDate, priority, labels, attachments
        var id: String { rawValue }
        var title: String {
            switch self {
            case .project: "Проект"
            case .dueDate: "Срок"
            case .priority: "Приоритет"
            case .labels: "Метки"
            case .attachments: "Вложения"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Название задачи", text: $viewModel.title, axis: .vertical)
                        .focused($isTitleFocused)
                        .submitLabel(.done)
                        .onSubmit { save() }
                    TextField("Описание", text: $viewModel.taskDescription, axis: .vertical)
                }

                Section("Параметры") {
                    parameterRow("Проект", value: projectName, icon: "folder") { activePicker = .project }
                    parameterRow("Срок", value: dueDateText, icon: "calendar") { activePicker = .dueDate }
                    parameterRow("Приоритет", value: viewModel.priority.label, icon: "flag") { activePicker = .priority }
                    parameterRow("Метки", value: labelsText, icon: "tag") { activePicker = .labels }
                    parameterRow("Вложения", value: attachmentsText, icon: "paperclip") { activePicker = .attachments }
                }

                Section {
                    Button {
                        onExpand()
                    } label: {
                        Label("Открыть полную форму", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                }
            }
            .navigationTitle("Новая задача")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await toggleDictation() } } label: {
                        Image(systemName: dictation.recordingState == .recording ? "stop.fill" : "mic")
                    }
                    .accessibilityLabel(dictation.recordingState == .recording ? "Остановить запись" : "Голосовой ввод")
                    .disabled(dictation.recordingState == .transcribing)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Добавить") { save() }
                        .disabled(!viewModel.isSaveEnabled)
                }
            }
        }
        .sheet(item: $activePicker) { picker in pickerScreen(picker) }
        .alert("Не удалось сохранить задачу", isPresented: Binding(
            get: { viewModel.saveErrorMessage != nil },
            set: { if !$0 { viewModel.saveErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.saveErrorMessage = nil }
        } message: {
            Text(viewModel.saveErrorMessage ?? "")
        }
        .task {
            await viewModel.loadAgents()
            isTitleFocused = true
        }
    }

    private func parameterRow(_ title: String, value: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            LabeledContent {
                Text(value).foregroundStyle(.secondary)
            } label: {
                Label(title, systemImage: icon)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Открывает выбор параметра")
    }

    private var projectName: String {
        projectStore.projects.first { $0.id == viewModel.projectId }?.name ?? "Не выбран"
    }

    private var dueDateText: String {
        guard let dueDate = viewModel.dueDate else { return "Не установлен" }
        let date = TaskDateText.dueLabel(dueDate)
        guard let minutes = viewModel.startMinutes else { return date }
        return "\(date), \(String(format: "%02d:%02d", minutes / 60, minutes % 60))"
    }

    private var labelsText: String {
        switch viewModel.selectedLabelIds.count {
        case 0: "Не выбраны"
        case 1: labelStore.labels.first { viewModel.selectedLabelIds.contains($0.id) }?.name ?? "1 метка"
        default: "\(viewModel.selectedLabelIds.count) метки"
        }
    }

    private var attachmentsText: String {
        let count = viewModel.attachments.uploaded.count + viewModel.attachments.pending.count
        return count == 0 ? "Нет" : "\(count)"
    }

    @ViewBuilder
    private func pickerScreen(_ picker: QuickAddPicker) -> some View {
        NavigationStack {
            Form {
                switch picker {
                case .project:
                    Picker("Проект", selection: $viewModel.projectId) {
                        Text("Не выбран").tag(String?.none)
                        ForEach(projectStore.projects) { project in
                            Text(project.name).tag(Optional(project.id))
                        }
                    }
                case .dueDate:
                    dueDatePicker
                case .priority:
                    Picker("Приоритет", selection: $viewModel.priority) {
                        ForEach(TaskPriority.allCases, id: \.rawValue) { priority in
                            Text(priority.label).tag(priority)
                        }
                    }
                    .pickerStyle(.inline)
                case .labels:
                    labelsPicker
                case .attachments:
                    attachmentsPicker
                }
            }
            .navigationTitle(picker.title)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { activePicker = nil }
                }
            }
        }
    }

    private var dueDatePicker: some View {
        Section {
            Toggle("Установить срок", isOn: hasDueDate)
            if viewModel.dueDate != nil {
                DatePicker("Дата", selection: dueDateSelection, displayedComponents: .date)
                Toggle("Указать время", isOn: hasStartTime)
                if viewModel.startMinutes != nil {
                    DatePicker("Время", selection: startTimeSelection, displayedComponents: .hourAndMinute)
                    Picker("Продолжительность", selection: $viewModel.durationMin) {
                        Text("Не указана").tag(Int?.none)
                        Text("15 минут").tag(Optional(15))
                        Text("30 минут").tag(Optional(30))
                        Text("45 минут").tag(Optional(45))
                        Text("1 час").tag(Optional(60))
                        Text("2 часа").tag(Optional(120))
                        Text("3 часа").tag(Optional(180))
                    }
                }
            }
        }
    }

    private var labelsPicker: some View {
        Section {
            ForEach(labelStore.labels) { label in
                Toggle(label.name, isOn: Binding(
                    get: { viewModel.selectedLabelIds.contains(label.id) },
                    set: { selected in
                        if selected { viewModel.selectedLabelIds.insert(label.id) }
                        else { viewModel.selectedLabelIds.remove(label.id) }
                    }
                ))
            }
        }
    }

    private var attachmentsPicker: some View {
        Section {
            Button { isAttachmentImporterPresented = true } label: {
                Label("Выбрать файл", systemImage: "paperclip")
            }
            .disabled(viewModel.attachments.isUploading)

            ForEach(viewModel.attachments.pending) { attachment in
                attachmentRow(attachment.fileName) { viewModel.attachments.removePending(attachment) }
            }
            ForEach(viewModel.attachments.uploaded) { attachment in
                attachmentRow(attachment.fileName) { Task { await viewModel.attachments.removeUploaded(attachment) } }
            }
        }
        .fileImporter(isPresented: $isAttachmentImporterPresented, allowedContentTypes: [.item]) { result in
            if case .success(let url) = result {
                Task { await viewModel.attachments.add(url: url) }
            }
        }
    }

    private func attachmentRow(_ name: String, remove: @escaping () -> Void) -> some View {
        HStack {
            Text(name).lineLimit(1)
            Spacer()
            Button(role: .destructive, action: remove) {
                Image(systemName: "trash")
            }
            .accessibilityLabel("Удалить \(name)")
        }
    }

    private var hasDueDate: Binding<Bool> {
        Binding(
            get: { viewModel.dueDate != nil },
            set: { enabled in
                if enabled { viewModel.dueDate = Calendar.current.startOfDay(for: Date()) }
                else {
                    viewModel.dueDate = nil
                    viewModel.startMinutes = nil
                    viewModel.durationMin = nil
                }
            }
        )
    }

    private var dueDateSelection: Binding<Date> {
        Binding(get: { viewModel.dueDate ?? Date() }, set: { viewModel.dueDate = $0 })
    }

    private var hasStartTime: Binding<Bool> {
        Binding(
            get: { viewModel.startMinutes != nil },
            set: { enabled in
                viewModel.startMinutes = enabled ? (viewModel.startMinutes ?? 9 * 60) : nil
                if !enabled { viewModel.durationMin = nil }
            }
        )
    }

    private var startTimeSelection: Binding<Date> {
        Binding(
            get: {
                let minutes = viewModel.startMinutes ?? 9 * 60
                return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                viewModel.startMinutes = (components.hour ?? 9) * 60 + (components.minute ?? 0)
            }
        )
    }

    private func toggleDictation() async {
        switch dictation.recordingState {
        case .idle, .failed:
            await dictation.startRecording()
        case .recording:
            guard let text = await dictation.stopRecordingAndTranscribe() else { return }
            viewModel.title += viewModel.title.isEmpty ? text : " \(text)"
        case .transcribing:
            break
        }
    }

    private func save() {
        guard viewModel.isSaveEnabled else { return }
        Task {
            if await viewModel.save(taskStore: taskStore) {
                onSaved()
            }
        }
    }
}
