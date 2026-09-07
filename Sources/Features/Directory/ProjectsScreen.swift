import SwiftUI

// «Проекты» — spec/SCREENS-2.md §7, `/projects`. Сверено построчно с живым
// `src/screens/ProjectsScreen.tsx` 31.08.2026 (ARCHITECTURE.md правило 3 —
// расходится спека с кодом, верю коду). Правка 03.09.2026 по прямой просьбе
// владельца — см. пункты 1 и 2 ниже.
//
// 1. Шапка — `.tfNativeHeader` (TFNativeHeader.swift), не самодельный
//    `.toolbarBackground(.ultraThinMaterial, ...)`. Старая ручная связка
//    конфликтовала с системным scroll edge effect (iOS 26 рисует блюр по
//    скроллу сама, без единой строчки кода — см. комментарий в
//    TFNativeHeader.swift) и давала серую плашку при прокрутке вверх.
// 2. Кнопка создания — «+» в toolbar (`topBarTrailing`), как у «Активности»
//    (ActivityScreen.swift). Раньше входа не было вообще: единственный путь
//    в вебе — `?create=1` от долгого нажатия таббара, а этот жест здесь не
//    реализован (см. ProjectsScreen.tsx/TFTabBar). Осознанное расхождение с
//    вебом по прямой просьбе владельца, не баг.
// 3. Пустое состояние — просто строка текста (не `TFEmptyState` с иконкой,
//    как у Меток) — 1:1 с кодом, текст обновлён под новую кнопку.
struct ProjectsScreen: View {
    @Environment(ProjectStore.self) private var projectStore

    @State private var editingID: String?
    @State private var showCreate = false
    @State private var deleteRequest: DirectoryConfirmRequest?
    @State private var errorMessage: String?

    private let apiClient = APIClient()

    var body: some View {
        ScrollView {
            // Интервал 8pt, а не 2pt: карточки (`ProjectCard`) — отдельные
            // объекты со скруглением, слипшийся ряд из них читается как
            // сломанная таблица.
            LazyVStack(spacing: TFSpacing.sm) {
                if showCreate {
                    ProjectCreateForm(onCreated: { showCreate = false }, onCancel: { showCreate = false })
                }

                ForEach(projectStore.projects) { project in
                    if editingID == project.id {
                        ProjectEditForm(project: project, apiClient: apiClient, onSaved: {
                            editingID = nil
                            Task { await projectStore.load() }
                        }, onCancel: { editingID = nil })
                    } else {
                        DirectorySwipeRow(
                            onEdit: { editingID = project.id },
                            onDelete: { requestDelete(project) },
                            cornerRadius: TFRadius.xl
                        ) {
                            projectRow(project)
                        }
                    }
                }

                if projectStore.projects.isEmpty && !projectStore.isLoading && !showCreate {
                    Text("Проектов пока нет — нажмите «+» вверху, чтобы создать")
                        .tfText(.action)
                        .foregroundStyle(Color.tfDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, TFSpacing.xs)
                }

                if projectStore.isLoading { TFLoading(.block) }
                TFErrorBanner(projectStore.errorMessage, variant: .inline)
                TFErrorBanner(errorMessage, variant: .block)
            }
            .padding(.horizontal, TFSpacing.screenHorizontal)
            .padding(.top, TFSpacing.sm)
            .padding(.bottom, TFSpacing.xl)
        }
        // Штатный pull-to-refresh (iOS 15+). Прокрути вниз и потяни — вызовет
        // projectStore.load(). Сегодня не трогаю по требованию владельца.
        .refreshable { await projectStore.load() }
        .background(Color.tfBackground)
        // Штатная SwiftUI-шапка. Системная стрелка назад добавляется стеком
        // навигации; в toolbar остаётся только «+».
        .tfNativeHeader("Проекты")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreate = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Создать проект")
            }
        }
        .task { if projectStore.projects.isEmpty { await projectStore.load() } }
        .directoryConfirm($deleteRequest)
    }

    /// Строка проекта — карточка (`ProjectCard`), а не однострочный ряд:
    /// владелец 08.09.2026 попросил видеть в списке жизнь проекта, а не одно
    /// число. Сам ряд остался кнопкой в тот же маршрут и по-прежнему живёт
    /// внутри `DirectorySwipeRow` (правка/удаление свайпом).
    private func projectRow(_ project: ApiProject) -> some View {
        NavigationLink(value: AppRoute.projectTasks(projectID: project.id)) {
            ProjectCard(project: project)
        }
        .buttonStyle(TFTapRowStyle())
    }

    /// Текст confirm-а зависит от `task_count` — прямая цитата `ProjectsScreen.tsx`.
    private func requestDelete(_ project: ApiProject) {
        let count = project.taskCount ?? 0
        deleteRequest = DirectoryConfirmRequest(
            title: "Удалить проект «\(project.name)»?",
            description: count > 0
                ? "Задачи внутри (\(count) \(DirectoryPluralize.taskWord(count))) не удалятся — они останутся без проекта. Сам проект и его столбец на доске исчезнут без возможности отмены."
                : "В нём сейчас нет задач. Действие нельзя отменить.",
            onConfirm: {
                Task {
                    await projectStore.delete(projectId: project.id)
                }
            }
        )
    }
}

/// Форма создания — над списком (по кнопке «+» в toolbar), симметрично
/// `ProjectEditForm` ниже: то же поле, те же свотчи, та же пара кнопок.
private struct ProjectCreateForm: View {
    @Environment(ProjectStore.self) private var projectStore
    let onCreated: () -> Void
    let onCancel: () -> Void

    @State private var name = ""
    @State private var color = DirectoryColors.project[0]
    @State private var isSaving = false
    /// Полка базы знаний. `nil` — общая база TaskFlow.
    @State private var datasetId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.md) {
            TextField("Название проекта", text: $name)
                .tfText(.input)
                .foregroundStyle(Color.tfText)
                .padding(.horizontal, TFSpacing.sm + 4)
                .padding(.vertical, TFSpacing.sm + 2)
                .background(Color.tfCard2)
                .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))

            DirectoryColorSwatches(colors: DirectoryColors.project, selected: $color, size: 24)

            // У нового проекта документов ещё нет, переносить нечего —
            // предупреждение о переиндексации здесь не нужно.
            KnowledgeDatasetPicker(selection: $datasetId)

            TFErrorBanner(projectStore.errorMessage, variant: .block)

            HStack(spacing: TFSpacing.sm) {
                Button("Отмена", action: onCancel)
                    .buttonStyle(TFTapRowStyle())
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .tfText(.row)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.tfSub)
                    .background(Color.tfCard2)
                    .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))

                Button {
                    Task { await create() }
                } label: {
                    Text(isSaving ? "Создаём…" : "Создать")
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .tfText(.row)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .background(Color.tfRedSolid)
                        .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
                }
                .buttonStyle(TFTapFadeStyle())
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
            }
        }
        .padding(TFSpacing.lg)
        .background(Color.tfCard)
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.xl))
    }

    private func create() async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }
        if await projectStore.create(
            name: trimmed, color: color, knowledgeDatasetId: datasetId
        ) != nil {
            onCreated()
        }
    }
}

/// Инлайн-форма переименования — разворачивается на месте строки (spec §7),
/// поле + 7 свотчей `PROJECT_COLORS`, «Отмена»/«Сохранить». Своим `APIClient()`
/// зовёт `patchProject` — `ProjectStore` метода `update` не даёт (Core чужой),
/// после успеха родитель перезагружает стор, чтобы кэш не разъехался с сервером.
private struct ProjectEditForm: View {
    let project: ApiProject
    let apiClient: APIClient
    let onSaved: () -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var color: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    /// Полка базы знаний. `nil` — общая база TaskFlow.
    @State private var datasetId: String?
    /// Текст предупреждения от сервера (409): сколько документов переедет и
    /// сколько примерно займёт переиндексация. Пока он не пуст — показан
    /// диалог, и до ответа владельца ничего не сохраняется.
    @State private var reindexPrompt: String?

    init(project: ApiProject, apiClient: APIClient, onSaved: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.project = project
        self.apiClient = apiClient
        self.onSaved = onSaved
        self.onCancel = onCancel
        _name = State(initialValue: project.name)
        _color = State(initialValue: project.color ?? DirectoryColors.project[0])
        _datasetId = State(initialValue: project.knowledgeDatasetId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.md) {
            TextField("Название проекта", text: $name)
                .tfText(.input)
                .foregroundStyle(Color.tfText)
                .padding(.horizontal, TFSpacing.sm + 4)
                .padding(.vertical, TFSpacing.sm + 2)
                .background(Color.tfCard2)
                .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))

            DirectoryColorSwatches(colors: DirectoryColors.project, selected: $color, size: 24)

            KnowledgeDatasetPicker(
                selection: $datasetId,
                reindexWarning: datasetChanged && documentCount > 0
                    ? "Смена базы знаний = переиндексация: \(documentCount) док. уедут "
                      + "в другую базу и будут посчитаны заново. Это займёт время, и "
                      + "пока идёт индексация, эти документы в поиске не находятся."
                    : nil
            )

            TFErrorBanner(errorMessage, variant: .block)

            HStack(spacing: TFSpacing.sm) {
                Button("Отмена", action: onCancel)
                    .buttonStyle(TFTapRowStyle())
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .tfText(.row)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.tfSub)
                    .background(Color.tfCard2)
                    .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))

                Button {
                    Task { await save() }
                } label: {
                    Text(isSaving ? "Сохраняем…" : "Сохранить")
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .tfText(.row)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .background(Color.tfRedSolid)
                        .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
                }
                .buttonStyle(TFTapFadeStyle())
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
            }
        }
        .padding(TFSpacing.lg)
        .background(Color.tfCard)
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.xl))
        // Текст диалога — тот, что прислал сервер: там точное число
        // документов и оценка минут, а не догадка клиента.
        .confirmationDialog(
            "Переиндексация",
            isPresented: Binding(
                get: { reindexPrompt != nil },
                set: { if !$0 { reindexPrompt = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Перенести и переиндексировать", role: .destructive) {
                Task { await save(confirmReindex: true) }
            }
            Button("Отмена", role: .cancel) { reindexPrompt = nil }
        } message: {
            Text(reindexPrompt ?? "")
        }
    }

    /// Документов у проекта — из карточки (`docs_count`). Нужно, чтобы не
    /// пугать предупреждением там, где переносить нечего.
    private var documentCount: Int { project.docsCount ?? 0 }

    private var datasetChanged: Bool { datasetId != project.knowledgeDatasetId }

    private func save(confirmReindex: Bool = false) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }

        var fields: [String: JSONValue] = [
            "name": .string(trimmed),
            "color": .string(color),
        ]
        // Датасет шлём только когда он реально поменялся: лишнее поле в теле
        // заставило бы сервер считать это сменой и требовать подтверждения.
        if datasetChanged {
            fields["knowledge_dataset_id"] = datasetId.map { JSONValue.string($0) } ?? .null
            if confirmReindex { fields["confirm_reindex"] = .bool(true) }
        }

        do {
            _ = try await apiClient.patchProject(id: project.id, fields: fields)
            reindexPrompt = nil
            onSaved()
        } catch APIError.conflict(let message) {
            // 409 — сервер ничего не записал и просит подтверждения; в
            // сообщении уже есть число документов и оценка времени.
            reindexPrompt = message
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? "Не удалось переименовать проект"
        }
    }
}
