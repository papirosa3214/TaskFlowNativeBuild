import SwiftUI

/// Сдача этапа в чате (владелец 14.10.2026, по образцу «Тикет 1 сдан…»):
/// отдельный блок в рамке — главное из отчёта роли и вход в полный отчёт.
struct ChatHandoffCard: View {
    let handoff: RoleChatHandoff

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: TFSpacing.sm) {
                Image(systemName: "checkmark.seal")
                    .foregroundStyle(Color.tfSub)
                Text("Сдача" + (handoff.stepTitle.map { " · " + $0 } ?? ""))
                    .tfText(.meta)
                    .foregroundStyle(Color.tfSub)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button { UIPasteboard.general.string = handoff.summary } label: {
                    Image(systemName: "doc.on.doc")
                        .frame(width: TFHitTarget.min, height: TFHitTarget.min)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.tfSub)
                .accessibilityLabel("Скопировать сдачу")
            }
            .padding(.leading, TFSpacing.md)
            Divider()
            RoleReplyMarkdown(text: handoff.summary)
                .equatable()
                .padding(TFSpacing.md)
            Divider()
            NavigationLink(value: AppRoute.noteEditor(noteID: handoff.noteID)) {
                HStack {
                    Text("Полный отчёт")
                        .tfText(.meta)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Color.tfSub)
                .padding(.horizontal, TFSpacing.md)
                .frame(minHeight: TFHitTarget.min)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("chat.handoff.report")
        }
        .background(Color.tfCard, in: RoundedRectangle(cornerRadius: TFRadius.lg))
        .overlay(RoundedRectangle(cornerRadius: TFRadius.lg).strokeBorder(Color.tfStroke, lineWidth: TFBorder.width))
        .accessibilityIdentifier("chat.handoff")
    }
}
