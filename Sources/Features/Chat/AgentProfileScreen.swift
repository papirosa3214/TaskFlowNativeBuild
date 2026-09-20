import SwiftUI

/// Профиль роли (LOCK-183): сначала сотрудник, потом его конфигурация.
/// Открывается тапом по строке «Команды», а не раскрытием тяжёлой карточки.
///
/// Здесь только то, что относится к роли: чем занята, модель,
/// инструкции, инструменты, навыки, права и короткий итог работы. Pi,
/// провайдеры, OAuth и credentials не показываются.
///
/// Визуально это тот же образец, что и «Модели и голоса» — эталон владельца
/// (20.09.2026): карточки `TFCard` со строками `VoiceModelRow` (иконка,
/// заголовок, подпись, значение, точка-статус), разделители `TFDivider`,
/// раскрытие прямо в строке. Своей вёрстки строк здесь нет.
struct AgentProfileScreen: View {
    let roleID: String

    @Environment(TaskStore.self) private var taskStore
    @Environment(SessionStore.self) private var session
    @State private var viewModel = AgentsViewModel()
    @State private var sheetTaskID: String?
    /// Развёрнута ли инструкция роли (тап по строке «Инструкции»).
    @State private var isInstructionsExpanded = false

    private var profile: RoleProfile? { viewModel.profile(for: roleID) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: TFSpacing.lg) {
                TFErrorBanner(viewModel.listErrorMessage.map { _ in "Не удалось загрузить профиль роли" })

                if let profile {
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

    // MARK: - Секции

    @ViewBuilder
    private func sections(_ profile: RoleProfile) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.lg) {
            section(title: "Роль") {
                currentRow(profile)
                rowDivider
                modelRow(profile)
                rowDivider
                instructionsRow(profile)
                if isInstructionsExpanded && !profile.prompt.isEmpty {
                    instructionsBlock(profile.prompt)
                }
            }

            section(title: "Возможности") {
                infoRow(
                    icon: "wrench.and.screwdriver",
                    title: "Инструменты",
                    subtitle: joined(profile.tools, empty: "не заданы")
                )
                rowDivider
                infoRow(
                    icon: "graduationcap",
                    title: "Навыки",
                    subtitle: joined(profile.skills.map(\.name), empty: "не установлены")
                )
                if let permissions = profile.permissions, !permissions.isEmpty {
                    rowDivider
                    infoRow(icon: "lock.shield", title: "Права", subtitle: permissions)
                }
                rowDivider
                infoRow(
                    icon: "clock.arrow.circlepath",
                    title: "Последняя работа",
                    subtitle: lastWorkText(profile)
                )
                if profile.hasProblems {
                    rowDivider
                    infoRow(
                        icon: "exclamationmark.triangle",
                        title: "Проблемы",
                        subtitle: profile.problems.joined(separator: " · ")
                    )
                }
            }
        }
    }

    /// Карточка раздела ровно как в «Моделях и голосах»: caps-заголовок,
    /// `TFCard(padding: 0)` и строки с разделителями.
    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            SettingsCapsLabel(title)
            TFCard(padding: 0) {
                VStack(spacing: 0) { content() }
            }
            .padding(.horizontal, TFSpacing.screenHorizontal)
        }
    }

    private var rowDivider: some View {
        TFDivider(inset: rowDividerInset).padding(.trailing, rowDividerInset)
    }

    private var rowDividerInset: CGFloat { TFSpacing.lg + 32 + TFSpacing.md }

    // MARK: - Строки

    /// Строка «Сейчас»: чем занята роль. Есть задача — тап открывает её.
    @ViewBuilder
    private func currentRow(_ profile: RoleProfile) -> some View {
        let dot = dotState(for: profile.status)
        if let task = profile.currentTask {
            infoRow(
                icon: "bolt",
                title: "Сейчас",
                subtitle: task.title,
                value: taskStateTitle(task.state),
                dot: dot,
                action: { sheetTaskID = task.id }
            )
        } else {
            infoRow(
                icon: "bolt",
                title: "Сейчас",
                subtitle: "Роль свободна",
                value: roleStatusLabel(profile.status),
                dot: dot
            )
        }
    }

    /// Строка «Модель». Меняет только владелец (сервер всё равно вернёт 403).
    /// Меню — только ДОСТУПНЫЕ модели, по провайдеру; выбор применяется сразу.
    ///
    /// РЕЗЕРВНЫЕ МОДЕЛИ УДАЛЕНЫ (20.09.2026) — не по прихоти, а потому что они
    /// НИГДЕ не использовались и ни на что не влияли: эскалацию при сбое делает
    /// глобальная лесенка (`model_ladder` / `nextModelForFailure` в
    /// `agent-state.ts`), а роль-специфичную цепочку primary+fallbacks читала
    /// единственная функция `nextModelForProfile` в `roleRouting.ts`, и она не
    /// вызывается нигде. В запуск Pi уходит только основная модель
    /// (`PiRuntimeAdapter`: `routing.models[role]`). Возвращать — только вместе
    /// с подключением резервных к реальной эскалации (серверная работа).
    @ViewBuilder
    private func modelRow(_ profile: RoleProfile) -> some View {
        let subtitle = "Основная модель роли"
        let value = profile.model ?? "не задана"
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
                VoiceModelRow(icon: "cpu", title: "Модель", subtitle: subtitle, value: value, dot: nil)
            }
            .buttonStyle(.plain)
            .tint(Color.tfSub)
        } else {
            infoRow(icon: "cpu", title: "Модель", subtitle: subtitle, value: value)
        }
    }

    /// Строка «Инструкции». Тап раскрывает ПОЛНЫЙ текст промпта роли — владелец
    /// 20.09.2026: «у агента просто символы и всё, а что там за символы —
    /// непонятно». Текст read-only: источник правды — файл на сервере.
    @ViewBuilder
    private func instructionsRow(_ profile: RoleProfile) -> some View {
        infoRow(
            icon: "text.alignleft",
            title: "Инструкции",
            subtitle: "Системный промпт роли",
            value: profile.prompt.isEmpty ? "не заданы" : "\(profile.prompt.count) символов",
            action: profile.prompt.isEmpty ? nil : {
                withAnimation(.easeInOut(duration: TFDuration.fast)) {
                    isInstructionsExpanded.toggle()
                }
            }
        )
    }

    @ViewBuilder
    private func infoRow(
        icon: String,
        title: String,
        subtitle: String,
        value: String? = nil,
        dot: VoiceDotState? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        let row = VoiceModelRow(icon: icon, title: title, subtitle: subtitle, value: value, dot: dot)
        if let action {
            Button(action: action) { row }.buttonStyle(TFTapRowStyle())
        } else {
            row
        }
    }

    /// Полный текст инструкции роли — читаемый блок под раскрытой строкой.
    @ViewBuilder
    private func instructionsBlock(_ prompt: String) -> some View {
        Text(prompt)
            .tfText(.action)
            .foregroundStyle(Color.tfSub)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, TFSpacing.lg)
            .padding(.bottom, TFSpacing.md)
    }

    // MARK: - Данные строк

    private var canEdit: Bool { viewModel.isOwner }

    private func joined(_ items: [String], empty: String) -> String {
        items.isEmpty ? empty : items.joined(separator: " · ")
    }

    private func dotState(for status: RoleRuntimeStatus) -> VoiceDotState {
        switch status {
        case .ready, .working: .ok
        case .blocked: .warn
        case .unavailable, .unknown: .off
        }
    }

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
}

/// Группа доступных моделей одного провайдера для меню выбора «Модель».
private struct ModelGroup: Identifiable {
    let provider: String
    let models: [RuntimeModel]
    var id: String { provider }
}
