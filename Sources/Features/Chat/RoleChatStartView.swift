import SwiftUI

/// Стартовый экран личного чата с ролью: пока сообщений нет — портрет роли,
/// её описание, четыре быстрые команды (владелец 29.10.2026, макет
/// `mockups/role-chat-start/`).
///
/// Собран из готовых компонентов дизайн-системы: `TFAvatar` (портрет роли),
/// шкала `tfText` и палитра `tf*`.
struct RoleChatStartView: View {
    /// Роль, с которой чат: её имя и портрет.
    let member: RoleChatMember?
    /// Приветствие и быстрые команды роли.
    let starter: RoleChatStarter
    /// Чем роль занимается — из реестра ролей (описание роли на сервере).
    let roleSummary: String?
    /// Команда подставляется в поле ввода (владелец может дописать своё).
    let onCommand: (String) -> Void

    private var roleName: String {
        member?.name ?? "Роль"
    }

    private var userID: String? {
        member?.id
    }

    var body: some View {
        VStack(spacing: TFSpacing.xl) {
            header
            commands
        }
        .padding(.horizontal, TFSpacing.lg)
        .padding(.top, TFSpacing.lg)
        .padding(.bottom, TFSpacing.xl)
        .frame(maxWidth: .infinity)
    }

    /// Портрет роли, её имя, чем она занимается и приветствие.
    private var header: some View {
        VStack(spacing: TFSpacing.md) {
            TFAvatar(size: .chatHero,
                     initials: String(roleName.prefix(1)),
                     userID: userID)
            Text(roleName)
                .tfText(.titleLarge)
                .foregroundStyle(Color.tfText)
                .multilineTextAlignment(.center)
            if let roleSummary, !roleSummary.isEmpty {
                Text(roleSummary)
                    .tfText(.body)
                    .foregroundStyle(Color.tfSub)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(starter.greeting)
                .tfText(.body)
                .foregroundStyle(Color.tfText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    /// Четыре быстрые команды в две колонки. Карточки одинаковой высоты —
    /// иначе сетка выглядит неровной (владелец 29.10.2026: «несимметричные,
    /// неравнозначные и неравноразмерные»).
    private var commands: some View {
        VStack(spacing: TFSpacing.sm) {
            sectionLabel
            LazyVGrid(columns: [GridItem(.flexible(), spacing: TFSpacing.sm),
                                GridItem(.flexible(), spacing: TFSpacing.sm)],
                      spacing: TFSpacing.sm) {
                ForEach(starter.commands) { command in
                    commandCard(command)
                }
            }
        }
    }

    private var sectionLabel: some View {
        HStack(spacing: TFSpacing.sm) {
            Text("Быстрые команды")
                .tfText(.meta)
                .foregroundStyle(Color.tfDim)
            Rectangle()
                .fill(Color.tfStroke)
                .frame(height: 1)
        }
    }

    private func commandCard(_ command: RoleChatStarterCommand) -> some View {
        Button {
            onCommand(command.prompt)
        } label: {
            VStack(alignment: .leading, spacing: TFSpacing.sm) {
                Image(systemName: command.icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.tfText)
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(command.title)
                    .tfText(.body)
                    .foregroundStyle(Color.tfText)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(command.hint)
                    .tfText(.caption)
                    .foregroundStyle(Color.tfDim)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .padding(TFSpacing.md)
            .background(Color.tfCard)
            .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
            .overlay {
                RoundedRectangle(cornerRadius: TFRadius.lg)
                    .strokeBorder(Color.tfStroke, lineWidth: TFBorder.width)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("chat.start.command.\(command.title)")
    }
}
