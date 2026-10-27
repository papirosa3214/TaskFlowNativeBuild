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
    @State private var openedRole: ChatRoomsSnapshot.RoleRoom?
    @AppStorage("chats.showClosed") private var showsClosed = false
    /// Развёрнутые проекты в списке сессий (владелец 21.10.2026): по
    /// умолчанию все свёрнуты, храним только раскрытые — названия через
    /// перевод строки, `@AppStorage` не хранит множества.
    @AppStorage("chats.expandedProjects") private var expandedProjectsRaw = ""
    private var expandedProjects: Set<String> { Set(expandedProjectsRaw.split(separator: "\n").map(String.init)) }
    private func toggleProject(_ title: String) {
        var set = expandedProjects
        if set.contains(title) { set.remove(title) } else { set.insert(title) }
        withAnimation(TFMotion.standard) { expandedProjectsRaw = set.sorted().joined(separator: "\n") }
    }
    @State private var listRequestVersion = 0
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingProjectCreate = false
    @Environment(\.openRoute) private var openRoute
    @State private var showingCreate = false
    @State private var realtime = RealtimeClient()
    private let api = APIClient()


    var projectsOnly = false

    /// Чаты по проектам живут в своей вкладке и в общем списке не светятся
    /// (владелец 06.10.2026).
    /// Список — сессии (21.10.2026): постоянные комнаты живут в панели,
    /// обсуждения задач (темы проектных чатов) идут сессиями под своим
    /// проектом. Сами проектные группы остаются во вкладке «Чаты проектов».
    private var visibleChats: [RoleChat] {
        if projectsOnly { return chats.filter { $0.parentChatID == nil && $0.projectID != nil } }
        return chats.filter { !$0.isPermanentRoom && ($0.parentChatID != nil || $0.projectID == nil) }
    }
    private var isOwner: Bool { session.currentUser?.role == .owner }

    /// Сессии по проектам: сначала проекты по свежести, «Без проекта» последним.
    private var sessionGroups: [(title: String, chats: [RoleChat])] {
        var order: [String] = []
        var groups: [String: [RoleChat]] = [:]
        for chat in visibleChats {
            let key = chat.projectName ?? ""
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(chat)
        }
        let named = order.filter { !$0.isEmpty }
        // Сессии без проекта — последней группой с пустым названием: без
        // подзаголовка, за разделительной линией (владелец 21.10.2026).
        return (named + (groups[""] == nil ? [] : [""])).map { (title: $0, chats: groups[$0] ?? []) }
    }
    private var projectsUnread: Int {
        chats.filter { $0.parentChatID == nil && $0.projectID != nil }.reduce(0) { $0 + $1.unread }
    }
    /// Иконки в списке чатов — тот же размер, что в списках задач (68 pt).
    /// 10.10.2026 пробовали поднять до 76 («рядом пустоты»), но кружок — это
    /// высота строки: строки стали выше, а владелец просил картинку побольше
    /// БЕЗ поднятия строк. Больше кружок тут расти не может.
    private let listAvatar: TFAvatar.Size = .taskList

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if isLoading && chats.isEmpty {
                    HStack(spacing: TFSpacing.sm) {
                        Spacer(minLength: 0)
                        ProgressView("Загрузка чатов")
                        Spacer(minLength: 0)
                    }
                    .padding(.top, TFSpacing.xl)
                } else if visibleChats.isEmpty {
                    Text(projectsOnly ? "Пока нет чатов по проектам." : "Пока нет сессий. Комнаты ролей — на панели справа.")
                        .tfText(.action)
                        .foregroundStyle(Color.tfDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, TFSpacing.screenHorizontal)
                        .padding(.top, TFSpacing.xl)
                } else {
                    if projectsOnly {
                        // Здесь чат и есть проект (владелец 21.10.2026):
                        // подзаголовок с тем же именем над ним лишний.
                        ForEach(Array(visibleChats.enumerated()), id: \.element.id) { index, chat in
                            sessionLink(chat)
                            if index < visibleChats.count - 1 { rowDivider }
                        }
                    } else {
                        // Подзаголовки проектов прилипают, как в «Сегодня».
                        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                            ForEach(sessionGroups, id: \.title) { group in
                                if group.title.isEmpty {
                                    // Без проекта: линия и сразу список, всегда раскрыт.
                                    TFDivider()
                                        .padding(.vertical, TFSpacing.sm)
                                    // Подзаголовок, чтобы при раскрытом проекте
                                    // было видно, где свои беспроектные сессии
                                    // (владелец 27.10.2026). Вид — как у
                                    // подзаголовка проекта, без сворачивания.
                                    Text("Открытые сессии")
                                        .tfText(.taskTitle)
                                        .foregroundStyle(Color.tfText)
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                        .padding(.horizontal, TFSpacing.screenHorizontal)
                                        .accessibilityAddTraits(.isHeader)
                                    ForEach(Array(group.chats.enumerated()), id: \.element.id) { index, chat in
                                        sessionLink(chat)
                                        if index < group.chats.count - 1 { rowDivider }
                                    }
                                } else {
                                let collapsed = !expandedProjects.contains(group.title)
                                Section {
                                    if !collapsed {
                                        ForEach(Array(group.chats.enumerated()), id: \.element.id) { index, chat in
                                            sessionLink(chat)
                                            if index < group.chats.count - 1 { rowDivider }
                                        }
                                    }
                                } header: {
                                    SessionGroupHeader(title: group.title, count: group.chats.count,
                                                       unread: group.chats.reduce(0) { $0 + $1.unread },
                                                       isCollapsed: collapsed) { toggleProject(group.title) }
                                }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.bottom, TFSpacing.xl)
        }
        .background(Color.tfBackground)
        // Бывшая панель участников чата — теперь в корне раздела и
        // показывает комнаты (владелец 21.10.2026).
        .overlay(alignment: .trailing) {
            if isOwner && !projectsOnly {
                ChatEdgeRail(isOpen: $isRoomsOpen, openLabel: "Комнаты", closedLabel: "Показать комнаты", identifier: "chats.roomsRail") {
                    ChatRoomsPanel(snapshot: rooms,
                                   onOpenCommon: { if let id = rooms?.common.chatID { openRoute?(.roleChat(id: id)) } },
                                   onOpenRole: { openedRole = $0 })
                }
            }
        }
        .sheet(item: $openedRole) { role in
            if let rooms {
                RoleRoomSheet(role: role, snapshot: rooms,
                              onOpen: { id in openRoute?(.roleChat(id: id)) },
                              onNewChat: { Task { await startChat(with: role) } })
            }
        }
        .tfNativeHeader(projectsOnly ? "Чаты проектов" : "Чаты")
        .tint(Color.tfText)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if !projectsOnly {
                        // Маршрутом, не `NavigationLink { }`: экран вне пути
                        // вкладки ломал переходы в группы и выход назад.
                        Button {
                            openRoute?(.projectChats)
                        } label: {
                            Label(projectsUnread > 0 ? "Чаты проектов · \(projectsUnread)" : "Чаты проектов", systemImage: "folder")
                        }
                        .accessibilityIdentifier("chats.menu.projects")
                        Divider()
                    }
                    Button { showsClosed.toggle() } label: {
                        Label("Показать закрытые", systemImage: showsClosed ? "checkmark" : "archivebox")
                    }
                        .accessibilityIdentifier("chats.menu.closed")
                    Divider()
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
                    Button("Чат с участниками") { showingCreate = true }
                    Button("Группа проекта") { showingProjectCreate = true }
                } label: { Image(systemName: "ellipsis") }
                    .accessibilityLabel("Меню чатов")
                    .accessibilityIdentifier("chats.menu")
            }
        }
        .sheet(isPresented: $showingProjectCreate) {
            ProjectChatPicker { Task { await load() } }
        }
        .sheet(isPresented: $showingCreate) {
            CreateRoleChatScreen {
                Task { await load() }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        // Живое обновление (владелец 22.09.2026: «чтобы не выходить и не
        // заходить заново»): пока список открыт, слушаем сокет и на новое
        // сообщение тихо перечитываем превью и непрочитанные.
        .task {
            realtime.onEvent = { event in
                switch event {
                case .roleChatMessage:
                    Task { await reloadSilently() }
                case .chatNew:
                    Task { await reloadSilently() }
                default:
                    break
                }
            }
            realtime.onReconnected = { Task { await reloadSilently() } }
            realtime.connect()
        }
        .onDisappear { realtime.disconnect() }
        .onChange(of: showsClosed) { Task { await load() } }
        .alert("Не удалось загрузить чаты", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Повторить") { Task { await load() } }
            Button("Закрыть", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    // MARK: - Строка сессии

    /// Разделитель отбит до начала текста, а не под аватар — так строка
    /// читается как строка списка, а не как карточка.
    private var rowDivider: some View {
        TFDivider(inset: TFSpacing.screenHorizontal + listAvatar.rawValue + TFSpacing.sm)
    }

    private func sessionLink(_ chat: RoleChat) -> some View {
        NavigationLink(value: AppRoute.roleChat(id: chat.id)) {
            chatRow(chat)
                .opacity(chat.closedAt == nil ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if isOwner {
                let closed = chat.closedAt != nil
                Button { Task { await setClosed(chat, closed: !closed) } } label: {
                    Label(closed ? "Вернуть сессию" : "Закрыть сессию", systemImage: closed ? "tray.and.arrow.up" : "archivebox")
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

    /// Новый чат с ролью из панели — тот же `POST /api/chats`, что у
    /// «Чат с участниками»; без названия: его даст первое сообщение.
    private func startChat(with role: ChatRoomsSnapshot.RoleRoom) async {
        do {
            let chat = try await api.createRoleChat(title: nil, memberIDs: [role.id])
            try await refreshList()
            openRoute?(.roleChat(id: chat.id))
        } catch { errorMessage = error.localizedDescription }
    }

    private func setClosed(_ chat: RoleChat, closed: Bool) async {
        do {
            _ = try await api.closeRoleChat(id: chat.id, closed: closed)
            try await refreshList()
        } catch { errorMessage = error.localizedDescription }
    }

    // MARK: - Строка чата с ролями

    private func chatRow(_ chat: RoleChat) -> some View {
        ChatListRow(
            avatar: AnyView(chatAvatar(chat)),
            title: chat.displayTitle(excluding: session.currentUser?.id),
            preview: previewText(chat),
            time: ChatListTime.label(chat.lastMessage?.createdAt),
            unread: chat.unread + chats.filter { $0.parentChatID == chat.id }.reduce(0) { $0 + $1.unread },
            taskTitle: chat.taskTitle,
            turn: chat.turn
        )
    }

    @ViewBuilder
    private func chatAvatar(_ chat: RoleChat) -> some View {
        let others = chat.others(excluding: session.currentUser?.id)
        if chat.kind == "group" {
            TFGroupAvatar(identity: chat.projectID ?? chat.id, size: listAvatar)
        } else if let member = others.first {
            RoleMemberAvatar(member: member, size: listAvatar)
        } else {
            TFAvatar(size: listAvatar, initials: "?", tint: Color(hex: TFHexDefault.unassigned))
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
        // Прошлый список из кэша — виден сразу, сеть его обновит.
        if chats.isEmpty, let cached = api.cachedRoleChats(includeClosed: showsClosed) { chats = cached }
        if rooms == nil, isOwner, !projectsOnly { rooms = api.cachedChatRooms() }
        isLoading = true
        defer { isLoading = false }
        do { try await refreshList() }
        catch is CancellationError { }
        catch { errorMessage = error.localizedDescription }
    }

    private func refreshList() async throws {
        listRequestVersion += 1
        let version = listRequestVersion
        async let freshChats = api.roleChats(includeClosed: showsClosed)
        let freshRooms: ChatRoomsSnapshot? = isOwner && !projectsOnly ? try? await api.chatRooms() : nil
        let fresh = try await freshChats
        guard version == listRequestVersion, !Task.isCancelled else { return }
        chats = fresh
        if let freshRooms { rooms = freshRooms }
    }

    private func reloadSilently() async { try? await refreshList() }

}

/// Комната чата по идентификатору — адресат маршрута `AppRoute.roleChat`.
/// Список отдаёт только id: маршрут обязан быть `Hashable` и не тащить
/// состав чата с собой.
struct RoleChatRoomLoader: View {
    let chatID: String
    /// true — открыть переписку группы проекта, а не список её тем.
    var opensGroupRoom = false
    @State private var chat: RoleChat?
    @State private var failed = false
    private let api = APIClient()

    var body: some View {
        Group {
            if let chat {
                if chat.projectID != nil && chat.parentChatID == nil && !opensGroupRoom {
                    ProjectTopicsScreen(group: chat)
                } else {
                    RoleChatRoomScreen(chat: chat)
                }
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

/// Строка списка чатов — одна на все виды (роль, группа, помощник владельца):
/// аватар, имя, превью, время, бейдж непрочитанных. Строка во всю ширину,
/// без карточки и шеврона — вид списка, а не меню настроек.
/// Подзаголовок группы сессий — название проекта (21.10.2026). Нажатие
/// сворачивает и разворачивает сессии проекта; у свёрнутого видно, сколько
/// в нём сессий и непрочитанных.
private struct SessionGroupHeader: View {
    let title: String
    let count: Int
    let unread: Int
    let isCollapsed: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            // Подзаголовок — как в карточке задачи (`taskSectionHeader` в
            // TaskFormScreen): `.tfText(.taskTitle)`, белый (владелец 21.10.2026).
            HStack(alignment: .firstTextBaseline, spacing: TFSpacing.sm) {
                Text(title)
                    .tfText(.taskTitle)
                    .foregroundStyle(Color.tfText)
                    .textCase(nil)
                    .lineLimit(1)
                if isCollapsed {
                    Text(unread > 0 ? "\(count) · \(unread) новых" : "\(count)")
                        .tfText(.meta)
                        .foregroundStyle(unread > 0 ? Color.tfRed : Color.tfDim)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, TFSpacing.screenHorizontal)
            .padding(.top, TFSpacing.sm)
            // Прилипший заголовок без подложки — полностью прозрачный, как
            // соседние подзаголовки секций (владелец 03.09.2026).
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), сессий: \(count)")
        .accessibilityValue(isCollapsed ? "свёрнут" : "развёрнут")
        .accessibilityHint(isCollapsed ? "Развернуть" : "Свернуть")
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("chats.group.\(title)")
    }
}

struct ChatListRow: View {
    let avatar: AnyView
    let title: String
    let preview: String
    let time: String?
    let unread: Int
    /// Название задачи, за которой закреплён чат (`nil` — свободный).
    var taskTitle: String?
    /// Ход роли в комнате: идёт — аватарка играет ролик; после — точка итога.
    var turn: RoomTurn? = nil

    var body: some View {
        HStack(spacing: TFSpacing.sm) {
            // Аватар — украшение: имя стоит рядом текстом, и VoiceOver не
            // должен читать «Аватар: Q» перед ним. Без этого строка
            // «Помощник владельца» озвучивалась дважды («Помощник владельца, Помощник владельца»).
            avatar
                .environment(\.tfAvatarLiveTurn, turn?.running == true)
                .accessibilityHidden(true)
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
                // Пометка «чат за задачей»: по ней видно, куда уходит
                // переписка (владелец 21.09.2026: «пометка нужна»).
                if let taskTitle, !taskTitle.isEmpty {
                    Label(taskTitle, systemImage: "checklist")
                        .tfText(.caption)
                        .foregroundStyle(Color.tfDim)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: TFSpacing.sm)
            VStack(alignment: .trailing, spacing: TFSpacing.sm) {
                if let time {
                    Text(time)
                        .tfText(.meta)
                        .foregroundStyle(Color.tfDim)
                }
                HStack(spacing: TFSpacing.xs) {
                    if let outcome = turn?.outcome { RoomTurnOutcomeDot(outcome: outcome) }
                    if unread > 0 { badge }
                }
            }
        }
        .padding(.horizontal, TFSpacing.screenHorizontal)
        .padding(.vertical, TFSpacing.sm)
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

// FlowLayout переехал в Sources/DesignSystem/Components/FlowLayout.swift
// (28.09.2026) — чипам «Сведения» на карточке задачи нужна та же раскладка.

/// «Разработчик печатает…» с анимированными точками — показывается только
/// по сигналу сервера, пока роль действительно готовит ответ (22.09.2026).
private struct RoleChatTypingLine: View {
    let names: [String]

    var body: some View {
        HStack(spacing: TFSpacing.sm) {
            Text(text)
                .tfText(.meta)
                .foregroundStyle(Color.tfSub)
                .lineLimit(1)
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    TypingDot(delay: Double(i) * TFAnimation.typingDotPhaseShift)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }

    private var text: String {
        if names.count == 1 { return "\(names[0]) печатает" }
        return "\(names.dropLast().joined(separator: ", ")) и \(names.last ?? "") печатают"
    }
}

/// Подпись/иконка по имени инструмента с сервера — сервер имя не
/// интерпретирует, это целиком презентационная таблица клиента.
enum RoleStepPresentation {
    static func label(forTool tool: String) -> String { RoleActionPresentation.forTool(tool).title }
    static func symbol(forTool tool: String) -> String { RoleActionPresentation.forTool(tool).symbol }
}

/// Строка «роль делает шаг прямо сейчас» — замена `RoleChatTypingLine`
/// в 1:1-чате, когда для роли пришёл `tool`. По мотивам референсного
/// AgentActivityFeed (26.09.2026, брейнсторм с владельцем).
struct RoleStepLine: View {
    let name: String
    let tool: String

    var body: some View {
        HStack(spacing: TFSpacing.sm) {
            Image(systemName: RoleStepPresentation.symbol(forTool: tool))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.tfSub)
                .symbolEffect(.pulse, options: .repeating)
            Text("\(name): \(RoleStepPresentation.label(forTool: tool))")
                .tfText(.meta)
                .foregroundStyle(Color.tfSub)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name): \(RoleStepPresentation.label(forTool: tool))")
    }
}

/// Аватар участника чата — фото, если оно есть у учётки, иначе инициалы.
struct RoleMemberAvatar: View {
    let member: RoleChatMember
    var size: TFAvatar.Size = .xl

    var body: some View {
        let initials = member.initials ?? String(member.name.prefix(1))
        let tint = Color(hex: member.avatarColor ?? TFHexDefault.unassigned)
        if let path = member.avatarURL,
           let url = URL(string: APIClient.baseURL.absoluteString + path) {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    TFAvatar(size: size, image: image, initials: initials, tint: tint, userID: member.id)
                } else {
                    TFAvatar(size: size, initials: initials, tint: tint, userID: member.id)
                }
            }
        } else {
            TFAvatar(size: size, initials: initials, tint: tint, userID: member.id)
        }
    }
}

/// Время в строке списка чатов: сегодня — часы, вчера — словом, дальше до
/// недели — день недели, ещё дальше — дата. Формат взят у Teams, потому что
/// строка списка читается «когда было последнее сообщение», а не «сколько
/// прошло» (`RelativeTime` в этой же папке отвечает на второй вопрос).
enum ChatListTime {
    /// Московские часы: строка списка и плашка дня внутри чата обязаны
    /// называть один и тот же день одним и тем же словом (общее правило
    /// проекта — все даты в Europe/Moscow).
    private static var moscow: TimeZone { TimeZone(identifier: "Europe/Moscow") ?? .current }
    private static func moscowCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = moscow
        return cal
    }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeZone = moscow
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let weekday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = moscow
        formatter.dateFormat = "EEE"
        return formatter
    }()

    private static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = moscow
        formatter.dateFormat = "dd.MM"
        return formatter
    }()

    static func label(_ raw: String?) -> String? {
        guard let moment = DateFormats.sqliteUTC(raw) else { return nil }
        let calendar = moscowCalendar()
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
    @State private var isLoadingRoles = true
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
                    if isLoadingRoles {
                        ProgressView("Загрузка ролей").frame(maxWidth: .infinity)
                    } else if roles.isEmpty {
                        Text("Нет ролей, доступных для чата.")
                            .tfText(.action).foregroundStyle(Color.tfDim)
                            .frame(maxWidth: .infinity)
                    }
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
                        .accessibilityIdentifier("chat.create.member.\(role.role)")
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
                // Крестик слева — закрыть, галочка справа — подтвердить:
                // так во всём приложении (владелец 21.09.2026).
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Закрыть")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await create() } } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(selectedIDs.isEmpty || isSaving)
                    .accessibilityLabel("Создать чат")
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
        isLoadingRoles = true
        defer { isLoadingRoles = false }
        do {
            // Только роли с учёткой могут быть участниками серверного чата.
            roles = try await api.roles().filter(\.canJoinChat)
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

/// Своё сообщение, которое уже видно в ленте, но сервер его ещё не принял
/// (или не принял совсем — `failed`). Как в мессенджерах: пузырь появляется
/// сразу по нажатию «Отправить», без ожидания сети.
private struct PendingOutgoing: Identifiable, Equatable {
    let id: String
    let text: String
    let attachments: [ApiChatAttachment]
    let mode: RoleChatWorkMode
    let executionMode: ChatExecutionMode
    var failed = false
}

struct RoleChatRoomScreen: View {
    @Environment(SecretaryVoiceViewModel.self) private var voiceSession: SecretaryVoiceViewModel?
    @Environment(SessionStore.self) private var session
    @Environment(TaskStore.self) private var taskStore
    @Environment(\.dismiss) private var dismiss
    @State private var chat: RoleChat
    @State private var messages: [RoleChatMessage] = []
    /// Лента получена с сервера хотя бы раз. До этого пустой `messages`
    /// значит «ещё грузится», а не «сообщений нет» (26.10.2026: при каждом
    /// открытии чата мелькала пустая страница «Пока нет сообщений»).
    @State private var hasLoadedMessages = false
    /// Последняя лента каждого открытого чата в памяти: при повторном входе
    /// переписка стоит сразу, сервер только досылает новое (26.10.2026).
    @MainActor private static var lastMessages: [String: [RoleChatMessage]] = [:]
    @State private var draft = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    /// Последнее сообщение, до которого чат уже отмечен прочитанным (LOCK-206).
    @State private var markedReadMessageID: String?
    /// Карточка задачи в сообщении (владелец 25.09.2026, этап 2 «Супер
    /// Помощника владельца») — открывает её шторкой, тот же приём, что у ChatBubble.
    @State private var pendingTaskID: String?
    @State private var voice = RoleChatVoiceController()
    @State private var isFileImporterPresented = false
    /// Меню «+» (владелец 26.09.2026): фото/файл/камера.
    @State private var isPhotoPickerPresented = false
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var isCameraPresented = false
    @State private var pendingAttachments: [ApiChatAttachment] = []
    @State private var isUploadingAttachment = false
    @State private var openingAttachmentIDs: Set<String> = []
    @State private var previewAttachmentURL: URL?
    @State private var player = VoicePlayer()
    @State private var pendingVoices: [VoiceMessage] = []
    @State private var pendingVoiceModes: [UUID: RoleChatWorkMode] = [:]
    @State private var uploadedVoiceIDs: [UUID: String] = [:]
    @State private var sendingVoiceIDs: Set<UUID> = []
    /// Режим выбора сообщений: включается из меню «…» или долгим нажатием на
    /// сообщение. В нём панель ввода заменяется полосой выбора, а тап по
    /// сообщению отмечает его (владелец 21.09.2026: «долгое нажатие максимум
    /// активирует эту функцию выбора, чтобы я потом протыкал и удалил»).
    @State private var isSelecting = false
    @State private var selectedMessageIDs: Set<String> = []
    @State private var isDeleteSelectedConfirmOpen = false
    @State private var isClearChatConfirmOpen = false
    @State private var isDetailsPresented = false
    @State private var isContentsPresented = false
    @State private var branchChat: RoleChat?
    @State private var isBranchPresented = false
    @State private var isBranching = false
    /// Сообщение, которое только что скопировали: рядом со значком на
    /// полторы секунды видна надпись «Скопировано» (владелец 14.10.2026).
    @State private var copiedMessageID: String?
    /// Текст, открытый в «Выделить текст» — системное выделение с ручками.
    @State private var selectingText: SelectableMessageText?
    @State private var contentsTargetID: String?
    @State private var realtime = RealtimeClient()
    @State private var roomEventRevision = 0
    /// Счётчик для строки рабочего плана роли (21.10.2026).
    @State private var workPlanRevision = 0
    @State private var workPlanEvent: JSONValue?
    @State private var refreshRevision = 0
    @State private var messageEventRevisions: [String: Int] = [:]
    /// Кто сейчас готовит ответ: userId → имя. Наполняет только сервер
    /// (`chats:typing`) — на время, пока роль действительно отвечает.
    @State private var typists: [String: String] = [:]
    /// Текущий инструмент по тайписту (userId → имя инструмента с сервера,
    /// например "read"/"edit"/"bash") — только пока `active == true` и
    /// сервер прислал `tool`. Живёт ровно как `typists`: без истории.
    @State private var typistTools: [String: String] = [:]
    /// Идущие ходы ролей (userId → снимок): текст по словам и шаги
    /// (`chats:live`, 27.09.2026). Рисуются и в группах.
    @State private var liveTurns: [String: RoleChatLiveTurn] = [:]
    @State private var restoredTurnIDs: Set<String> = []
    @State private var endedTurnIDs: Set<String> = []
    /// Ход дельтами (27.10.2026): состояние по роли и роли, у которых сервер
    /// уже шлёт дельты, — их старый полный снимок `chats:live` пропускаем.
    @State private var liveDeltas: [String: RoleChatLiveTurnState] = [:]
    @State private var deltaUsers: Set<String> = []
    @State private var liveSnapshotLoading = false
    /// Final messages stay in the paced queue until their text/actions are shown.
    @State private var completingTurns: [String: RoleChatLiveTurn] = [:]
    /// Строка ленты для каждого сообщения. Своя у каждого сообщения; у
    /// сообщения, ЗАВЕРШИВШЕГО живой ход, — строка хода: пока ход доигрывает
    /// ответ, сообщение скрыто, и при его появлении строка не должна
    /// пересоздаваться (пересоздание рвёт высоту и сбрасывает якорь
    /// прокрутки). Раньше id строился как «reply:автор:на что ответ», а такая
    /// пара не уникальна — ответ роли и служебные строки координации получали
    /// один id, и SwiftUI переиспользовал строки: текст пропадал, лента
    /// прыгала (владелец 22.10.2026).
    @State private var rowIDByMessageID: [String: String] = [:]
    /// Какое сообщение закрыло живой ход: ход прячет из ленты ровно ЭТО
    /// сообщение, а не все ответы того же автора подряд.
    @State private var completedMessageIDByTurn: [String: String] = [:]
    /// Свои сообщения в пути: видны сразу, до ответа сервера.
    @State private var pendingOutgoing: [PendingOutgoing] = []
    @State private var discussionStatus: RoleChatDiscussion? = nil
    /// Идёт запрос «Остановить» — кнопка не жмётся дважды.
    @State private var isStopping = false
    @State private var isSavingExecutionMode = false
    @State private var pendingVoiceExecutionModes: [UUID: ChatExecutionMode] = [:]
    @State private var workMode: RoleChatWorkMode = .work
    /// Столбец участников справа (владелец 20.10.2026) — помнит, открыт ли.
    @State private var noticeMessage: String?
    @State private var modelChoice = ChatModelChoice()
    @State private var workspaceChoice = ChatWorkspaceChoice()
    @State private var composerControls = ChatComposerControlStore()
    @State private var showsComposerCommands = false
    @State private var showsSessionPanel = false
    // SwiftUI owns the scroll position, including user interaction and resizing.
    @State private var chatScrollPosition = ScrollPosition()
    @State private var chatIsNearBottom = true
    @State private var eventBatch = ChatEventCoalescer<RealtimeEvent>()
    #if DEBUG
    @State private var chatScrollTrace = ChatScrollTrace()
    #endif
    @FocusState private var composerFocused: Bool
    private let api = APIClient()

    private var readingPreview: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["TASKFLOW_CHAT_READING_PREVIEW"] == "1"
        #else
        false
        #endif
    }

    private var pacesLiveText: Bool {
        #if DEBUG
        !readingPreview || ProcessInfo.processInfo.environment["TASKFLOW_CHAT_PACER_PREVIEW"] == "1"
        #else
        true
        #endif
    }

    #if DEBUG
    static var readingPreviewChat: RoleChat {
        if ProcessInfo.processInfo.environment["TASKFLOW_CHAT_ORDER_PREVIEW"] == "1" {
            return try! JSONDecoder().decode(RoleChat.self, from: Data(#"{"id":"reading-preview","title":"Порядок ответов","kind":"group","created_by":"preview-owner","members":[{"id":"role_code_orchestrator","name":"Оркестратор"},{"id":"role_architect","name":"Архитектор"}]}"#.utf8))
        }
        return try! JSONDecoder().decode(RoleChat.self, from: Data(#"{"id":"reading-preview","title":"Исследователь","kind":"direct","created_by":"preview-owner","members":[{"id":"role_researcher","name":"Исследователь","role_key":"researcher"}]}"#.utf8))
    }

    private static let structuredOutputPreviewJSON = #"""
    {
      "schema_version": 1,
      "ok": true,
      "output": [
        {"type": "text", "text": "Сверил **план с текущим состоянием**. Ниже — короткий итог и ход проверки."},
        {"type": "heading", "text": "Проверка результата"},
        {"type": "status", "title": "Проверка источников", "code": "passed", "text": "Все три источника доступны"},
        {"type": "table", "title": "Сверка этапов", "columns": ["Этап", "Статус", "Заметка"], "rows": [["Сверка", "Готово", "Длинная ячейка для проверки переноса текста на несколько строк внутри одной строки таблицы без наложения на соседние данные"], ["Итог", "В работе", "Следующая строка"]]},
        {"type": "progress", "title": "Готовность", "current": 3, "total": 4, "label": "3 из 4 проверок", "unit": "этапа"},
        {"type": "chart", "title": "Результаты по дням", "kind": "bar", "unit": "проверок", "points": [{"label": "Пн", "value": 4}, {"label": "Вт", "value": 7}, {"label": "Ср", "value": 5}]},
        {"type": "diagram", "title": "Ход работы", "kind": "chain", "items": [{"label": "Вход", "state": "done"}, {"label": "Анализ", "state": "done"}, {"label": "Проверка", "state": "in_progress"}, {"label": "Передача", "state": "queued"}]},
        {"type": "report", "report_kind": "intermediate", "sections": {
          "result": [{"type": "text", "text": "Подтвердил основной вывод."}],
          "work": [{"type": "list", "items": ["Сверены три источника.", "Сопоставлены этапы плана."]}],
          "checks": [{"label": "Доступность источников", "status": "passed", "detail": "Все три доступны"}],
          "limitations": [{"type": "text", "text": "Один источник обновляется с задержкой."}],
          "materials": [{"kind": "document", "title": "Исходная спецификация", "ref": "docs/spec.md"}]
        }},
        {"type": "text", "text": "Виджет из ответа:\n```widget\n{\"type\":\"card\",\"title\":\"Проверочный виджет\",\"body\":\"Отрисован внутри JSON-ответа чата.\"}\n```"}
      ],
      "artifacts": [],
      "plan_artifact": null,
      "error": null,
      "next_hint": "После проверки оформить итоговый отчёт.",
      "needs_human": false
    }
    """#

    private static var structuredOutputPreviewMessages: [RoleChatMessage] {
        let block: String
        if ProcessInfo.processInfo.environment["TASKFLOW_STRUCTURED_OUTPUT_INVALID_PREVIEW"] == "1" {
            block = "```tf-json\n{\"schema_version\":1,\"ok\":true,\"output\":[{\"type\":\"report\"}\n```"
        } else {
            block = "```tf-json\n\(structuredOutputPreviewJSON)\n```"
        }
        let envelope = (try? JSONSerialization.jsonObject(with: Data(structuredOutputPreviewJSON.utf8))) as? [String: Any]
        let serverEnvelope: [String: Any] = [
            "contract": "role.v1", "ok": true,
            "output": "Это фактический формат ответа сервера сегодня. Старые сообщения и текущие роли продолжают читаться.",
            "artifacts": [], "error": NSNull(), "next_hint": NSNull(), "needs_human": false
        ]
        let serverAnswer: [String: Any] = ["id": "structured-server-answer", "text": "Это фактический формат ответа сервера сегодня.", "role_envelope": serverEnvelope, "from_user_id": "role_researcher", "from_user_name": "Исследователь", "created_at": "2026-10-17T10:00:01Z", "sequence": 2, "reply_to_message_id": "structured-question", "is_session_marker": false]
        var answer: [String: Any] = ["id": "structured-answer", "text": block, "from_user_id": "role_researcher", "from_user_name": "Исследователь", "created_at": "2026-10-17T10:00:02Z", "sequence": 3, "reply_to_message_id": "structured-question", "is_session_marker": false]
        if ProcessInfo.processInfo.environment["TASKFLOW_STRUCTURED_OUTPUT_INVALID_PREVIEW"] != "1", let envelope {
            answer["role_envelope"] = envelope
        }
        let rows: [[String: Any]] = [
            ["id": "structured-question", "text": "Покажи, как выглядит структурированный результат.", "from_user_id": "preview-owner", "created_at": "2026-10-17T10:00:00Z", "sequence": 1, "is_session_marker": false],
            serverAnswer,
            answer
        ]
        return try! JSONDecoder().decode([RoleChatMessage].self, from: JSONSerialization.data(withJSONObject: rows))
    }

    private static func correctnessMessages(stress: Bool = false) -> [RoleChatMessage] {
        let rows: [[String: Any]] = stress ? (0..<300).map { index in
            ["id": "history-\(index)", "text": "Сообщение \(index). " + String(repeating: "Подробный текст результата для проверки прокрутки. ", count: 6),
             "from_user_id": index.isMultiple(of: 2) ? "preview-owner" : "role_architect",
             "created_at": "2026-10-11 14:20:50", "is_session_marker": false, "sequence": index]
        } : [
            ["id": "question-1", "text": "ПЕРВЫЙ ВОПРОС", "from_user_id": "preview-owner", "created_at": "2026-10-11 14:20:50", "sequence": 1, "is_session_marker": false],
            ["id": "question-2", "text": "ВТОРОЙ ВОПРОС", "from_user_id": "preview-owner", "created_at": "2026-10-11 14:20:51", "sequence": 2, "is_session_marker": false]
        ]
        return try! JSONDecoder().decode([RoleChatMessage].self, from: JSONSerialization.data(withJSONObject: rows))
    }

    private static var readingPreviewMessages: [RoleChatMessage] {
        try! JSONDecoder().decode([RoleChatMessage].self, from: Data(#"[{"id":"previous","is_session_marker":false,"text":"Расскажи о результате","from_user_id":"preview-owner","created_at":"2026-10-10T18:00:00Z"},{"id":"finished","is_session_marker":false,"text":"Ответ начинается здесь. Короткий готовый результат.","from_user_id":"role_researcher","created_at":"2026-10-10T18:01:00Z"}]"#.utf8))
    }
    private static func readingPreviewTurn(long: Bool) -> RoleChatLiveTurn {
        if ProcessInfo.processInfo.environment["TASKFLOW_ACTION_LABELS_PREVIEW"] == "1" {
            return RoleChatLiveTurn(chatID: "reading-preview", userID: "role_researcher", name: "Исследователь", startedAt: nil,
                items: RoleActionPreview.items, thinking: nil)
        }
        return         RoleChatLiveTurn(chatID: "reading-preview", userID: "role_researcher", name: "Исследователь", startedAt: nil,
            items: [.text(long ? "Ответ начинается здесь. " + String(repeating: "Подробное пояснение результата. ", count: 60) + "КОНЕЦ ДЛИННОГО ОТВЕТА" : "Ответ начинается здесь. Короткое пояснение.")], thinking: nil)
    }

    /// Пункты идущего хода для стенда шатания: реальный порядок с сервера —
    /// «размышление, шаг, шаг, размышление, шаг…» (база TaskFlow, 25.10.2026).
    private static func shakePreviewItems() -> [RoleChatLiveItem] {
        let steps: [(String, String)] = [
            ("read", "Sources/Core/Models/RoleChat.swift"),
            ("bash", "rg defaultScrollAnchor Sources"),
            ("edit", "Sources/Features/Chat/RoleActionGroup.swift"),
            ("bash", "npm run build"),
            ("read", "docs/2026-10-24-chat-smoothness-plan.md"),
            ("grep", "scrollPosition Sources/Features/Chat"),
            ("write", "docs/2026-10-25-chat-shake.md"),
            ("bash", "xcodebuild -scheme TaskFlow build"),
            ("read", "AGENT-WORK-SCOPES.md"),
            ("edit", "Sources/Features/Chat/RoleLiveTurnView.swift")
        ]
        var items: [RoleChatLiveItem] = []
        for (index, step) in steps.enumerated() {
            items.append(.thinking(RoleChatThinking(id: "thinking-\(index)", text: "Размышление \(index)", isRunning: true,
                startedAt: "2026-10-25T03:00:0\(index % 10)Z")))
            items.append(.step(RoleChatLiveStep(id: "step-\(index)", tool: step.0, detail: step.1, status: .done,
                startedAt: "2026-10-25T03:00:0\(index % 10)Z", endedAt: "2026-10-25T03:00:0\(index % 10)Z")))
        }
        return items
    }

    /// Снимок живого хода на тике стенда — повторяет фазы сервера: сначала
    /// размышление с растущим текстом, потом шаги, в конце ответ роли.
    static func shakePreviewItems(at tick: Int) -> [RoleChatLiveItem] {
        let start = "2026-10-25T03:00:00Z"
        func thinking(_ id: String, _ text: String, _ running: Bool) -> RoleChatLiveItem {
            .thinking(RoleChatThinking(id: id, text: text, isRunning: running, startedAt: start,
                endedAt: running ? nil : "2026-10-25T03:00:05Z"))
        }
        func step(_ id: String, _ tool: String, _ detail: String, _ running: Bool) -> RoleChatLiveItem {
            .step(RoleChatLiveStep(id: id, tool: tool, detail: detail, status: running ? .running : .done,
                startedAt: start, endedAt: running ? nil : "2026-10-25T03:00:05Z"))
        }
        var items: [RoleChatLiveItem] = []
        // Фаза 1: размышление (текст растёт), затем шаг.
        items.append(thinking("thinking-0", tick <= 1 ? "" : "Сверяю, что именно прыгает", tick < 4))
        if tick >= 4 { items.append(step("step-0", "read", "Sources/Core/Models/RoleChat.swift", tick < 5)) }
        // Фаза 2: второе размышление и второй шаг.
        if tick >= 6 {
            items.append(thinking("thinking-1", tick <= 6 ? "" : "Проверяю раскладку", tick < 8))
            items.append(step("step-1", "bash", "rg defaultScrollAnchor Sources", tick < 9))
        }
        // Фаза 3: ответ роли ПРИХОДИТ В СЕРЕДИНЕ хода (так и пишут роли:
        // «проверил первую часть» → снова инструменты → дописал).
        if tick >= 8 { items.append(.text("Проверил первую часть: полоса появляется вместо строки.")) }
        // Фаза 4: после текста снова инструменты.
        if tick >= 9 && tick < 11 {
            items.append(thinking("thinking-2", "", true))
        }
        if tick >= 9 { items.append(step("step-2", "edit", "Sources/Features/Chat/RoleActionGroup.swift", tick < 10)) }
        // Фаза 5: сервер прячет законченное ПУСТОЕ размышление (snapshot,
        // chatLiveTurn.ts): список пунктов снимка от этого становится короче —
        // клиент обязан пережить это без прыжка ленты.
        if tick >= 12 { items.append(.text("Проверил первую часть: полоса появляется вместо строки. Дописал вывод.")) }
        if tick >= 14 {
            items.append(.text("Проверил первую часть: полоса появляется вместо строки. Дописал вывод. Правку внёс."))
        }
        return items
    }
    #endif

    init(chat: RoleChat) {
        _chat = State(initialValue: chat)
        if let cached = Self.lastMessages[chat.id] ?? APIClient().cachedRoleChatMessages(id: chat.id) {
            _messages = State(initialValue: cached)
            _hasLoadedMessages = State(initialValue: true)
        }
        let saved = UserDefaults.standard.string(forKey: "roleChat.mode." + chat.createdBy + "." + chat.id)
        let mode = saved.flatMap(RoleChatWorkMode.init(rawValue:)) ?? .work
        _workMode = State(initialValue: RoleChatWorkMode.available(in: chat).contains(mode) ? mode : .work)
        #if DEBUG
        if readingPreview {
            // Предпросмотр задаёт ленту сразу, без запроса к серверу.
            _hasLoadedMessages = State(initialValue: true)
            let structuredOutputPreview = ProcessInfo.processInfo.environment["TASKFLOW_STRUCTURED_OUTPUT_PREVIEW"] == "1"
            _messages = State(initialValue: structuredOutputPreview ? Self.structuredOutputPreviewMessages : Array(Self.readingPreviewMessages.prefix(1)))
            if structuredOutputPreview {
                _liveTurns = State(initialValue: [:])
            } else if ProcessInfo.processInfo.environment["TASKFLOW_CHAT_ORDER_PREVIEW"] == "1" {
                _liveTurns = State(initialValue: [
                    "role_code_orchestrator": RoleChatLiveTurn(chatID:"reading-preview",userID:"role_code_orchestrator",name:"Оркестратор",startedAt:"2026-10-10T18:00:01Z",items:[.text("ПЕРВЫЙ ОТВЕТ ОРКЕСТРАТОРА")],thinking:nil),
                    "role_architect": RoleChatLiveTurn(chatID:"reading-preview",userID:"role_architect",name:"Архитектор",startedAt:"2026-10-10T18:00:02Z",items:[.text("ВТОРОЙ ОТВЕТ АРХИТЕКТОРА")],thinking:nil)
                ])
            } else {
                _liveTurns = State(initialValue: ["role_researcher": Self.readingPreviewTurn(long: false)])
            }
            if !structuredOutputPreview && ProcessInfo.processInfo.environment["TASKFLOW_CHAT_CORRECTNESS_PREVIEW"] == "1" {
                _messages = State(initialValue: Self.correctnessMessages())
                _liveTurns = State(initialValue: [
                    "role_code_orchestrator": RoleChatLiveTurn(chatID: "reading-preview", userID: "role_code_orchestrator", name: "Оркестратор", startedAt: "2026-10-11T14:20:51.500Z", items: [.text("```widget\n{\"type\":\"card\""), .text("```html\n<button>Готовый интерактив")], thinking: nil, triggerMessageID: "question-1"),
                    "role_architect": RoleChatLiveTurn(chatID: "reading-preview", userID: "role_architect", name: "Архитектор", startedAt: "2026-10-11T14:20:51.700Z", items: [.text("ВТОРОЙ ОТВЕТ")], thinking: nil, triggerMessageID: "question-2")
                ])
            }
            if !structuredOutputPreview && ProcessInfo.processInfo.environment["TASKFLOW_CHAT_STRESS_PREVIEW"] == "1" {
                _messages = State(initialValue: Self.correctnessMessages(stress: true))
                _liveTurns = State(initialValue: [:])
            }
            if !structuredOutputPreview && ProcessInfo.processInfo.environment["TASKFLOW_CHAT_SHAKE_PREVIEW"] == "1" {
                // Стенд шатания (25.10.2026): длинная переписка + идущий ход
                // роли. Пункты повторяют реальный порядок с сервера —
                // «размышление, шаг, шаг, размышление, шаг…» — pacer
                // проявляет их по одному, как в бою.
                _messages = State(initialValue: Self.correctnessMessages(stress: true))
                _liveTurns = State(initialValue: [
                    "role_builder": RoleChatLiveTurn(chatID: "reading-preview", userID: "role_builder",
                        name: "Разработчик", startedAt: "2026-10-25T03:00:00Z",
                        items: Self.shakePreviewItems(at: 0), thinking: nil)
                ])
            }
        }
        #endif
    }

    var body: some View {
        ZStack {
            // Владелец 25.09.2026: фон экрана ЗДЕСЬ — на самом верхнем
            // уровне, а не за панелью композера, и без ограничения edges
            // (регион .keyboard входит в .ignoresSafeArea() по умолчанию).
            // Иначе в углах системной клавиатуры (у неё скруглённые верхние
            // углы) сквозь скругление просвечивал фон корневого UIWindow
            // (чёрный) — композер стоит НАД клавиатурой, его собственный фон
            // до этого места физически не достаёт.
            Color.tfBackground.ignoresSafeArea()
            composerRoom
        }
        .quickLookPreview($previewAttachmentURL)
        .task(id: chat.id + ":" + (chat.taskID ?? "") + ":" + String(workPlanRevision) + ":" + String(refreshRevision)) {
            await loadDiscussionStatus()
        }
        .onChange(of: previewAttachmentURL) { oldURL, newURL in
            if newURL == nil, let oldURL {
                try? FileManager.default.removeItem(at: oldURL.deletingLastPathComponent())
            }
        }
        #if DEBUG
        .task { await runShakePreview() }
        #endif
    }

    #if DEBUG
    /// Стенд шатания (25.10.2026): снимки живого хода приходят каждые 150 мс,
    /// как их шлёт сервер (LIVE_BROADCAST_MS). Клиент тянет их тем же кодом,
    /// что и в бою: pacer проявляет действия, лента привязана к низу.
    private func runShakePreview() async {
        guard ProcessInfo.processInfo.environment["TASKFLOW_CHAT_SHAKE_PREVIEW"] == "1" else { return }
        for tick in 1...24 {
            try? await Task.sleep(for: .milliseconds(150))
            if tick == 20 {
                // Ход закончился: живой пузырь сменяется ответом роли.
                liveTurns["role_builder"] = nil
                let rows: [[String: Any]] = [
                    ["id": "preview-answer", "text": "Проверил первую часть: полоса появляется вместо строки. Дописал вывод. Правку внёс.",
                     "from_user_id": "role_builder", "from_user_name": "Разработчик",
                     "created_at": "2026-10-25T03:00:10Z", "is_session_marker": false]
                ]
                let replies = try! JSONDecoder().decode([RoleChatMessage].self,
                                                       from: JSONSerialization.data(withJSONObject: rows))
                for reply in replies { insertIncoming(reply) }
                continue
            }
            liveTurns["role_builder"] = RoleChatLiveTurn(chatID: "reading-preview", userID: "role_builder",
                name: "Разработчик", startedAt: "2026-10-25T03:00:00Z",
                items: Self.shakePreviewItems(at: tick), thinking: nil)
        }
    }
    #endif

    /// Snapshot belongs to this room; cancelled requests cannot replace it.
    private func loadDiscussionStatus() async {
        let chatID = chat.id
        guard let taskID = chat.taskID else {
            discussionStatus = nil
            return
        }
        do {
            let all = try await api.taskDiscussions(taskID: taskID)
            guard !Task.isCancelled, chat.id == chatID, chat.taskID == taskID else { return }
            discussionStatus = all.first { $0.chatID == chatID }
        } catch {
            guard !Task.isCancelled, chat.id == chatID, chat.taskID == taskID else { return }
            // Older servers have no discussion routes. Never invent a delivery state.
            discussionStatus = nil
        }
    }

    private var discussionStatusBar: some View {
        Group {
            if let discussion = discussionStatus {
                VStack(alignment: .leading, spacing: TFSpacing.xs) {
                    Text(discussion.statusTitle).tfText(.action)
                    if let detail = discussion.statusDetail {
                        Text(detail).tfText(.meta).foregroundStyle(Color.tfDim)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, TFSpacing.lg)
                .padding(.vertical, TFSpacing.xs)
                .hintAnchor(HintAnchorID.chatDiscussionDelivery)
                .accessibilityIdentifier("chat.discussionStatus")
            }
        }
    }

    /// Личку ролей владелец читает, не будучи участником: писать в неё нельзя.
    private var isReadOnlyDirectRoom: Bool {
        chat.roomKind == "dm" && !chat.members.contains { $0.id == session.currentUser?.id }
    }

    private var composerContent: some View {
        VStack(spacing: 0) {
            // Панель участников переехала в корень раздела «Чаты» и стала
            // панелью комнат (владелец 21.10.2026); состав чата — в «О чате».
            messageScroll
            discussionStatusBar
            // Рабочий план роли в этой сессии — над полем ввода (21.10.2026).
            ChatWorkPlanStrip(chatID: chat.id, members: chat.members, revision: workPlanRevision, event: workPlanEvent)
            if !mentionCandidates.isEmpty {
                mentionSuggestions
            }
            let slashCommands = ChatSlashCommand.suggestions(for: draft, from: composerControls.commands)
            if !slashCommands.isEmpty {
                ChatSlashSuggestions(commands: slashCommands) { command in
                    draft = command.inserting(into: draft)
                    composerFocused = true
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
            if isSelecting {
                selectionBar
            } else if isReadOnlyDirectRoom {
                // Личка двух ролей: владелец читает, пишет — в личной комнате роли.
                Text("Личная переписка ролей — только чтение")
                    .tfText(.action)
                    .foregroundStyle(Color.tfDim)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, TFSpacing.md)
                    .accessibilityIdentifier("chat.readOnlyDirect")
            } else {
                ChatVoiceComposer(
                    text: $draft,
                    placeholder: "Сообщение",
                    canSendText: (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingAttachments.isEmpty)
                        && !isSending && !isUploadingAttachment && !isSavingExecutionMode
                        && (!chat.isAssistantOnly || (modelChoice.isReady && !modelChoice.isSaving)),
                    voice: voice,
                    onAttachmentSource: { source in
                        switch source {
                        case .photo: isPhotoPickerPresented = true
                        case .file: isFileImporterPresented = true
                        case .camera: isCameraPresented = true
                        }
                    },
                    onSendText: { Task { await send() } },
                    onSendVoice: sendVoicePreview,
                    onDiscardVoice: { _ in },
                    workMode: $workMode,
                    executionMode: chat.isAssistantOnly ? nil : Binding(get: { chat.executionMode }, set: { mode in
                        Task { await changeExecutionMode(mode) }
                    }),
                    canChangeExecutionMode: !isSavingExecutionMode && !isSending && !isUploadingAttachment,
                    availableModes: RoleChatWorkMode.available(in: chat),
                    modelChoice: modelChoice,
                    workspaceChoice: workspaceChoice,
                    sessionControls: chat.isAssistantOnly ? AnyView(
                        Button { showsSessionPanel = true } label: {
                            Label("Сессия", systemImage: "bubble.left.and.text.bubble.right")
                                .tfText(.caption)
                                .frame(minWidth: 40, minHeight: 40)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("chat.session")
                        .hintAnchor(HintAnchorID.chatSession)
                    ) : nil,
                    onShowCommands: { showsComposerCommands = true },
                    contextControls: chat.composerRoleKeys.isEmpty ? nil : AnyView(HStack(spacing: 0) {
                        ForEach(chat.members.filter { $0.roleKey != nil || $0.id == "u-secretary" || $0.id.hasPrefix("role_") }) { member in
                            ChatContextControl(snapshot: composerControls.contexts[member.id],
                                roleName: chat.composerRoleKeys.count > 1 ? member.name : nil,
                                loadError: composerControls.errorText,
                                onRefresh: { Task { await composerControls.load(chat: chat) } })
                        }
                    }),
                    // Собачка: роли этого чата, кроме меня. Тот же справочник,
                    // что у подсказок при наборе «@» (RoleChatsScreen
                    // mentionCandidates), только берётся по нажатию, а не по
                    // набору (владелец 11.10.2026: «ее все время от руки
                    // писать не охоту»).
                    // Вдвоём выбирать не из кого — кнопка появляется, когда
                    // участников больше двух (владелец 14.10.2026).
                    mentionCandidates: chat.members.count > 2
                        ? chat.members.filter { $0.id != session.currentUser?.id } : [],
                    isResponding: !liveTurns.isEmpty || !typists.isEmpty,
                    isStopping: isStopping,
                    onStop: { Task { await stopTurns() } },
                    focus: $composerFocused
                )
                // Панель ввода ниже на 8 pt (владелец 27.10.2026: «чуть выше
                // требуемого»); общий компонент панели не трогаем.
                .padding(.bottom, -8)
                .disabled(isSavingExecutionMode)
            }
        }
    }

    private var composerNavigation: some View {
        composerContent
        .tint(Color.tfText)
        .navigationTitle(chat.displayTitle(excluding: session.currentUser?.id))
        .navigationBarTitleDisplayMode(.inline)
        // Ветка от сообщения — отдельный чат поверх основного; «назад»
        // возвращает в основной разговор (владелец 14.10.2026).
        .navigationDestination(isPresented: $isBranchPresented) {
            if let branchChat { RoleChatRoomScreen(chat: branchChat) }
        }
        .sheet(item: $selectingText) { item in
            SelectableTextSheet(text: item.text)
        }
        .sheet(isPresented: $isContentsPresented) {
            RoleChatContentsSheet(messages: visibleMessages, currentUserID: session.currentUser?.id) { id in
                isContentsPresented = false
                contentsTargetID = id
            }
        }
        .toolbar {
            #if DEBUG
            if readingPreview && ProcessInfo.processInfo.environment["TASKFLOW_MEMBER_SWIPE_PREVIEW"] != "1" {
                if ProcessInfo.processInfo.environment["TASKFLOW_CHAT_CORRECTNESS_PREVIEW"] == "1" {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Сигнал конца") {
                            for userID in Array(liveTurns.keys) { markLiveTurnEnded(userID) }
                        }.accessibilityIdentifier("chat.preview.end-live")
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Завершить оба") {
                            let rows: [[String: Any]] = [
                                ["id": "answer-1", "text": "ПЕРВЫЙ ОТВЕТ\n\n```widget\n{\"type\":\"card\",\"title\":\"Готовый виджет\",\"body\":\"Содержимое уже готово\"}\n```\n\n```html\n<button onclick=\"this.textContent='Нажато'\">Готовый интерактив</button>\n```", "from_user_id": "role_code_orchestrator", "created_at": "2026-10-11 14:20:52", "sequence": 3, "reply_to_message_id": "question-1", "is_session_marker": false],
                                ["id": "answer-2", "text": "ВТОРОЙ ОТВЕТ", "from_user_id": "role_architect", "created_at": "2026-10-11 14:20:51", "sequence": 4, "reply_to_message_id": "question-2", "is_session_marker": false]
                            ]
                            let replies = try! JSONDecoder().decode([RoleChatMessage].self, from: JSONSerialization.data(withJSONObject: rows))
                            for reply in replies { insertIncoming(reply) }
                        }.accessibilityIdentifier("chat.preview.complete-both")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") {
                        let done = try! JSONDecoder().decode(RoleChatMessage.self, from: Data(#"{"id":"done-orchestrator","from_user_id":"role_code_orchestrator","from_user_name":"Оркестратор","text":"ПЕРВЫЙ ОТВЕТ ОРКЕСТРАТОРА","created_at":"2026-10-10T18:00:03Z","is_session_marker":false}"#.utf8))
                        insertIncoming(done)
                    }.accessibilityIdentifier("chat.preview.finish-first")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        liveTurns["role_researcher"] = Self.readingPreviewTurn(long: true)
                    } label: { Image(systemName: "arrow.down.to.line") }
                    .accessibilityLabel("Длинный ответ")
                    Button {
                        let message = Self.readingPreviewMessages.last!
                        messages.append(message)
                        liveTurns = [:]
                    } label: { Image(systemName: "checkmark") }
                    .accessibilityLabel("Завершить ответ")
                }
            }
            #endif

            // Шапка — ещё и вход в состав: владелец 21.09.2026 — «нет
            // возможности понять, кто в этом чате присутствует». Тап открывает
            // название и участников.
            ToolbarItem(placement: .principal) {
                Button { isDetailsPresented = true } label: {
                    HStack(spacing: TFSpacing.sm) {
                        if chat.kind == "group" {
                            TFGroupAvatar(identity: chat.projectID ?? chat.id, size: .md)
                        }
                        VStack(spacing: 1) {
                        Text(chat.displayTitle(excluding: session.currentUser?.id))
                            // Кегль из шкалы (было системное `.headline`):
                            // ступень `.title` даёт те же 17 semibold.
                            .tfText(.title)
                            .lineLimit(1)
                        Text("\(chat.members.count) \(participantsWord(chat.members.count))")
                            .tfText(.caption)
                            .foregroundStyle(Color.tfSub)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Чат: название и участники")
            }
            if isSelecting {
                ToolbarItem(placement: .topBarLeading) {
                    Button { exitSelection() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Отменить выбор")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        isDeleteSelectedConfirmOpen = true
                    } label: {
                        Text(selectedMessageIDs.isEmpty
                             ? "Удалить"
                             : "Удалить (\(selectedMessageIDs.count))")
                    }
                    .disabled(selectedMessageIDs.isEmpty)
                }
            } else {
                if session.currentUser?.role == .owner, chat.kind == "direct",
                   chat.members.contains(where: { $0.id == "u-secretary" }), let voiceSession {
                    ToolbarItem(placement: .topBarTrailing) {
                        TFIconButton("waveform", label: "Голосовой разговор с Помощником владельца") {
                            Task { await voiceSession.start(chatID: chat.id) }
                        }
                        .accessibilityIdentifier("chat.voice.start")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isContentsPresented = true } label: {
                        Image(systemName: "list.bullet.indent")
                    }
                    .accessibilityLabel("Содержание чата")
                    .accessibilityIdentifier("chat.contents")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        // Меню «…» построено как соседние меню приложения
                        // (`ChatScreen`, `TodaySectionView`, `VoiceModelsScreen`):
                        // действия — `Label`, связанные группы — `Section`,
                        // выбор из списка — ПОДМЕНЮ `Menu`, выбранное отмечено
                        // галочкой (владелец 21.09.2026: «посмотри, как у нас
                        // троеточия и подменю, и сделай ровно так же»).
                        Section {
                            // Привязка к задаче — только создателю: сервер
                            // остальным отвечает 403.
                            if chat.createdBy == session.currentUser?.id {
                                Menu {
                                    if taskStore.tasks.isEmpty {
                                        Text("Нет задач")
                                    } else {
                                        ForEach(taskStore.tasks) { task in
                                            Button {
                                                Task { await bindTask(task.id) }
                                            } label: {
                                                if task.id == chat.taskID {
                                                    Label(task.title, systemImage: "checkmark")
                                                } else {
                                                    Text(task.title)
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    Label(chat.taskID == nil ? "Привязать к задаче" : "Сменить задачу",
                                          systemImage: "checklist")
                                }
                                if chat.taskID != nil {
                                    Button { Task { await bindTask(nil) } } label: {
                                        Label("Отвязать от задачи", systemImage: "xmark.circle")
                                    }
                                }
                            }
                        }
                        Section {
                            Button { enterSelection(selecting: nil) } label: {
                                Label("Выбрать сообщения", systemImage: "checkmark.circle")
                            }
                            // Владелец 25.09.2026: «очистить чат не надо —
                            // надо по сессиям потом полистать». История не
                            // трогается, сбрасывается только память роли.
                            if !chat.isAssistantOnly {
                                Button { Task { await newSession() } } label: {
                                    Label("Новая сессия", systemImage: "arrow.triangle.2.circlepath")
                                }
                                compactMenuItem
                            }
                            ShareLink(item: RoleChatTranscript(title: chat.displayTitle(excluding: session.currentUser?.id),
                                                               messages: visibleMessages),
                                      preview: SharePreview("Чат")) {
                                Label("Экспорт", systemImage: "square.and.arrow.up")
                            }
                        }
                        if session.currentUser?.role == .owner {
                            Section {
                                Button(role: .destructive) {
                                    isClearChatConfirmOpen = true
                                } label: {
                                    Label("Удалить все сообщения", systemImage: "trash")
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("Ещё")
                }
            }
        }
        .safeAreaInset(edge: .top) {
            if let taskID = chat.taskID {
                TaskCardLink(taskID: taskID) {
                    Label { Text("Задача чата").foregroundStyle(Color.tfText) } icon: { Image(systemName: "checklist").foregroundStyle(Color.tfRed) }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(TFSpacing.md)
                }
                .background(Color.tfCard)
            }
        }
    }

    private var composerSession: some View {
        composerNavigation
        .task { await connectRealtime() }
        .onDisappear { realtime.disconnect() }
        .task {
            if !readingPreview { await refresh() }
        }
        .alert("Ошибка чата", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Повторить") { Task { await refresh() } }
            Button("Закрыть", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .alert(noticeMessage ?? "", isPresented: Binding(
            get: { noticeMessage != nil },
            set: { if !$0 { noticeMessage = nil } }
        )) { Button("Готово", role: .cancel) { noticeMessage = nil } }
        .sheet(isPresented: $isDetailsPresented) {
            RoleChatDetailsSheet(chat: chat, onChanged: { updated in
                chat = updated
                Task { await refresh() }
            }, onDeleted: { dismiss() })
        }
        .confirmationDialog("Удалить выбранные сообщения?", isPresented: $isDeleteSelectedConfirmOpen,
                            titleVisibility: .visible) {
            Button("Удалить (\(selectedMessageIDs.count))", role: .destructive) {
                Task { await deleteSelected() }
            }
        }
        .confirmationDialog("Удалить все сообщения чата?", isPresented: $isClearChatConfirmOpen,
                            titleVisibility: .visible) {
            Button("Удалить все", role: .destructive) { Task { await clearChat() } }
        }
    }

    private var composerRoom: some View {
        composerSession
        .fileImporter(isPresented: $isFileImporterPresented, allowedContentTypes: [.item]) { result in
            handleFileImport(result)
        }
        .photosPicker(isPresented: $isPhotoPickerPresented, selection: $photoPickerItem, matching: .images)
        .onChange(of: photoPickerItem) { _, item in
            guard let item else { return }
            photoPickerItem = nil
            Task { await uploadPickedPhoto(item) }
        }
        .fullScreenCover(isPresented: $isCameraPresented) {
            CameraCaptureView(
                onCapture: { image in
                    isCameraPresented = false
                    Task { await uploadCameraPhoto(image) }
                },
                onCancel: { isCameraPresented = false }
            )
            .ignoresSafeArea()
        }
        .onChange(of: voice.errorMessage) { _, reason in
            if let reason { errorMessage = reason }
        }
        .onChange(of: workMode) { _, mode in
            UserDefaults.standard.set(mode.rawValue, forKey: "roleChat.mode." + chat.createdBy + "." + chat.id)
        }
        .onChange(of: chat.members.map(\.id)) { _, _ in
            if !RoleChatWorkMode.available(in: chat).contains(workMode) { workMode = .work }
        }
        .task(id: chat.members.map(\.id)) {
            await modelChoice.load(chat: chat)
            await workspaceChoice.load(chat: chat)
        }
        .task(id: chat.members.map(\.id).joined(separator: ":") + ":" + (messages.last?.id ?? "")) {
            await composerControls.load(chat: chat)
        }
        .sheet(isPresented: $showsSessionPanel) {
            ChatSessionPanel(chat: chat, choice: modelChoice, workspace: workspaceChoice,
                context: composerControls.contexts["u-secretary"], controls: composerControls,
                isWorking: !liveTurns.isEmpty || !typists.isEmpty,
                onRefresh: {
                    await modelChoice.load(chat: chat)
                    await workspaceChoice.load(chat: chat)
                    await composerControls.load(chat: chat)
                },
                onRename: { title in
                    do { chat = try await api.renameRoleChat(id: chat.id, title: title) }
                    catch { errorMessage = error.localizedDescription }
                },
                onNewSession: { Task { await createAssistantSession() } },
                onCompact: {
                    if let member = chat.members.first(where: { $0.id == "u-secretary" || $0.roleKey == "secretary" }) {
                        await compact(member)
                    }
                },
                onResetContext: { await newSession(roleID: "u-secretary") },
                onClose: {
                    do { chat = try await api.closeRoleChat(id: chat.id, closed: true); dismiss() }
                    catch { errorMessage = error.localizedDescription }
                },
                onSelectCommand: { command in
                    draft = command.inserting(into: draft)
                    composerFocused = true
                })
        }
        .sheet(isPresented: $showsComposerCommands) {
            ChatCommandPicker(commands: composerControls.commands, errorText: composerControls.errorText,
                              onRefresh: { Task { await composerControls.load(chat: chat) } }) { command in
                draft = command.inserting(into: draft)
                composerFocused = true
            }
        }
        .onDisappear { voice.cancel(); player.stop() }
        .taskCardSheet(taskID: $pendingTaskID)
    }

    private func connectRealtime() async {
        if readingPreview { return }
        // Живые события (22.09.2026): новое сообщение этого чата — сразу
        // перечитываем ленту; «печатает» — ровно по сигналу сервера.
        let chatID = chat.id
        let apply: (RealtimeEvent) -> Void = { event in
            switch event {
            case .unknown("chat:withdrawn", .object(let payload)) where payload["chat_id"]?.stringValue == chatID:
                if let id = payload["message_id"]?.stringValue {
                    messages.removeAll { $0.id == id }
                    selectedMessageIDs.remove(id)
                }
            case .unknown("chat:work_plan", let payload):
                workPlanEvent = payload
            case .roleChatMessage(let id, let message) where id == chatID:
                roomEventRevision += 1
                workPlanRevision += 1
                // Сервер прислал готовое сообщение — вставляем его сразу,
                // без перечитывания ленты (01.10.2026: пузырь ответа
                // появлялся с задержкой и лента вздрагивала).
                if let message { insertIncoming(message) } else { Task { await refresh() } }
            case .roleChatTyping(let id, let userID, let name, let active, let tool) where id == chatID:
                roomEventRevision += 1
                if active {
                    typists[userID] = name.isEmpty ? "Участник" : name
                    typistTools[userID] = tool
                } else {
                    typists[userID] = nil
                    typistTools[userID] = nil
                }
            case .roleChatLive(let id, let userID, let turn, let messageID) where id == chatID:
                // Роль уже идёт дельтами — полный снимок того же хода лишний.
                guard !deltaUsers.contains(userID) else { return }
                roomEventRevision += 1
                if let turn {
                    showLiveTurn(turn, userID: userID)
                } else {
                    endLiveTurn(userID: userID, messageID: messageID)
                }
            case .roleChatLiveDelta(let delta) where delta.chatID == chatID:
                roomEventRevision += 1
                applyLiveDelta(delta)
            case .roleChatLiveInterrupt(let event) where event.chatID == chatID:
                // Ход ждёт ответа владельца: в живом ходе — «Ждёт вашего
                // ответа», кнопки — карточка вопроса из его сообщения.
                guard var state = liveDeltas[event.userID], state.apply(event) else { return }
                roomEventRevision += 1
                liveDeltas[event.userID] = state
                showLiveTurn(state.liveTurn, userID: event.userID)
            default:
                break
            }
        }
        // События, пришедшие почти разом (ход роли, «печатает», готовое
        // сообщение), применяются одним обновлением: лента перекладывается
        // один раз, а не на каждое событие (владелец 27.10.2026).
        realtime.onEvent = { event in
            guard eventBatch.enqueue(event) else { return }
            Task { @MainActor in
                try? await Task.sleep(for: ChatEventCoalescer<RealtimeEvent>.window)
                eventBatch.drain().forEach(apply)
            }
        }
        realtime.onReconnected = {
            // За время разрыва сигнал «закончил» мог потеряться.
            typists = [:]
            typistTools = [:]
            Task {
                await refresh()
                await loadLiveTurns()
            }
        }
        realtime.connect()
        // Чат открыт посреди ответа роли — подтягиваем, что уже сделано.
        await loadLiveTurns()
    }

    private func showLiveTurn(_ turn: RoleChatLiveTurn, userID: String) {
        guard !endedTurnIDs.contains(turn.playbackID) else { return }
        if let trigger = turn.triggerMessageID, hasAnswer(on: trigger, from: userID) { return }
        liveTurns[userID] = turn
    }

    private func endLiveTurn(userID: String, messageID: String?) {
        if let messageID, let message = messages.first(where: { $0.id == messageID }) {
            // REST may have loaded the final message before chat:new.
            // Use the same completion path as the socket delivery.
            insertIncoming(message)
            return
        }
        typists[userID] = nil
        typistTools[userID] = nil
        markLiveTurnEnded(userID)
        // Ответа в ленте ещё нет (ход без ответа, потерянный
        // chat:new или старый сервер): сначала дочитываем
        // ленту и только потом убираем живой пузырь — без
        // мгновения пустоты между ними.
        let finishedStart: String? = liveTurns[userID]?.startedAt
        Task { await finishLiveTurn(userID: userID, messageID: messageID, startedAt: finishedStart) }
    }

    /// Ход дельтами: start заводит состояние, patch дописывает, end
    /// заканчивает ход тем же путём, что и старый снимок. Пропуск номера или
    /// незнакомый ход — перечитываем снимок.
    private func applyLiveDelta(_ delta: RoleChatLiveDelta) {
        let userID = delta.userID
        deltaUsers.insert(userID)
        if case .start(let state) = delta {
            liveDeltas[userID] = state
            showLiveTurn(state.liveTurn, userID: userID)
            return
        }
        guard var state = liveDeltas[userID] else {
            Task { await loadLiveTurns() }
            return
        }
        switch state.apply(delta) {
        case .applied:
            liveDeltas[userID] = state
            showLiveTurn(state.liveTurn, userID: userID)
        case .ended(let messageID):
            liveDeltas[userID] = nil
            endLiveTurn(userID: userID, messageID: messageID)
        case .needsSnapshot:
            Task { await loadLiveTurns() }
        case .ignored:
            break
        }
    }

    private func finishLiveTurn(userID: String, messageID: String?, startedAt: String?) async {
        await refresh()
        let currentStart: String? = liveTurns[userID]?.startedAt
        guard currentStart == startedAt else { return }
        if let messageID, let message = messages.first(where: { $0.id == messageID }) {
            insertIncoming(message)
        } else {
            liveTurns[userID] = nil
        }
    }

    private var messageScroll: some View {
        let orderedFeed = feedItems
        let dayDividers = dayDividerTitles(orderedFeed)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: TFSpacing.md) {
                if messages.isEmpty && hasLoadedMessages {
                    ContentUnavailableView("Пока нет сообщений", systemImage: "bubble.left",
                                           description: Text("Напишите первое сообщение."))
                } else if messages.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, TFSpacing.xl)
                        .accessibilityLabel("Загрузка сообщений")
                }
                // Перед первым сообщением нового дня — полоса с датой
                // («когда заканчивается день», владелец 03.10.2026).
                // Один элемент ленты — одна вью: полоса даты и строка лежат в
                // общем контейнере, иначе LazyVStack ошибается в оценке высот
                // и лента дёргается при прокрутке вверх (27.10.2026).
                ForEach(orderedFeed) { item in
                    VStack(alignment: .leading, spacing: TFSpacing.md) {
                        if let title = dayDividers[item.id] {
                            ChatFeedDivider(title: title)
                        }
                        if let turn = item.turn {
                            liveTurnRow(turn)
                        } else if let pending = item.pending {
                            outgoingRow(pendingMessage(pending), pending: pending)
                        } else if let message = item.message {
                            if isOutgoingRow(item) {
                                outgoingRow(message, pending: nil)
                            } else {
                                messageRow(message)
                            }
                        }
                    }
                    .id(item.id)
                    .transition(.opacity)
                }
                // Владелец 26.09.2026: плашки быстрых ответов должны
                // крепиться к сообщению роли, а не болтаться отдельным
                // оверлеем над полем ввода — переехали в саму ленту,
                // сразу под последним сообщением, и скроллятся вместе с
                // перепиской.
                //
                // 26.10.2026: плашка рисуется у СВОЕГО сообщения (в
                // `flatReplyRow`), а не отдельной строкой в конце ленты:
                // раньше проверка «последнее видимое сообщение» гасила
                // варианты, когда следом лежало служебное сообщение, —
                // вопрос стоял, а кнопок не было.
                ForEach(pendingVoices) { message in
                    VStack(alignment: .trailing, spacing: 4) {
                        // Ещё не отправленное голосовое: имя и иконка
                        // берутся из текущей сессии — сообщения с
                        // сервера для него пока нет.
                        VoiceMessageBubble(
                            message: message,
                            player: player,
                            style: RoleChatVoiceStyle.own,
                            header: AnyView(ownSenderLine)
                        )
                        if sendingVoiceIDs.contains(message.id) { ProgressView("Отправка…") }
                        else if message.transcript != .pending {
                            Button("Повторить отправку") { Task { await sendVoice(message.id) } }
                                .tfText(.meta)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .id(message.id)
                }
                if !visibleTypists.isEmpty {
                    if chat.kind != "group", let onlyUserID = visibleTypists.keys.first,
                       let tool = typingTool(onlyUserID) {
                        RoleStepLine(name: visibleTypists[onlyUserID] ?? "Роль", tool: tool)
                            .id("typing-line")
                            .transition(.opacity)
                    } else {
                        RoleChatTypingLine(names: visibleTypists.values.sorted())
                            .id("typing-line")
                            .transition(.opacity)
                    }
                }
            }
            .scrollTargetLayout()
            // Новые строки и строка «печатает…» появляются плавно, а не
            // рывком на свою высоту (27.10.2026).
            .animation(TFMotion.standard, value: orderedFeed.map(\.id))
            .animation(TFMotion.standard, value: visibleTypists.isEmpty)
        }
        .contentMargins(TFSpacing.lg, for: .scrollContent)
        .scrollPosition($chatScrollPosition, anchor: .bottom)
        .scrollDismissesKeyboard(.interactively)
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .defaultScrollAnchor(.bottom, for: .alignment)
        // Лента держится за низ, пока владелец сам не отлистал вверх. Раньше
        // условие было «не листал И у низа»: высокий блок (живой ход, ответ)
        // появлялся разом, лента на миг оказывалась «не у низа» и отпускала
        // привязку — новое уходило под строку контекста (владелец 26.10.2026).
        .defaultScrollAnchor(!chatScrollPosition.isPositionedByUser || chatIsNearBottom ? .bottom : nil, for: .sizeChanges)
        .background(Color.tfBackground)
        .contentShape(Rectangle())
        .onTapGesture { composerFocused = false }
        .accessibilityIdentifier("chat.feed")
        .tfSoftBottomScrollEdge()
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentSize.height - geometry.visibleRect.maxY <= 80
        } action: { _, nearBottom in
            // Observation only: this does not issue any scroll commands.
            chatIsNearBottom = nearBottom
        }
        #if DEBUG
        .onScrollGeometryChange(for: ChatScrollGeometry.self) { geometry in
            ChatScrollGeometry(offsetY: Double(geometry.contentOffset.y),
                               contentHeight: Double(geometry.contentSize.height),
                               viewportHeight: Double(geometry.containerSize.height),
                               visibleMaxY: Double(geometry.visibleRect.maxY),
                               offsetX: Double(geometry.contentOffset.x),
                               contentWidth: Double(geometry.contentSize.width),
                               viewportWidth: Double(geometry.containerSize.width))
        } action: { _, geometry in
            chatScrollTrace.record(geometry, rowIDs: orderedFeed.map(\.id),
                liveTurnCount: visibleLiveTurns.count, nearBottom: chatIsNearBottom,
                positionedByUser: chatScrollPosition.isPositionedByUser)
        }
        .onDisappear { chatScrollTrace.flush() }
        // Контекст замеров: фаза прокрутки (сдвиг в idle — не жест),
        // клавиатура и фокус поля ввода (владелец 27.10.2026).
        .onScrollPhaseChange { _, phase in
            chatScrollTrace.update({ $0.phase = String(describing: phase) }, event: "phase")
        }
        .onChange(of: composerFocused) { _, focused in
            chatScrollTrace.update({ $0.composerFocused = focused }, event: "focus")
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            let frame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? .zero
            let screen = note.object as? UIScreen
            let height = screen.map { max(0, $0.bounds.maxY - frame.minY) } ?? frame.height
            chatScrollTrace.update({ $0.keyboardHeight = Double(height) }, event: "keyboard")
        }
        #endif
        .overlay(alignment: .bottom) {
            if !chatIsNearBottom && !isSelecting {
                ChatScrollToBottomButton {
                    chatScrollPosition.scrollTo(edge: .bottom)
                }
                .padding(.bottom, TFSpacing.md)
            }
        }
        .onChange(of: contentsTargetID) { _, id in
            guard let id else { return }
            let feedID = feedItems.first { $0.message?.id == id }?.id ?? id
            chatScrollPosition.scrollTo(id: feedID, anchor: .top)
            contentsTargetID = nil
        }
    }

    /// Живой ход виден и в группе: у каждого ответа своя подпись роли.
    private var visibleLiveTurns: [RoleChatLiveTurn] {
        return (Array(liveTurns.values) + Array(completingTurns.values))
            .filter { !$0.items.isEmpty || $0.thinking != nil }
            .sorted { ($0.startDate ?? .distantFuture, $0.playbackID) < ($1.startDate ?? .distantFuture, $1.playbackID) }
    }

    private var visibleMessages: [RoleChatMessage] {
        messages.filter { message in
            // Служебная строка координации после ответа исчезает из ленты
            // (владелец 21.10.2026): ответ получен — показывать нечего.
            if message.isFinishedCoordinationRow { return false }
            // Прячем только то сообщение, которое закрыло живой ход: пока
            // ход доигрывает ответ, его текст уже в живом пузыре. Раньше
            // скрывалось ЛЮБОЕ сообщение того же автора, попавшее в окно
            // времени хода, — из-за этого из ленты пропадали ответы.
            return !completingTurns.keys.contains { playbackID in
                if let completed = completedMessageIDByTurn[playbackID] { return completed == message.id }
                // Ход восстановлен после перезапуска приложения: какое
                // сообщение его закрыло — неизвестно, берём прежнее правило.
                guard let turn = completingTurns[playbackID] else { return false }
                return turn.isCompleted(by: message)
            }
        }
    }

    private struct FeedItem: Identifiable {
        let id: String
        let dateString: String?
        let position: Int
        let message: RoleChatMessage?
        let turn: RoleChatLiveTurn?
        var pending: PendingOutgoing? = nil
        let date: Date
    }
    private var feedItems: [FeedItem] {
        let history = visibleMessages.enumerated().map { index, message in
            return FeedItem(id: feedItemID(for: message),
                dateString: message.createdAt, position: index, message: message, turn: nil,
                date: RoleChatTime.date(message.createdAt) ?? .distantPast)
        }
        let live = visibleLiveTurns.enumerated().map { index, turn in
            FeedItem(id: feedItemID(for: turn), dateString: turn.startedAt,
                position: messages.count + index, message: nil, turn: turn,
                date: turn.startDate ?? .distantFuture)
        }
        // История уже упорядочена серверной последовательностью. Не сортируем
        // её повторно по часам: точность даты и порядок доставки различаются.
        let plan = ChatTimelineProjection.project(
            messages: visibleMessages.map { .init(id: $0.id) },
            turns: visibleLiveTurns.map {
                .init(playbackID: $0.playbackID, anchorMessageID: $0.triggerMessageID)
            })
        // Keep the existing row IDs when a live reply becomes its saved message.
        var messagesByID: [String: FeedItem] = [:]
        for item in history {
            if let id = item.message?.id { messagesByID[id] = item }
        }
        var turnsByID: [String: FeedItem] = [:]
        for item in live {
            if let id = item.turn?.playbackID { turnsByID[id] = item }
        }
        let timeline: [FeedItem] = plan.compactMap { item in
            switch item.kind {
            case .message: return item.messageID.flatMap { messagesByID[$0] }
            case .liveTurn: return item.turnPlaybackID.flatMap { turnsByID[$0] }
            case .pending: return nil
            }
        }
        // Сообщения «в пути» — в той же ленте, в конце. После ответа сервера
        // их строку занимает отправленное сообщение (`rowIDByMessageID`):
        // тот же ForEach, тот же id и тот же вид — строка не пересоздаётся.
        let outgoing = pendingOutgoing.enumerated().map { index, pending in
            FeedItem(id: pending.id, dateString: nil, position: messages.count + live.count + index,
                     message: nil, turn: nil, pending: pending, date: .distantFuture)
        }
        return timeline + outgoing
    }

    /// Строка своего сообщения, которое было пузырём «в пути».
    private func isOutgoingRow(_ item: FeedItem) -> Bool {
        item.pending != nil || item.id.hasPrefix("local-")
    }

    /// Keep the same row identity while a live reply becomes its saved message.
    /// Replacing `playbackID` with the server message ID made LazyVStack tear
    /// down one variable-height row and insert another at the same position,
    /// which could reset the reader's scroll anchor during completion.
    ///
    /// Своя строка у каждого сообщения. Строки не строятся из пары
    /// «автор + на что ответ»: она не уникальна (ответ роли и служебные
    /// строки координации отвечают на одно сообщение), и одинаковые id в
    /// ForEach заставляли SwiftUI переиспользовать строки — текст пропадал, а
    /// лента прыгала (владелец 22.10.2026).
    private func feedItemID(for message: RoleChatMessage) -> String {
        rowIDByMessageID[message.id] ?? RoleChatRowID.message(message.id)
    }

    private func feedItemID(for turn: RoleChatLiveTurn) -> String {
        RoleChatRowID.turn(turn.playbackID)
    }


    /// Перед какими элементами ленты стоит полоса с датой: первый с датой и
    /// каждый, где день сменился. Элемент без разбираемой даты (живой ход
    /// без `startedAt`) дня не начинает и не прерывает — иначе после своего
    /// сообщения появлялась лишняя «Сегодня» (владелец 14.10.2026).
    private func dayDividerTitles(_ feed: [FeedItem]) -> [String: String] {
        var result: [String: String] = [:]
        var previousDay: String?
        for item in feed {
            guard let day = ChatDayLabel.dayKey(raw: item.dateString), day != previousDay else { continue }
            previousDay = day
            result[item.id] = ChatDayLabel.dividerTitle(raw: item.dateString)
        }
        return result
    }

    /// Вставить сообщение из сокета: новое — в конец, известное — заменить.
    /// Живой пузырь автора уходит тем же кадром, что появляется готовый, —
    /// лента не прыгает. Свой пузырь «в пути» с тем же текстом тоже уходит:
    /// сервер его принял.
    private func insertIncoming(_ message: RoleChatMessage) {
        roomEventRevision += 1
        messageEventRevisions[message.id] = roomEventRevision
        let mine = message.fromUserID == session.currentUser?.id
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if let index = messages.firstIndex(where: { $0.id == message.id }) {
                messages[index] = message
            } else {
                // Вставка по серверному порядку: раньше тут сортировалась вся
                // лента, и на каждом снимке живого ответа даты разбирались
                // заново — это и было главным тормозом ленты.
                messages = RoleChatMessageOrder.inserting(message, into: messages)
            }
            if let author = message.fromUserID, !mine {
                if let turn = liveTurns[author] {
                    if turn.isCompleted(by: message) {
                        completingTurns[turn.playbackID] = turn.completed(with: message)
                        // Это сообщение закрыло ход: пока ход доигрывает ответ,
                        // сообщение скрыто, а при его появлении оно должно
                        // занять ту же строку.
                        completedMessageIDByTurn[turn.playbackID] = message.id
                        rowIDByMessageID[message.id] = RoleChatRowID.turn(turn.playbackID)
                        endedTurnIDs.insert(turn.playbackID)
                        liveTurns[author] = nil
                        restoredTurnIDs.remove(turn.playbackID)
                        typists[author] = nil
                        typistTools[author] = nil
                        liveDeltas[author] = nil
                    }
                } else if message.replyToMessageID != nil {
                    typists[author] = nil
                    typistTools[author] = nil
                    liveDeltas[author] = nil
                }
            }
            if mine, let index = pendingOutgoing.firstIndex(where: { !$0.failed && $0.text == message.text }) {
                // Сервер принял наше сообщение: готовое занимает строку
                // пузыря «в пути» — лента не дёргается на смене карточки.
                rowIDByMessageID[message.id] = pendingOutgoing[index].id
                pendingOutgoing.remove(at: index)
            }
        }
        if !mine && message.id != markedReadMessageID {
            let id = message.id
            Task {
                if (try? await api.markRoleChatRead(id: chat.id)) != nil { markedReadMessageID = id }
            }
        }
    }

    /// Своё сообщение в пути: тот же пузырь, что у отправленного, но
    /// приглушён; не ушло — подпись и «Повторить».
    /// Своё сообщение: пока оно «в пути» и после доставки — один и тот же вид,
    /// меняется только прозрачность.
    private func outgoingRow(_ message: RoleChatMessage, pending: PendingOutgoing?) -> some View {
        VStack(alignment: .trailing, spacing: TFSpacing.xs) {
            // Выбор и удаление для него не имеют смысла — на сервере его нет.
            messageBubbleRow(message)
                .allowsHitTesting(pending == nil)
                .opacity(pending.map { $0.failed ? 1 : 0.6 } ?? 1)
            if let pending, pending.failed {
                HStack(spacing: TFSpacing.sm) {
                    Label("Не отправлено", systemImage: "exclamationmark.circle")
                        .foregroundStyle(Color.tfRed)
                    Button("Повторить") { Task { await deliver(pending.id) } }
                    Button("Убрать", role: .destructive) {
                        pendingOutgoing.removeAll { $0.id == pending.id }
                    }
                }
                .tfText(.meta)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func pendingMessage(_ pending: PendingOutgoing) -> RoleChatMessage {
        RoleChatMessage(
            id: pending.id,
            chatID: chat.id,
            fromUserID: session.currentUser?.id,
            fromUserName: session.currentUser?.name,
            fromUserColor: nil,
            fromUserAvatarURL: nil,
            fromUserInitials: nil,
            kind: nil,
            replyToMessageID: nil,
            replyToSenderName: nil,
            text: pending.text,
            roleEnvelope: nil,
            createdAt: nil,
            attachments: pending.attachments,
            taskID: nil,
            taskTitle: nil,
            quickReplies: nil,
            isSessionMarker: false,
            steps: nil,
            reactions: nil
        )
    }

    private func stopTurns() async {
        guard !isStopping else { return }
        isStopping = true
        defer { isStopping = false }
        do { try await api.stopRoleChat(chatID: chat.id) }
        catch { errorMessage = error.localizedDescription }
    }

    /// «Печатает» — пока у роли нет ни текста, ни шагов; дальше вместо
    /// точек растёт её живой пузырь.
    /// Роль, приславшая дельты хода, берёт строку из них; `chats:typing` —
    /// только для старого сервера (27.10.2026).
    private var visibleTypists: [String: String] {
        let live = Set(visibleLiveTurns.map(\.userID))
        var result = typists.filter { !deltaUsers.contains($0.key) }
        for (userID, state) in liveDeltas where state.activity != nil {
            result[userID] = state.name.isEmpty ? "Участник" : state.name
        }
        return result.filter { !live.contains($0.key) }
    }

    private func typingTool(_ userID: String) -> String? {
        guard deltaUsers.contains(userID) else { return typistTools[userID] }
        if case .tool(let tool)? = liveDeltas[userID]?.activity { return tool }
        return nil
    }

    private func liveTurnRow(_ turn: RoleChatLiveTurn) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.xs) {
            replyContext(messageID: turn.triggerMessageID, sender: nil)
            RoleLiveTurnBubble(turn: turn, showsName: chat.kind == "group", isComplete: endedTurnIDs.contains(turn.playbackID), pacesText: pacesLiveText,
                               startsWithSnapshot: restoredTurnIDs.contains(turn.playbackID),
                               onPlaybackComplete: {
                                   completingTurns[turn.playbackID] = nil
                                   endedTurnIDs.remove(turn.playbackID)
                               })
                .id(turn.playbackID)
        }
    }

    /// Ответ роли уже есть в ленте: служебные строки координации («Ответ
    /// получен», «Ход завершился ошибкой») ответом НЕ считаются — иначе
    /// живой ход не показывался бы, хотя текст ответа ещё не пришёл.
    private func hasAnswer(on trigger: String, from userID: String) -> Bool {
        messages.contains { message in
            message.fromUserID == userID
                && message.replyToMessageID == trigger
                && message.kind != "system"
        }
    }

    private func markLiveTurnEnded(_ userID: String) {
        guard let turn = liveTurns[userID] else { return }
        endedTurnIDs.insert(turn.playbackID)
        liveTurns[userID] = turn.ending()
        typists[userID] = nil
        typistTools[userID] = nil
    }

    private func loadLiveTurns() async {
        let revision = roomEventRevision
        guard !liveSnapshotLoading else { return }
        liveSnapshotLoading = true
        defer { liveSnapshotLoading = false }
        guard let snapshot = try? await api.roleChatLiveSnapshot(id: chat.id) else { return }
        // Состояние дельт берём, даже если за время запроса пришли события:
        // дельты идут каждые 150 мс, и снимок иначе не прижился бы никогда.
        // Своё не трогаем, если оно того же хода и не старее снимка.
        for state in snapshot.states {
            deltaUsers.insert(state.userID)
            if let current = liveDeltas[state.userID], current.turnID == state.turnID, current.seq >= state.seq { continue }
            liveDeltas[state.userID] = state
            let turn = state.liveTurn
            restoredTurnIDs.insert(turn.playbackID)
            showLiveTurn(turn, userID: state.userID)
        }
        guard revision == roomEventRevision else { return }
        let turns = snapshot.turns
        liveTurns = Dictionary(turns.map { ($0.userID, $0) }, uniquingKeysWith: { _, last in last })
        restoredTurnIDs = Set(turns.map(\.playbackID))
        typists = Dictionary(turns.map { ($0.userID, $0.name) }, uniquingKeysWith: { _, last in last })
        typistTools = typistTools.filter { liveTurns[$0.key] != nil }
    }

    /// Полоса выбора вместо панели ввода: отметить всё или снять отметки.
    private var selectionBar: some View {
        HStack(spacing: TFSpacing.md) {
            Button(allMessagesSelected ? "Снять выбор" : "Выбрать все") {
                if allMessagesSelected {
                    selectedMessageIDs.removeAll()
                } else {
                    selectedMessageIDs = Set(messages.map(\.id))
                }
            }
            .disabled(messages.isEmpty)
            Spacer(minLength: TFSpacing.md)
            Text("Выбрано: \(selectedMessageIDs.count)")
                .tfText(.action)
                .foregroundStyle(Color.tfSub)
        }
        .padding(.horizontal, TFSpacing.lg)
        .padding(.vertical, TFSpacing.md)
    }

    private var allMessagesSelected: Bool {
        !messages.isEmpty && selectedMessageIDs.count == messages.count
    }

    /// «1 участник / 2 участника / 5 участников» — тот же разбор исключений
    /// 11–14, что у `DirectoryPluralize`, но для слова «участник».
    private func participantsWord(_ count: Int) -> String {
        let mod100 = count % 100
        if mod100 >= 11 && mod100 <= 14 { return "участников" }
        switch count % 10 {
        case 1: return "участник"
        case 2, 3, 4: return "участника"
        default: return "участников"
        }
    }

    private func enterSelection(selecting id: String?) {
        isSelecting = true
        selectedMessageIDs = id.map { [$0] } ?? []
    }

    private func exitSelection() {
        isSelecting = false
        selectedMessageIDs.removeAll()
    }

    private func toggleSelection(_ id: String) {
        if selectedMessageIDs.contains(id) { selectedMessageIDs.remove(id) }
        else { selectedMessageIDs.insert(id) }
    }

    private func deleteSelected() async {
        let ids = selectedMessageIDs
        guard !ids.isEmpty else { return }
        do {
            try await api.deleteRoleChatMessages(chatID: chat.id, ids: Array(ids))
            messages.removeAll { ids.contains($0.id) }
            exitSelection()
        } catch { errorMessage = error.localizedDescription }
    }

    /// Новая сессия (владелец 25.09.2026, docs/ПЛАН Супер Помощник владельца/):
    /// сбрасывает память роли, история остаётся — сервер сам вставляет
    /// метку-разделитель, которую здесь просто дописываем в ленту.
    /// «Сжать» (владелец 20.10.2026). В чате с несколькими ролями — выбор роли.
    @ViewBuilder private var compactMenuItem: some View {
        let roles = chat.others(excluding: session.currentUser?.id).filter { $0.roleKey != nil }
        if roles.count > 1 {
            Menu {
                ForEach(roles) { member in
                    Button(member.name) { Task { await compact(member) } }
                }
            } label: { Label("Сжать сессию", systemImage: "arrow.down.right.and.arrow.up.left") }
        } else if let member = roles.first {
            Button { Task { await compact(member) } } label: {
                Label("Сжать сессию", systemImage: "arrow.down.right.and.arrow.up.left")
            }
        }
    }

    private func compact(_ member: RoleChatMember) async {
        do {
            try await api.compactRoleChatSession(chatID: chat.id, roleID: member.id)
            noticeMessage = "Сессия «\(member.name)» сжата."
            await composerControls.load(chat: chat)
        } catch { errorMessage = error.localizedDescription }
    }

    private func createAssistantSession() async {
        do {
            let next = try await api.createRoleChat(title: nil, memberIDs: ["u-secretary"])
            branchChat = next
            isBranchPresented = true
        } catch { errorMessage = error.localizedDescription }
    }

    private func newSession(roleID selectedRoleID: String? = nil) async {
        guard let roleID = selectedRoleID ?? chat.others(excluding: session.currentUser?.id).first?.id else { return }
        do {
            let marker = try await api.newRoleChatSession(chatID: chat.id, roleID: roleID)
            if !messages.contains(where: { $0.id == marker.id }) { messages.append(marker) }
            await composerControls.load(chat: chat)
        } catch { errorMessage = error.localizedDescription }
    }

    private func clearChat() async {
        do {
            try await api.deleteRoleChatMessages(chatID: chat.id)
            messages = []
            exitSelection()
        } catch { errorMessage = error.localizedDescription }
    }

    /// Привязать чат к задаче (`taskID == nil` — отвязать). Сервер отвечает
    /// обновлённым чатом, поэтому локальный состав переписки перечитывать не
    /// нужно — меняется только сама привязка.
    private func bindTask(_ taskID: String?) async {
        do {
            chat = try await api.bindRoleChatToTask(id: chat.id, taskID: taskID)
        } catch { errorMessage = error.localizedDescription }
    }

    @ViewBuilder
    private func messageRow(_ message: RoleChatMessage) -> some View {
        if let coordination = message.coordination {
            RoleCoordinationCard(coordination: coordination) {
                try await api.stopRoleCoordination(chatID: chat.id, messageID: message.id)
            }
            .hintAnchor(HintAnchorID.chatCoordination)
        } else if message.isSessionMarker {
            sessionMarkerRow(message)
        } else if isFlatReply(message) {
            flatReplyRow(message)
        } else {
            messageBubbleRow(message)
        }
    }

    /// Ответы ролей — по всей ширине в личных и групповых чатах.
    /// Свои сообщения, голосовые и сообщения других людей в группе — в пузырях.
    /// Это только оформление: состав чата и правила адресации не меняются.
    private func isFlatReply(_ message: RoleChatMessage) -> Bool {
        guard message.fromUserID != session.currentUser?.id else { return false }
        guard chat.kind != "group" || isAgentReply(message) else { return false }
        return !(message.attachments?.contains { $0.isVoiceRecording } ?? false)
    }

    @ViewBuilder
    private func replyContext(messageID: String?, sender: String?) -> some View {
        if let messageID, let original = messages.first(where: { $0.id == messageID }) {
            let excerpt = original.text.trimmingCharacters(in: .whitespacesAndNewlines)
            Text("В ответ на: " + (excerpt.isEmpty ? "Вложение" : excerpt))
                .tfText(.meta)
                .foregroundStyle(Color.tfSub)
                .lineLimit(2)
                .accessibilityIdentifier("chat.replyTo." + messageID)
        } else if messageID != nil {
            Text("В ответ на сообщение" + (sender.map { " · " + $0 } ?? ""))
                .tfText(.meta)
                .foregroundStyle(Color.tfSub)
        }
    }

    private func flatReplyRow(_ message: RoleChatMessage) -> some View {
        HStack(alignment: .top, spacing: TFSpacing.sm) {
            if isSelecting {
                Image(systemName: selectedMessageIDs.contains(message.id)
                      ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(selectedMessageIDs.contains(message.id)
                                     ? Color.tfRed : Color.tfDim)
            }
            VStack(alignment: .leading, spacing: TFSpacing.sm) {
                // Ответ роли подписан внизу (replyFooter), сверху — только чужой.
                if !isAgentReply(message) { senderLine(message, color: Color.tfSub) }
                replyContext(messageID: message.replyToMessageID, sender: message.replyToSenderName)
                if let steps = message.steps, steps.hasDetails {
                    RoleLiveItemsList(items: steps.items)
                }
                // Текст и карточка задачи — вместе, а не вместо: раньше
                // карточка подменяла всё сообщение, и вопрос роли пропадал
                // (владелец 14.10.2026: «приходит только виджет»).
                if !message.text.isEmpty || message.roleEnvelopeJSON != nil {
                    roleMessageContent(message, allowsCommands: session.currentUser?.role == .owner && !isSelecting)
                }
                if let handoff = message.handoff {
                    ChatHandoffCard(handoff: handoff)
                }
                // Уточнение роли у владельца (26.10.2026): форма с вариантами
                // ответа. Рисуется под ответом роли — там, где владелец её
                // ждёт.
                if let question = message.question {
                    RoleQuestionCard(question: question) { answers, note in
                        try await self.api.answerChatQuestion(chatID: self.chat.id,
                                                             questionID: question.id,
                                                             answers: answers,
                                                             note: note)
                        await self.refresh()
                    }
                }
                // Быстрые варианты ответа — у своего сообщения (26.10.2026).
                if !isSelecting, let replies = quickReplies(for: message) {
                    quickReplyRow(replies)
                }
                if let taskID = message.taskID, taskID != chat.taskID {
                    SecretaryDraftCard(taskID: taskID) { pendingTaskID = taskID }
                }
                nonVoiceAttachments(message)
                if isAgentReply(message) && !isSelecting { messageActions(message) }
            }
            // Долгое нажатие по ответу собеседника открывает меню действий
            // (владелец 26.10.2026): весь набор, включая ветвление.
            .contextMenu { if !isSelecting { messageContextMenu(message, isMine: false) } }
        }
        .contentShape(Rectangle())
        .overlay {
            if isSelecting {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { toggleSelection(message.id) }
            }
        }
    }

    /// Разделитель «новая сессия» (владелец 25.09.2026) — не пузырь,
    /// центрированная метка, как разрыв даты в iMessage.
    private func sessionMarkerRow(_ message: RoleChatMessage) -> some View {
        HStack {
            Spacer()
            Text("Новая сессия")
                .tfText(.caption)
                .foregroundStyle(Color.tfDim)
                .padding(.horizontal, TFSpacing.md)
                .padding(.vertical, 4)
                .background(Color.tfCard)
                .clipShape(Capsule())
            Spacer()
        }
    }

    private func messageBubbleRow(_ message: RoleChatMessage) -> some View {
        let mine = message.fromUserID == session.currentUser?.id
        let hasAudio = message.attachments?.contains { $0.isVoiceRecording } ?? false
        return HStack(alignment: .top, spacing: TFSpacing.sm) {
            if isSelecting {
                // Отметка выбора слева от сообщения — как в почте и Teams.
                Image(systemName: selectedMessageIDs.contains(message.id)
                      ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(selectedMessageIDs.contains(message.id)
                                     ? Color.tfRed : Color.tfDim)
                    .padding(.top, TFSpacing.md)
            }
            if mine { Spacer(minLength: 48) }
            VStack(alignment: .leading, spacing: TFSpacing.xs) {
                // Иконка отправителя — вплотную слева от его имени, внутри
                // сообщения сверху (владелец 21.09.2026). Раньше она стояла
                // отдельным столбцом сбоку и у своих сообщений не рисовалась
                // вовсе, хотя иконка есть у всех.
                //
                // У голосового своя подложка — пузырь, поэтому там эта строка
                // уезжает ВНУТРЬ пузыря, а не висит над ним отдельно.
                // У ответа роли подпись внизу, рядом с кнопками (владелец
                // 14.10.2026, по образцу: кто ответил и за сколько — в конце).
                if !hasAudio && (mine || !isAgentReply(message)) {
                    if mine {
                        senderLine(message, color: Color.tfSub)
                            .hintAnchor(HintAnchorID.chatOwnMessageCopy)
                    } else {
                        senderLine(message, color: Color.tfSub)
                    }
                }
                replyContext(messageID: message.replyToMessageID, sender: message.replyToSenderName)
                // Ход, который привёл к ответу (27.09.2026), — как шёл вживую (01.10.2026).
                if let steps = message.steps, steps.hasDetails {
                    RoleLiveItemsList(items: steps.items)
                }
                ForEach(message.attachments?.filter { $0.isVoiceRecording } ?? []) { attachment in
                    RoleChatRemoteVoiceBubble(
                        attachment: attachment,
                        message: message,
                        player: player,
                        api: api,
                        isOwn: mine,
                        header: AnyView(senderLine(message, color: mine ? Color.tfSub : .white.opacity(0.85)))
                    )
                }
                nonVoiceAttachments(message)
                // Карточка задачи (владелец 25.09.2026, этап 2 «Супер
                // Помощника владельца») — раньше была только у Помощника владельца
                // (ChatBubble.swift, message.fromUserId == secretaryID),
                // здесь — для любой роли, отправитель не важен.
                // Кроме чата самой задачи: его сообщения наследуют её
                // task_id, и карточка подменяла КАЖДОЕ сообщение — текста не
                // было видно вовсе (владелец 07.10.2026).
                // Текст и карточка — вместе (владелец 14.10.2026): карточка
                // больше не подменяет сообщение.
                if (!message.text.isEmpty || message.roleEnvelopeJSON != nil) && !hasAudio {
                    if mine {
                        Text(message.text)
                            .textSelection(.enabled)
                            .foregroundStyle(Color.tfText)
                    } else {
                        // В группе ответ роли использует тот же разбор контракта.
                        roleMessageContent(message, allowsCommands: session.currentUser?.role == .owner && !isSelecting)
                    }
                }
                if let handoff = message.handoff {
                    ChatHandoffCard(handoff: handoff)
                }
                if let taskID = message.taskID, taskID != chat.taskID {
                    SecretaryDraftCard(taskID: taskID) { pendingTaskID = taskID }
                }
                // Признак доставки под СВОИМ сообщением (карточка b504958a,
                // контракт §10): «Сохранено» — сообщение лежит в ленте,
                // «Передано исполнителю» — роль взяла его в работу. Под
                // ответом роли признака нет: доставки «исполнителю» там не
                // бывает, и значок сбивал бы владельца с толку.
                if let delivery = ChatDeliveryBadgePolicy.badge(
                    for: message,
                    isOwnMessage: mine,
                    isAgentReply: isAgentReply(message)
                ) {
                    ChatDeliveryBadge(state: delivery)
                        .hintAnchor(HintAnchorID.chatDeliveryBadge)
                }
                if !mine && isAgentReply(message) && !isSelecting {
                    messageActions(message)
                }
            }
            // Долгое нажатие по своему сообщению даёт те же действия, кроме
            // ветвления (владелец 26.10.2026).
            .contextMenu { if !isSelecting { messageContextMenu(message, isMine: mine) } }
            .padding(hasAudio ? 0 : TFSpacing.md)
            // Подложка одна и та же у своих и у чужих — отличает их только
            // обводка (владелец 21.09.2026: «в моих сообщениях делай такую же
            // самую подложку, как фон делаешь другим»).
            .background(hasAudio ? Color.clear : Color.tfCard)
            .overlay {
                if mine && !hasAudio {
                    RoundedRectangle(cornerRadius: TFRadius.lg)
                        .strokeBorder(Color.tfRed, lineWidth: TFBorder.width)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
            if !mine { Spacer(minLength: 48) }
        }
        // Долгое нажатие только ВКЛЮЧАЕТ выбор — с этим сообщением уже
        // отмеченным; дальше отмечаешь тапами (владелец 21.09.2026). В самом
        // режиме выбора тап по сообщению отмечает его, а внутренние кнопки
        // (воспроизведение) перекрыты прозрачным слоем, чтобы не срабатывали.
        .contentShape(Rectangle())
        .overlay {
            if isSelecting {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { toggleSelection(message.id) }
            }
        }
    }

    /// Отметки checklist-виджета уходят на сервер (карточка 21842242): роль
    /// читает их операцией `taskflow_checklist_state`, а состояние приходит с
    /// сервера — поэтому отметка переживает перезапуск приложения. Контекст
    /// только там, где блок виджета есть: у сообщения без него отправлять
    /// нечего.
    private func checklistContext(for message: RoleChatMessage) -> ChecklistSyncContext? {
        guard message.text.contains("```widget") || message.roleEnvelopeJSON?.contains("```widget") == true
        else { return nil }
        let chatID = chat.id
        let messageID = message.id
        return ChecklistSyncContext(
            chatID: chatID,
            messageID: messageID,
            seed: message.checklistState ?? []
        ) { item in
            try await api.setRoleChatChecklistItem(chatID: chatID, messageID: messageID, item: item)
        }
    }

    private func isAgentReply(_ message: RoleChatMessage) -> Bool {
        message.fromUserID?.hasPrefix("role_") == true || message.fromUserID == "u-secretary" || chat.members.contains { $0.id == message.fromUserID && $0.roleKey != nil }
    }

    @ViewBuilder
    private func roleMessageContent(_ message: RoleChatMessage, allowsCommands: Bool) -> some View {
        let checklist = checklistContext(for: message)
        if isAgentReply(message), let json = message.roleEnvelopeJSON {
            ChatStructuredOutputView(json: json, checklist: checklist, allowsCommands: allowsCommands)
                .roleMessageReveal(text: message.text, messageID: message.id,
                                   animate: chatIsNearBottom && message.id == messages.last?.id)
        } else {
            RoleReplyMarkdown(text: message.text, allowsCommands: allowsCommands, checklist: checklist, serverBlocks: message.blocks)
                .equatable()
                // Анимируем только новое сообщение и только когда лента внизу:
                // иначе проявление старых строк при прокрутке дёргает
                // автопривязку к низу (жалоба владельца 17.10.2026).
                .roleMessageReveal(text: message.text, messageID: message.id,
                                   animate: chatIsNearBottom && message.id == messages.last?.id)
        }
    }

    private func copyMessage(_ message: RoleChatMessage) {
        UIPasteboard.general.string = message.text
        copiedMessageID = message.id
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if copiedMessageID == message.id { copiedMessageID = nil }
        }
    }

    private func messageActions(_ message: RoleChatMessage) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.xs) {
            // Прерванный ответ (уточнение владельца остановило ход) не должен
            // выглядеть как завершённый (карточка b504958a, доработка D1).
            if let interruption = message.interruption {
                ChatInterruptionBadge(interruption: interruption, isPartial: message.partial == true)
            }
            if let usage = message.steps?.usage { RoleTurnUsageRow(usage: usage) }
            if let changes = message.steps?.codeChanges {
                TurnCodeChangesRow(changes: changes) { text in
                    draft = draft.isEmpty ? text : draft + "\n\n" + text
                    composerFocused = true
                }
            }
            messageActionRow(message)
        }
    }

    private func messageActionRow(_ message: RoleChatMessage) -> some View {
        // Владелец 26.10.2026: значки-действия под ответом убраны — копировать,
        // выделить, поделиться и ответвление есть в меню по долгому нажатию.
        // Под ответом осталась только подпись: кто ответил, сколько думал, время.
        replyFooter(message)
    }

    /// Подпись ответа роли внизу: иконка, имя, сколько думала, время.
    private func replyFooter(_ message: RoleChatMessage) -> some View {
        HStack(spacing: TFSpacing.xs) {
            RoleChatAvatar(message: message, size: .sm)
            Text(message.fromUserName ?? "Участник")
                .tfText(.caption)
            if let ms = message.steps?.durationMs, ms > 0 {
                Text("· \(Self.turnDuration(ms))")
                    .tfText(.caption)
            }
            if let time = ChatMessageTime.label(raw: message.createdAt) {
                Text("· \(time)")
                    .tfText(.caption)
                    .opacity(0.7)
            }
        }
        .lineLimit(1)
    }

    static func turnDuration(_ ms: Int) -> String {
        let seconds = max(1, ms / 1000)
        return seconds < 60 ? "\(seconds) с" : "\(seconds / 60) мин \(seconds % 60) с"
    }

    private func openBranch(from message: RoleChatMessage) async {
        guard !isBranching else { return }
        isBranching = true
        defer { isBranching = false }
        do {
            branchChat = try await api.createChatBranch(chatID: chat.id, messageID: message.id)
            isBranchPresented = true
        } catch { errorMessage = error.localizedDescription }
    }

    private func messageActionButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            // Владелец 20.10.2026: значки мельче и одного размера — 14 pt в
            // одинаковом квадрате 16×16; зона нажатия по-прежнему 44×44.
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .regular))
                .frame(width: 16, height: 16)
                .frame(width: TFHitTarget.min, height: TFHitTarget.min)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }

    /// Меню действий по долгому нажатию (владелец 26.10.2026): у своих
    /// сообщений — те же пункты, что обозначены иконками в конце сообщения
    /// собеседника, кроме ветвления; у собеседника — весь набор вместе с
    /// ветвлением. Набор описан в одном месте, чтобы новые действия не
    /// приходилось проставлять дважды.
    @ViewBuilder
    private func messageContextMenu(_ message: RoleChatMessage, isMine: Bool) -> some View {
        if !message.text.isEmpty {
            Button { selectingText = SelectableMessageText(text: message.text) } label: {
                Label("Выделить текст", systemImage: "text.cursor")
            }
            Button { copyMessage(message) } label: {
                Label("Скопировать текст", systemImage: "doc.on.doc")
            }
        }
        Button { exportMessage(message) } label: {
            Label("Сохранить или поделиться", systemImage: "square.and.arrow.up")
        }
        if isMine && message.canWithdraw == true
            && !liveTurns.values.contains(where: { $0.triggerMessageID == message.id })
            && !completingTurns.values.contains(where: { $0.triggerMessageID == message.id })
            && !messages.contains(where: { $0.replyToMessageID == message.id && isAgentReply($0) }) {
            Button(role: .destructive) { Task { await withdrawMessage(message) } } label: {
                Label("Убрать сообщение", systemImage: "trash")
            }
        }
        if !isMine {
            Button { Task { await openBranch(from: message) } } label: {
                Label("Ответвление: обсудить в отдельном чате", systemImage: "arrow.triangle.branch")
            }
            .disabled(isBranching)
        }
    }

    private func withdrawMessage(_ message: RoleChatMessage) async {
        guard message.fromUserID == session.currentUser?.id, message.canWithdraw == true else { return }
        do {
            try await api.withdrawRoleChatMessage(chatID: chat.id, messageID: message.id)
            messages.removeAll { $0.id == message.id }
            selectedMessageIDs.remove(message.id)
        } catch {
            // Состояние могло измениться, пока меню было открыто: сервер
            // повторно проверяет начало работы и сохраняет взятое сообщение.
            await refresh()
            errorMessage = error.localizedDescription
        }
    }

    private func exportMessage(_ message: RoleChatMessage) {
        do {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("message-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent("TaskFlow-сообщение.md")
            try message.text.write(to: url, atomically: true, encoding: .utf8)
            guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }), let root = scene.keyWindow?.rootViewController else { return }
            var top = root
            while let presented = top.presentedViewController { top = presented }
            let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            if let popover = controller.popoverPresentationController {
                popover.sourceView = top.view
                popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            top.present(controller, animated: true)
        } catch { errorMessage = error.localizedDescription }
    }

    @ViewBuilder
    private func nonVoiceAttachments(_ message: RoleChatMessage) -> some View {
        ForEach(message.attachments?.filter { !$0.isVoiceRecording } ?? []) { attachment in
            Button {
                Task { await openAttachment(attachment) }
            } label: {
                if attachment.mime?.hasPrefix("image/") == true {
                    VStack(alignment: .leading, spacing: TFSpacing.xs) {
                        ChatAttachmentImage(attachmentId: attachment.id, fileName: attachment.fileName)
                        Text(attachment.fileName)
                            .tfText(.caption)
                            .foregroundStyle(Color.tfSub)
                            .lineLimit(1)
                    }
                } else {
                    ChatFileChip(fileName: attachment.fileName)
                }
            }
            .buttonStyle(.plain)
            .disabled(openingAttachmentIDs.contains(attachment.id))
            .overlay {
                if openingAttachmentIDs.contains(attachment.id) { ProgressView() }
            }
            .accessibilityLabel("Открыть \(attachment.fileName)")
        }
    }

    private func openAttachment(_ attachment: ApiChatAttachment) async {
        guard openingAttachmentIDs.insert(attachment.id).inserted else { return }
        defer { openingAttachmentIDs.remove(attachment.id) }
        do {
            let data = try await api.downloadAttachment(id: attachment.id)
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("taskflow-chat-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let safeName = URL(fileURLWithPath: attachment.fileName).lastPathComponent
            let url = directory.appendingPathComponent(safeName.isEmpty ? "attachment" : safeName)
            try data.write(to: url, options: .atomic)
            previewAttachmentURL = url
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Иконка отправителя вплотную слева от имени — одна и та же строка и в
    /// текстовом сообщении, и внутри голосового пузыря. Цвет подписи зависит
    /// от подложки: на карточке — приглушённый, на заливке пузыря — белый.
    private func senderLine(_ message: RoleChatMessage, color: Color) -> some View {
        HStack(spacing: TFSpacing.sm) {
            RoleChatAvatar(message: message, size: .lg)
            Text(message.fromUserName ?? "Участник")
                .tfText(.meta)
                .foregroundStyle(color)
            // Время — и у своих, и у ответов (владелец 14.10.2026). У
            // сообщения «в пути» его ещё нет.
            if let time = ChatMessageTime.label(raw: message.createdAt) {
                Text(time)
                    .tfText(.caption)
                    .foregroundStyle(color.opacity(0.7))
            }
        }
    }

    /// Строка отправителя для голосового, которое ещё не отправлено: на
    /// сервере его пока нет, поэтому имя и иконка берутся из сессии.
    private var ownSenderLine: some View {
        HStack(spacing: TFSpacing.sm) {
            RoleChatAvatar(user: session.currentUser, size: .lg)
            Text(session.currentUser?.name ?? "Вы")
                .tfText(.meta)
                .foregroundStyle(Color.tfSub)
        }
    }

    private func refresh() async {
        refreshRevision += 1
        let revision = refreshRevision
        let eventRevision = roomEventRevision
        do {
            async let chatRequest = api.roleChat(id: chat.id)
            async let messagesRequest = api.roleChatMessages(id: chat.id)
            let (updatedChat, updatedMessages) = try await (chatRequest, messagesRequest)
            guard revision == refreshRevision else { return }
            chat = updatedChat
            // Снимок может менять текст и контекст ответа без изменения ID.
            // Объединяем его с событиями, пришедшими уже после начала запроса.
            do {
                for message in updatedMessages where !messages.contains(where: { $0.id == message.id }) {
                    if let author = message.fromUserID, let turn = liveTurns[author], turn.isCompleted(by: message) {
                        insertIncoming(message)
                    }
                }
                let receivedAfterRequest = Set(messageEventRevisions.filter { $0.value > eventRevision }.map(\.key))
                messages = RoleChatMessageOrder.mergingSnapshot(updatedMessages, current: messages, receivedAfterRequest: receivedAfterRequest)
                hasLoadedMessages = true
                Self.lastMessages[chat.id] = messages
            }
            // Комната открыта — всё в ней прочитано. Бейдж в списке сервер
            // считает от отметки прочтения, а двигает её только этот вызов
            // (LOCK-206): без него счётчик копился навсегда. Счётчика в
            // ответе на один чат нет, поэтому отмечаем при открытии и когда
            // появилось новое последнее сообщение, а не каждые 4 с опроса.
            if let lastID = updatedMessages.last?.id, lastID != markedReadMessageID {
                if (try? await api.markRoleChatRead(id: chat.id)) != nil {
                    markedReadMessageID = lastID
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            hasLoadedMessages = true
        }
    }

    /// Варианты у сообщения `message`: их место в ленте — сразу под ним.
    /// Пусто, если сообщение не от роли, вариантов нет, сообщение не своё
    /// или это не последнее видимое сообщение (своё сообщение владельца уже
    /// сняло актуальность).
    ///
    /// Список — ВИДИМЫЕ сообщения: скрытые служебные строки варианты не
    /// отменяют (26.10.2026, была жалоба «кнопок не видно у вопроса»).
    private func quickReplies(for message: RoleChatMessage) -> [String]? {
        ChatQuickReplyPolicy.replies(for: message, in: visibleMessages, ownerID: session.currentUser?.id)
    }

    /// То же стекло, что у капсулы поля ввода (`voiceCapsuleSurface`) —
    /// владелец 26.09.2026: «почему у композера фон есть, а тут нет» —
    /// плоская заливка читалась плашкой, голый контур без заливки — как
    /// дыра; нужна была именно системная капсула, а не то и не другое.
    private func quickReplyPillStyle<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .font(.body)
            .foregroundStyle(Color.tfText)
            .padding(.horizontal, TFSpacing.md)
            .padding(.vertical, TFSpacing.sm)
            .voiceCapsuleSurface()
            .overlay {
                Capsule().strokeBorder(Color.tfRed.opacity(0.3), lineWidth: TFBorder.width)
            }
    }

    /// Владелец 26.09.2026: плашки крепятся к сообщению роли, в ленте, а не
    /// в отдельном оверлее над композером. Раскладка — переносом строк
    /// (сколько влезает в строку, столько и встаёт, лишнее уходит на
    /// следующую), а не одна горизонтально скроллящаяся строка: владелец
    /// прямо попросил «так и клади, не в столбик» вместо горизонтального
    /// скролла или одного варианта на строку.
    private func quickReplyRow(_ replies: [String]) -> some View {
        FlowLayout(spacing: TFSpacing.sm) {
            ForEach(replies, id: \.self) { reply in
                Button {
                    draft = reply
                    Task { await send() }
                } label: {
                    quickReplyPillStyle { Text(reply) }
                }
                .buttonStyle(.plain)
                .disabled(isSending)
            }
        }
        .padding(.vertical, TFSpacing.xs)
    }

    /// Отправка без ожидания сети: пузырь встаёт в ленту сразу, поле ввода
    /// очищается тем же нажатием, сеть догоняет в фоне.
    private func changeExecutionMode(_ mode: ChatExecutionMode) async {
        guard !chat.isAssistantOnly, !isSavingExecutionMode, mode != chat.executionMode else { return }
        isSavingExecutionMode = true
        defer { isSavingExecutionMode = false }
        do {
            let updated = try await api.setChatExecutionMode(chatID: chat.id, mode: mode)
            // A refresh started before this response must not restore the old mode.
            refreshRevision += 1
            chat = updated
        } catch { errorMessage = error.localizedDescription }
    }

    private func send() async {
        guard !chat.isAssistantOnly || (modelChoice.isReady && !modelChoice.isSaving) else {
            errorMessage = modelChoice.errorText ?? "Дождитесь сохранения настроек сессии."
            return
        }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!text.isEmpty || !pendingAttachments.isEmpty), !isSending, !isUploadingAttachment, !isSavingExecutionMode else { return }
        let pending = PendingOutgoing(id: "local-\(UUID().uuidString)", text: text,
                                      attachments: pendingAttachments, mode: workMode, executionMode: chat.composerExecutionMode)
        draft = ""
        pendingAttachments = []
        // Вставка пузыря и прокрутка к низу — одной транзакцией: SwiftUI
        // прокручивает после раскладки новой строки, без задержки-подпорки
        // (прежде — `Task.sleep(50 мс)`, промахивался на тяжёлом кадре).
        #if DEBUG
        chatScrollTrace.event("send")
        #endif
        withAnimation(TFMotion.standard) {
            pendingOutgoing.append(pending)
            chatScrollPosition.scrollTo(edge: .bottom)
        }
        await deliver(pending.id)
    }

    /// Отправить (или повторить) сообщение из «в пути». Отправки идут по
    /// одной — порядок в ленте тот же, что порядок нажатий.
    private func deliver(_ pendingID: String) async {
        guard let pending = pendingOutgoing.first(where: { $0.id == pendingID }), !isSending else { return }
        isSending = true
        defer { isSending = false }
        if let index = pendingOutgoing.firstIndex(where: { $0.id == pendingID }) {
            pendingOutgoing[index].failed = false
        }
        do {
            let message = try await api.sendRoleChatMessage(chatID: chat.id, text: pending.text,
                                                            attachmentIDs: pending.attachments.map(\.id), mode: pending.mode, executionMode: pending.executionMode,
                                                            model: chat.isAssistantOnly ? nil : modelChoice.selected)
            pendingOutgoing.removeAll { $0.id == pendingID }
            if !messages.contains(where: { $0.id == message.id }) {
                // Своё отправленное сообщение занимает строку пузыря «в
                // пути»: строка не пересоздаётся, лента не прыгает.
                rowIDByMessageID[message.id] = pending.id
                messages = RoleChatMessageOrder.inserting(message, into: messages)
            }
        } catch {
            if let index = pendingOutgoing.firstIndex(where: { $0.id == pendingID }) {
                pendingOutgoing[index].failed = true
            }
        }
    }

    // MARK: - Упоминание через «@»

    /// Набираемое упоминание в конце черновика: «…@Раз» → «Раз». `nil` —
    /// упоминание сейчас не идёт. «@» засчитывается только в начале текста
    /// или после пробела — иначе сработало бы на адресе почты.
    private var mentionQuery: String? {
        guard let at = draft.lastIndex(of: "@") else { return nil }
        if at > draft.startIndex {
            let before = draft[draft.index(before: at)]
            guard before.isWhitespace else { return nil }
        }
        let query = draft[draft.index(after: at)...]
        guard !query.contains(where: { $0.isWhitespace }) else { return nil }
        return String(query)
    }

    /// Справочник для «@» — участники этого чата, кроме меня: сервер
    /// отвечает только ролями, которые есть в чате. Сначала совпадения с
    /// начала имени, потом по вхождению.
    private var mentionCandidates: [RoleChatMember] {
        guard !isSelecting, let query = mentionQuery?.lowercased() else { return [] }
        let others = chat.members.filter { $0.id != session.currentUser?.id }
        guard !query.isEmpty else { return others }
        let matching = others.filter { $0.name.lowercased().contains(query) }
        return matching.filter { $0.name.lowercased().hasPrefix(query) }
            + matching.filter { !$0.name.lowercased().hasPrefix(query) }
    }

    private var mentionSuggestions: some View {
        VStack(spacing: 0) {
            ForEach(mentionCandidates) { member in
                Button { insertMention(member) } label: {
                    HStack(spacing: TFSpacing.md) {
                        RoleMemberAvatar(member: member, size: .md)
                        Text(member.name)
                            .tfText(.body)
                            .foregroundStyle(Color.tfText)
                        Spacer()
                    }
                    .padding(.horizontal, TFSpacing.lg)
                    .padding(.vertical, TFSpacing.sm)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.tfCard)
    }

    /// «…@Раз» → «…@Разработчик » — пробел в конце, чтобы продолжение
    /// набора не слилось с именем и подсказка закрылась.
    private func insertMention(_ member: RoleChatMember) {
        guard let at = draft.lastIndex(of: "@") else { return }
        draft = String(draft[..<at]) + "@\(member.name) "
    }

    private func sendVoicePreview(_ message: VoiceMessage) async -> Bool {
        if !pendingVoices.contains(where: { $0.id == message.id }) {
            pendingVoices.append(message)
            pendingVoiceModes[message.id] = workMode
            pendingVoiceExecutionModes[message.id] = chat.composerExecutionMode
        }
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

    /// Фото из галереи (владелец 26.09.2026, пункт «Фото» в «+»). JPEG —
    /// `PhotosPickerItem` сам даёт исходные данные оригинала любого формата,
    /// но сервер/лента ожидают предсказуемый тип; пережимаем в JPEG 0.9,
    /// как это уже делает камера ниже.
    private func uploadPickedPhoto(_ item: PhotosPickerItem) async {
        isUploadingAttachment = true
        defer { isUploadingAttachment = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let jpeg = image.jpegData(compressionQuality: 0.9) else { return }
            let attachment = try await api.uploadRoleChatAttachment(fileName: "photo.jpg", data: jpeg, mime: "image/jpeg")
            pendingAttachments.append(attachment)
        } catch { errorMessage = error.localizedDescription }
    }

    /// Снимок камерой (владелец 26.09.2026, пункт «Камера» в «+»).
    private func uploadCameraPhoto(_ image: UIImage) async {
        isUploadingAttachment = true
        defer { isUploadingAttachment = false }
        guard let jpeg = image.jpegData(compressionQuality: 0.9) else { return }
        do {
            let attachment = try await api.uploadRoleChatAttachment(fileName: "camera.jpg", data: jpeg, mime: "image/jpeg")
            pendingAttachments.append(attachment)
        } catch { errorMessage = error.localizedDescription }
    }

    private func sendVoice(_ id: UUID) async {
        guard !chat.isAssistantOnly || (modelChoice.isReady && !modelChoice.isSaving) else {
            errorMessage = modelChoice.errorText ?? "Дождитесь сохранения настроек сессии."
            return
        }
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
            let sent = try await api.sendRoleChatMessage(chatID: chat.id, text: text, attachmentIDs: [attachmentID], mode: pendingVoiceModes[id] ?? workMode, executionMode: pendingVoiceExecutionModes[id] ?? chat.composerExecutionMode, model: chat.isAssistantOnly ? nil : modelChoice.selected)
            if !messages.contains(where: { $0.id == sent.id }) { messages.append(sent) }
            pendingVoices.removeAll { $0.id == id }
            pendingVoiceModes[id] = nil
            pendingVoiceExecutionModes[id] = nil
            uploadedVoiceIDs.removeValue(forKey: id)
        } catch { errorMessage = error.localizedDescription }
    }
}

/// Выбор задачи для привязки чата (владелец 21.09.2026: «привязка конкретных
/// чатов к проекту и, соответственно, к задаче»). Список берётся из общего
/// `TaskStore` — задачи уже загружены приложением, отдельный запрос не нужен.
/// Название и состав чата: переименование, добавление и исключение участников.
/// Владелец 21.09.2026: «нет возможности вообще как-то понять, кто в этом чате
/// присутствует», «переименовывать не умею», «исключать не умею», «добавлять не
/// умею».
///
/// Построено как остальные экраны приложения: крестик слева — закрыть, «…»
/// справа — действия (добавление участника — ПОДМЕНЮ со списком ролей, как
/// выбор модели в `VoiceModelsScreen`), удаление участника — по зажатию на
/// строке, без значков в списке.
private struct RoleChatDetailsSheet: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let onChanged: (RoleChat) -> Void
    /// Владелец 26.09.2026: «Удалить чат» переехал сюда, в «…» этой же
    /// шторки — раньше жил в общем меню комнаты чата вместе с «Название и
    /// участники», хотя открыть их можно было и тапом по имени. Строка
    /// удаления сама закрывает шторку и вызывает этот колбэк, который
    /// закрывает саму комнату чата (чата больше нет — там нечего показывать).
    let onDeleted: () -> Void
    @State private var chat: RoleChat
    @State private var title: String
    @State private var roles: [RoleProfile] = []
    @State private var isLoadingRoles = true
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var isDeleteChatConfirmOpen = false
    @AppStorage(RoleWorkDetailLevel.storageKey) private var workDetailLevel = RoleWorkDetailLevel.standard
    @AppStorage(RoleTranslator.autoKey) private var autoTranslate = false
    private let api = APIClient()

    init(chat: RoleChat, onChanged: @escaping (RoleChat) -> Void, onDeleted: @escaping () -> Void) {
        _chat = State(initialValue: chat)
        _title = State(initialValue: chat.title ?? "")
        self.onChanged = onChanged
        self.onDeleted = onDeleted
    }

    private var isCreator: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["TASKFLOW_MEMBER_SWIPE_PREVIEW"] == "1" { return true }
        #endif
        return chat.createdBy == session.currentUser?.id
    }
    private var isOwner: Bool { session.currentUser?.role == .owner }

    /// Роли, которых в чате ещё нет: участником может быть только роль с
    /// серверной учёткой — иначе отвечать в чате ей нечем.
    private var availableRoles: [RoleProfile] {
        roles.filter { profile in
            guard profile.canJoinChat, let account = profile.accountID else { return false }
            return !chat.members.contains { $0.id == account }
        }
    }

    private var titleChanged: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines) != (chat.title ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Название") {
                    if isCreator {
                        TextField("Без названия", text: $title)
                            .onSubmit { Task { await saveTitle() } }
                    } else {
                        Text(chat.title?.isEmpty == false ? chat.title! : "Без названия")
                            .foregroundStyle(Color.tfSub)
                    }
                }
                Section {
                    ForEach(chat.members) { member in
                        memberRow(member)
                    }
                } header: {
                    Text("Участники")
                } footer: {
                    Text(chat.kind == "direct"
                        ? "Личный чат: можно писать без @."
                        : "Групповой чат: выберите собеседника через @.")
                        .accessibilityIdentifier("chat.details.addressing")
                }
                // Одна настройка на все чаты (владелец 14.10.2026).
                Section {
                    Picker("Показ работы роли", selection: $workDetailLevel) {
                        ForEach(RoleWorkDetailLevel.allCases) { level in
                            Text(level.title).tag(level)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Показ работы роли")
                } footer: {
                    Text(workDetailLevel.explanation)
                }
                Section {
                    HStack {
                        Text("Переводить работу ролей сразу")
                        Spacer()
                        TFToggle(isOn: $autoTranslate)
                    }
                        .onChange(of: autoTranslate) { _, on in RoleTranslator.shared.isOn = on }
                        .accessibilityIdentifier("chat.details.autoTranslate")
                } footer: {
                    Text("Английские реплики ролей показываются по-русски. Переводит iPhone, без сервера; кнопка «Перевести» в ленте работает и без этой настройки.")
                }
            }
            .navigationTitle("Чат")
            .navigationBarTitleDisplayMode(.inline)
            .tint(.primary)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Закрыть")
                }
                if isCreator || isOwner {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            if isCreator {
                                Menu {
                                    if isLoadingRoles {
                                        Text("Загрузка ролей…")
                                    } else if availableRoles.isEmpty {
                                        Text("Все роли уже в чате")
                                    } else {
                                        ForEach(availableRoles) { profile in
                                            Button {
                                                guard let account = profile.accountID else { return }
                                                Task { await addMember(account) }
                                            } label: {
                                                Text(profile.title)
                                            }
                                        }
                                    }
                                } label: {
                                    Label("Добавить участника", systemImage: "person.badge.plus")
                                }
                            }
                            if isOwner {
                                Button(role: .destructive) {
                                    isDeleteChatConfirmOpen = true
                                } label: {
                                    Label("Удалить чат", systemImage: "trash")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .accessibilityLabel("Ещё")
                        .accessibilityIdentifier("chat.details.menu")
                        .hintAnchor(HintAnchorID.chatMembersMenu)
                    }
                }
            }
            .alert("Не удалось изменить чат", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("Закрыть", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
            .confirmationDialog("Удалить чат?", isPresented: $isDeleteChatConfirmOpen,
                                titleVisibility: .visible) {
                Button("Удалить чат", role: .destructive) { Task { await deleteChat() } }
            }
            // Название сохраняется само: отдельной кнопки в шапке нет — там
            // «…». Правка уходит на сервер по клавише «готово» и при закрытии
            // шторки, если текст успел измениться.
            .onDisappear {
                if titleChanged { Task { await saveTitle() } }
            }
            .task {
                #if DEBUG
                if ProcessInfo.processInfo.environment["TASKFLOW_MEMBER_SWIPE_PREVIEW"] == "1" { return }
                #endif
                isLoadingRoles = true
                defer { isLoadingRoles = false }
                do { roles = try await api.roles() }
                catch { errorMessage = error.localizedDescription }
            }
        }
    }

    private func memberRow(_ member: RoleChatMember) -> some View {
        let canRemove = isCreator && member.id != session.currentUser?.id
        return memberContent(member)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        .accessibilityIdentifier("chat.member." + member.id)
        .contextMenu {
            if canRemove {
                Button(role: .destructive) {
                    Task { await removeMember(member) }
                } label: {
                    Label("Удалить из чата", systemImage: "trash")
                }
            }
        }
    }

    private func memberContent(_ member: RoleChatMember) -> some View {
        HStack(spacing: TFSpacing.md) {
            RoleMemberAvatar(member: member, size: .node)
            VStack(alignment: .leading, spacing: 2) {
                Text(member.name).foregroundStyle(Color.tfText)
                if member.id == chat.createdBy {
                    Text("создатель чата").tfText(.meta).foregroundStyle(Color.tfDim)
                }
            }
            Spacer(minLength: TFSpacing.sm)
        }
        .contentShape(Rectangle())
    }

    /// Сервер отвечает обновлённым чатом — им и обновляем экран, и отдаём
    /// наверх, в комнату: переименование и состав видны сразу.
    private func apply(_ updated: RoleChat) {
        chat = updated
        title = updated.title ?? ""
        onChanged(updated)
    }

    private func saveTitle() async {
        guard titleChanged else { return }
        isBusy = true
        defer { isBusy = false }
        do { apply(try await api.renameRoleChat(id: chat.id, title: title)) }
        catch { errorMessage = error.localizedDescription }
    }

    private func deleteChat() async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await api.deleteRoleChat(id: chat.id)
            dismiss()
            onDeleted()
        } catch { errorMessage = error.localizedDescription }
    }

    private func addMember(_ memberID: String) async {
        isBusy = true
        defer { isBusy = false }
        do { apply(try await api.addRoleChatMember(chatID: chat.id, memberID: memberID)) }
        catch { errorMessage = error.localizedDescription }
    }

    private func removeMember(_ member: RoleChatMember) async {
        isBusy = true
        defer { isBusy = false }
        do { apply(try await api.removeRoleChatMember(chatID: chat.id, memberID: member.id)) }
        catch { errorMessage = error.localizedDescription }
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
    /// Своё голосовое — та же подложка, что у остальных, и красная обводка
    /// поверх. Отличает свои сообщения только обводка, как и у текстовых.
    /// Кнопка воспроизведения — один красный треугольник, без круга и без
    /// обводки (владелец 21.09.2026).
    ///
    /// Отступ и радиус — как у текстового сообщения в чате. С числами
    /// прототипа (14 и 22) иконка отправителя и текст расшифровки вставали
    /// на других вертикалях, чем в текстовом: владелец 21.09.2026 —
    /// «интервалы абсолютно одинаковые, симметрия».
    static let own = VoiceBubbleStyle(
        fill: Color.tfCard,
        stroke: Color.tfRed,
        playTint: Color.tfRed,
        playDisc: .none,
        contentColor: Color.tfText,
        padding: TFSpacing.md,
        cornerRadius: TFRadius.lg
    )

    /// Чужое голосовое: пузырь прототипа, но с теми же отступами, что у
    /// текстового сообщения — по той же причине.
    static let others = VoiceBubbleStyle(
        padding: TFSpacing.md,
        cornerRadius: TFRadius.lg
    )
}

private struct RoleChatRemoteVoiceBubble: View {
    let attachment: ApiChatAttachment
    /// Сообщение-владелец вложения: из него берётся расшифровка и строка
    /// отправителя (иконка + имя), которая у голосового стоит ВНУТРИ пузыря.
    let message: RoleChatMessage
    let player: VoicePlayer
    let api: APIClient
    /// Своё ли сообщение: голосовое приходит из истории теми же вложениями,
    /// поэтому сторону нужно передать явно — иначе своё голосовое нарисовалось
    /// бы чужой карточкой.
    let isOwn: Bool
    let header: AnyView
    @State private var localMessage: VoiceMessage?
    @State private var failed = false

    var body: some View {
        Group {
            if let localMessage {
                // Своё голосовое — та же подложка, что у остальных, плюс
                // красная обводка; чужое — прежний пузырь прототипа
                // (владелец 21.09.2026: вид не зависит от способа отправки).
                VoiceMessageBubble(
                    message: localMessage,
                    player: player,
                    style: isOwn ? RoleChatVoiceStyle.own : RoleChatVoiceStyle.others,
                    header: header
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
                let transcript = message.text
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
    let initials: String
    let tint: Color
    let avatarURL: String?
    let userID: String?
    /// В строке сообщения иконка стоит рядом с именем — там нужен мелкий
    /// размер (`.sm`), а не полноразмерный аватар отдельным столбцом.
    var size: TFAvatar.Size = .md

    /// Иконка автора сообщения с сервера.
    init(message: RoleChatMessage, size: TFAvatar.Size = .md) {
        self.initials = message.fromUserInitials ?? String((message.fromUserName ?? "?").prefix(1))
        self.tint = Color(hex: message.fromUserColor ?? TFHexDefault.unassigned)
        self.avatarURL = message.fromUserAvatarURL
        self.userID = message.fromUserID
        self.size = size
    }

    /// Иконка текущего пользователя — для голосового, которое ещё не ушло на
    /// сервер и потому не имеет строки сообщения.
    init(user: ApiUser?, size: TFAvatar.Size = .md) {
        let name = user?.name ?? "?"
        self.initials = user?.initials ?? String(name.prefix(1))
        self.tint = Color(hex: user?.avatarColor ?? TFHexDefault.unassigned)
        self.avatarURL = user?.avatarUrl
        self.userID = user?.id
        self.size = size
    }

    var body: some View {
        if let path = avatarURL,
           let url = URL(string: APIClient.baseURL.absoluteString + path) {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    TFAvatar(size: size, image: image, initials: initials, tint: tint, userID: userID)
                } else {
                    TFAvatar(size: size, initials: initials, tint: tint, userID: userID)
                }
            }
        } else {
            TFAvatar(size: size, initials: initials, tint: tint, userID: userID)
        }
    }
}

/// Текст сообщения для шторки «Выделить текст».
struct SelectableMessageText: Identifiable {
    let id = UUID()
    let text: String
}
