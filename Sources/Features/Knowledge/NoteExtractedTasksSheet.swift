import SwiftUI

// «Собрать задачи из текста» — содержимое нижней шторки, spec/SCREENS-2.md
// §2 «Меню AI»: AI только ПРЕДЛАГАЕТ задачи (`extract-tasks`), ничего не
// создаёт сам — здесь подтверждение (галочка включить/выключить + правка
// заголовка) и выбор проекта (существующий или «Новый проект» тут же).
// Веб-аналог — `TasksFromTextSheet.tsx` (эндпоинт общий), логика повторена,
// UI — свой (шторка `TFBottomSheetContent`, не веб-компоновка).
struct NoteExtractedTasksSheetContent: View {
    let tasks: [ExtractedNoteTask]
    let onDone: () -> Void

    @Environment(ProjectStore.self) private var projectStore
    private let apiClient = APIClient()

    struct Row: Identifiable {
        let id = UUID()
        var include = true
        var title: String
        let source: ExtractedNoteTask
    }

    @State private var rows: [Row] = []
    @State private var selectedProjectID: String?
    @State private var isCreatingNew = false
    @State private var newProjectName = ""
    @State private var isBusy = false
    @State private var errorMessage: String?

    private var includedCount: Int { rows.filter(\.include).count }
    private var canConfirm: Bool {
        includedCount > 0 && !isBusy
            && (isCreatingNew ? !newProjectName.trimmingCharacters(in: .whitespaces).isEmpty : selectedProjectID != nil)
    }

    private var confirmButtonTitle: String {
        if isBusy { return "Создаю…" }
        return includedCount > 0 ? "Создать (\(includedCount))" : "Создать"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.md) {
            if rows.isEmpty {
                Text("AI не нашёл в тексте конкретных задач")
                    .tfText(.action)
                    .foregroundStyle(Color.tfDim)
            } else {
                ForEach($rows) { $row in
                    rowView($row)
                }

                Text("КУДА ДОБАВИТЬ")
                    .tfText(.meta)
                    .foregroundStyle(Color.tfDim)
                    .padding(.top, TFSpacing.xs)

                ForEach(projectStore.projects) { project in
                    projectRow(project)
                }
                newProjectRow

                TFErrorBanner(errorMessage)

                // 16.10.2026 (LOCK-UI-DRIFT-KNOWN): `variant: .primary` проставлен явно.
                // Красный здесь законен — это подтверждение действия («Создать»),
                // такой же образец, как «Сохранить» в `EditProfileSheet` и
                // `TemplatesScreen`. Раньше вариант не был указан, и скан не мог
                // отличить подтверждение от действия по умолчанию, из-за чего
                // кнопка попадала в находки.
                TFButton(confirmButtonTitle, variant: .primary, isEnabled: canConfirm) {
                    Task { await confirm() }
                }
            }
        }
        .padding(.bottom, TFSpacing.xl)
        .task {
            if rows.isEmpty { rows = tasks.map { Row(title: $0.title, source: $0) } }
            if projectStore.projects.isEmpty { await projectStore.load() }
        }
    }

    private func rowView(_ row: Binding<Row>) -> some View {
        HStack(spacing: TFSpacing.sm) {
            TFCheckbox(
                isChecked: row.wrappedValue.include,
                label: "Включить задачу",
                action: { row.wrappedValue.include.toggle() }
            )

            // Подложка поля — канон `TFCard` (поверхность `card2`, радиус `md`),
            // раньше та же подложка собиралась руками. Отступы поля остались
            // внутри содержимого, поэтому у карточки отступ нулевой.
            TFCard(padding: 0, surface: .card2, radius: TFRadius.md) {
                TextField("Название", text: row.title)
                    // Поле ввода — ступень `input` (16), не `body` (15): правило
                    // «16 только под поля» держим единым (LOCK-TYPOGRAPHY-SPEC,
                    // дефект В).
                    .tfText(.input)
                    .foregroundStyle(Color.tfText)
                    .disabled(!row.wrappedValue.include)
                    .opacity(row.wrappedValue.include ? 1 : 0.4)
                    .padding(.horizontal, TFSpacing.sm)
                    .frame(height: TFHitTarget.min)
            }
        }
    }

    private func projectRow(_ project: ApiProject) -> some View {
        Button {
            selectedProjectID = project.id
            isCreatingNew = false
        } label: {
            HStack(spacing: TFSpacing.sm) {
                Image(systemName: "number")
                    .foregroundStyle(Color.tfReadableText(project.color.map { Color(hex: $0) } ?? Color.tfSub))
                Text(project.name)
                    .tfText(.body)
                    .foregroundStyle(Color.tfText)
                Spacer()
                if selectedProjectID == project.id && !isCreatingNew {
                    Image(systemName: "checkmark").foregroundStyle(Color.tfRed)
                }
            }
            .padding(.vertical, TFSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(TFTapRowStyle())
    }

    private var newProjectRow: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            Button {
                isCreatingNew = true
                selectedProjectID = nil
            } label: {
                HStack(spacing: TFSpacing.sm) {
                    Image(systemName: "plus").foregroundStyle(Color.tfSub)
                    Text("Новый проект").tfText(.body).foregroundStyle(Color.tfText)
                    Spacer()
                    if isCreatingNew { Image(systemName: "checkmark").foregroundStyle(Color.tfRed) }
                }
                .padding(.vertical, TFSpacing.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(TFTapRowStyle())
            if isCreatingNew {
                TFTextField("Название проекта", text: $newProjectName)
            }
        }
    }

    private func confirm() async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        var projectID = selectedProjectID
        if isCreatingNew {
            guard let created = await projectStore.create(name: newProjectName.trimmingCharacters(in: .whitespaces), withDocs: true) else {
                errorMessage = "Не удалось создать задачи"
                return
            }
            projectID = created.id
        }
        do {
            for row in rows where row.include && !row.title.trimmingCharacters(in: .whitespaces).isEmpty {
                let payload = APIClient.NewTaskRequest(
                    title: row.title.trimmingCharacters(in: .whitespaces),
                    description: row.source.description,
                    dueDate: row.source.dueDate,
                    projectId: projectID,
                    priority: row.source.priority
                )
                _ = try await apiClient.createTask(payload)
            }
            onDone()
        } catch {
            errorMessage = "Не удалось создать задачи"
        }
    }
}
