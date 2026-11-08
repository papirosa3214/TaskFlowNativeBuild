import SwiftUI

/// «Чаты → Архив» — отдельный экран, как в GPT
/// (владелец 08.11.2026: «архивировать, чтобы если что, потом когда-нибудь
/// вернуть, либо удалить насовсем — понятно, максимально»).
///
/// Здесь лежат только убранные чаты: возврат снимает и уборку, и закрытие,
/// удаление стирает переписку, вложения, очередь и вопросы насовсем.
struct ChatArchiveScreen: View {
    @Environment(\.openRoute) private var openRoute
    @State private var chats: [RoleChat] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var pendingPurge: RoleChat?
    private let api = APIClient()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                TFErrorBanner(errorMessage, variant: .inline)
                if isLoading {
                    TFLoading(.inline)
                } else if chats.isEmpty {
                    TFEmptyState(icon: "archivebox", text: "В архиве пусто")
                        .padding(.horizontal, TFSpacing.screenHorizontal)
                        .padding(.top, TFSpacing.xl)
                } else {
                    ForEach(chats) { chat in
                        row(chat)
                        TFDivider(inset: TFSpacing.screenHorizontal)
                    }
                }
            }
            .padding(.bottom, TFSpacing.xl)
        }
        .tfScreenBackground()
        .tfNativeHeader("Архив")
        .task { await load() }
        .refreshable { await load() }
        .confirmationDialog("Удалить чат навсегда?", isPresented: Binding(
            get: { pendingPurge != nil },
            set: { if !$0 { pendingPurge = nil } }
        ), titleVisibility: .visible) {
            Button("Удалить навсегда", role: .destructive) {
                if let chat = pendingPurge { Task { await purge(chat) } }
            }
            Button("Отмена", role: .cancel) { pendingPurge = nil }
        } message: {
            Text("Переписка и вложения пропадут насовсем — вернуть их будет нельзя.")
        }
    }

    private func row(_ chat: RoleChat) -> some View {
        Button { openRoute?(.roleChat(id: chat.id)) } label: {
            TFListRow(
                icon: "bubble.left.and.bubble.right",
                iconStyle: .plain,
                title: chat.title ?? (chat.kind == "direct" ? "Личная переписка" : "Групповой чат"),
                subtitle: subtitle(chat),
                trailing: AnyView(
                    Text(ChatListTime.label(chat.lastMessage?.createdAt) ?? "")
                        .tfText(.meta)
                        .foregroundStyle(Color.tfSub)
                ),
                titleStyle: .body,
                verticalPadding: TFSpacing.xs,
                chevron: .shown
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { Task { await restore(chat) } } label: {
                Label("Вернуть из архива", systemImage: "tray.and.arrow.up")
            }
            .accessibilityIdentifier("archive.restore")
            Button(role: .destructive) { pendingPurge = chat } label: {
                Label("Удалить навсегда", systemImage: "trash")
            }
            .accessibilityIdentifier("archive.purge")
        }
        .accessibilityIdentifier("archive.row.\(chat.id)")
    }

    private func subtitle(_ chat: RoleChat) -> String {
        if let project = chat.projectName, !project.isEmpty {
            return project + " · в архиве"
        }
        return "В архиве"
    }

    private func load() async {
        isLoading = chats.isEmpty
        do {
            let all = try await api.roleChats(includeClosed: true)
            chats = all.filter(\.isArchived)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func restore(_ chat: RoleChat) async {
        do {
            _ = try await api.unarchiveRoleChat(id: chat.id)
            try? LocalStore.shared.showChat(id: chat.id)
            await load()
        } catch { errorMessage = error.localizedDescription }
    }

    private func purge(_ chat: RoleChat) async {
        pendingPurge = nil
        do {
            try await api.purgeRoleChat(id: chat.id)
            try? LocalStore.shared.hideChat(id: chat.id)
            await load()
        } catch { errorMessage = error.localizedDescription }
    }
}
