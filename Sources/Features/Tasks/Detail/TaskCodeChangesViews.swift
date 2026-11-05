import SwiftUI

/// «Итог» → «Изменения кода»: что роль поменяла в своей ветке
/// (владелец 27.10.2026: «точно буду знать, что трогали, что не трогали»).
/// Только просмотр и замечания; вливание идёт через очередь слияний с
/// тестами, кнопки «Принять» здесь нет намеренно.
struct TaskCodeChangesRow: View {
    let taskID: String
    let changes: TaskCodeChanges
    var onToast: (String) -> Void = { _ in }

    @State private var isPresented = false

    var body: some View {
        CodeChangesSummaryButton(totals: changes.totals, summary: changes.summary,
                                 identifier: "outcome-code-changes") { isPresented = true }
            .tfSheet(isPresented: $isPresented) {
                NavigationStack {
                    CodeChangesScreen(
                        files: changes.files,
                        footer: changes.state == .merged ? "Уже влито в основную ветку." : "Ветка \(changes.branch), ещё не влита.",
                        sendTitle: "Отправить роли",
                        onToast: onToast
                    ) { text in
                        // Все замечания — одним комментарием карточки: роль
                        // прочтёт их при следующем запуске.
                        _ = try await APIClient().createComment(taskId: taskID, text: text)
                        onToast("Замечания отправлены роли")
                    }
                }
            }
    }
}

/// Ход роли в чате → под строкой токенов «Изменения кода» хода (владелец
/// 27.10.2026: «то же самое по окончании хода в чате, там, где токены»).
/// Замечания вставляются в поле ввода чата — владелец отправляет их сам.
struct TurnCodeChangesRow: View {
    let changes: TurnCodeChanges
    let onInsert: (String) -> Void

    @State private var isPresented = false

    var body: some View {
        CodeChangesSummaryButton(totals: changes.totals, summary: changes.summary,
                                 identifier: "chat.message.code-changes", quietIcon: true) { isPresented = true }
            .tfSheet(isPresented: $isPresented) {
                // Шторка — сначала до половины экрана, файл — тоже шторкой
                // снизу (владелец 27.10.2026).
                NavigationStack {
                    CodeChangesScreen(
                        files: changes.files,
                        footer: "Правки за этот ход. Изменения через команды терминала сюда не попадают.",
                        sendTitle: "В сообщение",
                        opensFileAsSheet: true
                    ) { text in onInsert(text) }
                }
                .presentationDetents([.medium, .large])
            }
    }
}

/// Строка «Изменения кода · 3 файла · +42 −7» — одна и в карточке, и в чате.
private struct CodeChangesSummaryButton: View {
    let totals: TaskCodeChanges.Totals
    let summary: String
    let identifier: String
    /// Значок и надпись как счётчики рядом: тот же шрифт и цвет (в чате, владелец 27.10.2026).
    var quietIcon = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: TFSpacing.sm) {
                if quietIcon {
                    HStack(spacing: TFSpacing.xs) {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .tfText(.meta)
                            .foregroundStyle(Color.tfSub)
                        Text("Изменения кода")
                            .tfText(.meta)
                            .foregroundStyle(Color.tfSub)
                    }
                } else {
                    Label("Изменения кода", systemImage: "chevron.left.forwardslash.chevron.right")
                        .tfText(.action)
                        .foregroundStyle(Color.tfText)
                }
                Spacer(minLength: 0)
                CodeCountsText(files: totals.files, additions: totals.additions, deletions: totals.deletions)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.tfDim)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Изменения кода, \(summary)")
        .accessibilityIdentifier(identifier)
    }
}

/// «3 файла · +42 −7»: зелёным добавленное, красным убранное.
private struct CodeCountsText: View {
    var files: Int?
    let additions: Int
    let deletions: Int

    var body: some View {
        HStack(spacing: TFSpacing.xs) {
            if let files {
                Text(TaskCodeChanges.filesWord(files)).foregroundStyle(Color.tfSub)
            }
            Text("+\(additions)").foregroundStyle(Color.tfGreen)
            Text("−\(deletions)").foregroundStyle(Color.tfRed)
        }
        .tfText(.meta)
        .monospacedDigit()
    }
}

/// Строка файла: имя, папка, что с ним сделано, сколько строк.
private struct CodeFileRow: View {
    let file: CodeFile

    var body: some View {
        HStack(spacing: TFSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(file.fileName).tfText(.row).lineLimit(1)
                if !file.directory.isEmpty {
                    Text(file.directory)
                        .tfText(.meta)
                        .foregroundStyle(Color.tfSub)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            Spacer(minLength: 0)
            if let badge = file.statusBadge {
                Text(badge).tfText(.meta).foregroundStyle(Color.tfSub)
            }
            CodeCountsText(additions: file.additions, deletions: file.deletions)
        }
    }
}

/// «Координация» → изменения кода: раскрываются прямо на экране, файл открывается
/// шторкой с диффом, замечания уходят роли одним комментарием (владелец 05.11.2026).
struct TaskCodeChangesDisclosure: View {
    let changes: TaskCodeChanges
    var title: String? = nil

    @State private var isExpanded = false
    @State private var comments: [CodeReviewComment] = []
    @State private var sheetFile: CodeFile?
    @State private var isSending = false
    @State private var sendError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            Button { isExpanded.toggle() } label: {
                HStack(spacing: TFSpacing.sm) {
                    Text(title ?? "Ветка карточки").tfText(.body).foregroundStyle(Color.tfText).lineLimit(1)
                    Spacer(minLength: 0)
                    CodeCountsText(files: changes.totals.files, additions: changes.totals.additions, deletions: changes.totals.deletions)
                    Image(systemName: "chevron.right")
                        .tfTypeFont(size: 13)
                        .foregroundStyle(Color.tfDim)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Изменения кода, \(changes.summary)")
            .accessibilityIdentifier("coord.code-changes")
            if isExpanded {
                Text(changes.state == .merged ? "Уже влито в основную ветку." : "Ветка \(changes.branch), ещё не влита.")
                    .tfText(.action)
                    .foregroundStyle(Color.tfSub)
                ForEach(changes.files) { file in
                    Button { sheetFile = file } label: { CodeFileRow(file: file).foregroundStyle(Color.tfText) }
                        .buttonStyle(TFTapRowStyle())
                }
                if !comments.isEmpty {
                    TFActionRow(title: "Отправить замечания роли: \(comments.count)", icon: "paperplane", isEnabled: !isSending) {
                        Task { await send() }
                    }
                }
                if let sendError { TFErrorBanner(sendError, variant: .block) }
            }
        }
        .tfSheet(item: $sheetFile) { file in
            NavigationStack { TaskCodeFileScreen(file: file, comments: $comments) }
                .presentationDetents([.medium, .large])
        }
    }

    private func send() async {
        isSending = true
        defer { isSending = false }
        do {
            _ = try await APIClient().createComment(taskId: changes.taskID, text: CodeReviewComment.message(comments))
            comments = []
            sendError = nil
        } catch {
            sendError = error.localizedDescription
        }
    }
}

/// Список файлов и отправка замечаний — общая шторка карточки и чата.
struct CodeChangesScreen: View {
    let files: [CodeFile]
    let footer: String
    let sendTitle: String
    /// Файл открывается шторкой снизу, а не переходом вбок (чат).
    var opensFileAsSheet = false
    var onToast: (String) -> Void = { _ in }
    let onSend: (String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var comments: [CodeReviewComment] = []
    @State private var isSending = false
    @State private var sheetFile: CodeFile?

    var body: some View {
        List {
            Section {
                ForEach(files) { file in
                    if opensFileAsSheet {
                        Button { sheetFile = file } label: { fileRow(file) }
                            .foregroundStyle(Color.tfText)
                    } else {
                        NavigationLink {
                            TaskCodeFileScreen(file: file, comments: $comments)
                        } label: {
                            fileRow(file)
                        }
                    }
                }
            } footer: {
                Text(footer)
            }
            if !comments.isEmpty {
                Section("Замечания") {
                    ForEach(comments) { comment in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(comment.location.replacingOccurrences(of: "`", with: ""))
                                .tfText(.meta)
                                .foregroundStyle(Color.tfSub)
                            Text(comment.text).tfText(.row)
                        }
                    }
                    .onDelete { comments.remove(atOffsets: $0) }
                }
            }
        }
        .tfNativeHeader("Изменения кода", displayMode: .inline)
        .tfSheet(item: $sheetFile) { file in
            NavigationStack {
                TaskCodeFileScreen(file: file, comments: $comments)
            }
            .presentationDetents([.medium, .large])
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Закрыть", systemImage: "xmark") { dismiss() }
            }
            if !comments.isEmpty {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSending ? "Отправляю…" : sendTitle) { Task { await send() } }
                        .disabled(isSending)
                }
            }
        }
    }

    private func fileRow(_ file: CodeFile) -> some View {
        CodeFileRow(file: file)
    }

    /// Все замечания — одним текстом: файл, строка, код, что не так.
    private func send() async {
        isSending = true
        defer { isSending = false }
        do {
            try await onSend(CodeReviewComment.message(comments))
            comments = []
            dismiss()
        } catch {
            onToast("Не отправилось: \(error.localizedDescription)")
        }
    }
}

private extension CodeFile {
    var statusBadge: String? {
        switch status {
        case .added: return "новый"
        case .deleted: return "удалён"
        case .renamed: return "переименован"
        case .modified, .unknown: return nil
        }
    }
}

/// Правка одного файла одной колонкой: убранное красным «−», добавленное
/// зелёным «+». Долгое нажатие на строку — «Прокомментировать».
struct TaskCodeFileScreen: View {
    let file: CodeFile
    @Binding var comments: [CodeReviewComment]

    @State private var commentLine: CodeLine?
    @State private var draft = ""

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if file.binary {
                    note("Двоичный файл — содержимое не показывается.")
                } else if file.hunks.isEmpty {
                    note(file.status == .renamed ? "Только переименован." : "Изменений в тексте нет.")
                }
                ForEach(Array(file.displayRows.enumerated()), id: \.offset) { _, row in
                    switch row {
                    case .line(let line): lineRow(line)
                    case .gap(let count): gapRow(count)
                    }
                }
                if file.truncated {
                    note("Файл большой: показана только часть правки.")
                }
            }
            .padding(.vertical, TFSpacing.sm)
        }
        .tfScreenBackground()
        .tfNativeHeader(file.fileName, displayMode: .inline)
        .alert("Замечание к строке", isPresented: Binding(
            get: { commentLine != nil },
            set: { if !$0 { commentLine = nil; draft = "" } }
        )) {
            TextField("Что не так", text: $draft, axis: .vertical)
            Button("Добавить") {
                if let line = commentLine, !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    comments.append(CodeReviewComment(path: file.path, line: line, text: draft))
                }
                commentLine = nil
                draft = ""
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            if let line = commentLine { Text(line.text.trimmingCharacters(in: .whitespaces)) }
        }
    }

    private func lineRow(_ line: CodeLine) -> some View {
        let hasComment = comments.contains { $0.path == file.path && $0.line == line }
        return HStack(alignment: .firstTextBaseline, spacing: TFSpacing.xs) {
            Text(line.new.map(String.init) ?? line.old.map(String.init) ?? "")
                .foregroundStyle(Color.tfDim)
                .frame(minWidth: 32, alignment: .trailing)
            Text(line.marker)
                .foregroundStyle(line.markerColor)
            Text(line.text.isEmpty ? " " : line.text)
                .foregroundStyle(Color.tfText)
                .frame(maxWidth: .infinity, alignment: .leading)
            if hasComment {
                Image(systemName: "text.bubble.fill").foregroundStyle(Color.tfBlue)
            }
        }
        .font(.system(.caption, design: .monospaced))
        .padding(.horizontal, TFSpacing.sm)
        .padding(.vertical, 1)
        .background(line.background)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Прокомментировать", systemImage: "text.bubble") { commentLine = line }
        }
    }

    private func gapRow(_ count: Int) -> some View {
        Text("… \(TaskCodeChanges.linesWord(count)) без изменений")
            .tfText(.meta)
            .foregroundStyle(Color.tfDim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, TFSpacing.sm)
            .padding(.vertical, TFSpacing.xs)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .tfText(.row)
            .foregroundStyle(Color.tfSub)
            .padding(TFSpacing.md)
    }
}

private extension CodeLine {
    var marker: String {
        switch kind {
        case .added: return "+"
        case .deleted: return "−"
        case .context: return " "
        }
    }

    var markerColor: Color {
        switch kind {
        case .added: return .tfGreen
        case .deleted: return .tfRed
        case .context: return .tfDim
        }
    }

    var background: Color {
        switch kind {
        case .added: return Color.tfGreen.opacity(0.12)
        case .deleted: return Color.tfRed.opacity(0.12)
        case .context: return .clear
        }
    }
}
