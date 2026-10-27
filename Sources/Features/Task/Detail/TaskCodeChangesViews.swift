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
        Button { isPresented = true } label: {
            HStack(spacing: TFSpacing.sm) {
                Label("Изменения кода", systemImage: "chevron.left.forwardslash.chevron.right")
                    .tfText(.action)
                    .foregroundStyle(Color.tfText)
                Spacer(minLength: 0)
                CodeCountsText(files: changes.totals.files, additions: changes.totals.additions,
                               deletions: changes.totals.deletions)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.tfDim)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Изменения кода, \(changes.summary)")
        .accessibilityIdentifier("outcome-code-changes")
        .sheet(isPresented: $isPresented) {
            NavigationStack {
                TaskCodeChangesScreen(taskID: taskID, changes: changes, onToast: onToast)
            }
        }
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

/// Список файлов и отправка замечаний роли.
struct TaskCodeChangesScreen: View {
    let taskID: String
    let changes: TaskCodeChanges
    var onToast: (String) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @State private var comments: [CodeReviewComment] = []
    @State private var isSending = false

    var body: some View {
        List {
            Section {
                ForEach(changes.files) { file in
                    NavigationLink {
                        TaskCodeFileScreen(file: file, comments: $comments)
                    } label: {
                        fileRow(file)
                    }
                }
            } footer: {
                Text(changes.state == .merged ? "Уже влито в основную ветку." : "Ветка \(changes.branch), ещё не влита.")
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
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Закрыть", systemImage: "xmark") { dismiss() }
            }
            if !comments.isEmpty {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSending ? "Отправляю…" : "Отправить роли") { Task { await send() } }
                        .disabled(isSending)
                }
            }
        }
    }

    private func fileRow(_ file: CodeFile) -> some View {
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

    /// Все замечания — одним комментарием карточки: роль прочтёт их при
    /// следующем запуске и поправит именно эти места.
    private func send() async {
        isSending = true
        defer { isSending = false }
        do {
            _ = try await APIClient().createComment(taskId: taskID, text: CodeReviewComment.message(comments))
            comments = []
            onToast("Замечания отправлены роли")
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
        .background(Color.tfBackground)
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
