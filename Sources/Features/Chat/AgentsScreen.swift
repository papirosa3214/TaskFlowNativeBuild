import SwiftUI

/// «Команда» — `/agents` (SCREENS-2 §4): список людей/агентов, форма
/// выпуска нового агента, справка по ролям. 1:1 `src/screens/AgentsScreen.tsx`.
struct AgentsScreen: View {
    @Environment(SessionStore.self) private var session
    @State private var viewModel = AgentsViewModel()

    @State private var isInviteFormOpen = false
    @State private var newAgentName = ""
    @State private var isKeyCopied = false
    @State private var agentPendingDelete: ApiUser?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: TFSpacing.xl) {
                TFErrorBanner(viewModel.listErrorMessage.map { _ in "Не удалось загрузить список агентов" })

                teamSection
                newAgentSection
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
        .sheet(item: $agentPendingDelete) { agent in
            deleteConfirmSheet(for: agent)
        }
    }

    // MARK: - Команда

    private var teamSection: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            TFSectionHeader("Команда")

            TFErrorBanner(viewModel.deleteErrorMessage.map { _ in "Не удалось удалить агента" }, variant: .block)

            if viewModel.isLoading && viewModel.agents.isEmpty {
                TFLoading(.block)
            }

            TFCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.agents.enumerated()), id: \.element.id) { index, agent in
                        if index > 0 {
                            TFDivider()
                                .padding(.leading, TFSpacing.lg + 40 + TFSpacing.md)
                        }
                        AgentRow(
                            agent: agent,
                            editable: viewModel.isOwner && agent.type == .ai,
                            isExpanded: viewModel.isExpanded(agent.id),
                            viewModel: viewModel,
                            onTapRow: { viewModel.toggleExpand(agent.id) },
                            onRequestDelete: { agentPendingDelete = $0 }
                        )
                    }
                    if !viewModel.isLoading && viewModel.agents.isEmpty {
                        Text("Нет пользователей")
                            .tfText(.action)
                            .foregroundStyle(Color.tfDim)
                            .padding(.horizontal, TFSpacing.lg)
                            .padding(.vertical, TFSpacing.md)
                    }
                }
            }
        }
    }

    // MARK: - Новый агент

    private var newAgentSection: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            TFSectionHeader("Новый агент")

            TFCard(padding: 0) {
                if let issued = viewModel.issuedToken {
                    issuedTokenCard(issued)
                } else if isInviteFormOpen {
                    inviteForm
                } else {
                    Button {
                        isInviteFormOpen = true
                    } label: {
                        HStack(spacing: TFSpacing.md) {
                            Image(systemName: "plus")
                                .font(.system(size: TFIconSize.sm))
                                .foregroundStyle(Color.tfRed)
                            Text("Завести агента")
                                .tfText(.row)
                                .foregroundStyle(Color.tfText)
                        }
                        .padding(.horizontal, TFSpacing.lg)
                        .padding(.vertical, TFSpacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay {
                            RoundedRectangle(cornerRadius: TFRadius.xl)
                                .strokeBorder(Color.tfStroke, style: StrokeStyle(lineWidth: TFBorder.width, dash: [5]))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(TFTapRowStyle())
                }
            }
        }
    }

    private func issuedTokenCard(_ issued: (agentID: String, name: String, token: String)) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            Text("Агент «\(issued.name)» заведён")
                .tfText(.body)
                .foregroundStyle(Color.tfText)
            Text("Ключ показывается один раз — сохраните его сейчас. Потом он нигде не отображается, можно только выпустить новый.")
                .tfText(.meta)
                .foregroundStyle(Color.tfSub)

            Text(issued.token)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.tfText)
                .padding(TFSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.tfCard2)
                .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
                .textSelection(.enabled)

            HStack(spacing: TFSpacing.sm) {
                Button {
                    UIPasteboard.general.string = issued.token
                    isKeyCopied = true
                } label: {
                    Text(isKeyCopied ? "Скопировано" : "Скопировать ключ")
                        .tfText(.row).fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, TFSpacing.lg)
                        .frame(height: 44)
                        .background(Color.tfRedSolid)
                        .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
                }
                .buttonStyle(TFTapScaleStyle())

                Button {
                    viewModel.dismissIssuedToken()
                    isKeyCopied = false
                } label: {
                    Text("Готово")
                        .tfText(.row)
                        .foregroundStyle(Color.tfSub)
                        .padding(.horizontal, TFSpacing.lg)
                        .frame(height: 44)
                        .background(Color.tfCard2)
                        .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
                }
                .buttonStyle(TFTapScaleStyle())
            }
        }
        .padding(TFSpacing.lg)
    }

    private var inviteForm: some View {
        VStack(alignment: .leading, spacing: TFSpacing.md) {
            TFTextField("Имя агента — например, Гермес", text: $newAgentName)
            TFErrorBanner(viewModel.createErrorMessage, variant: .block)
            HStack(spacing: TFSpacing.sm) {
                Button {
                    Task {
                        await viewModel.createAgent(name: newAgentName)
                        if viewModel.issuedToken != nil {
                            newAgentName = ""
                            isInviteFormOpen = false
                        }
                    }
                } label: {
                    Text("Завести")
                        .tfText(.row).fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, TFSpacing.lg)
                        .frame(height: 44)
                        .background(Color.tfRedSolid)
                        .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
                }
                .buttonStyle(TFTapScaleStyle())
                .opacity(newAgentName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
                .disabled(newAgentName.trimmingCharacters(in: .whitespaces).isEmpty)

                Button {
                    isInviteFormOpen = false
                    newAgentName = ""
                } label: {
                    Text("Отмена")
                        .tfText(.row)
                        .foregroundStyle(Color.tfSub)
                        .padding(.horizontal, TFSpacing.lg)
                        .frame(height: 44)
                        .background(Color.tfCard2)
                        .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
                }
                .buttonStyle(TFTapScaleStyle())
            }
        }
        .padding(TFSpacing.lg)
    }

    // MARK: - Роль агента

    // Была цветная иконка (crown/square.and.arrow.up/cpu/eye) перед именем
    // роли — просьба владельца 03.09.2026: «убери аватарки [иконки], сделай
    // такие же бейджи — агент фиолетовый с фиолетовой подложкой» — та же
    // приглушённая плашка (`color.opacity(0.18)`), что и у настоящих ролей
    // в списке выше (`AgentRow.roleBadge`), легенда теперь выглядит как её
    // прямое продолжение, а не отдельным стилем.
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

    // MARK: - Удаление (SCREENS-2 §0.5: свой bottom sheet, БЕЗ drag-to-dismiss)

    private func deleteConfirmSheet(for agent: ApiUser) -> some View {
        TFBottomSheetContent(onClose: { agentPendingDelete = nil }) {
            VStack(alignment: .leading, spacing: TFSpacing.md) {
                HStack(spacing: TFSpacing.sm) {
                    Image(systemName: "trash.fill")
                        .foregroundStyle(Color.tfCoral)
                    Text("Удалить агента «\(agent.name)»?")
                        .tfText(.title)
                        .foregroundStyle(Color.tfText)
                }
                Text("Учётка и ключ доступа удалятся. Если за агентом остались задачи, шаги или комментарии — сервер откажет, их сначала нужно переназначить. Действие нельзя отменить.")
                    .tfText(.action)
                    .foregroundStyle(Color.tfSub)

                TFButton("Удалить", variant: .primary) {
                    Task {
                        await viewModel.deleteAgent(agent)
                        agentPendingDelete = nil
                    }
                }
                TFButton("Отмена", variant: .secondary) {
                    agentPendingDelete = nil
                }
            }
            .padding(.bottom, TFSpacing.xl)
        }
        .interactiveDismissDisabled() // §0.5: подтверждающая шторка не закрывается случайным свайпом
    }
}
