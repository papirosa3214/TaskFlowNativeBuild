import SwiftUI

/// Профиль роли (LOCK-183): сначала сотрудник, потом его конфигурация.
/// Открывается тапом по строке «Команды», а не раскрытием тяжёлой карточки.
///
/// Здесь только то, что относится к роли: чем занята, модель,
/// инструкции, инструменты, навыки, права и короткий итог работы. Pi,
/// провайдеры, OAuth и credentials не показываются.
struct AgentProfileScreen: View {
    let roleID: String

    @Environment(TaskStore.self) private var taskStore
    @Environment(SessionStore.self) private var session
    @State private var viewModel = AgentsViewModel()
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
            await viewModel.loadModelsIfNeeded()
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

            modelMenuRow(profile)

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

    /// Строка «Модель» с системным меню выбора. Показываем только ДОСТУПНЫЕ
    /// модели (провайдер авторизован — ключ есть и жив), сгруппированные по
    /// провайдеру: каталог Pi отдаёт 1000+ моделей всех провайдеров, включая
    /// недоступные, — весь этот список показывать нельзя (владелец 20.09.2026).
    /// Выбор применяется сразу.
    ///
    /// РЕЗЕРВНЫЕ МОДЕЛИ УДАЛЕНЫ (20.09.2026) — не по прихоти, а потому что они
    /// НИГДЕ не использовались и ни на что не влияли: эскалацию при сбое делает
    /// глобальная лесенка (`model_ladder` / `nextModelForFailure` в
    /// `agent-state.ts`), а роль-специфичную цепочку primary+fallbacks читала
    /// единственная функция `nextModelForProfile` в `roleRouting.ts`, и она не
    /// вызывается нигде. В запуск Pi уходит только основная модель
    /// (`PiRuntimeAdapter`: `routing.models[role]`). То есть ручка «резервная»
    /// была пустой. Убраны и «Резервные модели» из карточки, и шторка-редактор
    /// `RoleModelEditorSheet`. Возвращать — только вместе с подключением
    /// резервных к реальной эскалации (серверная работа), иначе это самообман.
    @ViewBuilder
    private func modelMenuRow(_ profile: RoleProfile) -> some View {
        if canEdit {
            Menu {
                ForEach(modelProviderGroups) { group in
                    Section(modelProviderTitle(group.provider)) {
                        ForEach(group.models) { model in
                            Button {
                                setModel(model.id, role: profile.role)
                            } label: {
                                if model.id == profile.model {
                                    Label(model.displayName, systemImage: "checkmark")
                                } else {
                                    Text(model.displayName)
                                }
                            }
                        }
                    }
                }
            } label: {
                rowContent(
                    title: "Модель",
                    value: profile.model ?? "не задана",
                    detail: nil,
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
            .tint(Color.tfSub)
        } else {
            valueRow(title: "Модель", value: profile.model ?? "не задана", detail: nil)
        }
    }

    private func setModel(_ id: String, role: String) {
        Task {
            _ = await viewModel.updateModelPolicy(role: role, primary: id)
        }
    }

    /// Доступные модели, сгруппированные по провайдеру (порядок — как в каталоге).
    private var modelProviderGroups: [ModelGroup] {
        var order: [String] = []
        var byProvider: [String: [RuntimeModel]] = [:]
        for model in viewModel.models where model.available {
            if byProvider[model.provider] == nil { order.append(model.provider) }
            if byProvider[model.provider, default: []].contains(where: { $0.id == model.id }) {
                continue
            }
            byProvider[model.provider, default: []].append(model)
        }
        return order.map { ModelGroup(provider: $0, models: byProvider[$0] ?? []) }
    }

    /// Человеческие подписи провайдеров; неизвестный — как есть.
    private func modelProviderTitle(_ provider: String) -> String {
        switch provider {
        case "anthropic": return "Anthropic"
        case "openai", "openai-codex": return "OpenAI"
        case "minimax", "minimax-cn": return "MiniMax"
        case "opencode": return "OpenCode"
        case "opencode-go": return "OpenCode Go"
        case "google", "google-vertex": return "Google"
        case "ollama": return "Ollama (на сервере)"
        default: return provider
        }
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

/// Группа доступных моделей одного провайдера для меню выбора «Модель».
private struct ModelGroup: Identifiable {
    let provider: String
    let models: [RuntimeModel]
    var id: String { provider }
}
