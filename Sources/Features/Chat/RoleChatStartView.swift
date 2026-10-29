import SwiftUI

/// Стартовый экран личного чата с ролью: пока сообщений нет — приветствие
/// роли и четыре быстрые команды (владелец 29.10.2026, макет
/// `mockups/role-chat-start/`).
///
/// Собран из готовых компонентов дизайн-системы: `TFAvatar` (портрет роли),
/// `TFCard` (карточка команды), шкала `tfText` и палитра `tf*`.
struct RoleChatStartView: View {
    /// Роль, с которой чат: её имя и портрет.
    let member: RoleChatMember?
    /// Приветствие и быстрые команды роли.
    let starter: RoleChatStarter
    /// Команда подставляется в поле ввода (владелец может дописать своё).
    let onCommand: (String) -> Void

    private var roleName: String {
        member?.name ?? "Роль"
    }

    private var userID: String? {
        member?.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.lg) {
            header
            sectionLabel
            commands
        }
        .padding(.horizontal, TFSpacing.lg)
        .padding(.vertical, TFSpacing.xl)
        .frame(maxWidth: .infinity)
    }

    /// Приветствие: портрет, имя роли и её фраза.
    private var header: some View {
        VStack(spacing: TFSpacing.sm) {
            TFAvatar(size: .profile,
                     initials: String(roleName.prefix(1)),
                     userID: userID)
            Text(roleName)
                .tfText(.title)
                .foregroundStyle(Color.tfText)
                .multilineTextAlignment(.center)
            Text(starter.greeting)
                .tfText(.body)
                .foregroundStyle(Color.tfSub)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
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

    /// Четыре команды: две колонки, по две строки.
    private var commands: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: TFSpacing.sm),
                            GridItem(.flexible(), spacing: TFSpacing.sm)],
                  spacing: TFSpacing.sm) {
            ForEach(starter.commands) { command in
                Button {
                    onCommand(command.prompt)
                } label: {
                    commandCard(command)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("chat.start.command.\(command.title)")
            }
        }
    }

    private func commandCard(_ command: RoleChatStarterCommand) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.xs) {
            Image(systemName: command.icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.tfText)
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(TFSpacing.md)
        .background(Color.tfCard)
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.xl))
        .overlay {
            RoundedRectangle(cornerRadius: TFRadius.xl)
                .strokeBorder(Color.tfStroke, lineWidth: TFBorder.width)
        }
    }
}
