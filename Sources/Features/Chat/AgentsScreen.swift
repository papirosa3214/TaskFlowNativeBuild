import SwiftUI

/// «Команда» — плоский список сотрудников-ролей (LOCK-176 → переделан в
/// LOCK-183). Сначала человек, потом его конфигурация: в списке только имя,
/// роль, статус и чем занят; вся машинерия — на экране профиля.
///
/// Данные — `GET /api/roles`. Pi и провайдеры наружу не выносятся.
struct AgentsScreen: View {
    @Environment(SessionStore.self) private var session
    @Environment(TaskStore.self) private var taskStore
    @State private var viewModel = AgentsViewModel()

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

                teamSection
                roleInfoSection
            }
            .padding(.vertical, TFSpacing.lg)
        }
        .background(Color.tfBackground)
        .tfNativeHeader("Команда")
        .task {
            viewModel.configure(currentUser: session.currentUser)
            viewModel.start()
        }
        .onDisappear { viewModel.stop() }
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

    private var teamSection: some View {
        TFCard(padding: 0) {
            VStack(spacing: 0) {
                if viewModel.isLoading && viewModel.profiles.isEmpty {
                    TFLoading(.block)
                }
                ForEach(Array(viewModel.profiles.enumerated()), id: \.element.id) { index, profile in
                    if index > 0 {
                        TFDivider(inset: TFSpacing.lg + 36 + TFSpacing.md)
                    }
                    NavigationLink(value: AppRoute.agentProfile(id: profile.role)) {
                        AgentRow(profile: profile, currentTask: currentTask(for: profile))
                    }
                    .buttonStyle(.plain)
                }
                if !viewModel.isLoading && viewModel.profiles.isEmpty {
                    Text("Сервер не вернул ни одной роли")
                        .tfText(.action)
                        .foregroundStyle(Color.tfDim)
                        .padding(TFSpacing.md)
                }
            }
        }
        .padding(.horizontal, TFSpacing.screenHorizontal)
    }

    /// Текущая задача роли из общего стора — для названия и времени. Ищем по
    /// id из профиля, чтобы не путать с просто назначенными задачами.
    private func currentTask(for profile: RoleProfile) -> ApiTask? {
        guard let id = profile.currentTask?.id else { return nil }
        return taskStore.tasks.first { $0.id == id }
    }

    private var roleInfoSection: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            TFSectionHeader("Роль агента")
            TFCard {
                VStack(alignment: .leading, spacing: TFSpacing.md) {
                    roleInfoRow(color: .tfRed, name: "Владелец", text: "полный доступ ко всем задачам и настройкам")
                    roleInfoRow(color: .tfBlue, name: "Оркестратор", text: "ведёт работу ботов: заводит и правит любые задачи и проекты, назначает исполнителей, но ничего не удаляет")
                    roleInfoRow(color: .tfPurple, name: "Агент", text: "может редактировать назначенные задачи, добавлять комментарии, отмечать выполнение")
                    roleInfoRow(color: .tfDim, name: "Наблюдатель", text: "только просмотр")
                }
            }
        }
        .padding(.horizontal, TFSpacing.screenHorizontal)
    }

    private func roleInfoRow(color: Color, name: String, text: String) -> some View {
        HStack(alignment: .top, spacing: TFSpacing.sm) {
            Text(name)
                .tfText(.meta)
                .foregroundStyle(color)
                .padding(.horizontal, TFSpacing.sm)
                .padding(.vertical, 2)
                .background(color.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: TFRadius.pill))
            Text(text)
                .tfText(.action)
                .foregroundStyle(Color.tfSub)
        }
    }
}
