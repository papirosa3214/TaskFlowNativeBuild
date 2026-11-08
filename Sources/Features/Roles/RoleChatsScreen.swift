import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import PhotosUI
import UIKit
import QuickLook

/// Личные и групповые чаты живут отдельно от старого окна постановки задач.
///
/// Вид списка — по образцу Microsoft Teams (владелец 21.09.2026, LOCK-195):
/// аватар слева, имя, превью последнего сообщения, справа время и бейдж
/// непрочитанных, строки во всю ширину — без карточек и шевронов. Фон и
/// шапку экрана правка НЕ трогает: владелец прямо сказал «фон не трогай».
///
/// Отдельным блоком над списком — «Помощник владельца»: это прежний owner-канал
/// (надиктовка → карточка), но в списке он выглядит как обычный собеседник.
/// Владелец 21.09.2026: «сделай его просто как отдельный вид участника», без
/// подписей-подсказок.
struct RoleChatsScreen: View {
    @Environment(SessionStore.self) private var session
    @State private var chats: [RoleChat] = []
    /// Панель «Комнаты» (владелец 21.10.2026): Общая, личные комнаты ролей и
    /// их лички. Раньше личный чат с Помощником стоял отдельным блоком над
    /// списком — теперь он в панели вместе с остальными ролями.
    @State private var rooms: ChatRoomsSnapshot?
    @AppStorage("chats.roomsRail.open") private var isRoomsOpen = false
    /// Что выбрано на панели: роль или групповые чаты (владелец 05.11.2026).
    /// По умолчанию — Помощник, с которым идёт основная работа.
    @AppStorage("chats.selectedScope") private var selectedScopeRaw = "u-secretary"
    private var selectedScope: RoleSessionScope { RoleSessionScope(stored: selectedScopeRaw) }
    @AppStorage("chats.showClosed") private var showsClosed = false
    @State private var listRequestVersion = 0
    @State private var isLoading = true
    @State private var errorMessage: String?
    @Environment(\.openRoute) private var openRoute
    @State private var showingCreate = false
    /// Чат, выбранный для окончательного удаления: ждёт подтверждения,
    /// потому что вернуть его уже будет нельзя.
    @State private var pendingPurge: RoleChat?
    /// Свёрнутые папки проектов в каталоге «Групповые чаты»: свернул — комнаты
    /// задач этого проекта убраны, развернул — снова видны.
    @State private var openProjects: Set<String> = []
    @Environment(RealtimeClient.self) private var realtime
    @State private var realtimeObserver = RealtimeObserverSlot<UUID>()
    private let api = APIClient()


    /// Список — сессии выбранного на панели пункта, ветки деревом под своей
    /// сессией. Лички ролей показаны отдельно, под сессиями роли.
    private var visibleRows: [(row: RoleSessionRow, chat: RoleChat)] {
        guard isOwner else {
            return chats.filter { !$0.isPermanentRoom }.map { (RoleSessionRow(id: $0.id, lines: []), $0) }
        }
        let byID = Dictionary(chats.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return RoleSessionList.rows(candidates, scope: selectedScope).compactMap { row in
            byID[row.id].map { (row, $0) }
        }
    }

    /// Что список знает о каждом чате для раскладки по спискам.
    private var candidates: [RoleSessionCandidate] {
        let ownerID = session.currentUser?.id
        return chats.map {
            RoleSessionCandidate(id: $0.id, kind: $0.kind, roomKind: $0.roomKind, parentChatID: $0.parentChatID,
                                 projectID: $0.projectID, otherMemberIDs: $0.others(excluding: ownerID).map(\.id),
                                 lastActivity: $0.lastMessage?.createdAt, branchOfChatID: $0.branchOfChatID,
                                 folder: $0.projectName)
        }
    }

    /// Каталог «Групповые чаты» папками проектов (спецификация 08.11.2026, §3):
    /// проект — папка комнат его задач, а не чат; комнаты без проекта лежат вне
    /// папок.
    private var groupSections: [RoleSessionGroup] {
        RoleSessionList.groups(candidates, scope: .groups)
    }
    /// Переписка выбранной роли с коллегами: открывается только на чтение.
    private var selectedRoleDMs: [ChatRoomsSnapshot.DirectRoom] {
        guard isOwner, case .role(let id) = selectedScope else { return [] }
        return rooms?.role(id)?.dms ?? []
    }
    private var headerTitle: String {
        guard isOwner else { return "Чаты" }
        switch selectedScope {
        case .groups: return "Групповые чаты"
        case .role(let id): return rooms?.role(id)?.name ?? "Чаты"
        }
    }
    private var isOwner: Bool { session.currentUser?.role == .owner }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if isLoading && chats.isEmpty {
                    TFLoading(.block)
                } else if visibleRows.isEmpty && selectedRoleDMs.isEmpty {
                    Text("Пока нет сессий.")
                        .tfText(.action)
                        .foregroundStyle(Color.tfDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, TFSpacing.screenHorizontal)
                        .padding(.top, TFSpacing.xl)
                } else if selectedScope == .groups {
                    groupsCatalog
                } else {
                    let rows = visibleRows
                    ForEach(Array(rows.enumerated()), id: \.element.row.id) { index, item in
                        HStack(spacing: 0) {
                            if !item.row.lines.isEmpty { SessionBranchLines(lines: item.row.lines) }
                            sessionLink(item.chat, isBranch: !item.row.lines.isEmpty)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        // Под сессией с ветками линии не прерываем разделителем.
                        if index < rows.count - 1, rows[index + 1].row.lines.isEmpty { rowDivider }
                    }
                    if !selectedRoleDMs.isEmpty {
                        Text("Переписка с коллегами")
                            .tfText(.meta)
                            .foregroundStyle(Color.tfDim)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, TFSpacing.screenHorizontal)
                            .padding(.top, TFSpacing.lg)
                            .padding(.bottom, TFSpacing.xs)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(selectedRoleDMs) { dm in
                            NavigationLink(value: AppRoute.roleChat(id: dm.chatID)) {
                                ChatListRow(title: rooms?.role(dm.peerID)?.name ?? "Роль",
                                            preview: dmPreview(dm.lastMessage),
                                            time: ChatListTime.label(dm.lastMessage?.createdAt),
                                            unread: 0, turn: dm.turn)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("chats.room.\(dm.chatID)")
                        }
                    }
                }
            }
            .padding(.bottom, TFSpacing.xl)
        }
        .tfScreenBackground()
        // Бывшая панель участников чата — теперь в корне раздела и
        // показывает комнаты (владелец 21.10.2026).
        .overlay(alignment: .trailing) {
            if isOwner {
                ChatEdgeRail(isOpen: $isRoomsOpen, openLabel: "Комнаты", closedLabel: "Показать комнаты", identifier: "chats.roomsRail") {
                    ChatRoomsPanel(snapshot: rooms,
                                   onOpenRole: { select(.role($0.id)) },
                                   onOpenGroups: { select(.groups) })
                }
            }
        }
        .tfNativeHeader(headerTitle)
        .tint(Color.tfText)
        .toolbar {
            if isOwner {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { startNewSession() } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Новая сессия")
                        .accessibilityIdentifier("chats.newSession")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showsClosed.toggle() } label: {
                        Label("Показать закрытые", systemImage: showsClosed ? "checkmark" : "archivebox")
                    }
                        .accessibilityIdentifier("chats.menu.closed")
                    if let candidates = rooms?.externalCandidates, !candidates.isEmpty {
                        // Внешние агенты — без постоянной комнаты, пока владелец
                        // сам её не заведёт (21.10.2026).
                        Menu {
                            ForEach(candidates) { agent in
                                Button(agent.name) { Task { await openExternalRoom(agent) } }
                            }
                        } label: { Label("Комната внешнего агента", systemImage: "person.crop.circle.badge.plus") }
                        .accessibilityIdentifier("chats.menu.externalRoom")
                    }
                } label: { Image(systemName: "ellipsis") }
                    .accessibilityLabel("Меню чатов")
                    .accessibilityIdentifier("chats.menu")
            }
        }
        .tfSheet(isPresented: $showingCreate) {
            CreateRoleChatScreen {
                Task { await load() }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        // Живое обновление (владелец 22.09.2026: «чтобы не выходить и не
        // заходить заново»): пока список открыт, слушаем общий сокет и на новое
        // сообщение тихо перечитываем превью и непрочитанные.
        .task {
            guard !Task.isCancelled else { return }
            realtimeObserver.replace(add: {
                realtime.addObserver { event in
                    switch event {
                    case .roleChatMessage:
                        Task { await reloadSilently() }
                    case .chatNew:
                        Task { await reloadSilently() }
                    default:
                        break
                    }
                }
            }, remove: realtime.removeObserver)
        }
        .onDisappear { realtimeObserver.clear(remove: realtime.removeObserver) }
        .onChange(of: realtime.connectionRevision) {
            guard realtimeObserver.isActive else { return }
            Task { await reloadSilently() }
        }
        .onChange(of: showsClosed) { Task { await load() } }
        .alert("Не удалось загрузить чаты", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Повторить") { Task { await load() } }
            Button("Закрыть", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .confirmationDialog(
            "Удалить чат навсегда?",
            isPresented: Binding(
                get: { pendingPurge != nil },
                set: { if !$0 { pendingPurge = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) {
                guard let chat = pendingPurge else { return }
                pendingPurge = nil
                Task { await purge(chat) }
            }
            Button("Отмена", role: .cancel) { pendingPurge = nil }
        } message: {
            Text("Переписка и вложения пропадут насовсем — вернуть их будет нельзя.")
        }
    }

    // MARK: - Строка сессии

    /// Папки проектов и комнаты внутри них. Папка одной строкой, комнаты —
    /// теми же строками списка, что и везде.
    @ViewBuilder
    private var groupsCatalog: some View {
        let byID = Dictionary(chats.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let sections = groupSections
        ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
            if let title = section.title {
                folderRow(title: title, isOpen: openProjects.contains(title), count: section.ids.count,
                          isFirst: index == 0)
                rowDivider
            }
            let isOpen = section.title.map { openProjects.contains($0) } ?? true
            if isOpen {
                let rooms = section.ids.compactMap { byID[$0] }
                ForEach(Array(rooms.enumerated()), id: \.element.id) { position, chat in
                    sessionLink(chat, isBranch: false)
                    if position < rooms.count - 1 { rowDivider }
                }
            }
            if index < sections.count - 1, sections[index + 1].title != nil, !isOpen { rowDivider }
        }
    }

    /// Строка папки проекта: название проекта и число комнат в нём.
    @ViewBuilder
    private func folderRow(title: String, isOpen: Bool, count: Int, isFirst: Bool) -> some View {
        let row = Button {
            withAnimation(TFMotion.standard) {
                if isOpen { openProjects.remove(title) } else { openProjects.insert(title) }
            }
        } label: {
            TFListRow(
                icon: "folder",
                iconStyle: .plain,
                title: title,
                subtitle: RoleSessionList.roomsCount(count),
                trailing: isOpen
                    ? AnyView(Image(systemName: "chevron.down").tfTypeFont(size: 13).foregroundStyle(Color.tfDim))
                    : nil,
                chevron: isOpen ? .hidden : .shown,
                verticalPadding: TFSpacing.sm
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("chats.folder.\(title)")
        .accessibilityValue(isOpen ? "Развёрнута" : "Свёрнута")
        // Подсказка вешается на первую папку: одна точка на весь каталог.
        if isFirst {
            row.hintAnchor(HintAnchorID.chatsProjectFolders)
        } else {
            row
        }
    }

    /// Разделитель отбит до начала текста: строка читается как строка списка.
    private var rowDivider: some View {
        TFDivider(inset: TFSpacing.screenHorizontal)
    }

    private func sessionLink(_ chat: RoleChat, isBranch: Bool) -> some View {
        NavigationLink(value: AppRoute.roleChat(id: chat.id)) {
            chatRow(chat, isBranch: isBranch)
                .opacity(chat.closedAt == nil ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .contextMenu {
            // Постоянные комнаты не закрываются: сервер это отклоняет.
            if isOwner && !chat.isPermanentRoom {
                let closed = chat.closedAt != nil
                Button { Task { await setClosed(chat, closed: !closed) } } label: {
                    Label(closed ? "Вернуть сессию" : "Закрыть сессию", systemImage: closed ? "tray.and.arrow.up" : "archivebox")
                }
                // «В архив» и «Удалить» (владелец 08.11.2026): как в любой
                // программе — сначала архив, потом удаление. Удалённое не
                // возвращается, поэтому пункт есть только у чата из архива.
                if chat.isArchived || closed {
                    Button(role: .destructive) { pendingPurge = chat } label: {
                        Label("Удалить", systemImage: "trash")
                    }
                    .accessibilityIdentifier("chats.row.purge")
                } else {
                    Button { Task { await moveToArchive(chat) } } label: {
                        Label("В архив", systemImage: "archivebox.circle")
                    }
                    .accessibilityIdentifier("chats.row.archive")
                }
            }
        }
    }

    private func openExternalRoom(_ agent: RoleChatMember) async {
        do {
            let room = try await api.personalRoom(roleID: agent.id)
            try await refreshList()
            openRoute?(.roleChat(id: room.id))
        } catch { errorMessage = error.localizedDescription }
    }

    /// Роль выбрана — вкладка уходит за край и не закрывает список сессий.
    private func select(_ scope: RoleSessionScope) {
        selectedScopeRaw = scope.stored
        withAnimation(TFMotion.standard) { isRoomsOpen = false }
    }

    private func startNewSession() {
        switch selectedScope {
        case .groups: showingCreate = true
        case .role(let id): Task { await startChat(withRole: id) }
        }
    }

    /// Новая сессия с ролью — тот же `POST /api/chats`, что у «Чат с
    /// участниками»; без названия: его даст первое сообщение.
    private func startChat(withRole roleID: String) async {
        do {
            let chat = try await api.createRoleChat(title: nil, memberIDs: [roleID])
            try await refreshList()
            openRoute?(.roleChat(id: chat.id))
        } catch { errorMessage = error.localizedDescription }
    }

    private func setClosed(_ chat: RoleChat, closed: Bool) async {
        do {
            _ = try await api.closeRoleChat(id: chat.id, closed: closed)
            // Сразу из списка, не дожидаясь сети: строка не стирается, а
            // прячется в «Показать закрытые» — как на сервере.
            if closed { try? LocalStore.shared.hideChat(id: chat.id) }
            try await refreshList()
        } catch { errorMessage = error.localizedDescription }
    }

    /// «В архив»: чат уходит из общего списка, история и сообщения остаются.
    private func moveToArchive(_ chat: RoleChat) async {
        do {
            _ = try await api.archiveRoleChat(id: chat.id)
            try? LocalStore.shared.hideChat(id: chat.id)
            try await refreshList()
        } catch { errorMessage = error.localizedDescription }
    }

    /// «Удалить» насовсем: сервер принимает только чат из архива. Откатить
    /// нельзя — поэтому сначала подтверждение.
    private func purge(_ chat: RoleChat) async {
        do {
            try await api.purgeRoleChat(id: chat.id)
            try? LocalStore.shared.hideChat(id: chat.id)
            try await refreshList()
        } catch { errorMessage = error.localizedDescription }
    }

    // MARK: - Строка чата с ролями

    private func chatRow(_ chat: RoleChat, isBranch: Bool) -> some View {
        ChatListRow(
            title: rowTitle(chat, isBranch: isBranch),
            preview: previewText(chat),
            time: ChatListTime.label(chat.lastMessage?.createdAt),
            unread: chat.unread + chats.filter { $0.parentChatID == chat.id }.reduce(0) { $0 + $1.unread },
            taskTitle: chat.taskTitle,
            turn: chat.turn,
            contextLabel: selectedScope == .groups ? nil : chat.contextUsage?.label,
            // В каталоге проект уже назван папкой, в строке он был бы повтором.
            projectName: selectedScope == .groups
                ? nil
                : (chat.projectName == chat.title ? nil : chat.projectName)
        )
    }

    private func rowTitle(_ chat: RoleChat, isBranch: Bool) -> String {
        if chat.roomKind == "personal" { return "Личная комната" }
        let title = chat.displayTitle(excluding: session.currentUser?.id)
        // В дереве и так видно, что это ветка.
        return isBranch && title.hasPrefix("Ветка: ") ? String(title.dropFirst("Ветка: ".count)) : title
    }

    /// Чьё последнее сообщение — видно по имени: в личке ролей «Вы» не бывает.
    private func dmPreview(_ message: ChatRoomsSnapshot.RoomMessage?) -> String {
        guard let message else { return "" }
        let author = rooms?.role(message.fromUserID)?.name
        return author.map { "\($0): \(message.text)" } ?? message.text
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
        // Локальная база: список виден сразу, без сети. Это первое, что
        // рисуется, — сеть его только обновит.
        if chats.isEmpty, let local = try? LocalStore.shared.chats(includeClosed: showsClosed), !local.isEmpty {
            chats = local
        }
        // Прошлый список из кэша — виден сразу, сеть его обновит.
        if chats.isEmpty, let cached = api.cachedRoleChats(includeClosed: showsClosed) { chats = cached }
        if rooms == nil, isOwner { rooms = api.cachedChatRooms() }
        isLoading = true
        defer { isLoading = false }
        do { try await refreshList(forceFull: true) }
        catch is CancellationError { }
        catch {
            // Нет связи или сервер перезапускается, а список уже на экране из
            // локальной базы — окно ничего не даёт, список обновится при
            // следующем заходе или событии (владелец 06.11.2026). Окно — для
            // пустого экрана и настоящих ошибок сервера.
            if case APIError.transport = error, !chats.isEmpty { return }
            errorMessage = error.localizedDescription
        }
    }

    /// `forceFull` — забрать список телом, без отпечатка. Нужен при открытии
    /// экрана: локальная таблица могла сохранить чаты, которых на сервере
    /// уже нет (закрытая или убранная сессия), и ответ 304 вернул бы их в
    /// список. Полный ответ заодно прячет такой хвост — `hideChats`.
    private func refreshList(forceFull: Bool = false) async throws {
        listRequestVersion += 1
        let version = listRequestVersion
        // С отпечатком: список чатов не менялся — сервер отвечает 304, и
        // список не качается заново. Отпечаток лежит в локальной базе,
        // поэтому перезапуск приложения его не теряет.
        async let freshChats = api.roleChatsSync(
            includeClosed: showsClosed,
            etag: forceFull ? nil : LocalStore.shared.syncState(SyncStateKeys.chatsETag)
        )
        let freshRooms: ChatRoomsSnapshot? = isOwner ? try? await api.chatRooms() : nil
        let result = try await freshChats
        guard version == listRequestVersion, !Task.isCancelled else { return }
        if result.notModified {
            // Список не менялся — берём его из локальной базы.
            if let local = try? LocalStore.shared.chats(includeClosed: showsClosed), !local.isEmpty {
                chats = local
            }
        } else {
            let envelope = try api.decode(APIClient.RoleChatsSyncEnvelope.self, from: result.data)
            chats = envelope.chats
            // В базу — сырое тело ответа сервера.
            try? LocalStore.shared.upsertChats(result.data)
            // Полный список — это ровно то, что видит владелец: всё прочее в
            // локальной таблице устарело (закрытые сессии, уборка, правки с
            // другого устройства). Без этого «удалённая» сессия возвращалась
            // из локальной базы после перезапуска.
            try? LocalStore.shared.hideChats(notIn: Set(envelope.chats.map(\.id)))
            if let etag = result.etag { LocalStore.shared.setSyncState(SyncStateKeys.chatsETag, etag) }
        }
        if let freshRooms { rooms = freshRooms }
    }

    private func reloadSilently() async { try? await refreshList() }

}

/// Линии дерева слева от ветки: отводы и вертикали до следующих веток.
private struct SessionBranchLines: View {
    let lines: [RoleSessionRow.Line]
    private static let levelWidth: CGFloat = 16

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                SessionBranchLineShape(line: line)
                    .stroke(Color.tfDim.opacity(0.6), style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
                    .frame(width: Self.levelWidth)
            }
        }
        .padding(.leading, TFSpacing.screenHorizontal)
        .accessibilityHidden(true)
    }
}

private struct SessionBranchLineShape: Shape {
    let line: RoleSessionRow.Line

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let x = rect.minX + 1
        switch line {
        case .blank:
            break
        case .through:
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
        case .branch:
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            path.move(to: CGPoint(x: x, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        case .lastBranch:
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
        return path
    }
}
