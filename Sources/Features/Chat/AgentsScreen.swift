import SwiftUI

/// «Команда» — список ПРОФИЛЕЙ РОЛЕЙ (LOCK-176, миграция AgentProfile).
///
/// Раньше экран смешивал людей, ИИ-учётки и сервисные личности (`ApiUser`) с
/// их инфраструктурой: API-токены, подключение модели, provider, runtime,
/// MCP, скиллы, права. Теперь исполнитель — роль, и экран показывает восемь
/// ролей с их моделью, текущей задачей и статусом. Pi/runtime наружу не
/// выносится.
///
/// Выпуск сервисных учёток/токенов не удалён — он переехал в
/// Settings → Service Accounts (LOCK-181): там та же механика, но она больше
/// не называется «агентом».
struct AgentsScreen: View {
    @Environment(SessionStore.self) private var session
    @State private var viewModel = AgentsViewModel()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: TFSpacing.xl) {
                TFErrorBanner(viewModel.listErrorMessage.map { _ in "Не удалось загрузить команду" })

                if let ready = viewModel.runtimeReady, !ready, !viewModel.profiles.isEmpty {
                    runtimeDownBanner
                }

                teamSection
                roleInfoSection
            }
            .padding(.horizontal, TFSpacing.lg)
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
    }

    // MARK: - Команда

    private var teamSection: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            TFSectionHeader("Команда")

            if viewModel.isLoading && viewModel.profiles.isEmpty {
                TFLoading(.block)
            }

            TFCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.profiles.enumerated()), id: \.element.id) { index, profile in
                        if index > 0 {
                            TFDivider()
                                .padding(.leading, TFSpacing.lg + 36 + TFSpacing.md)
                        }
                        AgentRow(
                            profile: profile,
                            editable: canEdit(profile),
                            isExpanded: viewModel.isExpanded(profile.role),
                            viewModel: viewModel,
                            onTapRow: { viewModel.toggleExpand(profile.role) }
                        )
                    }
                    if !viewModel.isLoading && viewModel.profiles.isEmpty {
                        Text("Сервер не вернул ни одной роли")
                            .tfText(.action)
                            .foregroundStyle(Color.tfDim)
                            .padding(.horizontal, TFSpacing.lg)
                            .padding(.vertical, TFSpacing.md)
                    }
                }
            }
        }
    }

    /// Менять модель роли можно владельцу и только при живом исполнителе.
    private func canEdit(_ profile: RoleProfile) -> Bool {
        viewModel.isOwner && profile.runtimeReady && profile.status != .unavailable
    }

    // MARK: - Роль агента

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
