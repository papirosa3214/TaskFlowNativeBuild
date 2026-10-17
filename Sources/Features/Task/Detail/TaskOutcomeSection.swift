import SwiftUI
import UniformTypeIdentifiers

/// Содержимое секции «Итог» карточки (владелец 01.10.2026): что решили и
/// что сдали — одним местом. Вердикт проверяющего и итог каждой роли
/// открываются шторкой целиком; документы — заметки проекта, открываются
/// как заметка, в меню — «В базу знаний» и «Сохранить на телефон».
/// Строки — прямо в `Section` списка карточки (оборачивает
/// `collapsibleSection` в `TaskFormScreen`), без своих фонов.
struct TaskOutcomeContent: View {
    let outcome: ApiTaskOutcome
    /// Название роли по ключу (`analyst` → «Аналитик») — из ролей карточки.
    let roleTitle: (String) -> String
    let onToast: (String) -> Void
    /// Открыть документ (заметку) — шторкой поверх карточки.
    let onOpenDocument: (String) -> Void
    /// Открыть отдельный read-only предпросмотр Markdown.
    let onPreviewDocument: (String, String) -> Void
    /// Чат этой задачи: ответ владельца на результат роли уходит туда. nil —
    /// чата нет, поле ответа не показываем.
    var replyChatID: String? = nil
    /// Подзадача шага по его ключу в плане — чтобы ответ был адресован
    /// именно этому шагу, а не лёг в чат отдельной репликой.
    var subtaskID: (String) -> String? = { _ in nil }

    private let api = APIClient()

    var body: some View {
        if let verdict = outcome.verdict {
            OutcomeTextRow(sheetTitle: "Вердикт проверяющего", markdown: verdict.findings, replyChatID: replyChatID) {
                HStack(spacing: TFSpacing.sm) {
                    Image(systemName: verdict.isApproved ? "checkmark.seal.fill" : "exclamationmark.bubble.fill")
                        .foregroundStyle(verdict.isApproved ? Color.tfGreen : Color.tfOrange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Проверяющий: \(verdict.title)")
                            .tfText(.action)
                            .foregroundStyle(Color.tfText)
                        if let date = verdict.createdDate {
                            Text(RelativeTime.relative(from: date))
                                .tfText(.meta)
                                .foregroundStyle(Color.tfDim)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.tfReadableTertiary)
                }
            }
        }

        ForEach(outcome.nodes) { node in
            OutcomeTextRow(sheetTitle: nodeTitle(node), markdown: node.displayResult ?? "Роль ничего не написала.", replyChatID: replyChatID,
                           replySubtaskID: node.slotKey.flatMap(subtaskID)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(nodeTitle(node))
                        .tfText(.action)
                        .foregroundStyle(Color.tfText)
                    if let result = node.displayResult, !result.isEmpty {
                        Text(result)
                            .tfText(.meta)
                            .foregroundStyle(Color.tfSub)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        ForEach(outcome.documents) { document in
            HStack(spacing: TFSpacing.sm) {
                // Кнопка, а не переход по маршруту: карточка сама открыта
                // шторкой, и маршрут в ней некому обработать.
                Button { onOpenDocument(document.id) } label: {
                    Label(document.title, systemImage: document.isOutcome ? "flag.checkered" : "doc.text")
                        .tfText(.action)
                        .foregroundStyle(Color.tfText)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Menu {
                    Button {
                        onPreviewDocument(document.id, document.title)
                    } label: {
                        Label("Предпросмотр", systemImage: "doc.text.magnifyingglass")
                    }
                    Button {
                        Task { await pushToKnowledge(document) }
                    } label: {
                        Label("В базу знаний", systemImage: "books.vertical")
                    }
                    ShareLink(
                        item: NoteMarkdownExport(id: document.id, title: document.title),
                        preview: SharePreview(document.title)
                    ) {
                        Label("Сохранить на телефон", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(Color.tfSub)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Действия с документом")
            }
        }

        if let branch = outcome.branch {
            VStack(alignment: .leading, spacing: 2) {
                Label("Код: ветка \(branch.name)", systemImage: "arrow.triangle.branch")
                    .tfText(.action)
                    .foregroundStyle(Color.tfText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(branch.commit) — \(branch.subject)")
                    .tfText(.meta)
                    .foregroundStyle(Color.tfSub)
                    .lineLimit(2)
            }
        }
    }

    private func nodeTitle(_ node: ApiTaskOutcome.Node) -> String {
        guard let role = node.role else { return node.displayTitle }
        return "\(roleTitle(role)) — \(node.displayTitle)"
    }

    private func pushToKnowledge(_ document: ApiTaskOutcome.Document) async {
        do {
            try await api.pushNoteToKnowledge(noteId: document.id)
            onToast("«\(document.title)» — в базе знаний")
        } catch {
            onToast("Не удалось отправить в базу знаний")
        }
    }
}

/// Строка, тап по которой открывает полный текст шторкой. Шторка своя у
/// каждой строки: один `.sheet` на весь набор строк в `List` не сработал бы.
private struct OutcomeTextRow<Label: View>: View {
    let sheetTitle: String
    let markdown: String
    var replyChatID: String? = nil
    var replySubtaskID: String? = nil
    @ViewBuilder let label: () -> Label
    @State private var isPresented = false

    var body: some View {
        Button { isPresented = true } label: {
            label().contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isPresented) {
            OutcomeTextSheet(title: sheetTitle, markdown: markdown, replyChatID: replyChatID, replySubtaskID: replySubtaskID)
        }
    }
}

/// Полный текст вердикта или итога роли — системная шторка на пол-экрана.
private struct OutcomeTextSheet: View {
    let title: String
    let markdown: String
    var replyChatID: String? = nil
    var replySubtaskID: String? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var reply = ""
    @State private var isSending = false
    @State private var replyStatus: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                RoleReplyMarkdown(text: markdown)
                    .textSelection(.enabled)
                    .padding(.horizontal, TFSpacing.screenHorizontal)
                    .padding(.vertical, TFSpacing.md)
            }
            .tfNativeHeader(title, displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let replyChatID { replyBar(chatID: replyChatID) }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

extension OutcomeTextSheet {
    /// Ответ владельца прямо из шторки (07.10.2026): роль пишет «жду…» —
    /// отвечаем здесь же. Результат роли — не сообщение чата, «ответить на
    /// него» как на реплику нельзя; поэтому ответ уходит в чат этой задачи
    /// адресованным шагу, чей результат открыт (`recipient_subtask_id`), с
    /// пометкой, на что это ответ. Сообщение владельца в чате задачи будит план.
    private func replyBar(chatID: String) -> some View {
        // Тот же вид, что у поля ввода в чатах (`ChatVoiceComposer`): стеклянная
        // капсула высотой `TFChatComposer.elementHeight`, красный самолётик.
        VStack(alignment: .leading, spacing: TFSpacing.xs) {
            if let replyStatus {
                Text(replyStatus).tfText(.caption).foregroundStyle(Color.tfSub)
                    .padding(.horizontal, 12)
            }
            HStack(spacing: 8) {
                TextField("Ответить", text: $reply, axis: .vertical)
                    // Поле ввода — `.input` 16 (было системное 17)
                    // (LOCK-TYPOGRAPHY-SPEC, дефект В).
                    .tfText(.input)
                    .lineLimit(1...4)
                    .frame(maxWidth: .infinity, minHeight: TFChatComposer.elementHeight, alignment: .leading)
                    .contentShape(Rectangle())
                    .textInputAutocapitalization(.sentences)
                    .accessibilityIdentifier("outcome-reply-field")
                let canSend = !isSending && !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                Button { Task { await sendReply(chatID: chatID) } } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(canSend ? Color.tfRed : Color.tfReadableSecondary)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel("Отправить ответ")
                .accessibilityIdentifier("outcome-reply-send")
            }
            .padding(.horizontal, 12)
            .frame(minHeight: TFChatComposer.elementHeight)
            .voiceCapsuleSurface()
        }
        .padding(.horizontal).padding(.vertical, 10)
    }

    private func sendReply(chatID: String) async {
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        isSending = true
        defer { isSending = false }
        do {
            _ = try await APIClient().sendRoleChatMessage(chatID: chatID, text: "По «\(title)»: \(text)",
                                                         recipientSubtaskID: replySubtaskID)
            reply = ""
            replyStatus = "Отправлено в чат задачи"
        } catch {
            replyStatus = "Не отправлено: \(error.localizedDescription)"
        }
    }
}

/// Документ файлом `.md` для «Поделиться»: текст берётся с сервера в момент
/// выбора — сохранить в «Файлы», отправить себе, открыть в другом
/// приложении.
struct NoteMarkdownExport: Transferable {
    let id: String
    let title: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: UTType(filenameExtension: "md") ?? .plainText) { item in
            let note = try await APIClient().note(id: item.id, format: "markdown")
            let name = item.title
                .components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|"))
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(name.isEmpty ? "Документ" : String(name.prefix(120)))
                .appendingPathExtension("md")
            try (note.markdown ?? "").write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }
}
