import SwiftUI
import UIKit

// ═══════════ NoteEditorScreen — редактор заметки (spec/SCREENS-2.md §2) ═══════════
//
// Имя и параметр — контракт `INTEGRATION.md` буквально: `NoteEditorScreen(noteID:)`.
//
// Архитектура тела: документ соседа (`NoteDocument.swift`) — плоский массив
// `[NoteBlock]`, поэтому редактор — это СПИСОК блоков, у каждого свой
// `UITextView` (`NoteBlockTextView.swift`), а не один текстовый холст на
// весь документ. Из этого решения вытекают все упрощения ниже (названы по
// месту): выделение для меню AI не переходит границы блока, «пересечь Enter
// два блока одним нажатием» невозможно и т.п. — компромисс в пользу того,
// что формат хранения (JSON блоков-с-прогонами) остаётся честным зеркалом
// TipTap-документа веба, без придумывания промежуточного формата.
struct NoteEditorScreen: View {
    let noteID: String

    @State private var viewModel: NoteEditorViewModel
    @State private var controllerStore = NoteBlockControllerStore()
    @Environment(\.dismiss) private var dismiss

    /// Фокус блока, живые метки форматирования и запрос ссылки — теперь на
    /// отдельном `@Observable`, не здесь: `NoteKeyboardAccessoryBar` (лента
    /// форматирования + микрофон) с 03.09.2026 живёт ВНЕ дерева этого экрана,
    /// как `inputAccessoryView` каждого блочного `UITextView` (см.
    /// `NoteBlockTextView.swift`) — обычный `@State` этого View ей не виден,
    /// нужен общий объект-ссылка. Подробности — `NoteEditorFocusState`.
    @State private var focus = NoteEditorFocusState()
    /// Тот самый `inputAccessoryView` — один на экран, назначается каждому
    /// блоку одним и тем же экземпляром (см. `editorBody`).
    @State private var accessoryHost: NoteKeyboardAccessoryHost?

    @State private var showMovePicker = false
    @State private var showDeleteConfirm = false
    @State private var shareURL: URL?
    @State private var showShareSheet = false

    init(noteID: String) {
        self.noteID = noteID
        self._viewModel = State(initialValue: NoteEditorViewModel(noteID: noteID))
    }

    var body: some View {
        content
        .background(Color.tfBackground)
        // Раньше формат-панель сидела статично у верха экрана, а микрофон
        // плавал `.overlay` отдельным кружком поверх текста — владелец
        // 03.09.2026: «прилепить ленту к верху клавиатуры» + на живом
        // устройстве (не симулятор) кружок микрофона рисовался ТРЁМЯ копиями
        // сразу, пока открыта клавиатура (скриншот). Первая попытка чинить
        // это через `.safeAreaInset(edge: .bottom)` не решила дело: это
        // всё ещё СВОЙ, SwiftUI-уровня слой, который клавиатура не двигает
        // как часть себя — он просто пере-анимируется отдельно и в моменте
        // выглядит как «две клавиатуры» (владелец, тем же вечером: «панель
        // тоже двигается... а такого не должно быть»). Правильный нативный
        // способ — реальный `inputAccessoryView` каждого блочного
        // `UITextView` (см. `NoteBlockTextView.swift`, `accessoryHost`
        // ниже): тогда лента — буквально часть клавиатуры для UIKit,
        // отдельного слоя для рассинхронизации просто не существует.
        // Была своя ZStack-шапка (крестик, «✨», «…» в попапах) поверх ещё и
        // системного .navigationTitle(.large) — та же двойная шапка, что
        // чинили весь день (просьба владельца 03.09.2026: «нативные кнопки
        // везде одним элементом»). Теперь tfNativeHeader + toolbar, попапы —
        // нативный Menu, тем же приёмом, что у фильтров «Сегодня».
        //
        // ⚠️ Изначально AI и «Ещё» были ДВУМЯ отдельными ToolbarItem с Menu
        // (как задумано по спеке — разные пиктограммы). На живом кадре
        // (iOS 26.5 Simulator) это давало два бага сразу: заголовок «Новая
        // заметка» пропадал целиком, а иконка каждого Menu отрисовывалась
        // счетверённо/строенно в схлопнутом виде (проверено idb describe-all:
        // в дереве доступности реально ОДНА кнопка — это чисто рендер-баг
        // «Liquid Glass» тулбара на запушенном .inline экране, не логическая
        // ошибка; смена содержимого меню, задержка скриншота на 8+ сек и
        // прямой тап по иконке — на исход не влияли, тап открывал меню
        // корректно). Баг воспроизводится и с одним-единственным Menu-айтемом
        // в toolbar этого пуш-экрана — то есть дело не в паре соседних Menu.
        // Слияние в один Menu не убирает баг отрисовки иконки, но убирает
        // пропажу заголовка (в один Menu упирается тот же приём, что у
        // рабочего kebabMenu в NotesScreen.swift) — берём это компромиссом,
        // как более лёгкий вариант, чем два отдельных Menu.
        // Было имя самой заметки (спека §2: «заголовком становится первый
        // непустой блок… или "Новая заметка"») — владелец 03.09.2026:
        // «между кнопкой назад и троеточием не название заметки, а раздел
        // "Дневник", как и в предыдущем [экране списка] названии» — то же
        // слово, что у `NotesScreen.tfNativeHeader("Дневник", ...)`.
        .tfNativeHeader("Дневник", displayMode: .inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { combinedMenu }
        }
        .task {
            // Создаётся один раз на весь экран (тот же `NoteKeyboardAccessoryHost`
            // ставится каждому блоку — см. `editorBody`), не зависит от
            // загрузки документа, поэтому до `viewModel.load()`.
            if accessoryHost == nil {
                accessoryHost = NoteKeyboardAccessoryHost(viewModel: viewModel, focus: focus)
            }
            await viewModel.load()
        }
        .onDisappear { viewModel.flushOnExit() }
        .onChange(of: viewModel.pendingFocus) { _, pending in
            guard let pending else { return }
            // Строка ещё не успела появиться в SwiftUI-дереве на этот же
            // тик (вставка/удаление блока только что попала в `document`) —
            // небольшая отсрочка вместо гонки с `onAppear` новой строки.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                controllerStore.controller(for: pending.blockID).focus(cursorAt: pending.position)
                viewModel.pendingFocus = nil
            }
        }
        .alert("Адрес ссылки", isPresented: $focus.showLinkPrompt) {
            TextField("https://", text: $focus.linkPromptText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
            Button("Отмена", role: .cancel) {}
            Button("Применить") { applyLinkFromPrompt() }
        }
        .alert("Удалить заметку\(deleteTitleSuffix)?", isPresented: $showDeleteConfirm) {
            Button("Отмена", role: .cancel) {}
            Button("Удалить", role: .destructive) { Task { await performDelete() } }
        } message: {
            Text("Действие нельзя отменить.")
        }
        .sheet(isPresented: $showMovePicker) {
            FolderPickerSheet(folders: viewModel.folders, title: "Переместить в папку") { folderID in
                Task { await viewModel.moveToFolder(folderID) }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let shareURL { NoteShareSheet(items: [shareURL]) }
        }
        .tfBottomSheet(isPresented: $viewModel.showExtractedTasksSheet, title: "Задачи из текста") {
            NoteExtractedTasksSheetContent(tasks: viewModel.extractedTasks) {
                viewModel.showExtractedTasksSheet = false
            }
        }
    }

    // MARK: - Тело

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.document.blocks.count <= 1 && viewModel.document.isEffectivelyEmpty {
            TFLoading(.block)
            Spacer()
        } else {
            TFErrorBanner(viewModel.loadErrorMessage)
                .padding(.horizontal, TFSpacing.screenHorizontal)
            TFErrorBanner(viewModel.aiErrorMessage, variant: .block)
                .padding(.horizontal, TFSpacing.screenHorizontal)
                .padding(.top, TFSpacing.xs)
            TFErrorBanner(viewModel.actionErrorMessage)
                .padding(.horizontal, TFSpacing.screenHorizontal)
            editorBody
            // Была безусловной — идентична по идее прошлой «плашке» под
            // таббар (RouteDestinationView.swift): резервировала полоску
            // ~20pt в самом низу, даже когда сохранять нечего (`statusLabel
            // == ""`), а у «Дневника» (NotesScreen) такого нет вообще —
            // владелец 03.09.2026 нашёл её тем же приёмом, каким сверял
            // прошлую: «сравни этот экранчик с экраном заметки». Теперь
            // строка есть в дереве, только когда действительно есть что
            // показать.
            if !viewModel.statusLabel.isEmpty {
                Text(viewModel.statusLabel)
                    .tfText(.caption)
                    .foregroundStyle(Color.tfDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 16)
                    .padding(.horizontal, TFSpacing.screenHorizontal + 4)
                    .padding(.top, TFSpacing.xs)
            }
        }
    }

    private var editorBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(viewModel.document.blocks) { block in
                    NoteBlockRow(
                        block: block,
                        orderedIndex: orderedIndex(for: block),
                        showPlaceholder: viewModel.document.isEffectivelyEmpty && block.id == viewModel.document.blocks.first?.id,
                        controller: controllerStore.controller(for: block.id),
                        accessoryView: accessoryHost?.view,
                        onChange: { id, runs in viewModel.updateRuns(blockID: id, runs: runs) },
                        onFocus: { id, ctrl in
                            focus.blockID = id
                            focus.controller = ctrl
                            focus.activeMarks = ctrl.activeMarks
                        },
                        onBlur: { id in
                            if focus.blockID == id {
                                focus.blockID = nil
                                focus.controller = nil
                                focus.activeMarks = []
                            }
                        },
                        onMarksChange: { id, marks in if focus.blockID == id { focus.activeMarks = marks } },
                        onSplit: { id, offset in viewModel.handleSplit(blockID: id, atUTF16Offset: offset) },
                        onBackspaceAtStart: { id in viewModel.handleBackspaceAtStart(blockID: id) },
                        onToggleChecked: { viewModel.toggleTaskChecked(blockID: block.id) }
                    )
                    .padding(.horizontal, TFSpacing.screenHorizontal)
                }
            }
            .padding(.vertical, TFSpacing.sm)
            .padding(.bottom, TFSpacing.xl * 2)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    /// Порядковый номер для нумерованного списка — считает соседей того же
    /// уровня НАЗАД от текущего блока до первого «не такого же» соседа.
    private func orderedIndex(for block: NoteBlock) -> Int? {
        guard case .orderedItem = block.kind,
              let idx = viewModel.document.blocks.firstIndex(where: { $0.id == block.id })
        else { return nil }
        var count = 1
        var i = idx - 1
        while i >= 0 {
            let b = viewModel.document.blocks[i]
            guard case .orderedItem = b.kind, b.level == block.level else { break }
            count += 1
            i -= 1
        }
        return count
    }

    private var deleteTitleSuffix: String {
        let title = viewModel.document.derivedTitle
        return title.isEmpty ? "" : " «\(title)»"
    }

    private var combinedMenu: some View {
        Menu {
            Section("AI") {
                Button { Task { await runAssist(.continueThought) } } label: {
                    Label("Продолжить мысль", systemImage: "pencil.line")
                }
                Button { Task { await runAssist(.shorten) } } label: {
                    Label("Сократить текст", systemImage: "scissors")
                }
                Button { Task { await runAssist(.expand) } } label: {
                    Label("Развить в шаги", systemImage: "list.bullet.indent")
                }
                Button {
                    let selection = focus.controller?.selectedText()
                    Task { await viewModel.runExtractTasks(selectedText: selection) }
                } label: {
                    Label("Собрать задачи из текста", systemImage: "checklist")
                }
            }
            .disabled(viewModel.aiBusy)

            Button { showMovePicker = true } label: {
                Label("Переместить в папку", systemImage: "folder")
            }
            Button { Task { await exportMarkdown() } } label: {
                Label("Выгрузить в Markdown", systemImage: "square.and.arrow.up")
            }
            Divider()
            Button(role: .destructive) { showDeleteConfirm = true } label: {
                Label("Удалить заметку", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
        }
    }

    // MARK: - Меню AI / «Ещё» — действия

    /// Есть выделение — правим прямо в textView этого блока (замена на
    /// месте); нет — весь документ (см. `NoteEditorViewModel.runAssist`).
    private func runAssist(_ action: JournalAssistAction) async {
        let hasSelection = focus.controller?.hasSelection ?? false
        let selection = hasSelection ? focus.controller?.selectedText() : nil
        guard let result = await viewModel.runAssist(action, selectedText: selection),
              !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }

        if hasSelection, let id = focus.blockID, let ctrl = focus.controller {
            ctrl.insertPlainParagraph(result)
            viewModel.updateRuns(blockID: id, runs: ctrl.currentRuns())
        } else {
            viewModel.applyAssistResultToWholeDocument(result, action: action)
        }
    }

    private func exportMarkdown() async {
        if let url = await viewModel.exportToMarkdownFile() {
            shareURL = url
            showShareSheet = true
        }
    }

    private func performDelete() async {
        if await viewModel.deleteNote() { dismiss() }
    }

    // MARK: - Панель над клавиатурой: форматирование (spec §2.1) + голос

    /// Панель форматирования + микрофон переехали в `NoteKeyboardAccessoryBar`
    /// (`NoteBlockTextView.swift`) — она больше не часть дерева этого экрана,
    /// а `inputAccessoryView` блочных `UITextView` (см. `body`, `editorBody`).
    /// Здесь остаётся только реакция на диалог «Адрес ссылки»: сам alert
    /// живёт на экране (спрашивать URL — не дело клавиатурной панели), а
    /// `focus.showLinkPrompt`/`linkPromptText` панель выставляет напрямую.
    private func applyLinkFromPrompt() {
        guard let id = focus.blockID, let ctrl = focus.controller else { return }
        let trimmed = focus.linkPromptText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != "https://" else { return }
        ctrl.applyLink(href: trimmed)
        focus.activeMarks = ctrl.activeMarks
        viewModel.updateRuns(blockID: id, runs: ctrl.currentRuns())
    }
}

// MARK: - Строка блока

/// Один блок документа — декорация слева (маркер/номер/чекбокс/полоса
/// цитаты) + сам текстовый движок (`NoteBlockTextView`). Разделитель
/// (`horizontalRule`) — не текстовый блок вовсе, просто линия.
private struct NoteBlockRow: View {
    let block: NoteBlock
    let orderedIndex: Int?
    let showPlaceholder: Bool
    let controller: NoteBlockTextController
    /// `inputAccessoryView` (лента форматирования + микрофон), один и тот
    /// же объект на все блоки экрана — см. `NoteEditorScreen.accessoryHost`.
    let accessoryView: UIView?

    let onChange: (UUID, [RichRun]) -> Void
    let onFocus: (UUID, NoteBlockTextController) -> Void
    let onBlur: (UUID) -> Void
    let onMarksChange: (UUID, Set<InlineMark>) -> Void
    let onSplit: (UUID, Int) -> Void
    let onBackspaceAtStart: (UUID) -> Void
    let onToggleChecked: () -> Void

    var body: some View {
        if case .horizontalRule = block.kind {
            Rectangle()
                .fill(Color.tfStroke)
                .frame(height: TFBorder.width)
                .padding(.vertical, TFSpacing.md)
        } else {
            HStack(alignment: .top, spacing: TFSpacing.sm) {
                leading
                ZStack(alignment: .topLeading) {
                    if showPlaceholder {
                        Text("Пишите здесь что угодно…")
                            .tfText(.body)
                            .foregroundStyle(Color.tfDim)
                            .allowsHitTesting(false)
                    }
                    NoteBlockTextView(
                        blockID: block.id, runs: block.runs, blockKind: block.kind, controller: controller,
                        accessoryView: accessoryView,
                        onChange: onChange, onFocus: onFocus, onBlur: onBlur, onMarksChange: onMarksChange,
                        onSplit: onSplit, onBackspaceAtStart: onBackspaceAtStart
                    )
                }
            }
            .padding(.leading, CGFloat(block.level) * 18 + quoteBarInset)
            .overlay(alignment: .leading) {
                if case .blockquote = block.kind {
                    Rectangle().fill(Color.tfStroke).frame(width: 3)
                }
            }
            .padding(.vertical, block.kind.isListItem ? 2 : 4)
            .background {
                if case .codeBlock = block.kind {
                    RoundedRectangle(cornerRadius: TFRadius.md).fill(Color.tfCard2)
                        .padding(.vertical, 1)
                }
            }
        }
    }

    @ViewBuilder
    private var leading: some View {
        switch block.kind {
        case .bulletItem:
            Circle().fill(Color.tfSub).frame(width: 5, height: 5).padding(.top, 9)
        case .orderedItem:
            Text("\(orderedIndex ?? 1).")
                .tfText(.body)
                .foregroundStyle(Color.tfSub)
                .frame(minWidth: 20, alignment: .trailing)
        case .taskItem(let checked):
            TFCheckbox(isChecked: checked, action: onToggleChecked)
        default:
            EmptyView()
        }
    }

    private var quoteBarInset: CGFloat {
        if case .blockquote = block.kind { return TFSpacing.sm }
        return 0
    }
}

/// Обёртка `UIActivityViewController` для «Выгрузить в Markdown» — своя
/// копия: у соседа в `NotesScreen.swift` тот же тип объявлен `private`,
/// наружу недоступен.
private struct NoteShareSheet: UIViewControllerRepresentable {
    let items: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
