import SwiftUI

/// Только вложенный чат карточки: жест ленты не должен закрывать окно.
/// Общая шторка самой задачи сохраняет прежние жесты.
struct TaskChatSheet: View {
    let chatID: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack { RoleChatRoomLoader(chatID: chatID) }
            .safeAreaInset(edge: .top, spacing: 0) {
                Button { dismiss() } label: {
                    Capsule()
                        .fill(Color.tfDim)
                        .frame(width: 36, height: 5)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Закрыть чат по задаче")
                .accessibilityHint("Потяните вниз за верхний край или нажмите")
                .accessibilityIdentifier("task.chat.dismiss-handle")
                .highPriorityGesture(
                    DragGesture(minimumDistance: 12)
                        .onEnded { value in
                            guard value.translation.height > 45,
                                  value.translation.height > abs(value.translation.width) else { return }
                            dismiss()
                        }
                )
            }
            // Системный pan действует на всё окно, включая начало истории.
            // Его отключаем целиком; закрытие разрешено только ручкой выше.
            .interactiveDismissDisabled()
            .presentationDetents([.large])
            .presentationContentInteraction(.scrolls)
            .presentationDragIndicator(.hidden)
    }
}
