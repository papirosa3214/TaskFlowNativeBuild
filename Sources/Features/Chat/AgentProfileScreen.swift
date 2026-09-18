import SwiftUI

/// Профиль роли (LOCK-183): сначала сотрудник, потом его конфигурация.
/// Открывается тапом по строке «Команды», а не раскрытием тяжёлой карточки.
///
/// Здесь только то, что относится к роли: чем занята, модель и резерв,
/// инструкции, инструменты, навыки, права и короткий итог работы. Pi,
/// провайдеры, OAuth и credentials не показываются.
struct AgentProfileScreen: View {
    let roleID: String

    @Environment(TaskStore.self) private var taskStore
    @Environment(SessionStore.self) private var session
    @State private var viewModel = AgentsViewModel()
    @State private var isEditingModel = false
    @State private var sheetTaskID: String?

    private var profile: RoleProfile? { viewModel.profile(for: roleID) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: TFSpacing.lg) {
                TFErrorBanner(viewModel.listErrorMessage.map { _ in "Не удалось загрузить профиль роли" })

                if let profile {
                    header(profile)
                    sections(profile)
                } else if viewModel.isLoading {
                    TFLoading(.block)
                }
            }
            .padding(.vertical, TFSpacing.lg)
        }
        .background(Color.tfBackground)
        .tfNativeHeader(profile?.title ?? "Профиль")
        .task {
            viewModel.configure(currentUser: session.currentUser)
            await viewModel.load()
        }
        .sheet(isPresented: $isEditingModel) {
            if let profile {
                RoleModelEditorSheet(profile: profile, viewModel: viewModel)
            }
        }
        .sheet(item: Binding(
            get: { sheetTaskID.map(TaskRef.init) },
            set: { sheetTaskID = $0?.id }
        )) { ref in
            NavigationStack { TaskFormScreen(taskID: ref.id) }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private struct TaskRef: Identifiable { let id: String }

    // MARK: - Шапка профиля

    private func header(_ profile: RoleProfile) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.md) {
            HStack(spacing: TFSpacing.md) {
                RoleAvatarView(initials: initials(profile.title), tint: roleAccentColor(profile.role), size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.title)
                        .tfText(.title)
                        .foregroundStyle(Color.tfText)
                    Text(roleSubtitle(profile.role))
                        .tfText(.meta)
                        .foregroundStyle(Color.tfDim)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                Circle()
                    .fill(roleStatusColor(profile.status))
                    .frame(width: 8, height: 8)
                Text(roleStatusLabel(profile.status))
                    .tfText(.action)
                    .foregroundStyle(Color.tfSub)
            }
        }
        .padding(.horizontal, TFSpacing.screenHorizontal)
    }

    private func initials(_ title: String) -> String {
        let parts = title.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    // MARK: - Секции

    @ViewBuilder
    private func sections(_ profile: RoleProfile) -> some View {
        VStack(spacing: 0) {
            if let task = profile.currentTask {
                actionRow(
                    title: "Сейчас",
                    value: task.title,
                    detail: taskStateTitle(task.state),
                    action: { sheetTaskID = task.id }
                )
            } else {
                valueRow(title: "Сейчас", value: "Свободен", detail: nil)
            }

            TFDivider(inset: TFSpacing.lg)

            actionRow(
                title: "Модель",
                value: profile.model ?? "не задана",
                detail: nil,
                action: canEdit ? { isEditingModel = true } : nil
            )

            if !profile.fallbacks.isEmpty {
                TFDivider(inset: TFSpacing.lg)
                fallbacksBlock(profile.fallbacks)
            }

            TFDivider(inset: TFSpacing.lg)
            valueRow(
                title: "Инструкции",
                value: profile.prompt.isEmpty ? "не заданы" : "\(profile.prompt.count) символов",
                detail: nil
            )

            TFDivider(inset: TFSpacing.lg)
            listBlock(title: "Инструменты", items: profile.tools, empty: "не заданы")

            TFDivider(inset: TFSpacing.lg)
            listBlock(title: "Навыки", items: profile.skills.map(\.name), empty: "не установлены")

            if let permissions = profile.permissions, !permissions.isEmpty {
                TFDivider(inset: TFSpacing.lg)
                valueRow(title: "Права", value: permissions, detail: nil)
            }

            TFDivider(inset: TFSpacing.lg)
            valueRow(title: "Последняя работа", value: lastWorkText(profile), detail: nil)

            if profile.hasProblems {
                TFDivider(inset: TFSpacing.lg)
                listBlock(title: "Проблемы", items: profile.problems, empty: "—")
            }
        }
        .background(Color.tfCard)
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
        .padding(.horizontal, TFSpacing.screenHorizontal)
    }

    /// Модель меняет только владелец; сервер всё равно вернёт 403, но
    /// не показывать лишнюю ручку — честнее.
    private var canEdit: Bool { viewModel.isOwner }

    private func taskStateTitle(_ state: String?) -> String? {
        switch state {
        case "in_progress": "в работе"
        case "blocked": "заблокирована"
        case "review": "на проверке"
        default: nil
        }
    }

    /// «12 задач · 10 завершено» — по задачам, где исполнитель = учётка роли.
    /// Считаем на клиенте из общего стора (отдельного поля сервер не отдаёт).
    private func lastWorkText(_ profile: RoleProfile) -> String {
        guard let accountID = profile.accountID else { return "нет данных" }
        let tasks = taskStore.tasks.filter { $0.assigneeId == accountID }
        guard !tasks.isEmpty else { return "пока ничего" }
        let completed = tasks.count { $0.status == .completed }
        return "\(tasks.count) \(Self.plural(tasks.count, "задача", "задачи", "задач")) · \(completed) завершено"
    }

    private static func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let mod100 = n % 100
        if mod100 >= 11 && mod100 <= 14 { return many }
        switch n % 10 {
        case 1: return one
        case 2, 3, 4: return few
        default: return many
        }
    }

    // MARK: - Строители строк

    @ViewBuilder
    private func actionRow(title: String, value: String, detail: String?, action: (() -> Void)?) -> some View {
        let content = rowContent(title: title, value: value, detail: detail, showsChevron: action != nil)
        if let action {
            Button(action: action) { content }.buttonStyle(.plain)
        } else {
            content
        }
    }

    @ViewBuilder
    private func valueRow(title: String, value: String, detail: String?) -> some View {
        rowContent(title: title, value: value, detail: detail, showsChevron: false)
    }

    private func rowContent(title: String, value: String, detail: String?, showsChevron: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: TFSpacing.md) {
            Text(title)
                .tfText(.action)
                .foregroundStyle(Color.tfSub)
            Spacer(minLength: TFSpacing.sm)
            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .tfText(.body)
                    .foregroundStyle(Color.tfText)
                    .multilineTextAlignment(.trailing)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .tfText(.caption)
                        .foregroundStyle(Color.tfDim)
                }
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.tfDim)
            }
        }
        .padding(.horizontal, TFSpacing.lg)
        .frame(minHeight: TFField.height)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func fallbacksBlock(_ fallbacks: [String]) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.xs) {
            Text("Резервные модели")
                .tfText(.meta)
                .foregroundStyle(Color.tfDim)
            ForEach(Array(fallbacks.enumerated()), id: \.offset) { index, model in
                Text("\(index + 1). \(model)")
                    .tfText(.body)
                    .foregroundStyle(Color.tfText)
            }
        }
        .padding(.horizontal, TFSpacing.lg)
        .padding(.vertical, TFSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func listBlock(title: String, items: [String], empty: String) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.xs) {
            Text(title)
                .tfText(.meta)
                .foregroundStyle(Color.tfDim)
            if items.isEmpty {
                Text(empty)
                    .tfText(.action)
                    .foregroundStyle(Color.tfDim)
            } else {
                Text(items.joined(separator: " · "))
                    .tfText(.action)
                    .foregroundStyle(Color.tfText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, TFSpacing.lg)
        .padding(.vertical, TFSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Редактор модели роли

/// Primary + упорядоченные fallback. Порядок fallback'ов — порядок
/// эскалации, поэтому список перемещаемый, а не сортируемый.
private struct RoleModelEditorSheet: View {
    let profile: RoleProfile
    let viewModel: AgentsViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var primary: String = ""
    @State private var fallbacks: [String] = []
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            List {
                if viewModel.modelsLoading {
                    HStack { ProgressView(); Text("Загружаем модели…").foregroundStyle(.secondary) }
                }
                if let msg = viewModel.modelsErrorMessage {
                    Text(msg).foregroundStyle(Color.tfRed)
                }

                Section {
                    Picker("Основная", selection: $primary) {
                        ForEach(primaryChoices, id: \.self) { id in
                            Text(label(for: id)).tag(id)
                        }
                    }
                } header: {
                    Text("Primary")
                } footer: {
                    Text("Модель, с которой роль начинает работу.")
                }

                Section {
                    ForEach(fallbacks, id: \.self) { id in
                        Text(label(for: id))
                    }
                    .onMove { from, to in fallbacks.move(fromOffsets: from, toOffset: to) }
                    .onDelete { offsets in fallbacks.remove(atOffsets: offsets) }

                    Menu {
                        ForEach(addableChoices, id: \.self) { id in
                            Button(label(for: id)) { fallbacks.append(id) }
                        }
                    } label: {
                        Label("Добавить fallback", systemImage: "plus.circle")
                    }
                    .disabled(addableChoices.isEmpty)
                } header: {
                    Text("Fallback")
                } footer: {
                    Text("Порядок — порядок эскалации: если primary не справился, роль переходит к следующей сверху вниз.")
                }
            }
            .navigationTitle("Модель роли")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        isSaving = true
                        Task {
                            let ok = await viewModel.updateModelPolicy(
                                role: profile.role, primary: primary, fallbacks: fallbacks
                            )
                            isSaving = false
                            if ok { dismiss() }
                        }
                    }
                    .disabled(isSaving || primary.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            await viewModel.loadModelsIfNeeded()
            primary = profile.model ?? primaryChoices.first ?? ""
            fallbacks = profile.fallbacks
        }
    }

    private var primaryChoices: [String] {
        var ids = orderedModelIDs
        if let current = profile.model, !current.isEmpty, !ids.contains(current) {
            ids.insert(current, at: 0)
        }
        return ids
    }

    private var addableChoices: [String] {
        orderedModelIDs.filter { $0 != primary && !fallbacks.contains($0) }
    }

    private var orderedModelIDs: [String] {
        var seen = Set<String>()
        return viewModel.models.compactMap { model in
            seen.insert(model.id).inserted ? model.id : nil
        }
    }

    private func label(for id: String) -> String {
        viewModel.models.first { $0.id == id }.map { model in
            model.displayName == model.id ? id : "\(model.displayName) · \(id)"
        } ?? id
    }
}
