import SwiftUI

/// Комната роли из панели «Комнаты» (владелец 21.10.2026): личный чат
/// владельца с ролью и её лички с коллегами. Отсюда видно, что пришло роли
/// от другой роли и что она ответила; лички открываются только на чтение.
/// «Новый чат» (владелец 26.10.2026) заводит с ролью отдельную сессию: сервер
/// назовёт её по первому сообщению, и она ляжет строкой в список чатов.
struct RoleRoomSheet: View {
    let role: ChatRoomsSnapshot.RoleRoom
    let snapshot: ChatRoomsSnapshot
    let onOpen: (String) -> Void
    let onNewChat: () -> Void

    @Environment(\.dismiss) private var dismiss
    private let avatar: TFAvatar.Size = .taskList

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    Button {
                        dismiss()
                        onNewChat()
                    } label: {
                        ChatListRow(avatar: AnyView(RoleMemberAvatar(member: role.member, size: avatar)),
                                    title: "Новый чат",
                                    preview: "Название появится по первому сообщению",
                                    time: nil, unread: 0)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("chats.room.newChat")
                    if let personal = role.personalChatID {
                        row(chatID: personal,
                            avatar: AnyView(RoleMemberAvatar(member: role.member, size: avatar)),
                            title: "Личная комната",
                            preview: role.lastMessage?.text ?? "",
                            time: role.lastMessage?.createdAt,
                            turn: role.personalTurn)
                    }
                    if !role.dms.isEmpty {
                        Text("Переписка с коллегами")
                            .tfText(.meta)
                            .foregroundStyle(Color.tfDim)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, TFSpacing.screenHorizontal)
                            .padding(.top, TFSpacing.lg)
                            .padding(.bottom, TFSpacing.xs)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(role.dms) { dm in
                            let peer = snapshot.role(dm.peerID)
                            row(chatID: dm.chatID,
                                avatar: AnyView(peerAvatar(peer, live: dm.live, pair: dm.pair)),
                                title: peer?.name ?? "Роль",
                                preview: preview(dm.lastMessage),
                                time: dm.lastMessage?.createdAt,
                                turn: dm.turn)
                        }
                    }
                }
                .padding(.bottom, TFSpacing.xl)
            }
            // Своей заливки нет: шторку рисует система (26.10.2026, владелец:
            // серая заливка сливалась с фоном и портила нативный вид).
            .navigationTitle(role.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(chatID: String, avatar: AnyView, title: String, preview: String, time: String?, turn: RoomTurn?) -> some View {
        Button {
            dismiss()
            onOpen(chatID)
        } label: {
            ChatListRow(avatar: avatar, title: title, preview: preview, time: ChatListTime.label(time), unread: 0, turn: turn)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("chats.room.\(chatID)")
    }

    private func peerAvatar(_ peer: ChatRoomsSnapshot.RoleRoom?, live: Bool, pair: String) -> some View {
        Group {
            if let peer {
                RoleMemberAvatar(member: peer.member, size: avatar)
            } else {
                TFAvatar(size: avatar, initials: "?", tint: Color(hex: TFHexDefault.unassigned))
            }
        }
        .overlay(alignment: .topTrailing) {
            if live { RoomLinkBadge(colors: [RoomLinkPalette.color(for: pair)], side: avatar.rawValue) }
        }
    }

    /// Чьё последнее сообщение — видно по имени: в личке ролей «Вы» не бывает.
    private func preview(_ message: ChatRoomsSnapshot.RoomMessage?) -> String {
        guard let message else { return "" }
        let author = message.fromUserID == role.id ? role.name : snapshot.role(message.fromUserID)?.name
        return author.map { "\($0): \(message.text)" } ?? message.text
    }
}
