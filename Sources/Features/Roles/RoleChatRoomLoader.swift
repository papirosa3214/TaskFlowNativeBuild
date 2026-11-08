import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import PhotosUI
import UIKit
import QuickLook

/// Ссылочная коробка вокруг коалесцера событий: её изменения не поднимают
/// перерисовку экрана, в отличие от прямой записи в `@State`.
@MainActor
final class ChatEventBatchBox {
    private var coalescer = ChatEventCoalescer<RealtimeEvent>()
    func enqueue(_ event: RealtimeEvent) -> Bool { coalescer.enqueue(event) }
    func drain() -> [RealtimeEvent] { coalescer.drain() }
}

/// Комната чата по идентификатору — адресат маршрута `AppRoute.roleChat`.
/// Список отдаёт только id: маршрут обязан быть `Hashable` и не тащить
/// состав чата с собой.
struct RoleChatRoomLoader: View {
    let chatID: String
    @State private var chat: RoleChat?
    @State private var failed = false
    private let api = APIClient()

    var body: some View {
        Group {
            if let chat {
                // Комната открывается обычным разговором: у комнаты задачи
                // внутренних топиков нет, а проектного чата не существует
                // (спецификация 08.11.2026, §3).
                RoleChatRoomScreen(chat: chat)
            } else if failed {
                TFEmptyState(
                    icon: "bubble.left",
                    text: "Чат не открылся",
                    description: "Проверьте связь и зайдите ещё раз.",
                    actionTitle: "Повторить",
                    action: { failed = false; Task { await load() } }
                )
            } else {
                TFLoading(.block)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tfScreenBackground()
        .task { await load() }
    }

    /// Чат из локальной базы открывается сразу и без сети: экран чата сам
    /// перечитывает его с сервера. Сеть нужна, только если чата в базе нет
    /// (владелец 06.11.2026: «Чат не открылся» при пропавшей связи, хотя
    /// переписка уже лежала на телефоне).
    private func load() async {
        if let local = try? LocalStore.shared.chats().first(where: { $0.id == chatID }) {
            chat = local
            return
        }
        do { chat = try await api.roleChat(id: chatID) }
        catch { failed = true }
    }
}

extension View {
    /// Пока открыта клавиатура, содержимое под этим щитом не реагирует: тап или
    /// свайп только прячут клавиатуру (владелец 05.11.2026).
    @ViewBuilder func keyboardDismissShield(isActive: Bool, dismiss: @escaping () -> Void) -> some View {
        overlay {
            if isActive {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onEnded { _ in dismiss() })
                    .accessibilityHidden(true)
            }
        }
    }
}
