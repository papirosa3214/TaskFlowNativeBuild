import SwiftUI

/// Уточнение роли у владельца из чата (26.10.2026).
///
/// Форма под ответом роли: текст вопроса, варианты с пояснениями, поле
/// «свой вариант» и кнопка отправки. После ответа карточка показывает, что
/// выбрано, и больше не даёт ответить.
///
/// Нативный вид: без своих `tint`, фонов и имитаций — только компоненты
/// дизайн-системы (`TFCard`, `TFButton`, `TFTextField`, `FlowLayout`).
struct RoleQuestionCard: View {
    let question: ChatQuestion
    var nativePresentation = false
    let onAnswer: ([ChatQuestionAnswerEntry], String?) async throws -> Void

    @State private var selected: [Int: Set<String>] = [:]
    @State private var custom: [Int: String] = [:]
    @State private var note: String = ""
    @State private var isSending = false
    @State private var failure: String?

    var body: some View {
        if nativePresentation {
            nativeContent
        } else {
            styledContent
        }
    }

    private var styledContent: some View {
        // По образцу владельца (06.11.2026): тёмная карточка без рамки,
        // варианты — плитки столбцом, выбранный — красный, как кнопка.
        TFCard(surface: .dark) {
            VStack(alignment: .leading, spacing: TFSpacing.md) {
                header
                ForEach(Array(question.questions.enumerated()), id: \.offset) { index, item in
                    questionBlock(index: index, item: item)
                }
                if !question.isAnswered {
                    TFTextField("Заметка для роли (необязательно)", text: $note, surface: .tile)
                    sendButton
                } else {
                    answeredFooter
                }
                if let failure {
                    Text(failure).tfText(.meta).foregroundStyle(Color.tfSub)
                }
            }
        }
        .accessibilityIdentifier("chat.question")
        .hintAnchor(HintAnchorID.chatQuestion)
    }

    private var nativeContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(question.isAnswered ? "Ответ отправлен" : "Нужен ваш выбор")
                .font(.headline)
            ForEach(Array(question.questions.enumerated()), id: \.offset) { index, item in
                VStack(alignment: .leading, spacing: 12) {
                    if let header = item.header, !header.isEmpty {
                        Text(header).font(.subheadline)
                    }
                    Text(item.question)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(item.options) { option in
                        Button {
                            toggle(index: index, label: option.label, multi: item.multiSelect)
                        } label: {
                            HStack(alignment: .top) {
                                Image(systemName: isSelected(index: index, label: option.label)
                                      ? "checkmark.circle.fill" : "circle")
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(option.label)
                                    if let description = option.description, !description.isEmpty {
                                        Text(description).font(.subheadline)
                                    }
                                }
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .disabled(question.isAnswered || isSending)
                        .accessibilityAddTraits(isSelected(index: index, label: option.label) ? .isSelected : [])
                    }
                    if !question.isAnswered {
                        TextField("Свой вариант", text: Binding(
                            get: { custom[index] ?? "" },
                            set: { custom[index] = $0 }
                        ), axis: .vertical)
                    }
                }
            }
            if !question.isAnswered {
                TextField("Заметка для роли (необязательно)", text: $note, axis: .vertical)
                Button(isSending ? "Отправляю…" : "Отправить ответ") {
                    Task { await send() }
                }
                .disabled(!canSend || isSending)
            } else {
                Text("Ответ сохранён — роль продолжает работу")
            }
            if let failure { Text(failure) }
        }
    }

    /// Шапка карточки: «Нужен ваш выбор» и метка вопроса.
    private var header: some View {
        VStack(alignment: .leading, spacing: TFSpacing.xs) {
            Text(question.isAnswered ? "Ответ отправлен" : "Нужен ваш выбор")
                .tfText(.title)
                .foregroundStyle(Color.tfChatText)
            if question.isAnswered {
                Text("Роль продолжает работу").tfText(.meta).foregroundStyle(Color.tfSub)
            }
        }
    }

    @ViewBuilder
    private func questionBlock(index: Int, item: ChatQuestionItem) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            if let header = item.header, !header.isEmpty {
                TFSectionHeader(header, style: .caps)
            }
            Text(item.question)
                .tfText(.body)
                .foregroundStyle(Color.tfChatText)
                .fixedSize(horizontal: false, vertical: true)
            options(index: index, item: item)
            if question.isAnswered {
                answeredSelection(index: index, item: item)
            } else {
                TFTextField("Свой вариант", text: Binding(
                    get: { custom[index] ?? "" },
                    set: { custom[index] = $0 }
                ), surface: .tile)
            }
        }
    }

    /// Варианты: капсулы с пояснением. Один выбор — тап переключает, несколько
    /// — отметка накапливается.
    @ViewBuilder
    private func options(index: Int, item: ChatQuestionItem) -> some View {
        // Плитки столбцом на всю ширину — как на образце владельца.
        VStack(spacing: TFSpacing.sm) {
            ForEach(item.options) { option in
                Button {
                    toggle(index: index, label: option.label, multi: item.multiSelect)
                } label: {
                    optionPill(option, selected: isSelected(index: index, label: option.label),
                               multi: item.multiSelect)
                }
                .buttonStyle(.plain)
                .disabled(question.isAnswered || isSending)
            }
        }
    }

    private func optionPill(_ option: ChatQuestionOption, selected: Bool, multi: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: TFSpacing.xs) {
                if multi {
                    Image(systemName: selected ? "checkmark.square.fill" : "square")
                        .tfTypeFont(size: 13, weight: .semibold)
                }
                Text(option.label)
                    .tfText(.action)
                    .fontWeight(.semibold)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let description = option.description, !description.isEmpty {
                Text(description)
                    .tfText(.caption)
                    .foregroundStyle(Color.tfSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(selected ? Color.tfText : Color.tfChatText)
        .padding(.horizontal, TFSpacing.lg)
        .padding(.vertical, TFSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Плитка без рамки; выбранная — как кнопка: полупрозрачный красный и
        // тёмно-красная кромка (образец владельца 06.11.2026, там — синим).
        .background(selected ? Color.tfRed.opacity(0.18) : Color.tfTile,
                    in: RoundedRectangle(cornerRadius: TFRadius.lg, style: .continuous))
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: TFRadius.lg, style: .continuous)
                    .strokeBorder(Color.tfButtonEdge, lineWidth: TFBorder.width)
            }
        }
        .accessibilityIdentifier("chat.question.option." + option.label)
    }

    /// Что выбрано — после ответа.
    @ViewBuilder
    private func answeredSelection(index: Int, item: ChatQuestionItem) -> some View {
        let entry = question.answer?.first { $0.questionIndex == index }
        let labels = entry?.selected ?? []
        let own = entry?.custom ?? ""
        if !labels.isEmpty {
            Text("Выбрано: " + labels.joined(separator: ", "))
                .tfText(.meta)
                .foregroundStyle(Color.tfSub)
        }
        if !own.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text("Свой ответ: " + own)
                .tfText(.meta)
                .foregroundStyle(Color.tfSub)
        }
    }

    private var answeredFooter: some View {
        Text("Ответ сохранён — роль продолжает работу")
            .tfText(.meta)
            .foregroundStyle(Color.tfSub)
    }

    private var sendButton: some View {
        TFButton(isSending ? "Отправляю…" : "Отправить ответ",
                 icon: "paperplane.fill",
                 variant: .secondary,
                 isEnabled: canSend) {
            Task { await send() }
        }
        .disabled(!canSend || isSending)
        .accessibilityIdentifier("chat.question.send")
    }

    /// Ответить можно, когда по каждому вопросу что-то выбрано или написано.
    private var canSend: Bool {
        question.questions.indices.allSatisfy { index in
            let hasOption = !(selected[index] ?? []).isEmpty
            let hasOwn = !(custom[index] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return hasOption || hasOwn
        }
    }

    private func isSelected(index: Int, label: String) -> Bool {
        selected[index]?.contains(label) == true
    }

    private func toggle(index: Int, label: String, multi: Bool) {
        var picked = selected[index] ?? []
        if multi {
            if picked.contains(label) { picked.remove(label) } else { picked.insert(label) }
        } else {
            picked = picked.contains(label) && picked.count == 1 ? [] : [label]
        }
        selected[index] = picked
    }

    private func send() async {
        guard canSend, !isSending else { return }
        isSending = true
        failure = nil
        defer { isSending = false }
        var entries: [ChatQuestionAnswerEntry] = []
        for index in question.questions.indices {
            let labels = (selected[index] ?? []).sorted()
            let own = (custom[index] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            entries.append(ChatQuestionAnswerEntry(
                questionIndex: index,
                selected: labels,
                custom: own.isEmpty ? nil : own
            ))
        }
        let noteText = note.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await onAnswer(entries, noteText.isEmpty ? nil : noteText)
        } catch {
            failure = (error as? APIError)?.localizedDescription ?? error.localizedDescription
        }
    }
}
