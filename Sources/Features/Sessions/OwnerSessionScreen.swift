import SwiftUI
import NewChatCore

/// Маршрут экрана сессии владельца. Свой тип, а не `AppRoute`: стек вкладки —
/// `NavigationPath`, а сессии пока живут за флагом в «Чате».
struct OwnerSessionRoute: Hashable {
    /// `nil` — новая сессия (`POST /api/sessions`).
    let id: String?
    let token = UUID()
}

// ═══ НОВАЯ ВЕРСИЯ ЧАТА: «Сессии (бета)» ═══
// Работа над чатом с Помощником идёт ЗДЕСЬ: этот экран, `SessionLiveTurn.swift`
// и движок `Sources/Features/Sessions/Engine/`. Старая версия — комната чата
// роли `Sources/Features/Roles/RoleChatRoomScreen.swift` — правки сессий туда
// не вносить (владелец 13.11.2026: «разграничить, чтобы агенты не путались»).
// Общие компоненты (`RoleLiveTurnView.swift`, `RoleReplyMarkdown`,
// `ChatComposerPill`, `ChatVoiceComposer`) задевают ОБЕ версии.

/// Сессия владельца — обычный разговор с Помощником (владелец 12.11.2026:
/// «из помощника делать не роль, а просто обычные сессии… без всяких
/// очередей и процента»). Движок — из прототипа NewChatTF
/// (`Sources/Features/Sessions/Engine`), вид — наш: лента сообщений чата,
/// поле ввода `ChatVoiceComposer`, ответы Помощника блоками конверта.
/// Пока сессия отвечает, отправка подмешивает сообщение в ответ (`steer`),
/// «стоп» обрывает ответ.
struct OwnerSessionScreen: View {
    let route: OwnerSessionRoute

    @State private var model = SessionViewModel(apiClient: SessionAPIClient(), realtime: SessionRealtimeClient())
    @State private var voice = RoleChatVoiceController()
    @FocusState private var composerFocused: Bool
    /// Клавиатура реально на экране — как в комнате чата (d431f8c4).
    @State private var keyboardUp = false
    /// Когда начался текущий ответ — для таймера «Работает» в пилюле.
    @State private var workStartedAt: Date?
    /// Лента у низа — иначе у пилюли кружок «вниз», как в комнате чата.
    @State private var isNearBottom = true
    @State private var scrollDownTick = 0
    /// Замер контекста сессии для кольца в поле ввода (как в комнате).
    @State private var context: ChatContextSnapshot?
    @Environment(\.dismiss) private var dismiss
    @Environment(SecretaryVoiceViewModel.self) private var voiceSession: SecretaryVoiceViewModel?
    /// Метки этой сессии (название, проект, закрепление) — из списка сессий.
    @State private var summary: SessionSummary?
    @State private var projects: [ApiProject] = []
    @State private var isContentsPresented = false
    @State private var scrollTarget: String?
    @State private var isRenaming = false
    @State private var renameText = ""
    /// Раскрытые полосы «Действия» и шаги — переживают пересборку строк.
    @StateObject private var feedExpansion = RoleFeedExpansion()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: TFSpacing.md) {
                    // История ходами, как в старой комнате: размышления и
                    // шаги — полосой «Действия», ответ — разметкой сервера
                    // (владелец 12.11.2026: «вернуть живой ход… инструменты, DIF»).
                    ForEach(model.displayRows) { row in
                        OwnerSessionRowView(row: row, expansion: feedExpansion)
                            .id(row.id)
                    }
                    if !model.liveTurn.isEmpty {
                        // Идущий ход — тем же пузырём, что ход роли в комнате:
                        // текст проявляется по словам, шаги встают по мере вызова.
                        SessionLiveTurnBubble(turn: liveRoleTurn, showsName: false,
                                           isComplete: !model.isStreaming, pacesText: true,
                                           expansionRow: Self.liveTurnID, expansion: feedExpansion)
                            .id(Self.liveTurnID)
                    }
                    // Кубик хода из ленты убран (владелец 13.11.2026: «убери кубик…
                    // там было 4 иконки, двигающиеся» — нужен был не кубик).
                    // Было: Кубик хода (видео владельца 12.11.2026): думает,
                    // инструмент, роли, пишет — поворотом на свою грань.
                    // Рядом словечко, как у Claude Code: грань — чем занят Помощник.
                    // Значок хода в ленте снят: анимация — у «Действия»,
                    // словечки — в пилюле (владелец 13.11.2026: «мне по факту нужно только это»).
                    if model.displayRows.isEmpty && !model.isStreaming && !model.isLoading {
                        Text("Напишите, что нужно сделать.")
                            .tfText(.action)
                            .foregroundStyle(Color.tfDim)
                            .padding(.top, TFSpacing.xl)
                    }
                    // Метка самого низа ленты (владелец 13.11.2026: кружок «вниз»
                    // не прятался у дна). Видна — лента у низа; к ней же едет
                    // кнопка «вниз». Расчёт по геометрии с отступом поля ввода
                    // ошибался на высоту поля и считал дно «не низом».
                    // Раньше: «У низа» — по тем же правилам, что лента комнаты чата
                    // (`ChatFeedScrollPolicy`, с верхним и нижним отступами): кружок
                    // «вниз» у низа прятался не всегда (владелец 12.11.2026). Смена
                    // пишется в журнал телефона — если кружок опять не спрячется,
                    // будет видно, что считала лента.
                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomID)
                        .onScrollVisibilityChange(threshold: 0.01) { visible in
                            isNearBottom = visible
                            ClientLog.shared.add("session=\(model.activeSessionID ?? "new") scroll:nearBottom=\(visible)")
                        }
                }
                .padding(.horizontal, TFSpacing.screenHorizontal)
                .padding(.vertical, TFSpacing.md)
            }
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            // Боковой ползунок прокрутки владельцу мешает (12.11.2026).
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            // Тап в ленту сворачивает клавиатуру — тот же приём, что в комнате
            // (владелец 12.11.2026: «убрать клавиатуру никак не могу»).
            .keyboardDismissShield(isActive: composerFocused || keyboardUp) { dismissKeyboard() }
            .onChange(of: model.timeline.count) { _, _ in if isNearBottom { scrollToEnd(proxy) } }
            // Своё сообщение — всегда к низу, даже если читал выше.
            .onChange(of: model.pendingOutgoing) { _, pending in if pending != nil { scrollToEnd(proxy) } }
            // Ход растёт — лента идёт за низом, только если владелец у низа
            // (как лента комнаты: уехал читать выше — не дёргаем).
            .onChange(of: model.liveTurn) { _, _ in if isNearBottom { scrollToEnd(proxy) } }
            .onChange(of: scrollDownTick) { _, _ in
                guard let target = bottomTargetID else { return }
                withAnimation(TFMotion.standard) { proxy.scrollTo(target, anchor: .bottom) }
            }
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                withAnimation(TFMotion.standard) { proxy.scrollTo(target, anchor: .top) }
                scrollTarget = nil
            }
        }
        .safeAreaInset(edge: .bottom) {
            // Зазор между полем ввода и клавиатурой / низом экрана.
            // Та же нижняя панель, что в комнате чата (владелец 12.11.2026:
            // «готовая панель ввода с верхней пилюлей — забрать и перенести»):
            // статусная пилюля над полем ввода и само поле.
            VStack(spacing: 0) {
                ChatComposerPill(
                    // Работающие роли-субагенты — в пилюле, как в чатах ролей.
                    plans: [], members: [], status: ChatComposerStatus(running: SessionRoleCall.running(in: model.liveTurn.items)),
                    onDeletePlan: { _ in }, onOpenChat: { _ in },
                    onSendNow: { _ in }, onRemove: { _ in },
                    onStop: model.isStreaming ? { Task { await model.abort() } } : nil,
                    showsScrollDown: !isNearBottom,
                    onScrollDown: { scrollDownTick += 1 },
                    isWorking: model.isStreaming,
                    workStartedAt: workStartedAt,
                    // Словечко кубика вместо «Работает» (владелец 13.11.2026).
                    workingWordSeed: model.liveTurn.startedAt.map { Int($0.timeIntervalSince1970) } ?? 0
                )
                composer.padding(.bottom, TFSpacing.sm)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardUp = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardUp = false
        }
        .environment(\.roleReplyPlainFallback, true)
        .tfScreenBackground()
        .tfNativeHeader(headerTitle, displayMode: .inline)
        // Внутри сессии нижней панели вкладок нет (владелец 08.11.2026,
        // 12.11.2026): модификатор на самом экране — на `NavigationStack`
        // панель оставалась и налезала на панель ввода.
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if let id = model.activeSessionID {
                if let voiceSession {
                    ToolbarItem(placement: .topBarTrailing) {
                        // Голосовой разговор с Помощником в этой сессии: мост
                        // пишет реплики в сессию (владелец 12.11.2026).
                        TFIconButton("waveform", label: "Голосовой разговор с Помощником владельца") {
                            Task { await voiceSession.start(chatID: id) }
                        }
                        .accessibilityIdentifier("session.voice.start")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isContentsPresented = true } label: {
                        Image(systemName: "list.bullet.indent")
                    }
                    .accessibilityLabel("Содержание чата")
                    .accessibilityIdentifier("session.contents")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu { sessionMenu } label: { Image(systemName: "ellipsis") }
                        .accessibilityLabel("Меню сессии")
                        .accessibilityIdentifier("session.menu")
                }
            }
        }
        .tfSheet(isPresented: $isContentsPresented) {
            RoleChatContentsSheet(entries: model.timeline
                .filter { $0.kind == .message && ($0.role == "user" || $0.role == "assistant") }
                .map { .init(id: $0.id, author: $0.role == "user" ? "Вы" : "Помощник", text: $0.text) }
            ) { id in
                isContentsPresented = false
                scrollTarget = id
            }
        }
        .alert("Название чата", isPresented: $isRenaming) {
            TextField("Название", text: $renameText)
            Button("Сохранить") { Task { await patch(.title(renameText.trimmingCharacters(in: .whitespaces))) } }
            Button("Отмена", role: .cancel) {}
        }
        .overlay {
            if model.isLoading && model.activeSessionID == nil { TFLoading(.block) }
        }
        .alert("Сессия", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("Понятно", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .task {
            await model.open(sessionID: route.id)
            await reloadSummary()
            projects = (try? await APIClient().projects()) ?? []
            await model.loadModels()
            await reloadContext()
        }
        // Внутри сессии нижней панели вкладок нет — как в комнате чата
        // (владелец 08.11.2026: панель только на главных экранах).
        .onAppear { ChatSectionState.shared.hold(Self.tabBarHoldKey) }
        // Ответ закончен — перечитываем снимок: в нём ответ уже с разметкой.
        .onChange(of: model.isStreaming) { _, streaming in
            workStartedAt = streaming ? Date() : nil
            if !streaming { Task { await model.refresh(); await reloadContext() } }
        }
        .onChange(of: voiceSession?.presentation.isActive ?? false) { _, active in
            if !active { Task { await model.refresh() } }
        }
        .onDisappear {
            model.disconnect()
            ChatSectionState.shared.release(Self.tabBarHoldKey)
        }
    }

    private static let liveID = "owner-session-live"
    private static let liveTurnID = "owner-session-live-turn"
    private static let bottomID = "owner-session-bottom"

    /// Идущий ход сессии в форме хода роли для `SessionLiveTurnBubble`.
    private var liveRoleTurn: RoleChatLiveTurn {
        RoleChatLiveTurn(chatID: model.activeSessionID ?? "session", userID: "u-secretary", name: "Помощник",
                         startedAt: model.liveTurn.startedAt.map { $0.ISO8601Format() },
                         items: model.liveTurn.items, thinking: nil)
    }

    private func dismissKeyboard() {
        composerFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    /// Ключ держателя скрытия нижней панели для сессии владельца.
    private static let tabBarHoldKey = "owner.session"

    /// Состояние хода для кубика — из того, что уже приходит событиями сессии.
    private var activityPhase: TFActivityPhase {
        if model.childSessions.contains(where: { model.state.childActivity[$0.id] == .running }) { return .roles }
        if model.liveActivities.contains(where: { $0.kind == .tool && $0.status == .running }) { return .tool }
        if model.liveTurn.hasRunningTool { return .tool }
        if case .text? = model.liveTurn.items.last { return .writing }
        return .thinking
    }

    private var headerTitle: String {
        if model.activeSessionID == nil { return "Новый чат" }
        return summary?.title ?? summary?.firstMessage.map { String($0.prefix(40)) } ?? "Новый чат"
    }

    /// Меню «…» сессии — как у строк списка, плюс экспорт и модель.
    @ViewBuilder
    private var sessionMenu: some View {
        Button { renameText = summary?.title ?? ""; isRenaming = true } label: {
            Label("Переименовать", systemImage: "pencil")
        }
        Button { Task { await patch(.pinned(!(summary?.pinned ?? false))) } } label: {
            Label(summary?.pinned == true ? "Открепить" : "Закрепить",
                  systemImage: summary?.pinned == true ? "pin.slash" : "pin")
        }
        if !projects.isEmpty {
            Menu {
                ForEach(projects) { project in
                    Button { Task { await patch(.project(project.id)) } } label: {
                        if summary?.projectID == project.id { Label(project.name, systemImage: "checkmark") } else { Text(project.name) }
                    }
                }
                if summary?.projectID != nil {
                    Button("Без проекта") { Task { await patch(.project(nil)) } }
                }
            } label: { Label("Перенести в проект", systemImage: "folder") }
        }
        if !model.availableModelGroups.isEmpty {
            Menu {
                ForEach(model.availableModelGroups) { group in
                    Menu(group.title) {
                        ForEach(group.models, id: \.self) { item in
                            Button {
                                Task { try? await model.selectModel(provider: item.provider, id: item.id) }
                            } label: {
                                if model.currentModel?.id == item.id { Label(item.displayName, systemImage: "checkmark") } else { Text(item.displayName) }
                            }
                        }
                    }
                }
            } label: { Label("Модель: \(model.currentModelTitle)", systemImage: "cpu") }
        }
        if let file = exportFile {
            ShareLink(item: file) { Label("Экспорт в Markdown", systemImage: "square.and.arrow.up") }
        }
        Button(role: .destructive) {
            Task {
                await patch(.archived(true))
                dismiss()
            }
        } label: { Label("В архив", systemImage: "archivebox") }
    }

    /// Переписка сессии файлом .md для «Поделиться».
    private var exportFile: URL? {
        let items = model.timeline.filter { $0.kind == .message && ($0.role == "user" || $0.role == "assistant") }
        guard !items.isEmpty else { return nil }
        let title = headerTitle
        let body = items.map { "**\($0.role == "user" ? "Вы" : "Помощник"):**\n\n\($0.text)" }
        let markdown = (["# \(title)", ""] + body).joined(separator: "\n\n")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(title.prefix(60)).md")
        try? markdown.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func reloadContext() async {
        guard let id = model.activeSessionID else { return }
        context = try? await SessionAPIClient().context(sessionID: id)
    }

    private func reloadSummary() async {
        guard let id = model.activeSessionID,
              let list = try? await SessionAPIClient().listSessions() else { return }
        summary = list.sessions.first { $0.id == id }
    }

    private func patch(_ change: SessionMetaPatch) async {
        guard let id = model.activeSessionID else { return }
        do {
            try await SessionAPIClient().patchSession(id: id, change)
            await reloadSummary()
        } catch { model.errorMessage = error.localizedDescription }
    }

    private var composer: some View {
        ChatVoiceComposer(
            text: $model.composerText,
            placeholder: "Сообщение",
            sessionLook: true,
            canSendText: model.activeSessionID != nil
                && !model.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !model.isSendingCommand,
            voice: voice,
            onAttachmentSource: { _ in },
            onSendText: { Task { await model.send() } },
            onSendVoice: { _ in false },
            onDiscardVoice: { _ in },
            contextControls: AnyView(ChatContextControl(snapshot: context, roleName: "Помощник", loadError: nil) {
                Task { await reloadContext() }
            }),
            isResponding: model.isStreaming,
            onStop: { Task { await model.abort() } },
            focus: $composerFocused
        )
    }

    /// Нижняя видимая строка ленты. Раньше целью был `timeline.last?.id`, а у
    /// строк ленты свои id — прокрутка не доезжала до низа, и кружок «вниз»
    /// не прятался (владелец 13.11.2026).
    private var bottomTargetID: String? { Self.bottomID }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        guard let target = bottomTargetID else { return }
        withAnimation(TFMotion.standard) { proxy.scrollTo(target, anchor: .bottom) }
    }
}

/// Одна запись ленты сессии: сообщение владельца, ответ Помощника или шаг
/// инструмента (свёрнутой строкой). Размышления и шаги инструментов идут той
/// же полосой «Действия» и шторкой шага, что в комнате.
private struct OwnerSessionRowView: View {
    let row: SessionFeedRow
    let expansion: RoleFeedExpansion

    var body: some View {
        switch row {
        case .user(_, let text):
            HStack {
                Spacer(minLength: 48)
                Text(text)
                    .tfText(.body)
                    .textSelection(.enabled)
                    .foregroundStyle(Color.tfText)
                    .padding(TFSpacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: TFRadius.lg, style: .continuous)
                            .fill(Color.tfFieldDark)
                    )
            }
        case .work(let id, let items):
            SessionLiveItemsList(items: items, showsActionPreview: true,
                              expansionRow: id, expansion: expansion)
        case .reply(_, let text, let blocks):
            OwnerSessionReply(text: text, isStreaming: false,
                              blocks: blocks.flatMap { ChatServerBlock.list(fromFoundation: $0.sessionFoundation) })
        }
    }
}

/// Ответ Помощника: конверт с блоками — нашими блоками ответа, обычный
/// текст — тем же Markdown, что в чате.
private struct OwnerSessionReply: View {
    let text: String
    let isStreaming: Bool
    var blocks: [ChatServerBlock]? = nil

    var body: some View {
        if let json = SessionFeed.envelope(in: text) {
            // Конверт — блоками, как в чате; сырой JSON не показываем, даже если
            // модель написала ответ словами и следом им же конвертом (13.11.2026).
            ChatStructuredOutputView(json: json, isStreaming: isStreaming)
        } else {
            // Готовый ответ — тем же разбором, что живой ход (владелец 13.11.2026:
            // «как оно вначале пишется, и всё, не приходил этот итоговый ответ»).
            // Разметку сервера (`blocks`) здесь не берём: иначе по концу хода
            // текст перерисовывался в другой вид.
            RoleReplyMarkdown(text: text)
        }
    }

    static func inlineMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}
