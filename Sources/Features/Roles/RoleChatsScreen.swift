import SwiftUI
import NewChatCore
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
/// Аватар роли стоит слева у строки её чата. В корне раздела над полем поиска —
/// ряд ролей, как истории в Telegram (`ChatStoriesHeader.swift`, владелец 12.11.2026).
struct RoleChatsScreen: View {
    /// Экран, открытый переходом: у него системный возврат и своя область
    /// (роль или групповые чаты), корень раздела внутри него не живёт.
    private let openedScope: RoleSessionScope?

    init(openedScope: RoleSessionScope? = nil) {
        self.openedScope = openedScope
        _selectedScopeRaw = State(initialValue: openedScope?.stored ?? Self.ChatHomeScopeKey)
    }

    @Environment(SessionStore.self) private var session
    @State private var chats: [RoleChat] = []
    /// Панель «Комнаты» (владелец 21.10.2026): Общая, личные комнаты ролей и
    /// их лички. Раньше личный чат с Помощником стоял отдельным блоком над
    /// списком — теперь он в панели вместе с остальными ролями.
    @State private var rooms: ChatRoomsSnapshot?
    /// Что выбрано на панели: роль или групповые чаты (владелец 05.11.2026).
    /// По умолчанию — Помощник, с которым идёт основная работа.
    @State private var selectedScopeRaw = ChatHomeScopeKey
    /// Раскладка корня раздела: список всех комнат, а не сразу чья-то роль.
    private static let ChatHomeScopeKey = "all"
    /// Ключ держателя скрытия нижней панели для этого экрана.
    private static let tabBarHoldKey = "chats.section"
    private var selectedScope: RoleSessionScope { RoleSessionScope(stored: selectedScopeRaw) }
    @AppStorage("chats.showClosed") private var showsClosed = false
    @State private var listRequestVersion = 0
    /// Экран уже показывался: следующий `onAppear` — возврат из комнаты.
    @State private var hasAppeared = false
    @State private var isLoading = true
    @State private var errorMessage: String?
    @Environment(\.openRoute) private var openRoute
    @Environment(\.dismiss) private var dismiss
    /// Чат, выбранный для окончательного удаления: ждёт подтверждения,
    /// потому что вернуть его уже будет нельзя.
    @State private var pendingPurge: RoleChat?
    /// Штатный поиск в шапке списка.
    @State private var query = ""
    @State private var hits: [ChatSearchHit] = []
    @State private var isSearching = false
    /// Ряд ролей над поиском: где сейчас лента (кадры полёта кружков) и
    /// положение прокрутки, которым ряд прячут под шапку и раскрывают.
    @State private var storiesMotion = ChatStoriesMotion()
    @State private var storiesScroll = ScrollPosition(edge: .top)
    /// Нижний отступ короткого списка: дотягивает ленту до «видимая часть плюс
    /// ряд». Иначе при двух сессиях ленте не на что прокрутиться, ряд не
    /// прячется под шапку и висит раскрытым (владелец 12.11.2026: «в обычном
    /// состоянии аватарки должны быть в углу»). Ни `frame(minHeight:)`, ни
    /// пустая вставка в конце размер прокрутки не меняли — проверено журналом;
    /// `contentMargins` прокрутка учитывает.
    @State private var storiesFiller: CGFloat = 0
    /// Папки сессий — проекты TaskFlow (владелец 12.11.2026).
    @State private var projects: [ApiProject] = []
    /// Выбранная папка; пустая строка — «Все».
    @AppStorage("chats.folder") private var folderID = ""
    /// Новые сессии вместо чата Помощника — за флагом, пока старый чат рядом
    /// (владелец 12.11.2026: «из помощника — обычные сессии»).
    @AppStorage("chats.ownerSessions") private var ownerSessionsBeta = false
    @State private var ownerSessions: [SessionSummary] = []
    @State private var renamingSession: SessionSummary?
    /// Идёт горизонтальный свайп по папкам — строки не открываются.
    @State private var swipingFolders = false
    /// Когда палец последний раз шёл вбок: тап строки сразу после свайпа
    /// не открывает сессию (отключение нажатия посреди касания тап не отменяло).
    @State private var folderSwipeAt = Date.distantPast
    @State private var openedOwnerSession: OwnerSessionRoute?
    /// Правка порядка проектов в полоске; снимается тапом по пустому месту.
    @State private var folderEditing = false
    /// Меню проекта в полоске папок (владелец 12.11.2026).
    @State private var editingProject: ApiProject?
    @State private var sessionsProject: ApiProject?
    @State private var deletingProject: ApiProject?
    /// Чат, у которого меняют название.
    @State private var renameTarget: RoleChat?
    @State private var renameText = ""
    /// Закреплённые чаты — через запятую (владелец 08.11.2026).
    @AppStorage("chats.pinned") private var pinnedRaw = ""
    @Environment(RealtimeClient.self) private var realtime
    @State private var realtimeObserver = RealtimeObserverSlot<UUID>()
    private let api = APIClient()


    /// Список — сессии выбранного на панели пункта, ветки деревом под своей
    /// сессией. Лички ролей показаны отдельно, под сессиями роли.
    private var visibleRows: [(row: RoleSessionRow, chat: RoleChat)] {
        sessionRows(for: selectedScope)
    }

    private func sessionRows(for scope: RoleSessionScope) -> [(row: RoleSessionRow, chat: RoleChat)] {
        guard isOwner else {
            return chats.filter { !$0.isPermanentRoom }.map { (RoleSessionRow(id: $0.id, lines: []), $0) }
        }
        let byID = Dictionary(chats.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return RoleSessionList.rows(candidates, scope: scope).compactMap { row in
            byID[row.id].map { (row, $0) }
        }
    }

    /// Помощник — это сам чат, а не одна из ролей: корень вкладки — его
    /// сессии (владелец 12.11.2026).
    private static let assistantID = "u-secretary"

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

    /// Переписка выбранной роли с коллегами: открывается только на чтение.
    private var selectedRoleDMs: [ChatRoomsSnapshot.DirectRoom] {
        guard isOwner, case .role(let id) = selectedScope else { return [] }
        return rooms?.role(id)?.dms ?? []
    }
    private var headerTitle: String {
        guard isOwner else { return "Чаты" }
        if selectedScopeRaw == Self.ChatHomeScopeKey { return "Чат" }
        switch selectedScope {
        case .groups: return "Чаты"
        case .role(let id): return rooms?.role(id)?.name ?? "Чаты"
        }
    }
    private var isOwner: Bool { session.currentUser?.role == .owner }

    var body: some View {
        chatScroll
            .tfNativeHeader(headerTitle)
            .modifier(ChatsSystemSearch(enabled: openedScope != nil, text: $query))
            .tint(Color.tfText)
            .toolbar {
                if isOwner, !isHome, openedScope == nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { selectHome() } label: {
                            Label("Чаты", systemImage: "chevron.left")
                                .labelStyle(.titleAndIcon)
                        }
                        .accessibilityLabel("Все чаты")
                        .accessibilityIdentifier("chats.backHome")
                    }
                }
                if isOwner, !isHome {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { startNewSession() } label: { Image(systemName: "plus") }
                            .accessibilityLabel("Новая сессия")
                            .accessibilityIdentifier("chats.newSession")
                    }
                }
                if isOwner, isHome, ownerSessionsBeta {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink(value: OwnerSessionRoute(id: nil)) {
                            Image(systemName: "square.and.pencil")
                        }
                        .accessibilityLabel("Новый чат")
                        .accessibilityIdentifier("chats.newOwnerSession")
                    }
                } else if isOwner, isHome {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { Task { await startChat(withRole: Self.assistantID, projectID: folderID.isEmpty ? nil : folderID) } } label: {
                            Image(systemName: "square.and.pencil")
                        }
                        .accessibilityLabel("Новый чат")
                        .accessibilityIdentifier("chats.newAssistantChat")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            openRoute?(.chatArchive)
                        } label: {
                            Label("Архивные", systemImage: "archivebox")
                        }
                        .accessibilityIdentifier("chats.menu.archive")
                        if isOwner {
                            Button { ownerSessionsBeta.toggle() } label: {
                                Label("Новые сессии (бета)", systemImage: ownerSessionsBeta ? "checkmark" : "sparkles")
                            }
                            .accessibilityIdentifier("chats.menu.ownerSessions")
                        }
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
            .task(id: query) { await runSearch() }
            .task(id: ownerSessionsBeta) { await reloadOwnerSessions() }
            .navigationDestination(for: OwnerSessionRoute.self) { route in
                OwnerSessionScreen(route: route)
            }
            .navigationDestination(item: $openedOwnerSession) { route in
                OwnerSessionScreen(route: route)
            }
            .tfSheet(item: $editingProject) { project in
                ScrollView {
                    ProjectEditForm(project: project, apiClient: api, onSaved: {
                        editingProject = nil
                        Task { await reloadProjects() }
                    }, onCancel: { editingProject = nil })
                    .padding(TFSpacing.screenHorizontal)
                }
                .tfScreenBackground()
            }
            .tfSheet(item: $sessionsProject) { project in
                ChatsProjectSessionsSheet(project: project, sessions: assistantSessions) { add, remove in
                    Task { await moveChats(add: add, remove: remove, project: project.id) }
                }
            }
            .confirmationDialog("Удалить проект?", isPresented: Binding(
                get: { deletingProject != nil }, set: { if !$0 { deletingProject = nil } }
            ), titleVisibility: .visible) {
                Button("Удалить", role: .destructive) {
                    if let project = deletingProject { Task { await archiveProject(project) } }
                }
                Button("Отмена", role: .cancel) { deletingProject = nil }
            } message: {
                Text("Проект уйдёт в архив вместе с задачами, его сессии закроются. Вернуть можно из архива проектов.")
            }
            .alert("Название чата", isPresented: Binding(
                get: { renamingSession != nil }, set: { if !$0 { renamingSession = nil } })) {
                TextField("Название", text: $renameText)
                Button("Сохранить") {
                    let id = renamingSession?.id
                    let title = renameText.trimmingCharacters(in: .whitespaces)
                    renamingSession = nil
                    if let id { Task { await patchOwnerSession(id, .title(title)) } }
                }
                Button("Отмена", role: .cancel) { renamingSession = nil }
            }
            .alert("Название чата", isPresented: renamePresented) {
                TextField("Название", text: $renameText)
                Button("Сохранить") { Task { await applyRename() } }
                Button("Отмена", role: .cancel) { renameTarget = nil }
            }
            .task { await load() }
            .refreshable { await load() }
            // Внутри раздела нижней панели нет — только на главных экранах
            // (владелец 08.11.2026).
            .onChange(of: selectedScopeRaw, initial: true) { _, raw in
                if raw == Self.ChatHomeScopeKey {
                    ChatSectionState.shared.release(Self.tabBarHoldKey)
                } else {
                    ChatSectionState.shared.hold(Self.tabBarHoldKey)
                }
            }
            .onDisappear { ChatSectionState.shared.release(Self.tabBarHoldKey) }
            // Возврат из комнаты: бейдж непрочитанных считается на сервере от
            // отметки прочтения, а отпечаток списка от неё не зависит — с 304
            // локальная база вернула бы старый счётчик (владелец 08.11.2026:
            // «семёрка продолжает висеть»). Поэтому возврат — полное чтение.
            .onAppear {
                guard hasAppeared else { hasAppeared = true; return }
                Task { try? await refreshList(forceFull: true) }
            }
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
            .alert("Не удалось загрузить чаты", isPresented: errorPresented) {
                Button("Повторить") { Task { await load() } }
                Button("Закрыть", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
            .confirmationDialog(
                "Удалить чат навсегда?",
                isPresented: purgePresented,
                titleVisibility: .visible
            ) {
                Button("Удалить навсегда", role: .destructive) {
                    guard let chat = pendingPurge else { return }
                    pendingPurge = nil
                    Task { await purge(chat) }
                }
                Button("Отмена", role: .cancel) { pendingPurge = nil }
            } message: {
                Text("Переписка и вложения пропадут насовсем — вернуть их будет нельзя.")
            }
    }

    /// Список ленивый намеренно: строк может быть две сотни (боевая база —
    /// 216 чатов), и `VStack` верстал их все в первом же кадре. Переход
    /// «чаты → чаты роли» ждал эту вёрстку вместе с появлением поля поиска
    /// в шапке (владелец 11.11.2026: «при переходе из чатов в чаты роли идёт
    /// задержка с появлением списка и поля ввода»). `LazyVStack` строит только
    /// то, что видно, — остальное достраивается по прокрутке.
    private var chatScroll: some View {
        ScrollView {
            // Ряд и поиск — в обычном стеке над ленивым списком: внутри
            // ленивого их высота пересчитывалась, когда ряд уходил за экран, и
            // лента откатывалась на 76 точек (журнал 12.11.2026).
            VStack(spacing: 0) {
            if openedScope == nil {
                if storiesActive {
                    ChatStoriesRow(stories: stories, motion: storiesMotion)
                }
                ChatsSearchField(text: $query, motion: storiesMotion,
                                 rowHeight: storiesActive ? ChatStoriesLayout.rowHeight : 0)
            }
            // Полоска проектов — липкий заголовок списка: едет со списком,
            // а дойдя до шапки, прилипает под ней; поиск над ней схлопывается
            // (владелец 12.11.2026: «липкий подзаголовок»).
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
              Section {
               // Зазор до первой сессии от полоски проектов (владелец 13.11.2026).
               Group {
                if isSearchMode {
                    searchResults
                } else if isHome {
                    chatsHome
                } else if isLoading && chats.isEmpty {
                    TFLoading(.block)
                } else if visibleRows.isEmpty && selectedRoleDMs.isEmpty {
                    Text("Пока нет сессий.")
                        .tfText(.action)
                        .foregroundStyle(Color.tfDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, TFSpacing.screenHorizontal)
                        .padding(.top, TFSpacing.xl)
                } else {
                    sessionList(visibleRows)
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
                                            unread: 0, turn: dm.turn,
                                            member: rooms?.role(dm.peerID)?.member)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("chats.room.\(dm.chatID)")
                        }
                    }
                }
                // Добор высоты короткого списка — последней строкой самого
                // списка: ни рамка, ни вставка снаружи, ни `contentMargins`
                // длину прокрутки не меняли (последний сужал видимую область,
                // проверено журналом).
                if storiesActive, storiesFiller > 0 {
                    Color.clear.frame(height: storiesFiller)
                }
               }
               .overlay {
                   // Тап по списку во время правки полоски — «готово».
                   if folderEditing {
                       Color.clear.contentShape(Rectangle())
                           .onTapGesture { withAnimation(TFMotion.standard) { folderEditing = false } }
                   }
               }
               .padding(.top, ChatStoriesLayout.listTopGap)
              } header: {
                if openedScope == nil, isOwner, isHome, !projects.isEmpty, !isSearchMode {
                    ChatsFolderBar(projects: projects, selected: $folderID, actions: folderActions,
                                   editing: $folderEditing)
                }
              }
            }
            .padding(.bottom, TFSpacing.xl)
            .contentShape(Rectangle())
            // Свайп по списку влево/вправо — соседний проект, как папки в
            // Telegram (владелец 12.11.2026). Только явно горизонтальный жест:
            // вертикальная прокрутка его не задевает.
            .simultaneousGesture(DragGesture(minimumDistance: 30).onChanged { value in
                // Палец явно пошёл вбок — строки перестают ловить нажатие, иначе
                // свайп между проектами открывал сессию под пальцем (владелец 12.11.2026).
                let dx = value.translation.width, dy = value.translation.height
                if abs(dx) > 20, abs(dx) > abs(dy) * 2 {
                    swipingFolders = true
                    folderSwipeAt = Date()
                }
            }.onEnded { value in
                if swipingFolders {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { swipingFolders = false }
                }
                guard isOwner, isHome, !projects.isEmpty, !isSearchMode else { return }
                let dx = value.translation.width, dy = value.translation.height
                guard abs(dx) > 60, abs(dx) > abs(dy) * 2 else { return }
                let order = [""] + projects.map(\.id)
                let index = order.firstIndex(of: folderID) ?? 0
                let next = dx < 0 ? index + 1 : index - 1
                guard order.indices.contains(next) else { return }
                withAnimation(TFMotion.standard) { folderID = order[next] }
            })
            }
        }
        .scrollIndicators(.hidden)
        .scrollPosition($storiesScroll)
        .scrollTargetBehavior(ChatStoriesSnap(rowHeight: storiesActive ? ChatStoriesLayout.rowHeight : 0,
                                              limit: storiesActive && storiesFiller > 0
                                                  ? ChatStoriesLayout.rowHeight + ChatStoriesLayout.searchHeight : nil,
                                              motion: storiesMotion))
        // Упругость (владелец 13.11.2026): флик не утаскивает ряд ролей и
        // полоску проектов. При начале жеста гасим прошлую отметку, при
        // отпускании запоминаем, был ли ряд ещё раскрыт, — по ней
        // `ChatStoriesSnap` отбивает ленту назад вместо схлопывания.
        .onScrollPhaseChange { _, phase in
            switch phase {
            case .interacting:
                storiesMotion.releasedExpanded = false
            case .decelerating:
                storiesMotion.releasedExpanded = storiesMotion.progress >= 0.5
            default:
                break
            }
        }
        .onScrollGeometryChange(for: ChatStoriesGeometry.self) { geo in
            ChatStoriesGeometry(offset: geo.contentOffset.y + geo.contentInsets.top,
                                topInset: geo.contentInsets.top,
                                container: geo.containerSize.height,
                                content: geo.contentSize.height,
                                spare: geo.contentSize.height + geo.contentInsets.top
                                    + geo.contentInsets.bottom - geo.containerSize.height)
        } action: { _, geo in
            trackStories(geo)
        }

        .overlay {
            if storiesActive {
                ChatStoriesFlight(stories: stories, motion: storiesMotion, title: headerTitle) {
                    withAnimation(TFMotion.standard) { storiesScroll.scrollTo(y: 0) }
                }
            }
        }
        .tfScreenBackground()
    }

    /// Ряд ролей есть только в корне раздела, на «Все чаты».
    private var storiesActive: Bool {
        openedScope == nil && isOwner && isHome && !stories.isEmpty
    }

    /// Роли ряда: сначала свои роли, потом внешние агенты. Помощника в ряду
    /// нет — он и есть этот чат, а не одна из ролей (владелец 12.11.2026).
    private var stories: [ChatStory] {
        let roles = rooms?.roles.filter { $0.personalChatID != nil && $0.id != Self.assistantID } ?? []
        let internalRoles = roles.filter { !RoleAvatarAsset.isExternalChatRole(roleKey: $0.roleKey, userID: $0.id) }
        let externalRoles = roles.filter { RoleAvatarAsset.isExternalChatRole(roleKey: $0.roleKey, userID: $0.id) }
        return (internalRoles + externalRoles).map {
            ChatStory(id: $0.id, name: $0.name, roleKey: $0.roleKey, member: $0.member,
                      working: $0.working || $0.personalTurn?.running == true)
        }
    }

    /// Кадр прокрутки → полёт кружков. Первый раз, когда список дорос до
    /// высоты, при которой ряд можно спрятать, лента встаёт на высоту ряда:
    /// в покое кружки лежат стопкой у заголовка.
    private func trackStories(_ geo: ChatStoriesGeometry) {
        storiesMotion.offset = geo.offset
        storiesMotion.topInset = geo.topInset
        if storiesActive {
            // Считается от высоты экрана, а не от нижней вставки: отступ сам
            // входит во вставку, и расчёт от неё замыкался (324 → 0 → 324).
            // Нижняя панель вкладок в расчёт не входит — лишние точки внизу
            // безвредны. +2: запас на дробные точки.
            // Высота прокрутки сама уменьшается на нижний отступ (707 → 256 в
            // журнале), поэтому берём наибольшую виденную — она от отступа не
            // зависит, и расчёт не качается.
            storiesMotion.fullHeight = max(storiesMotion.fullHeight, geo.container)
            let base = geo.content - storiesFiller
            // Наибольшее смещение = высота содержимого минус высота прокрутки,
            // шапка в него не входит (журнал: при 737 содержимого лента
            // упиралась в 30 вместо 106).
            let need = max(0, storiesMotion.fullHeight + ChatStoriesLayout.rowHeight + ChatStoriesLayout.searchHeight + 2 - base)
            if abs(need - storiesFiller) > 1 {
                storiesFiller = need
                // Ленивый список сообщает новую высоту только при следующей
                // прокрутке, поэтому к ряду едем сами, не дожидаясь события.
                if !storiesMotion.placed {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        storiesScroll.scrollTo(y: ChatStoriesLayout.rowHeight)
                    }
                }
            }
        }
        guard storiesActive, !storiesMotion.placed, geo.spare >= ChatStoriesLayout.rowHeight - 1 else { return }
        // Отметка — только когда лента действительно встала на высоту ряда:
        // прокрутка, данная в тот же кадр, что и нижний отступ, обрезалась до
        // нуля, а повтора не было. Сама прокрутка — на следующем кадре.
        if geo.offset >= ChatStoriesLayout.rowHeight - 1 {
            storiesMotion.placed = true
            return
        }
        DispatchQueue.main.async { storiesScroll.scrollTo(y: ChatStoriesLayout.rowHeight) }
    }

    /// Сессии деревом: ветки линиями под своей сессией.
    @ViewBuilder
    private func sessionList(_ rows: [(row: RoleSessionRow, chat: RoleChat)]) -> some View {
        ForEach(Array(rows.enumerated()), id: \.element.row.id) { index, item in
            HStack(spacing: 0) {
                if !item.row.lines.isEmpty { SessionBranchLines(lines: item.row.lines) }
                sessionLink(item.chat, isBranch: !item.row.lines.isEmpty)
            }
            .allowsHitTesting(!swipingFolders)
            .fixedSize(horizontal: false, vertical: true)
            // Под сессией с ветками линии не прерываем разделителем.
            if index < rows.count - 1, rows[index + 1].row.lines.isEmpty {
                rowDivider(afterAvatar: rowMember(item.chat) != nil)
            }
        }
    }

    /// Поле поиска: пока введено что-то, вместо секций — выдача по всем чатам.
    private var isSearchMode: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    private var renamePresented: Binding<Bool> {
        Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })
    }

    private var pinnedIDs: Set<String> {
        Set(pinnedRaw.split(separator: ",").map(String.init).filter { !$0.isEmpty })
    }

    private func togglePin(_ chat: RoleChat) {
        var ids = pinnedIDs
        if ids.contains(chat.id) { ids.remove(chat.id) } else { ids.insert(chat.id) }
        pinnedRaw = ids.sorted().joined(separator: ",")
    }

    private func runSearch() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { hits = []; return }
        try? await Task.sleep(nanoseconds: 250_000_000)
        guard !Task.isCancelled else { return }
        isSearching = true
        defer { isSearching = false }
        hits = (try? await api.chatSearch(query: text)) ?? []
    }

    private func applyRename() async {
        guard let chat = renameTarget else { return }
        let title = renameText.trimmingCharacters(in: .whitespaces)
        renameTarget = nil
        do {
            _ = try await api.renameRoleChat(id: chat.id, title: title)
            try await refreshList()
        } catch { errorMessage = error.localizedDescription }
    }

    /// Корень раздела: все комнаты списком, чтобы было видно, что выбираешь
    /// (владелец 08.11.2026: «раздел чата сразу на какой-то роли — странно»).
    private var isHome: Bool { selectedScopeRaw == Self.ChatHomeScopeKey }

    /// Корень вкладки — сессии Помощника плоским списком (владелец 12.11.2026:
    /// «помощник — он и есть этот чат, и у него сразу идут сессии»). Роли —
    /// кружками в ряду над поиском; разделы «Роли», «Внешние агенты» и каталог
    /// «Групповые чаты» из вкладки убраны («всю эту хламину удаляем»). Данные
    /// на сервере не трогаются.
    @ViewBuilder
    private var chatsHome: some View {
        if ownerSessionsBeta {
            ownerSessionsHome
        } else {
            assistantChatsHome
        }
    }

    /// Корень вкладки на новых сессиях: только корневые сессии разговора,
    /// ответвления и субагенты — внутри сессии.
    @ViewBuilder
    private var ownerSessionsHome: some View {
        let all = ownerSessions.filter { $0.relation == nil || $0.relation == .root }
        let roots = folderID.isEmpty ? all : all.filter { $0.projectID == folderID }
        let pinned = roots.filter(\.pinned)
        let rest = roots.filter { !$0.pinned }
        if !pinned.isEmpty {
            homeHeader("Закреплённые")
            ownerSessionRows(pinned)
            homeHeader("Сессии")
        }
        if roots.isEmpty {
            Text("Пока нет сессий.")
                .tfText(.action)
                .foregroundStyle(Color.tfDim)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, TFSpacing.screenHorizontal)
                .padding(.top, TFSpacing.xl)
        } else {
            ownerSessionRows(rest)
        }
    }

    /// Строки сессий — та же строка, что у чатов: название (своё или первая
    /// реплика), превью первой реплики, время последнего изменения.
    @ViewBuilder
    private func ownerSessionRows(_ rows: [SessionSummary]) -> some View {
        ForEach(Array(rows.enumerated()), id: \.element.id) { index, summary in
            Button {
                guard Date().timeIntervalSince(folderSwipeAt) > 0.4 else { return }
                openedOwnerSession = OwnerSessionRoute(id: summary.id)
            } label: {
                ChatListRow(
                    title: summary.title ?? summary.firstMessage.map { String($0.prefix(60)) } ?? "Новый чат",
                    preview: summary.title == nil ? "" : (summary.firstMessage ?? ""),
                    time: ChatListTime.label(summary.modified),
                    unread: 0
                )
            }
            .buttonStyle(.plain)
            .contextMenu { ownerSessionMenu(summary) }
            .accessibilityIdentifier("chats.ownerSession.\(summary.id)")
            if index < rows.count - 1 { rowDivider() }
        }
    }

    @ViewBuilder
    private func ownerSessionMenu(_ summary: SessionSummary) -> some View {
        Button { Task { await patchOwnerSession(summary.id, .pinned(!summary.pinned)) } } label: {
            Label(summary.pinned ? "Открепить" : "Закрепить", systemImage: summary.pinned ? "pin.slash" : "pin")
        }
        Button {
            renameText = summary.title ?? ""
            renamingSession = summary
        } label: { Label("Переименовать", systemImage: "pencil") }
        if !projects.isEmpty {
            Menu {
                ForEach(projects) { project in
                    Button(project.name) { Task { await patchOwnerSession(summary.id, .project(project.id)) } }
                }
                if summary.projectID != nil {
                    Button("Без проекта") { Task { await patchOwnerSession(summary.id, .project(nil)) } }
                }
            } label: { Label("Перенести в проект", systemImage: "folder") }
        }
        Button(role: .destructive) { Task { await patchOwnerSession(summary.id, .archived(true)) } } label: {
            Label("В архив", systemImage: "archivebox")
        }
    }

    private func patchOwnerSession(_ id: String, _ patch: SessionMetaPatch) async {
        do {
            try await SessionAPIClient().patchSession(id: id, patch)
            await reloadOwnerSessions()
        } catch { errorMessage = error.localizedDescription }
    }

    private func reloadOwnerSessions() async {
        guard ownerSessionsBeta, isOwner else { return }
        if let list = try? await SessionAPIClient().listSessions() { ownerSessions = list.sessions }
    }

    @ViewBuilder
    private var assistantChatsHome: some View {
        let all = isOwner ? sessionRows(for: .role(Self.assistantID)) : visibleRows
        let rows = folderID.isEmpty ? all : all.filter { $0.chat.projectID == folderID }
        let pinned = rows.filter { pinnedIDs.contains($0.chat.id) && $0.row.lines.isEmpty }
        if !pinned.isEmpty {
            homeHeader("Закреплённые")
            ForEach(Array(pinned.enumerated()), id: \.element.chat.id) { index, item in
                sessionLink(item.chat, isBranch: false)
                if index < pinned.count - 1 { rowDivider(afterAvatar: rowMember(item.chat) != nil) }
            }
            homeHeader("Сессии")
        }
        if isLoading && chats.isEmpty {
            TFLoading(.block)
        } else if rows.isEmpty {
            Text("Пока нет сессий.")
                .tfText(.action)
                .foregroundStyle(Color.tfDim)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, TFSpacing.screenHorizontal)
                .padding(.top, TFSpacing.xl)
        } else {
            sessionList(rows)
        }
    }

    /// Подпись раздела по центру. Это подзаголовок: кегль и гарнитура —
    /// токен «Подзаголовок» из «Настройки → Шрифт». В чате шкала приложения
    /// выключена, поэтому для этой строки её включают обратно: иначе
    /// `.title` уехал бы в чатовый «Заголовок».
    private func homeHeader(_ title: String) -> some View {
        Text(title)
            .tfText(.title)
            .foregroundStyle(Color.tfSub)
            .environment(\.tfTypeSettingsEnabled, true)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, TFSpacing.xs)
    }

    /// Выдача поиска по всем чатам: название, откуда нашлось и кусок текста.
    @ViewBuilder
    private var searchResults: some View {
        if hits.isEmpty {
            Text(isSearching ? "Ищу…" : "Ничего не нашлось.")
                .tfText(.action)
                .foregroundStyle(Color.tfDim)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, TFSpacing.screenHorizontal)
                .padding(.top, TFSpacing.xl)
        } else {
            ForEach(Array(hits.enumerated()), id: \.element.id) { index, hit in
                NavigationLink(value: AppRoute.roleChat(id: hit.chatID)) {
                    ChatListRow(title: hit.title,
                                preview: hit.subtitle ?? "",
                                time: nil, unread: 0, turn: nil)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("chats.hit.\(hit.chatID)")
                if index < hits.count - 1 { rowDivider() }
            }
        }
    }

    private func selectHome() {
        // Экран открыт переходом — «назад» один: системный возврат.
        if openedScope != nil {
            dismiss()
            return
        }
        selectedScopeRaw = Self.ChatHomeScopeKey
    }

    // MARK: - Строка сессии

    /// Разделитель отбит до начала текста: у строки с аватаром — за кружком.
    private func rowDivider(afterAvatar: Bool = false) -> some View {
        let extra: CGFloat = afterAvatar ? TFAvatar.Size.xl.rawValue + TFSpacing.xs : 0
        return TFDivider(inset: TFSpacing.screenHorizontal + extra)
    }

    private func sessionLink(_ chat: RoleChat, isBranch: Bool) -> some View {
        NavigationLink(value: AppRoute.roleChat(id: chat.id)) {
            chatRow(chat, isBranch: isBranch)
                .opacity(chat.closedAt == nil ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .contextMenu {
            // Владелец 08.11.2026: «как в GPT — архивировать чат либо
            // удалить насовсем, и понятно, максимально». Никаких «закрыть
            // сессию»: архив и есть уборка, а вернуть можно из архива.
            // Сам архив — пунктом меню, один на все роли.
            Button { togglePin(chat) } label: {
                Label(pinnedIDs.contains(chat.id) ? "Открепить" : "Закрепить",
                      systemImage: pinnedIDs.contains(chat.id) ? "pin.slash" : "pin")
            }
            .accessibilityIdentifier("chats.row.pin")
            if isOwner, isHome, !projects.isEmpty {
                Menu {
                    Button { Task { await moveChat(chat, to: nil) } } label: {
                        Label("Без проекта", systemImage: chat.projectID == nil ? "checkmark" : "tray")
                    }
                    ForEach(projects) { project in
                        Button { Task { await moveChat(chat, to: project.id) } } label: {
                            if chat.projectID == project.id {
                                Label(project.name, systemImage: "checkmark")
                            } else {
                                Text(project.name)
                            }
                        }
                    }
                } label: {
                    Label("Перенести в проект", systemImage: "folder")
                }
                .accessibilityIdentifier("chats.row.move")
            }
            Button { Task { await exportSessions(of: nil, only: chat) } } label: {
                Label("Экспорт в Markdown", systemImage: "square.and.arrow.up")
            }
            .accessibilityIdentifier("chats.row.export")
            if isOwner && !chat.isPermanentRoom {
                Button {
                    renameText = chat.title ?? ""
                    renameTarget = chat
                } label: {
                    Label("Переименовать", systemImage: "pencil")
                }
                .accessibilityIdentifier("chats.row.rename")
                Button { Task { await moveToArchive(chat) } } label: {
                    Label("Архивировать чат", systemImage: "archivebox")
                }
                .accessibilityIdentifier("chats.row.archive")
                Button(role: .destructive) { pendingPurge = chat } label: {
                    Label("Удалить навсегда", systemImage: "trash")
                }
                .accessibilityIdentifier("chats.row.purge")
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

    private var errorPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
    private var purgePresented: Binding<Bool> {
        Binding(get: { pendingPurge != nil }, set: { if !$0 { pendingPurge = nil } })
    }
    private func startNewSession() {
        switch selectedScope {
        case .groups: break
        case .role(let id): Task { await startChat(withRole: id) }
        }
    }

    /// Новая сессия с ролью — тот же `POST /api/chats`, что у «Чат с
    /// участниками»; без названия: его даст первое сообщение.
    private func startChat(withRole roleID: String, projectID: String? = nil) async {
        do {
            var chat = try await api.createRoleChat(title: nil, memberIDs: [roleID])
            // Выбрана папка — новый чат сразу в ней (владелец 12.11.2026).
            if let projectID { chat = try await api.setRoleChatProject(id: chat.id, projectID: projectID) }
            try await refreshList()
            openRoute?(.roleChat(id: chat.id))
        } catch { errorMessage = error.localizedDescription }
    }

    /// Меню проекта в полоске папок.
    private var folderActions: ChatsFolderBar.Actions {
        ChatsFolderBar.Actions(
            edit: { editingProject = $0 },
            addSessions: { sessionsProject = $0 },
            reorder: { order in Task { await saveProjectOrder(order) } },
            export: { project in Task { await exportSessions(of: project) } },
            delete: { deletingProject = $0 }
        )
    }

    /// Сессии Помощника для листа «Добавить сессии».
    private var assistantSessions: [ChatsProjectSessionsSheet.Session] {
        sessionRows(for: .role(Self.assistantID))
            .filter { $0.row.lines.isEmpty }
            .map { .init(id: $0.chat.id, title: rowTitle($0.chat, isBranch: false), projectID: $0.chat.projectID) }
    }

    private func reloadProjects() async {
        if let list = try? await api.projects() { projects = list }
    }

    private func moveChats(add: [String], remove: [String], project: String) async {
        do {
            for id in add { _ = try await api.setRoleChatProject(id: id, projectID: project) }
            for id in remove { _ = try await api.setRoleChatProject(id: id, projectID: nil) }
            try await refreshList()
        } catch { errorMessage = error.localizedDescription }
    }

    /// «Изменить порядок → Готово»: позиции проектов по новому порядку.
    private func saveProjectOrder(_ order: [ApiProject]) async {
        projects = order
        do {
            for (position, item) in order.enumerated() where item.position != position {
                _ = try await api.patchProject(id: item.id, fields: ["position": .number(Double(position))])
            }
            await reloadProjects()
        } catch { errorMessage = error.localizedDescription }
    }

    /// «Удалить» — как в «Проектах»: проект в архив вместе с задачами.
    private func archiveProject(_ project: ApiProject) async {
        deletingProject = nil
        do {
            try await api.deleteProject(id: project.id)
            if folderID == project.id { folderID = "" }
            await reloadProjects()
            try await refreshList()
        } catch { errorMessage = error.localizedDescription }
    }

    /// Экспорт в Markdown: одна сессия или все сессии проекта одним файлом.
    private func exportSessions(of project: ApiProject?, only chat: RoleChat? = nil) async {
        let chosen: [RoleChat] = if let chat { [chat] } else {
            sessionRows(for: .role(Self.assistantID)).map(\.chat).filter { $0.projectID == project?.id }
        }
        guard !chosen.isEmpty else {
            errorMessage = "В проекте пока нет сессий"
            return
        }
        do {
            var transcripts: [RoleChatTranscript] = []
            for item in chosen {
                let messages = try await api.roleChatMessages(id: item.id, projection: .full)
                transcripts.append(RoleChatTranscript(title: rowTitle(item, isBranch: false), messages: messages))
            }
            let title = chat.map { rowTitle($0, isBranch: false) } ?? (project?.name ?? "Сессии")
            try RoleChatMarkdownExport.share(title: title, transcripts: transcripts)
        } catch { errorMessage = error.localizedDescription }
    }

    /// Переложить сессию в проект-папку или достать из папки.
    private func moveChat(_ chat: RoleChat, to projectID: String?) async {
        do {
            _ = try await api.setRoleChatProject(id: chat.id, projectID: projectID)
            try await refreshList()
        } catch { errorMessage = error.localizedDescription }
    }

    /// «Архивировать чат»: уходит из списка в «Архив», история остаётся и её
    /// можно вернуть.
    private func moveToArchive(_ chat: RoleChat) async {
        do {
            _ = try await api.archiveRoleChat(id: chat.id)
            await hideLocalChat(id: chat.id)
            try await refreshList()
        } catch { errorMessage = error.localizedDescription }
    }

    /// «Удалить насовсем»: работает и без архива (как в GPT), вернуть нельзя —
    /// поэтому сначала подтверждение.
    private func purge(_ chat: RoleChat) async {
        do {
            try await api.purgeRoleChat(id: chat.id)
            await hideLocalChat(id: chat.id)
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
            // Одна форма у всех сессий (владелец 12.11.2026): контекст есть
            // всегда — без замера «0%», — и рядом стадия: ждёт или работает.
            contextLabel: chat.contextUsage?.label ?? "Контекст 0%",
            status: chat.turn?.running == true ? "В работе" : "Ожидает",
            projectName: chat.projectName == chat.title ? nil : chat.projectName,
            member: rowMember(chat)
        )
    }

    /// Слева у строки — собеседник, когда он один. В группе лиц несколько,
    /// один кружок за всех не ставится.
    /// Внутри экрана конкретной роли кружка нет вовсе: роль названа заголовком,
    /// а одинаковый кружок у каждой сессии только шумит (владелец 11.11.2026).
    /// В корне вкладки теперь сессии Помощника — у всех один и тот же кружок,
    /// поэтому его тоже нет (владелец 12.11.2026: «тупо, когда все сессии с
    /// одной аватаркой»).
    private func rowMember(_ chat: RoleChat) -> RoleChatMember? {
        guard !isHome, RoleSessionList.showsAvatar(in: selectedScope) else { return nil }
        let others = chat.others(excluding: session.currentUser?.id)
        return others.count == 1 ? others.first : nil
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

    /// Чтение локальной базы — в фоне, всегда.
    ///
    /// База на диске: двести с лишним чатов читаются и разбираются из JSON
    /// заметное время. Ждали её на главном потоке — и переход с экрана чатов
    /// в чаты роли вставал вместе со штатным полем поиска в шапке (владелец
    /// 11.11.2026: «наверху поле ввода поиска… задержка какая-то идёт»).
    /// `Task.detached` — не для порядка, а чтобы разбор шёл не там, где рисуют.
    private func localChats(includeClosed: Bool) async -> [RoleChat]? {
        await Task.detached(priority: .userInitiated) {
            try? LocalStore.shared.chats(includeClosed: includeClosed)
        }.value
    }

    /// Дисковый кэш ответов (`ResponseCache`) — тоже чтение файла; в фоне.
    private func cachedChats(includeClosed: Bool) async -> [RoleChat]? {
        await Task.detached(priority: .userInitiated) {
            APIClient().cachedRoleChats(includeClosed: includeClosed)
        }.value
    }

    private func cachedRooms() async -> ChatRoomsSnapshot? {
        await Task.detached(priority: .userInitiated) {
            APIClient().cachedChatRooms()
        }.value
    }

    private func localETag() async -> String? {
        await Task.detached(priority: .userInitiated) {
            LocalStore.shared.syncState(SyncStateKeys.chatsETag)
        }.value
    }

    /// Запись ответа сервера в локальную базу — тоже в фоне: это чтение всех
    /// id, запись (upsert) и уборка лишнего в одной транзакции.
    private func storeChats(_ data: Data, keeping ids: Set<String>, etag: String?) async {
        await Task.detached(priority: .utility) {
            try? LocalStore.shared.upsertChats(data)
            try? LocalStore.shared.hideChats(notIn: ids)
            LocalStore.shared.setSyncState(SyncStateKeys.chatsETag, etag)
        }.value
    }

    private func hideLocalChat(id: String) async {
        await Task.detached(priority: .utility) {
            try? LocalStore.shared.hideChat(id: id)
        }.value
    }

    private func load() async {
        // Локальная база: список виден сразу, без сети. Это первое, что
        // рисуется, — сеть его только обновит.
        if chats.isEmpty, let local = await localChats(includeClosed: showsClosed), !local.isEmpty {
            chats = local
        }
        // Прошлый список из кэша — виден сразу, сеть его обновит.
        if chats.isEmpty, let cached = await cachedChats(includeClosed: showsClosed) { chats = cached }
        if rooms == nil, isOwner { rooms = await cachedRooms() }
        isLoading = true
        defer { isLoading = false }
        if isOwner, let list = try? await api.projects() { projects = list }
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
        let etag = forceFull ? nil : await localETag()
        async let freshChats = api.roleChatsSync(
            includeClosed: showsClosed,
            etag: etag
        )
        let freshRooms: ChatRoomsSnapshot? = isOwner ? try? await api.chatRooms() : nil
        let result = try await freshChats
        guard version == listRequestVersion, !Task.isCancelled else { return }
        if result.notModified {
            // Список не менялся — берём его из локальной базы.
            if let local = await localChats(includeClosed: showsClosed), !local.isEmpty {
                chats = local
            }
        } else {
            let envelope = try api.decode(APIClient.RoleChatsSyncEnvelope.self, from: result.data)
            chats = envelope.chats
            // В базу — сырое тело ответа сервера. Полный список — это ровно то,
            // что видит владелец: всё прочее в локальной таблице устарело
            // (закрытые сессии, уборка, правки с другого устройства). Без
            // уборки «удалённая» сессия возвращалась из базы после перезапуска.
            await storeChats(result.data, keeping: Set(envelope.chats.map(\.id)), etag: result.etag)
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

/// Обёртка для шторки фото: роль в списке — строка, `sheet(item:)` ждёт Identifiable.

/// Что ряду ролей нужно знать о прокрутке списка.
private struct ChatStoriesGeometry: Equatable {
    /// Прокрутка от верха списка.
    var offset: CGFloat
    /// Строка состояния плюс шапка.
    var topInset: CGFloat
    /// Высота самой прокрутки.
    var container: CGFloat
    /// Высота содержимого ленты вместе с добором.
    var content: CGFloat
    /// На сколько список длиннее экрана.
    var spare: CGFloat
}
