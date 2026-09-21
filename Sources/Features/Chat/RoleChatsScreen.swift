import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

/// Личные и групповые чаты живут отдельно от старого окна постановки задач.
///
/// Вид списка — по образцу Microsoft Teams (владелец 21.09.2026, LOCK-195):
/// аватар слева, имя, превью последнего сообщения, справа время и бейдж
/// непрочитанных, строки во всю ширину — без карточек и шевронов. Фон и
/// шапку экрана правка НЕ трогает: владелец прямо сказал «фон не трогай».
///
/// Отдельным блоком над списком — «Секретарь»: это прежний owner-канал
/// (надиктовка → карточка), но в списке он выглядит как обычный собеседник.
/// Владелец 21.09.2026: «сделай его просто как отдельный вид участника», без
/// подписей-подсказок.
struct RoleChatsScreen: View {
    @Environment(SessionStore.self) private var session
    @State private var chats: [RoleChat] = []
    @State private var secretary: SecretarySnapshot?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingCreate = false
    private let api = APIClient()

    /// Блок «Секретарь» кормится старым каналом `owner`: у новых чатов
    /// свой контракт (`GET /api/chats`), у него — `GET /chat` и `/chat/unread`.
    private struct SecretarySnapshot: Equatable {
        var preview: String
        var fromMe: Bool
        var createdAt: String?
        var unread: Int
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if isLoading && chats.isEmpty && secretary == nil {
                    ProgressView("Загрузка чатов")
                        .frame(maxWidth: .infinity)
                        .padding(.top, TFSpacing.xl)
                } else {
                    secretaryBlock
                    // Граница блока: «Секретарь» стоит особняком, а не первым
                    // в общем списке (владелец 21.09.2026).
                    TFDivider()
                    if chats.isEmpty {
                        Text("Пока нет чатов. Создайте чат с одной или несколькими ролями.")
                            .tfText(.action)
                            .foregroundStyle(Color.tfDim)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, TFSpacing.screenHorizontal)
                            .padding(.top, TFSpacing.xl)
                    } else {
                    ForEach(Array(chats.enumerated()), id: \.element.id) { index, chat in
                        NavigationLink(value: AppRoute.roleChat(id: chat.id)) {
                            chatRow(chat)
                        }
                        .buttonStyle(.plain)
                            if index < chats.count - 1 {
                                // Разделитель отбит до начала текста, а не под
                                // аватар — так строка читается как строка
                                // списка, а не как карточка.
                                TFDivider(inset: TFSpacing.screenHorizontal + TFAvatar.Size.xl.rawValue + TFSpacing.md)
                            }
                        }
                    }
                }
            }
            .padding(.bottom, TFSpacing.xl)
        }
        .background(Color.tfBackground)
        .tfNativeHeader("Чаты")
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

    // MARK: - Блок «Секретарь»

    @ViewBuilder
    private var secretaryBlock: some View {
        // Только владельцу: owner-канал — его разговор с секретарём, у
        // остальных учёток этого чата нет.
        if session.currentUser?.role == .owner {
            NavigationLink(value: AppRoute.secretaryChat) {
                ChatListRow(
                    avatar: AnyView(TFAvatar(
                        size: .xl,
                        initials: secretaryInitials,
                        tint: Color.tfTeal
                    )),
                    title: "Секретарь",
                    preview: secretaryPreview,
                    time: ChatListTime.label(secretary?.createdAt),
                    unread: secretary?.unread ?? 0
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var secretaryInitials: String {
        "С"
    }

    private var secretaryPreview: String {
        guard let secretary, !secretary.preview.isEmpty else { return "" }
        return secretary.fromMe ? "Вы: \(secretary.preview)" : secretary.preview
    }

    // MARK: - Строка чата с ролями

    private func chatRow(_ chat: RoleChat) -> some View {
        ChatListRow(
            avatar: AnyView(chatAvatar(chat)),
            title: chat.displayTitle(excluding: session.currentUser?.id),
            preview: previewText(chat),
            time: ChatListTime.label(chat.lastMessage?.createdAt),
            unread: chat.unread
        )
    }

    @ViewBuilder
    private func chatAvatar(_ chat: RoleChat) -> some View {
        let others = chat.others(excluding: session.currentUser?.id)
        if chat.kind == "group" {
            RoleGroupAvatar(members: others)
        } else if let member = others.first {
            RoleMemberAvatar(member: member)
        } else {
            TFAvatar(size: .xl, initials: "?", tint: Color(hex: TFHexDefault.unassigned))
        }
    }

    private func previewText(_ chat: RoleChat) -> String {
        guard let last = chat.lastMessage else { return "" }
        let body = last.displayText
        guard !body.isEmpty else { return "" }
        if last.fromUserID == session.currentUser?.id { return "Вы: \(body)" }
        // Имя отправителя нужно только там, где он неочевиден, — в группе.
        if chat.kind == "group", let name = last.fromUserName, !name.isEmpty {
            return "\(name): \(body)"
        }
        return body
    }

    // MARK: - Загрузка

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do { chats = try await api.roleChats() }
        catch { errorMessage = error.localizedDescription }
        await loadSecretary()
    }

    /// Отдельно от списка чатов: падение этого блока не должно показывать
    /// ошибку всего экрана — и наоборот.
    private func loadSecretary() async {
        guard session.currentUser?.role == .owner else {
            secretary = nil
            return
        }
        async let history = try? api.fetchChatHistory(channel: .owner, limit: 1)
        async let unread = try? api.chatUnread()
        let (page, counter) = await (history, unread)
        let last = page?.messages.first
        secretary = SecretarySnapshot(
            preview: last?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            fromMe: last?.fromUserId != nil && last?.fromUserId == session.currentUser?.id,
            createdAt: last?.createdAt,
            unread: counter?.count ?? 0
        )
    }
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
                RoleChatRoomScreen(chat: chat)
            } else if failed {
                ContentUnavailableView(
                    "Чат не открылся",
                    systemImage: "bubble.left",
                    description: Text("Проверьте связь и зайдите ещё раз.")
                )
            } else {
                ProgressView("Загрузка чата")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.tfBackground)
        .task { await load() }
    }

    private func load() async {
        do { chat = try await api.roleChat(id: chatID) }
        catch { failed = true }
    }
}

/// Обёртка для блока «Секретарь». `ChatScreen` считает себя корневым экраном
/// вкладки «Чат»: его стрелка «назад» зовёт действие, которое кладёт
/// `RootShellView` (сброс вкладки в «Обзор»). Здесь он открыт пушем из
/// списка, поэтому свою стрелку он не рисует (`hidesOwnBackButton`), а
/// действие всё равно подменяем на закрытие пуша — на случай, если системную
/// кнопку в будущем уберут.
struct SecretaryChatScreen: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ChatScreen(hidesOwnBackButton: true)
            .environment(\.chatBackAction, { dismiss() })
    }
}

/// Строка списка чатов — одна на все виды (роль, группа, секретарь):
/// аватар, имя, превью, время, бейдж непрочитанных. Строка во всю ширину,
/// без карточки и шеврона — вид списка, а не меню настроек.
private struct ChatListRow: View {
    let avatar: AnyView
    let title: String
    let preview: String
    let time: String?
    let unread: Int

    var body: some View {
        HStack(spacing: TFSpacing.md) {
            // Аватар — украшение: имя стоит рядом текстом, и VoiceOver не
            // должен читать «Аватар: Q» перед ним. Без этого строка
            // «Секретарь» озвучивалась дважды («Секретарь, Секретарь»).
            avatar.accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .tfText(.body)
                    .fontWeight(unread > 0 ? .semibold : .regular)
                    .foregroundStyle(Color.tfText)
                    .lineLimit(1)
                Text(preview)
                    .tfText(.action)
                    .foregroundStyle(Color.tfSub)
                    .lineLimit(1)
            }
            Spacer(minLength: TFSpacing.sm)
            VStack(alignment: .trailing, spacing: TFSpacing.sm) {
                if let time {
                    Text(time)
                        .tfText(.meta)
                        .foregroundStyle(Color.tfDim)
                }
                if unread > 0 { badge }
            }
        }
        .padding(.horizontal, TFSpacing.screenHorizontal)
        .padding(.vertical, TFSpacing.md)
        .contentShape(Rectangle())
        // Строка целиком — одна единица для VoiceOver: без этого он читает
        // аватар, имя, превью и время как четыре отдельных элемента.
        .accessibilityElement(children: .combine)
    }

    private var badge: some View {
        Text(unread > 99 ? "99+" : "\(unread)")
            .tfText(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, TFSpacing.xs + 2)
            .frame(minWidth: 20, minHeight: 20)
            .background(Capsule().fill(Color.tfRedSolid))
            .accessibilityLabel("Непрочитанных: \(unread)")
    }
}

/// Аватар участника чата — фото, если оно есть у учётки, иначе инициалы.
private struct RoleMemberAvatar: View {
    let member: RoleChatMember
    var size: TFAvatar.Size = .xl

    var body: some View {
        let initials = member.initials ?? String(member.name.prefix(1))
        let tint = Color(hex: member.avatarColor ?? TFHexDefault.unassigned)
        if let path = member.avatarURL,
           let url = URL(string: APIClient.baseURL.absoluteString + path) {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    TFAvatar(size: size, image: image, initials: initials, tint: tint)
                } else {
                    TFAvatar(size: size, initials: initials, tint: tint)
                }
            }
        } else {
            TFAvatar(size: size, initials: initials, tint: tint)
        }
    }
}

/// Составной аватар группы: двое участников внахлёст, как в Teams. Больше
/// двух не рисуем — на 44pt третий уже неразличим, а полный состав виден в
/// заголовке комнаты.
private struct RoleGroupAvatar: View {
    let members: [RoleChatMember]

    var body: some View {
        let shown = Array(members.prefix(2))
        ZStack {
            if shown.count == 1 {
                RoleMemberAvatar(member: shown[0])
            } else if shown.count >= 2 {
                RoleMemberAvatar(member: shown[0], size: .md)
                    .overlay(Circle().stroke(Color.tfBackground, lineWidth: 2))
                    .offset(x: -7)
                RoleMemberAvatar(member: shown[1], size: .md)
                    .overlay(Circle().stroke(Color.tfBackground, lineWidth: 2))
                    .offset(x: 7)
            } else {
                TFAvatar(size: .xl, initials: "?", tint: Color(hex: TFHexDefault.unassigned))
            }
        }
        .frame(width: TFAvatar.Size.xl.rawValue, height: TFAvatar.Size.xl.rawValue)
    }
}

/// Время в строке списка чатов: сегодня — часы, вчера — словом, дальше до
/// недели — день недели, ещё дальше — дата. Формат взят у Teams, потому что
/// строка списка читается «когда было последнее сообщение», а не «сколько
/// прошло» (`RelativeTime` в этой же папке отвечает на второй вопрос).
private enum ChatListTime {
    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let weekday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "EEE"
        return formatter
    }()

    private static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "dd.MM"
        return formatter
    }()

    static func label(_ raw: String?) -> String? {
        guard let moment = DateFormats.sqliteUTC(raw) else { return nil }
        let calendar = Calendar.autoupdatingCurrent
        if calendar.isDateInToday(moment) { return clock.string(from: moment) }
        if calendar.isDateInYesterday(moment) { return "Вчера" }
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: moment),
            to: calendar.startOfDay(for: Date())
        ).day ?? 0
        if days < 7 { return weekday.string(from: moment).capitalized }
        return shortDate.string(from: moment)
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
                                // Своё голосовое — только красная обводка, без
                                // заливки: вид отправленного сообщения не
                                // зависит от способа отправки (владелец
                                // 21.09.2026).
                                VoiceMessageBubble(
                                    message: message,
                                    player: player,
                                    style: RoleChatVoiceStyle.own
                                )
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
                .background(Color.tfBackground)
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
        }
        .chatComposerBar {
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
                NavigationLink(value: AppRoute.taskDetail(taskID: taskID)) {
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
                    RoleChatRemoteVoiceBubble(attachment: attachment, transcript: message.text,
                                              player: player, api: api, isOwn: mine)
                }
                if !message.text.isEmpty && !hasAudio {
                    Text(message.text)
                        // Мои — только красная обводка, без заливки; у
                        // остальных обводки нет (владелец 21.09.2026).
                        .foregroundStyle(Color.tfText)
                }
            }
            .padding(hasAudio ? 0 : TFSpacing.md)
            .background(hasAudio ? Color.clear : (mine ? Color.clear : Color.tfCard))
            .overlay {
                if mine && !hasAudio {
                    RoundedRectangle(cornerRadius: TFRadius.lg)
                        .strokeBorder(Color.tfRed, lineWidth: TFBorder.width)
                }
            }
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

/// Оформление голосового пузыря в чате. Своё сообщение — красная обводка без
/// заливки, ровно как у своего текстового: вид отправленного сообщения не
/// зависит от того, как его отправили (владелец 21.09.2026).
///
/// Цвета задаются ЗДЕСЬ, а не в `VoiceMessageBubble`: тот файл собирается
/// ещё и в отдельное приложение-прототип `VoiceMessageLab`, которому
/// дизайн-система TaskFlow недоступна.
enum RoleChatVoiceStyle {
    static let own = VoiceBubbleStyle(
        fill: .clear,
        stroke: Color.tfRed,
        playTint: Color.tfRed,
        playFilled: false
    )
}

private struct RoleChatRemoteVoiceBubble: View {
    let attachment: ApiChatAttachment
    let transcript: String
    let player: VoicePlayer
    let api: APIClient
    /// Своё ли сообщение: голосовое приходит из истории теми же вложениями,
    /// поэтому сторону нужно передать явно — иначе своё голосовое нарисовалось
    /// бы чужой карточкой.
    let isOwn: Bool
    @State private var localMessage: VoiceMessage?
    @State private var failed = false

    var body: some View {
        Group {
            if let localMessage {
                // Своё голосовое — обводка без заливки, как у своего
                // текстового; чужое — прежний пузырь прототипа (владелец
                // 21.09.2026: вид не зависит от способа отправки).
                VoiceMessageBubble(
                    message: localMessage,
                    player: player,
                    style: isOwn ? RoleChatVoiceStyle.own : VoiceBubbleStyle()
                )
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
