import SwiftUI

/// Личные и групповые чаты живут отдельно от старого окна постановки задач.
struct RoleChatsScreen: View {
    @Environment(SessionStore.self) private var session
    @State private var chats: [RoleChat] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingCreate = false
    private let api = APIClient()

    var body: some View {
        List {
            if isLoading && chats.isEmpty {
                ProgressView("Загрузка чатов")
            } else if chats.isEmpty && errorMessage == nil {
                ContentUnavailableView("Пока нет чатов", systemImage: "bubble.left.and.bubble.right",
                                       description: Text("Создайте чат с одной или несколькими ролями."))
            }
            ForEach(chats) { chat in
                NavigationLink {
                    RoleChatRoomScreen(chat: chat)
                } label: {
                    VStack(alignment: .leading, spacing: TFSpacing.xs) {
                        Text(chat.displayTitle(excluding: session.currentUser?.id))
                            .foregroundStyle(Color.tfText)
                        Text(chat.members.filter { $0.id != session.currentUser?.id }.map(\.name).joined(separator: ", "))
                            .font(.subheadline)
                            .foregroundStyle(Color.tfSub)
                            .lineLimit(1)
                        if let preview = chat.lastMessage {
                            Text(preview.text)
                                .font(.subheadline)
                                .foregroundStyle(Color.tfDim)
                                .lineLimit(1)
                        }
                    }
                    .padding(.vertical, TFSpacing.xs)
                }
            }
        }
        .background(Color.tfBackground)
        .navigationTitle("Чаты")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingCreate = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Создать чат")
            }
        }
        .sheet(isPresented: $showingCreate) {
            CreateRoleChatScreen {
                Task { await load() }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .alert("Не удалось загрузить чаты", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Повторить") { Task { await load() } }
            Button("Закрыть", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do { chats = try await api.roleChats() }
        catch { errorMessage = error.localizedDescription }
    }
}

private struct CreateRoleChatScreen: View {
    @Environment(\.dismiss) private var dismiss
    let onCreated: () -> Void
    @State private var roles: [RoleProfile] = []
    @State private var selectedIDs: Set<String> = []
    @State private var title = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    private let api = APIClient()

    var body: some View {
        NavigationStack {
            Form {
                Section("Название") {
                    TextField("Необязательно", text: $title)
                }
                Section {
                    if roles.isEmpty { ProgressView("Загрузка ролей") }
                    ForEach(roles) { role in
                        Button {
                            guard let id = role.accountID else { return }
                            if !selectedIDs.insert(id).inserted { selectedIDs.remove(id) }
                        } label: {
                            HStack {
                                Text(role.title)
                                    .foregroundStyle(Color.tfText)
                                Spacer()
                                if let id = role.accountID, selectedIDs.contains(id) {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } header: {
                    Text("Роли")
                } footer: {
                    Text("Одна роль — персональный чат, несколько — групповой.")
                }
            }
            .navigationTitle("Новый чат")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Создать") { Task { await create() } }
                        .disabled(selectedIDs.isEmpty || isSaving)
                }
            }
            .task { await loadRoles() }
            .alert("Не удалось создать чат", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("Закрыть", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }

    private func loadRoles() async {
        do {
            // Только роли с учёткой могут быть участниками серверного чата.
            roles = try await api.roles().filter { $0.accountID?.hasPrefix("role_") == true }
        } catch { errorMessage = error.localizedDescription }
    }

    private func create() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let ids = roles.compactMap(\.accountID).filter { selectedIDs.contains($0) }
            _ = try await api.createRoleChat(title: name.isEmpty ? nil : name, memberIDs: ids)
            dismiss()
            onCreated()
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct RoleChatRoomScreen: View {
    @Environment(SessionStore.self) private var session
    @State private var chat: RoleChat
    @State private var messages: [RoleChatMessage] = []
    @State private var draft = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    private let api = APIClient()

    init(chat: RoleChat) { _chat = State(initialValue: chat) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: TFSpacing.md) {
                        if messages.isEmpty {
                            ContentUnavailableView("Пока нет сообщений", systemImage: "bubble.left",
                                                   description: Text("Напишите первое сообщение."))
                        }
                        ForEach(messages) { message in
                            messageRow(message)
                                .id(message.id)
                        }
                    }
                    .padding(TFSpacing.lg)
                }
                .onChange(of: messages.last?.id) { _, id in
                    if let id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
                }
            }
            HStack(spacing: TFSpacing.sm) {
                TextField("Сообщение", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.roundedBorder)
                Button { Task { await send() } } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                .accessibilityLabel("Отправить")
            }
            .padding(TFSpacing.md)
        }
        .background(Color.tfBackground)
        .navigationTitle(chat.displayTitle(excluding: session.currentUser?.id))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Пока у новых чатов нет отдельного WS-клиента: обновляем ленту при открытом экране.
            await refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                if !Task.isCancelled { await refresh() }
            }
        }
        .alert("Ошибка чата", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Повторить") { Task { await refresh() } }
            Button("Закрыть", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func messageRow(_ message: RoleChatMessage) -> some View {
        let mine = message.fromUserID == session.currentUser?.id
        return HStack(alignment: .top, spacing: TFSpacing.sm) {
            if mine { Spacer(minLength: 48) }
            if !mine {
                RoleChatAvatar(message: message)
            }
            VStack(alignment: .leading, spacing: TFSpacing.xs) {
                Text(message.fromUserName ?? "Участник")
                    .font(.caption)
                    .foregroundStyle(Color.tfSub)
                Text(message.text)
                    .foregroundStyle(mine ? .white : Color.tfText)
            }
            .padding(TFSpacing.md)
            .background(mine ? Color.tfRed : Color.tfCard)
            .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
            if !mine { Spacer(minLength: 48) }
        }
    }

    private func refresh() async {
        do {
            async let chatRequest = api.roleChat(id: chat.id)
            async let messagesRequest = api.roleChatMessages(id: chat.id)
            let (updatedChat, updatedMessages) = try await (chatRequest, messagesRequest)
            chat = updatedChat
            if updatedMessages.map(\.id) != messages.map(\.id) { messages = updatedMessages }
        } catch { errorMessage = error.localizedDescription }
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSending = true
        defer { isSending = false }
        do {
            let message = try await api.sendRoleChatMessage(chatID: chat.id, text: text)
            draft = ""
            if !messages.contains(where: { $0.id == message.id }) { messages.append(message) }
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct RoleChatAvatar: View {
    let message: RoleChatMessage

    var body: some View {
        let initials = message.fromUserInitials ?? String((message.fromUserName ?? "?").prefix(1))
        let tint = Color(hex: message.fromUserColor ?? TFHexDefault.unassigned)
        if let path = message.fromUserAvatarURL,
           let url = URL(string: APIClient.baseURL.absoluteString + path) {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    TFAvatar(size: .md, image: image, initials: initials, tint: tint)
                } else {
                    TFAvatar(size: .md, initials: initials, tint: tint)
                }
            }
        } else {
            TFAvatar(size: .md, initials: initials, tint: tint)
        }
    }
}
