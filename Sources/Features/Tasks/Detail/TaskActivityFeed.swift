import SwiftUI

/// Лента активности задачи — она же переписка по задаче (владелец 12.11.2026:
/// «воспользуемся лентой активности как чатом», групповых чатов задач больше
/// нет). Живёт во вкладке «Лента» экрана «Координация»; в карточке — только
/// последние записи и переход сюда.
///
/// На виду — комментарии: владельца и ответы ролей. Служебное — события
/// задачи и переписка ролей между собой, пришедшая из чата, — сворачивается
/// в одну строку «N служебных», раскрывается тапом.
///
/// Строки перенесены из `TaskCardContent` без изменений вида (плоская строка,
/// без аватарок: они тянули видео-портреты и вешали открытие карточки).
struct TaskActivityFeed: View {
    enum Mode: Equatable {
        /// Полная лента с полем ввода и «Загрузить ещё».
        case full
        /// Последние `count` записей без поля ввода — превью в карточке.
        case preview(count: Int)
    }

    let viewModel: TaskFormViewModel
    var mode: Mode = .full

    @Environment(SessionStore.self) private var session
    @Environment(\.colorScheme) private var colorScheme
    @State private var commentFocus = NoteEditorFocusState()
    @State private var visibleCount = 50
    /// Раскрытые группы служебного (по id первой записи группы).
    @State private var openGroups: Set<String> = []

    var body: some View {
        if mode == .full { composer }
        let items = Self.fold(entries: shownEntries, ownerID: session.currentUser?.id)
        ForEach(items) { item in
            switch item {
            case .entry(let entry):
                row(entry)
            case .service(let id, let entries):
                serviceRow(id: id, entries: entries)
                if openGroups.contains(id) {
                    ForEach(entries) { row($0) }
                }
            }
        }
        if mode == .full, visibleCount < viewModel.journalEntries.count {
            Button("Загрузить ещё (\(viewModel.journalEntries.count - visibleCount))") {
                visibleCount = min(visibleCount + 50, viewModel.journalEntries.count)
            }
            .buttonStyle(.borderless)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var shownEntries: [TaskJournalEntry] {
        switch mode {
        case .full: Array(viewModel.journalEntries.suffix(visibleCount))
        case .preview(let count):
            // В превью — последние записи, которые на виду, а не служебное.
            Array(viewModel.journalEntries.filter { !Self.isService($0, ownerID: session.currentUser?.id) }.suffix(count))
        }
    }

    // MARK: - Ввод

    /// Enter — перенос строки, отправка только кнопкой (владелец 30.09.2026:
    /// «Интер не отправляет сообщения ни в одном месте приложения»). Поле —
    /// тот же `BlockDocumentEditor`, что у названия и описания карточки.
    private var composer: some View {
        HStack(alignment: .bottom) {
            BlockDocumentEditor(
                blocks: Binding(get: { viewModel.commentBlocks }, set: { viewModel.commentBlocks = $0 }),
                focus: commentFocus,
                placeholder: "Комментарий",
                textColor: UIColor(colorScheme == .light ? Color.tfText : Color.tfSub)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Отправить") { Task { await viewModel.sendComment() } }
                .buttonStyle(.borderless)
                .disabled(
                    !viewModel.isEditing
                    || viewModel.commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                .accessibilityIdentifier("task.feed.send")
        }
    }

    // MARK: - Свёртка служебного

    enum Item: Identifiable {
        case entry(TaskJournalEntry)
        case service(id: String, entries: [TaskJournalEntry])

        var id: String {
            switch self {
            case .entry(let entry): entry.id
            case .service(let id, _): "service-\(id)"
            }
        }
    }

    /// Служебное — событие задачи или сообщение из чата не от владельца
    /// (переписка ролей между собой).
    static func isService(_ entry: TaskJournalEntry, ownerID: String?) -> Bool {
        switch entry {
        case .event: return true
        case .comment(let comment):
            return comment.isFromChat && comment.userId != ownerID
        }
    }

    /// Подряд идущее служебное — одной группой; одиночная служебная запись
    /// остаётся строкой, сворачивать её незачем.
    static func fold(entries: [TaskJournalEntry], ownerID: String?) -> [Item] {
        var items: [Item] = []
        var run: [TaskJournalEntry] = []
        func flush() {
            if run.count > 1, let first = run.first {
                items.append(.service(id: first.id, entries: run))
            } else {
                items.append(contentsOf: run.map(Item.entry))
            }
            run = []
        }
        for entry in entries {
            if isService(entry, ownerID: ownerID) {
                run.append(entry)
            } else {
                flush()
                items.append(.entry(entry))
            }
        }
        flush()
        return items
    }

    private func serviceRow(id: String, entries: [TaskJournalEntry]) -> some View {
        let isOpen = openGroups.contains(id)
        return Button {
            withAnimation(TFMotion.standard) {
                if isOpen { openGroups.remove(id) } else { openGroups.insert(id) }
            }
        } label: {
            TFListRow(
                title: "\(entries.count) \(Self.pluralService(entries.count))",
                trailing: isOpen
                    ? AnyView(Image(systemName: "chevron.down").tfTypeFont(size: 13).foregroundStyle(Color.tfDim))
                    : nil,
                titleStyle: .meta,
                titleColor: .tfDim,
                verticalPadding: TFSpacing.xs,
                horizontalPadding: 0,
                chevron: isOpen ? .hidden : .shown
            )
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier("task.feed.service")
        .accessibilityValue(isOpen ? "развёрнуто" : "свёрнуто")
    }

    static func pluralService(_ n: Int) -> String {
        let mod100 = n % 100
        if mod100 >= 11 && mod100 <= 14 { return "служебных" }
        switch n % 10 {
        case 1: return "служебное"
        default: return "служебных"
        }
    }

    // MARK: - Строки (из карточки, без изменений вида)

    @ViewBuilder
    private func row(_ entry: TaskJournalEntry) -> some View {
        switch entry {
        case .comment(let comment):
            // Сообщение привязанного чата открывает саму переписку
            // (владелец 21.09.2026).
            if comment.isFromChat, let chatID = comment.chatID {
                NavigationLink(value: AppRoute.roleChat(id: chatID)) {
                    commentContent(comment)
                }
            } else {
                commentContent(comment)
            }
        case .event(let event):
            // Кто сделал — обязательно (владелец 22.09.2026). Нет автора —
            // действие системы. Имя и действие разделены точкой, чтобы не
            // согласовывать глагол с родом («Система взял»).
            HStack(alignment: .firstTextBaseline) {
                (Text(event.actorName?.isEmpty == false ? event.actorName! : "Система").fontWeight(.medium)
                    + Text(" · ")
                    + Text(TaskJournalView.eventText(event)))
                    .tfText(.action).foregroundStyle(Color.tfSub)
                Spacer()
                if let date = event.createdAtDate {
                    Text(TaskDateText.relativeTime(date)).tfText(.meta).foregroundStyle(Color.tfSub)
                }
            }
        }
    }

    @ViewBuilder
    private func commentContent(_ comment: ApiComment) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(comment.userName?.isEmpty == false ? comment.userName! : "Система")
                    .tfText(.body).fontWeight(.medium)
                if comment.isFromChat {
                    // Пометка нейтральная: синий акцент в приложении не используется.
                    TFPill("из чата", color: Color.tfSub)
                }
                Spacer()
                if let date = comment.createdAtDate {
                    Text(TaskDateText.relativeTime(date)).tfText(.meta).foregroundStyle(Color.tfSub)
                }
            }
            let isRole = comment.userId.map { author in
                author == "u-secretary" || author.hasPrefix("role_") || viewModel.roles.contains { $0.accountID == author }
            } ?? false
            TaskRoleReply(text: comment.text, isRole: isRole, serverBlocks: ChatServerBlock.list(from: comment.textBlocks))
            // Вложения — только именами: превью тяжёлые и вешали открытие.
            if let attachments = comment.attachments, !attachments.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(attachments) { attachment in
                        Text("📎 \(attachment.fileName)")
                            .tfText(.meta)
                            .foregroundStyle(Color.tfSub)
                    }
                }
                .padding(.top, 4)
            }
        }
    }
}
