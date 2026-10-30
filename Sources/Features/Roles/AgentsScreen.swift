import SwiftUI

/// «Команда» — плоский список сотрудников-ролей (LOCK-176 → переделан в
/// LOCK-183, дополнен в LOCK-205).
///
/// Данные — `GET /api/roles?all=1`: владелец видит и отключённые, чтобы
/// было что включить обратно. Список делится на две секции (включённые
/// сверху, отключённые — внизу), Pi и провайдеры наружу не выносятся.
struct AgentsScreen: View {
    @Environment(SessionStore.self) private var session
    @Environment(TaskStore.self) private var taskStore
    @Environment(RealtimeClient.self) private var realtime
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel = AgentsViewModel()
    @State private var showAppearance = false
    @State private var showCommonInstructions = false
    @State private var editorMode: RoleEditorSheet.Mode?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: TFSpacing.lg) {
                TFErrorBanner(viewModel.listErrorMessage.map { _ in "Не удалось загрузить команду" })

                if !viewModel.summaryText.isEmpty {
                    Text(viewModel.summaryText)
                        .tfText(.action)
                        .foregroundStyle(Color.tfSub)
                        .padding(.horizontal, TFSpacing.screenHorizontal)
                }

                if let ready = viewModel.runtimeReady, !ready, !viewModel.profiles.isEmpty {
                    runtimeDownBanner
                }

                if viewModel.isOwner {
                    commonInstructionsEntry
                    runJobsEntry
                    memoryEntry
                }
                enabledSection
                if !viewModel.disabledProfiles.isEmpty {
                    disabledSection
                }
            }
            .padding(.vertical, TFSpacing.lg)
        }
        .background(Color.tfBackground)
        .tfNativeHeader("Команда")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if viewModel.isOwner {
                        Button("Добавить участника", systemImage: "person.badge.plus") {
                            editorMode = .create
                        }
                        .accessibilityIdentifier("team-add-member")
                        Button("Найти агентов", systemImage: "arrow.triangle.2.circlepath") {
                            Task { await viewModel.refreshExternalAgents() }
                        }
                        .accessibilityIdentifier("team-find-agents")
                    }
                    Button("Внешний вид", systemImage: "person.crop.circle") { showAppearance = true }
                        .accessibilityIdentifier("team-appearance-open")
                } label: { Image(systemName: "ellipsis") }
                .accessibilityLabel("Меню команды")
                .accessibilityIdentifier("team-menu")
            }

        }
        .task(id: "\(scenePhase):\(realtime.connectionRevision):\(realtime.rolesRevision)") {
            guard scenePhase == .active else { return }
            viewModel.configure(currentUser: session.currentUser)
            await viewModel.load()
        }
        .sheet(isPresented: $showCommonInstructions) {
            if let role = viewModel.profiles.first {
                RolePromptSettingsSheet(role: role, blockID: "role.system", title: "Общие инструкции агентов")
            }
        }
        .sheet(isPresented: $showAppearance) {
            TeamAppearanceSheet()
        }
        .sheet(item: $editorMode) { mode in
            RoleEditorSheet(mode: mode, viewModel: viewModel)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private var commonInstructionsEntry: some View {
        TFCard(padding: 0) {
            TFListRow(icon: "text.alignleft", iconStyle: .plain,
                      title: "Общие инструкции агентов",
                      action: { showCommonInstructions = true })
                .disabled(viewModel.profiles.isEmpty)
                .accessibilityIdentifier("team.common-instructions")
                .hintAnchor(HintAnchorID.agentInstructions)
        }
        .padding(.horizontal, TFSpacing.screenHorizontal)
    }

    private var runtimeDownBanner: some View {
        HStack(alignment: .top, spacing: TFSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.tfOrange)
            Text("Исполнитель не запущен — роли не начнут работу, пока служба не поднимется.")
                .tfText(.action)
                .foregroundStyle(Color.tfSub)
            Spacer(minLength: 0)
        }
        .padding(TFSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tfCard)
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
        .padding(.horizontal, TFSpacing.screenHorizontal)
    }

    /// Вход в очередь запусков ролей (LOCK-208) — только владельцу: сервер
    /// остальным отвечает `403`. Строка как в «Настройках» (`navRow`).
    private var runJobsEntry: some View {
        TFCard(padding: 0) {
            NavigationLink(value: AppRoute.roleRunJobs) {
                TFListRow(
                    icon: "bolt.horizontal", iconStyle: .plain, title: "Запуски агентов",
                    trailing: AnyView(
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.tfDim)
                    ),
                    titleStyle: .action, verticalPadding: TFSpacing.xs
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, TFSpacing.screenHorizontal)
    }

    /// Вход в память ролей (02.10.2026): что роли запомнили, файлы,
    /// правка и закрепление — только владельцу.
    private var memoryEntry: some View {
        TFCard(padding: 0) {
            NavigationLink(value: AppRoute.memory) {
                TFListRow(
                    icon: "brain", iconStyle: .plain, title: "Память команды",
                    trailing: AnyView(
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.tfDim)
                    ),
                    titleStyle: .action, verticalPadding: TFSpacing.xs
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("memory-entry")
        }
        .padding(.horizontal, TFSpacing.screenHorizontal)
    }

    private var enabledSection: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            TFSectionHeader("В команде")
            teamCard(profiles: viewModel.enabledProfiles)
        }
        .padding(.horizontal, TFSpacing.screenHorizontal)
    }

    private var disabledSection: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            TFSectionHeader("Отключённые")
            teamCard(profiles: viewModel.disabledProfiles, dimmed: true)
        }
        .padding(.horizontal, TFSpacing.screenHorizontal)
    }

    /// Список ролей внутри одной карточки — `dimmed` затемняет строки
    /// отключённых, чтобы отделить их от рабочих без отдельной визуальной
    /// ветки в дизайн-системе.
    private func teamCard(profiles: [RoleProfile], dimmed: Bool = false) -> some View {
        TFCard(padding: 0) {
            VStack(spacing: 0) {
                if viewModel.isLoading && viewModel.profiles.isEmpty {
                    TFLoading(.block)
                }
                ForEach(Array(profiles.enumerated()), id: \.element.id) { index, profile in
                    if index > 0 {
                        TFDivider(inset: TFSpacing.lg + 36 + TFSpacing.md)
                    }
                    row(for: profile, dimmed: dimmed)
                }
                if !viewModel.isLoading && profiles.isEmpty {
                    Text("Нет ролей")
                        .tfText(.action)
                        .foregroundStyle(Color.tfDim)
                        .padding(TFSpacing.md)
                }
            }
        }
    }

    /// Тап открывает лист правки — для всех ролей одинаково. Внутри листа
    /// действия («Сохранить», «Отключить/Включить») есть только у владельца:
    /// сервер отдаёт `403` на «не владелец», и UI не показывает то, что
    /// всё равно упрётся в ошибку.
    @ViewBuilder
    private func row(for profile: RoleProfile, dimmed: Bool) -> some View {
        if viewModel.isOwner {
            Button {
                editorMode = .edit(profile)
            } label: {
                AgentRow(profile: profile, currentTask: currentTask(for: profile))
            }
            .buttonStyle(.plain)
            .opacity(dimmed ? 0.55 : 1)
        } else {
            NavigationLink(value: AppRoute.agentProfile(id: profile.role)) {
                AgentRow(profile: profile, currentTask: currentTask(for: profile))
            }
            .buttonStyle(.plain)
            .opacity(dimmed ? 0.55 : 1)
        }
    }

    /// Текущая задача роли из общего стора — для названия и времени. Ищем по
    /// id из профиля, чтобы не путать с просто назначенными задачами.
    private func currentTask(for profile: RoleProfile) -> ApiTask? {
        guard let id = profile.currentTask?.id else { return nil }
        return taskStore.tasks.first { $0.id == id }
    }

}
