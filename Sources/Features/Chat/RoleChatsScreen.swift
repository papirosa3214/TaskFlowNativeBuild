import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

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
    @State private var voice = RoleChatVoiceController()
    @State private var isFileImporterPresented = false
    @State private var pendingAttachments: [ApiChatAttachment] = []
    @State private var isUploadingAttachment = false
    @State private var player = VoicePlayer()
    @State private var pendingVoices: [VoiceMessage] = []
    @State private var uploadedVoiceIDs: [UUID: String] = [:]
    @State private var sendingVoiceIDs: Set<UUID> = []
    @State private var isDrafting = false
    @State private var assembledTaskID: String?
    @State private var draftStatusText: String?
    private let api = APIClient()

    init(chat: RoleChat) { _chat = State(initialValue: chat) }

    var body: some View {
        VStack(spacing: 0) {
            if let draftStatusText {
                Text(draftStatusText)
                    .font(.footnote)
                    .foregroundStyle(Color.tfSub)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, TFSpacing.md)
            }
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
                        ForEach(pendingVoices) { message in
                            VStack(alignment: .trailing, spacing: 4) {
                                VoiceMessageBubble(message: message, player: player)
                                if sendingVoiceIDs.contains(message.id) { ProgressView("Отправка…") }
                                else if message.transcript != .pending {
                                    Button("Повторить отправку") { Task { await sendVoice(message.id) } }
                                        .font(.caption)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .id(message.id)
                        }
                    }
                    .padding(TFSpacing.lg)
                }
                .onChange(of: messages.last?.id) { _, id in
                    if let id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
                }
            }
            if !pendingAttachments.isEmpty {
                HStack {
                    ForEach(pendingAttachments) { attachment in
                        Label(attachment.fileName, systemImage: "paperclip")
                            .lineLimit(1)
                        Button { pendingAttachments.removeAll { $0.id == attachment.id } } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel("Убрать вложение")
                    }
                }
                .padding(.horizontal, TFSpacing.lg)
            }
            ChatVoiceComposer(
                text: $draft,
                placeholder: "Сообщение",
                canSendText: (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingAttachments.isEmpty)
                    && !isSending && !isUploadingAttachment,
                voice: voice,
                onAttachment: { isFileImporterPresented = true },
                onSendText: { Task { await send() } },
                onSendVoice: sendVoicePreview,
                onDiscardVoice: { _ in }
            )
        }
        .background(Color.tfBackground)
        .navigationTitle(chat.displayTitle(excluding: session.currentUser?.id))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Собрать задачу") { Task { await assembleTask() } }
                    .disabled(isDrafting)
            }
        }
        .safeAreaInset(edge: .top) {
            if let taskID = chat.taskID ?? assembledTaskID {
                NavigationLink {
                    TaskFormScreen(taskID: taskID)
                } label: {
                    Label("Задача чата", systemImage: "checklist")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(TFSpacing.md)
                }
                .background(Color.tfCard)
            }
        }
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
        .fileImporter(isPresented: $isFileImporterPresented, allowedContentTypes: [.item]) { result in
            handleFileImport(result)
        }
        .onChange(of: voice.errorMessage) { _, reason in
            if let reason { errorMessage = reason }
        }
        .onDisappear { voice.cancel(); player.stop() }
    }

    private func messageRow(_ message: RoleChatMessage) -> some View {
        let mine = message.fromUserID == session.currentUser?.id
        let hasAudio = message.attachments?.contains { $0.isVoiceRecording } ?? false
        return HStack(alignment: .top, spacing: TFSpacing.sm) {
            if mine { Spacer(minLength: 48) }
            if !mine {
                RoleChatAvatar(message: message)
            }
            VStack(alignment: .leading, spacing: TFSpacing.xs) {
                Text(message.fromUserName ?? "Участник")
                    .font(.caption)
                    .foregroundStyle(Color.tfSub)
                ForEach(message.attachments?.filter { $0.isVoiceRecording } ?? []) { attachment in
                    RoleChatRemoteVoiceBubble(attachment: attachment, transcript: message.text, player: player, api: api)
                }
                if !message.text.isEmpty && !hasAudio {
                    Text(message.text)
                        .foregroundStyle(mine ? .white : Color.tfText)
                }
            }
            .padding(hasAudio ? 0 : TFSpacing.md)
            .background(hasAudio ? Color.clear : (mine ? Color.tfRed : Color.tfCard))
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
            if chat.taskID != nil { draftStatusText = nil }
            if updatedMessages.map(\.id) != messages.map(\.id) || updatedMessages.map(\.attachments) != messages.map(\.attachments) {
                messages = updatedMessages
            }
        } catch { errorMessage = error.localizedDescription }
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!text.isEmpty || !pendingAttachments.isEmpty), !isSending, !isUploadingAttachment else { return }
        isSending = true
        defer { isSending = false }
        do {
            let message = try await api.sendRoleChatMessage(chatID: chat.id, text: text,
                                                            attachmentIDs: pendingAttachments.map(\.id))
            draft = ""
            pendingAttachments = []
            if !messages.contains(where: { $0.id == message.id }) { messages.append(message) }
        } catch { errorMessage = error.localizedDescription }
    }

    private func sendVoicePreview(_ message: VoiceMessage) async -> Bool {
        if !pendingVoices.contains(where: { $0.id == message.id }) { pendingVoices.append(message) }
        await sendVoice(message.id)
        // Запись передана ленте; при сетевой ошибке в ней остаётся повтор.
        return true
    }

    private func handleFileImport(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        Task {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            isUploadingAttachment = true
            defer { isUploadingAttachment = false }
            do {
                let data = try Data(contentsOf: url)
                let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                let attachment = try await api.uploadRoleChatAttachment(fileName: url.lastPathComponent,
                                                                        data: data, mime: mime)
                pendingAttachments.append(attachment)
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func sendVoice(_ id: UUID) async {
        guard let message = pendingVoices.first(where: { $0.id == id }),
              message.transcript != .pending,
              sendingVoiceIDs.insert(id).inserted else { return }
        defer { sendingVoiceIDs.remove(id) }
        do {
            let attachmentID: String
            if let existing = uploadedVoiceIDs[id] {
                attachmentID = existing
            } else {
                let data = try Data(contentsOf: message.audioURL)
                let attachment = try await api.uploadRoleChatAttachment(
                    fileName: message.audioURL.lastPathComponent, data: data, mime: "application/octet-stream"
                )
                attachmentID = attachment.id
                uploadedVoiceIDs[id] = attachmentID
            }
            let text: String
            if case .ready(let recognized) = message.transcript { text = recognized }
            else { text = "" }
            let sent = try await api.sendRoleChatMessage(chatID: chat.id, text: text, attachmentIDs: [attachmentID])
            if !messages.contains(where: { $0.id == sent.id }) { messages.append(sent) }
            pendingVoices.removeAll { $0.id == id }
            uploadedVoiceIDs.removeValue(forKey: id)
        } catch { errorMessage = error.localizedDescription }
    }

    private func assembleTask() async {
        isDrafting = true
        defer { isDrafting = false }
        do {
            let result = try await api.assembleRoleChatTask(chatID: chat.id)
            assembledTaskID = result.createdTaskID
            draftStatusText = result.createdTaskID == nil ? "Задача собирается…" : nil
            await refresh()
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct RoleChatRemoteVoiceBubble: View {
    let attachment: ApiChatAttachment
    let transcript: String
    let player: VoicePlayer
    let api: APIClient
    @State private var localMessage: VoiceMessage?
    @State private var failed = false

    var body: some View {
        Group {
            if let localMessage {
                VoiceMessageBubble(message: localMessage, player: player)
            } else if failed {
                Label("Не удалось загрузить аудио", systemImage: "exclamationmark.triangle")
            } else {
                ProgressView("Загрузка аудио…")
            }
        }
        .task(id: attachment.id) {
            do {
                let data = try await api.downloadRaw(path: "/attachments/\(attachment.id)")
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("role-chat-\(attachment.id).m4a")
                try data.write(to: url, options: .atomic)
                let duration = try AVAudioPlayer(contentsOf: url).duration
                localMessage = VoiceMessage(
                    audioURL: url,
                    duration: duration,
                    transcript: transcript.isEmpty ? .failed : .ready(transcript)
                )
            } catch { failed = true }
        }
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
