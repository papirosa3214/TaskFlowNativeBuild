import SwiftUI
import UIKit

// ═══════════ Текстовый движок одного блока ═══════════
//
// Спека (§2.1) просит SwiftUI-эквивалент AttributedString/TextKit-редактора.
// Чистый SwiftUI `TextEditor` не даёт программного доступа к атрибутам
// выделения (нужно для «подсветить активную кнопку тулбара» и «применить
// жирный к выделению») — поэтому здесь `UITextView` через
// `UIViewRepresentable`, ОДИН на блок документа (параграф/заголовок/пункт
// списка/…), а не один на весь документ: так проще сопоставить с плоской
// моделью `[NoteBlock]` соседа и не переизобретать текстовый движок для
// вставки/удаления целых блоков — это делает ViewModel на уровне массива,
// а не курсор внутри одной гигантской строки.

/// Куда поставить курсор при программном фокусе (после Enter/Backspace/⌫).
enum NoteCursorPosition: Equatable {
    case start
    case end
    case offset(Int)
}

/// Точка входа для тулбара/меню «Ещё» — тулбар живёт в соседнем View
/// (шапка экрана), а не внутри блока, поэтому ему нужен объект, которым
/// можно скомандовать «сделай жирным» БЕЗ обхода через `@Binding`
/// (Binding пересобирается на каждый рендер и не годится для императивных
/// вызовов кнопки). Класс переживает пересоздания `NoteBlockTextView`,
/// пока жив сам блок (хранится в `@State` строки — см. `NoteBlockRow`).
@MainActor
final class NoteBlockTextController {
    fileprivate weak var textView: UITextView?
    var blockKind: BlockKind = .paragraph
    /// Кегль ячейки таблицы: тип блока у неё `paragraph`, а шапка рисуется
    /// полужирной — см. `NoteRichText.attributedString(runs:blockKind:base:)`.
    var baseFontOverride: UIFont?

    /// Шрифт, которым переклеиваются атрибуты при переключении марок. Через
    /// него же идут `applyLink`/`insertPlainParagraph` — иначе правка марки
    /// внутри ячейки сбрасывала бы её кегль на общеблочный.
    var baseFont: UIFont { baseFontOverride ?? NoteRichText.baseFont(for: blockKind) }

    /// `false`, если строка блока ещё не успела появиться в дереве SwiftUI
    /// (`textView == nil`) — вызывающий (см. `NoteEditorScreen`) не должен
    /// в этом случае молча считать фокус применённым: старый блок так и
    /// останется первым респондером с ещё НЕ обрезанным текстом (до/после
    /// разбивки), и следующее нажатие клавиши запишет его как есть,
    /// задвоив содержимое между двумя блоками.
    @discardableResult
    func focus(cursorAt position: NoteCursorPosition) -> Bool {
        guard let tv = textView else { return false }
        if !tv.isFirstResponder { tv.becomeFirstResponder() }
        let length = tv.attributedText.length
        switch position {
        case .start: tv.selectedRange = NSRange(location: 0, length: 0)
        case .end: tv.selectedRange = NSRange(location: length, length: 0)
        case .offset(let n): tv.selectedRange = NSRange(location: min(max(n, 0), length), length: 0)
        }
        return true
    }

    var hasSelection: Bool { (textView?.selectedRange.length ?? 0) > 0 }

    func currentRuns() -> [RichRun] {
        guard let tv = textView else { return [] }
        return NoteRichText.runs(from: tv.attributedText)
    }

    /// Текст текущего выделения — читает меню AI («применяется к выделенному
    /// фрагменту», spec §2 «Меню AI»). `textView` намеренно `fileprivate` —
    /// наружу отдаём только готовую строку, не сам `UITextView`.
    func selectedText() -> String? {
        guard let tv = textView, tv.selectedRange.length > 0 else { return nil }
        return (tv.attributedText.string as NSString).substring(with: tv.selectedRange)
    }

    private func runState(at attrs: [NSAttributedString.Key: Any]) -> RichRun {
        RichRun(
            text: "",
            bold: (attrs[NoteMarkKey.bold] as? Bool) ?? false,
            italic: (attrs[NoteMarkKey.italic] as? Bool) ?? false,
            underline: (attrs[NoteMarkKey.underline] as? Bool) ?? false,
            strike: (attrs[NoteMarkKey.strike] as? Bool) ?? false,
            highlight: (attrs[NoteMarkKey.highlight] as? Bool) ?? false,
            code: (attrs[NoteMarkKey.code] as? Bool) ?? false,
            linkHref: attrs[NoteMarkKey.link] as? String
        )
    }

    private func marks(of run: RichRun) -> Set<InlineMark> {
        var s: Set<InlineMark> = []
        if run.bold { s.insert(.bold) }
        if run.italic { s.insert(.italic) }
        if run.underline { s.insert(.underline) }
        if run.strike { s.insert(.strike) }
        if run.highlight { s.insert(.highlight) }
        if run.code { s.insert(.code) }
        if run.linkHref?.isEmpty == false { s.insert(.link) }
        return s
    }

    /// Марки под курсором/на выделении — при выделении активна только
    /// марка, которой отмечен ВЕСЬ диапазон (пересечение), иначе кнопка
    /// тулбара подсветилась бы на смешанном форматировании как включённая.
    var activeMarks: Set<InlineMark> {
        guard let tv = textView else { return [] }
        let range = tv.selectedRange
        if range.length == 0 {
            return marks(of: runState(at: tv.typingAttributes))
        }
        guard let storage = tv.textStorage as NSTextStorage?,
              range.location >= 0, range.location + range.length <= storage.length
        else { return [] }
        var result: Set<InlineMark>?
        storage.enumerateAttributes(in: range, options: []) { attrs, _, _ in
            let m = marks(of: runState(at: attrs))
            result = result.map { $0.intersection(m) } ?? m
        }
        return result ?? []
    }

    var currentLinkHref: String? {
        guard let tv = textView else { return nil }
        let range = tv.selectedRange
        if range.length == 0 {
            return tv.typingAttributes[NoteMarkKey.link] as? String
        }
        return linkExtendedRange().href
    }

    /// Расширяет пустое выделение до границ марки `link` под курсором —
    /// аналог `extendMarkRange("link")` веба (спека: «снимаем ссылку, если
    /// курсор уже внутри неё»).
    private func linkExtendedRange() -> (range: NSRange?, href: String?) {
        guard let tv = textView, let storage = tv.textStorage as NSTextStorage?, storage.length > 0 else { return (nil, nil) }
        var range = tv.selectedRange
        if range.length > 0 {
            var allSame = true
            var href: String?
            storage.enumerateAttribute(NoteMarkKey.link, in: range, options: []) { value, _, stop in
                let v = value as? String
                if href == nil && v != nil { href = v }
                if v != href { allSame = false; stop.pointee = true }
            }
            return allSame ? (range, href) : (nil, nil)
        }
        let probe = max(0, min(range.location, storage.length - 1))
        guard probe < storage.length, let href = storage.attribute(NoteMarkKey.link, at: probe, effectiveRange: &range) as? String else {
            return (nil, nil)
        }
        return (range, href)
    }

    private func toggle(_ mark: InlineMark, apply: @escaping (inout RichRun, Bool) -> Void) {
        guard let tv = textView else { return }
        let base = baseFont
        let range = tv.selectedRange
        if range.length == 0 {
            var run = runState(at: tv.typingAttributes)
            let turnOn = !marks(of: run).contains(mark)
            apply(&run, turnOn)
            tv.typingAttributes = NoteRichText.attributes(for: run, base: base)
            return
        }
        guard let storage = tv.textStorage as NSTextStorage? else { return }
        let semanticKey = Self.semanticKey(for: mark)
        var allHave = true
        storage.enumerateAttribute(semanticKey, in: range, options: []) { value, _, stop in
            if !((value as? Bool) ?? false) { allHave = false; stop.pointee = true }
        }
        let turnOn = !allHave
        storage.beginEditing()
        storage.enumerateAttributes(in: range, options: []) { attrs, subrange, _ in
            var run = runState(at: attrs)
            apply(&run, turnOn)
            storage.setAttributes(NoteRichText.attributes(for: run, base: base), range: subrange)
        }
        storage.endEditing()
        tv.selectedRange = range
    }

    func toggleBold() { toggle(.bold) { $0.bold = $1 } }
    func toggleItalic() { toggle(.italic) { $0.italic = $1 } }
    func toggleUnderline() { toggle(.underline) { $0.underline = $1 } }
    func toggleStrike() { toggle(.strike) { $0.strike = $1 } }
    func toggleHighlight() { toggle(.highlight) { $0.highlight = $1 } }
    func toggleCode() { toggle(.code) { $0.code = $1 } }

    static func semanticKey(for mark: InlineMark) -> NSAttributedString.Key {
        switch mark {
        case .bold: NoteMarkKey.bold
        case .italic: NoteMarkKey.italic
        case .underline: NoteMarkKey.underline
        case .strike: NoteMarkKey.strike
        case .highlight: NoteMarkKey.highlight
        case .code: NoteMarkKey.code
        case .link: NoteMarkKey.link
        }
    }

    /// Применяет ссылку к выделению (или к границам уже существующей марки
    /// под курсором — «продлить и заменить URL»).
    func applyLink(href: String) {
        guard let tv = textView, let storage = tv.textStorage as NSTextStorage? else { return }
        let base = baseFont
        let range = linkExtendedRange().range ?? tv.selectedRange
        guard range.length > 0 else { return }
        storage.beginEditing()
        storage.enumerateAttributes(in: range, options: []) { attrs, subrange, _ in
            var run = runState(at: attrs)
            run.linkHref = href
            storage.setAttributes(NoteRichText.attributes(for: run, base: base), range: subrange)
        }
        storage.endEditing()
        tv.selectedRange = NSRange(location: range.location + range.length, length: 0)
    }

    func removeLink() {
        guard let tv = textView, let storage = tv.textStorage as NSTextStorage?,
              let range = linkExtendedRange().range
        else { return }
        let base = baseFont
        storage.beginEditing()
        storage.enumerateAttributes(in: range, options: []) { attrs, subrange, _ in
            var run = runState(at: attrs)
            run.linkHref = nil
            storage.setAttributes(NoteRichText.attributes(for: run, base: base), range: subrange)
        }
        storage.endEditing()
    }

    /// Вставляет текст (например, распознанную диктовку или ответ ИИ) в
    /// позицию курсора как обычный текст без марок — используется меню AI.
    func insertPlainParagraph(_ text: String) {
        guard let tv = textView else { return }
        let base = baseFont
        let insertion = NSAttributedString(text: text, attributes: NoteRichText.attributes(for: RichRun(text: text), base: base))
        let range = tv.selectedRange
        guard let storage = tv.textStorage as NSTextStorage? else { return }
        storage.replaceCharacters(in: range, with: insertion)
        tv.selectedRange = NSRange(location: range.location + insertion.length, length: 0)
    }
}

private extension NSAttributedString {
    convenience init(text: String, attributes: [NSAttributedString.Key: Any]) {
        self.init(string: text, attributes: attributes)
    }
}

/// Реестр контроллеров «блок → его текстовый движок» на весь экран.
/// Обычный класс, НЕ `@Observable` — держится в `@State` только затем,
/// чтобы пережить пересоздания `NoteEditorScreen.body`; сама мутация
/// словаря внутри вызова `body` не должна дёргать SwiftUI-инвалидацию
/// (иначе получили бы «изменение состояния во время обновления вью»),
/// поэтому это простой ссылочный тип-кладовка, а не `@State`-словарь.
@MainActor
final class NoteBlockControllerStore {
    private var controllers: [UUID: NoteBlockTextController] = [:]

    func controller(for blockID: UUID) -> NoteBlockTextController {
        if let existing = controllers[blockID] { return existing }
        let created = NoteBlockTextController()
        controllers[blockID] = created
        return created
    }
}

// ═══════════ Панель над клавиатурой: форматирование + голос ═══════════
//
// 03.09.2026: раньше лента форматирования сидела статично у верха экрана,
// а микрофон был отдельным SwiftUI `.overlay` поверх текста — владелец
// сначала попросил «прилепить ленту к клавиатуре», это сделали через
// `.safeAreaInset(edge: .bottom)`, но и это оказалось не тем: такой слой
// всё ещё СВОЙ, SwiftUI-уровня, клавиатура его не двигает как часть себя —
// он просто анимируется отдельно и в моменте выглядит как две клавиатуры
// сразу («панель тоже двигается... а такого не должно быть»). Плюс на
// живом устройстве кружок микрофона рисовался тремя копиями (тот же класс
// рендер-глюка, что уже описан в `NoteEditorScreen.swift` про кебаб-меню
// шапки — там он безобиден, здесь давал реальный дубль). Правильный
// нативный способ — «как у всех» — самый обычный `inputAccessoryView`
// каждого блочного `UITextView`: тогда для UIKit лента буквально часть
// клавиатуры, отдельного слоя для рассинхронизации просто не существует.

/// Общее состояние фокуса на весь экран заметки. Раньше жило как три
/// отдельных `@State` в `NoteEditorScreen` — но `NoteKeyboardAccessoryBar`
/// теперь рендерится ВНЕ дерева этого экрана (см. `NoteKeyboardAccessoryHost`
/// ниже), обычный `@State` ей не виден. `@Observable`-класс — общая ссылка,
/// видна обеим сторонам одним и тем же экземпляром. `showLinkPrompt`/
/// `linkPromptText` тоже здесь, а не на экране — их выставляет кнопка
/// «ссылка» из вынесенной панели, а сам alert остаётся на экране
/// (спрашивать URL — не дело клавиатурной панели).
@MainActor
@Observable
final class NoteEditorFocusState {
    var blockID: UUID?
    var controller: NoteBlockTextController?
    var activeMarks: Set<InlineMark> = []
    var showLinkPrompt = false
    var linkPromptText = ""
}

/// Лента форматирования (spec §2.1) + микрофон (spec §0.7) — содержимое
/// `inputAccessoryView`. Один экземпляр на экран (не на блок, см.
/// `NoteKeyboardAccessoryHost`), поэтому при переходе фокуса между блоками
/// сама лента не пересоздаётся — просто читает уже другой `focus.controller`.
struct NoteKeyboardAccessoryBar: View {
    let viewModel: NoteEditorViewModel
    let focus: NoteEditorFocusState
    @State private var dictation = DictationEngine.shared

    var body: some View {
        HStack(spacing: TFSpacing.sm) {
            dismissKeyboardButton
            toolbar
            micButton
        }
        .padding(.horizontal, TFSpacing.screenHorizontal)
        .padding(.vertical, TFSpacing.sm)
        .frame(height: NoteKeyboardAccessoryHost.height)
        // Было `.regularMaterial` (блюр) — владелец 03.09.2026: «чёрный
        // блюр ещё не убрал, он под текстом» — на тёмной теме материал
        // читается тёмным полупрозрачным пятном под последней строкой
        // текста. Плоский фон, тот же токен, что у самого экрана — ничего
        // не просвечивает, лишнего слоя нет.
        .background(Color.tfBackground)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.tfStroke).frame(height: TFBorder.width)
        }
    }

    private var toolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                toolbarButton("bold", active: focus.activeMarks.contains(.bold)) { toggleMark(.bold) }
                toolbarButton("italic", active: focus.activeMarks.contains(.italic)) { toggleMark(.italic) }
                toolbarButton("underline", active: focus.activeMarks.contains(.underline)) { toggleMark(.underline) }
                toolbarButton("strikethrough", active: focus.activeMarks.contains(.strike)) { toggleMark(.strike) }
                toolbarButton("highlighter", active: focus.activeMarks.contains(.highlight)) { toggleMark(.highlight) }
                toolbarButton("curlybraces", active: focus.activeMarks.contains(.code)) { toggleMark(.code) }
                toolbarButton("link", active: focus.activeMarks.contains(.link)) { handleLinkTap() }

                divider

                headingButton(1)
                headingButton(2)
                headingButton(3)

                divider

                toolbarButton("list.bullet", active: isBlockKind { if case .bulletItem = $0 { true } else { false } }) {
                    viewModel.toggleList(.bullet, blockID: focus.blockID)
                }
                toolbarButton("list.number", active: isBlockKind { if case .orderedItem = $0 { true } else { false } }) {
                    viewModel.toggleList(.ordered, blockID: focus.blockID)
                }
                toolbarButton("checklist", active: isBlockKind { if case .taskItem = $0 { true } else { false } }) {
                    viewModel.toggleList(.task, blockID: focus.blockID)
                }

                divider

                toolbarButton("quote.opening", active: isBlockKind { $0 == .blockquote }) {
                    viewModel.toggleQuote(blockID: focus.blockID)
                }
                toolbarButton("chevron.left.forwardslash.chevron.right", active: isBlockKind { if case .codeBlock = $0 { true } else { false } }) {
                    viewModel.toggleCodeBlock(blockID: focus.blockID)
                }
                toolbarButton("minus", active: false) {
                    viewModel.insertHorizontalRule(afterBlockID: focus.blockID)
                }
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(Color.tfStroke).frame(width: TFBorder.width, height: 20).padding(.horizontal, TFSpacing.xs)
    }

    /// Владелец 03.09.2026: «на кнопки, когда нажимаю, чтобы вибрировало» —
    /// именно у панельки, не глобально (`TFTapScaleStyle` — DesignSystem,
    /// общий на всё приложение, трогать нельзя, ARCHITECTURE.md). `.light` —
    /// тот же стиль, что уже взят для щелчка клавиши в `TFKeyboardHaptics`
    /// (ближайший по смыслу прецедент в проекте: часто повторяющийся тап по
    /// мелкой кнопке), не `.soft`, каким в остальном приложении помечен
    /// свайп-жест — это другая, более тяжёлая моторика.
    private func tapHaptic() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func toolbarButton(_ icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button {
            tapHaptic()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(active ? Color.tfRed : Color.tfSub)
                .frame(width: 36, height: 36)
                .background(active ? Color.tfRed.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: TFRadius.md))
        }
        .buttonStyle(TFTapScaleStyle())
    }

    private func headingButton(_ level: Int) -> some View {
        let active = isBlockKind { if case .heading(let l) = $0 { l == level } else { false } }
        return Button {
            tapHaptic()
            viewModel.toggleHeading(level, blockID: focus.blockID)
        } label: {
            Text("H\(level)")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(active ? Color.tfRed : Color.tfSub)
                .frame(width: 36, height: 36)
                .background(active ? Color.tfRed.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: TFRadius.md))
        }
        .buttonStyle(TFTapScaleStyle())
    }

    private func isBlockKind(_ predicate: (BlockKind) -> Bool) -> Bool {
        guard let idx = viewModel.document.blocks.firstIndex(where: { $0.id == focus.blockID }) else { return false }
        return predicate(viewModel.document.blocks[idx].kind)
    }

    private func toggleMark(_ mark: InlineMark) {
        guard let id = focus.blockID, let ctrl = focus.controller else { return }
        switch mark {
        case .bold: ctrl.toggleBold()
        case .italic: ctrl.toggleItalic()
        case .underline: ctrl.toggleUnderline()
        case .strike: ctrl.toggleStrike()
        case .highlight: ctrl.toggleHighlight()
        case .code: ctrl.toggleCode()
        case .link: return // ссылка — свой обработчик (нужен URL), см. handleLinkTap
        }
        focus.activeMarks = ctrl.activeMarks
        viewModel.updateRuns(blockID: id, runs: ctrl.currentRuns())
    }

    /// «Снимаем ссылку, если курсор уже внутри неё; иначе… спрашиваем URL»
    /// (spec §2.1, п.7 «Ссылка»). Сам alert — на `NoteEditorScreen`, здесь
    /// только выставляем `focus.showLinkPrompt`.
    private func handleLinkTap() {
        guard let id = focus.blockID, let ctrl = focus.controller else { return }
        if let href = ctrl.currentLinkHref, !href.isEmpty {
            ctrl.removeLink()
            focus.activeMarks = ctrl.activeMarks
            viewModel.updateRuns(blockID: id, runs: ctrl.currentRuns())
        } else {
            guard ctrl.hasSelection else { return } // «применяет ссылку к выделенному тексту» — без выделения нечего помечать
            focus.linkPromptText = "https://"
            focus.showLinkPrompt = true
        }
    }

    /// Слева от ленты — владелец 03.09.2026: «не хватает этого момента»,
    /// построена тем же приёмом, что и `micButton` (тот же размер/материал/
    /// кружок). `resignFirstResponder` глобально, без явной ссылки на
    /// текущий `UITextView` — эта панель сама не знает, какой блок сейчас
    /// первый респондер, а глобальный `sendAction` находит его сам, тем же
    /// способом, каким системная кнопка «спрятать клавиатуру» работает
    /// в других приложениях.
    private var dismissKeyboardButton: some View {
        Button {
            tapHaptic()
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        } label: {
            Image(systemName: "keyboard.chevron.compact.down")
                .font(.system(size: 18))
                .foregroundStyle(Color.tfText)
                .frame(width: TFHitTarget.min, height: TFHitTarget.min)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(TFTapScaleStyle())
        .accessibilityLabel("Скрыть клавиатуру")
    }

    private var micButton: some View {
        Button {
            tapHaptic()
            Task { await toggleDictation() }
        } label: {
            Group {
                switch dictation.recordingState {
                case .recording:
                    Image(systemName: "waveform")
                        .symbolEffect(.variableColor.iterative, isActive: true)
                case .transcribing:
                    ProgressView().tint(Color.tfText)
                default:
                    Image(systemName: "mic.fill")
                }
            }
            .font(.system(size: 18))
            .foregroundStyle(dictation.recordingState == .recording ? Color.tfRed : Color.tfText)
            .frame(width: TFHitTarget.min, height: TFHitTarget.min)
            .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(TFTapScaleStyle())
        .disabled(dictation.recordingState == .transcribing)
    }

    /// Тап — старт записи, повторный тап — стоп + вставка распознанного
    /// текста в текущий блок (тот же приём, что у AI-результата в
    /// `runAssist`: `insertPlainParagraph` + `updateRuns`). Просьба владельца
    /// 03.09.2026 «подключи распознавание речи» — `DictationEngine`.
    private func toggleDictation() async {
        switch dictation.recordingState {
        case .idle, .failed:
            await dictation.startRecording()
        case .recording:
            guard let text = await dictation.stopRecordingAndTranscribe(),
                  let id = focus.blockID, let ctrl = focus.controller
            else { return }
            ctrl.insertPlainParagraph(text)
            viewModel.updateRuns(blockID: id, runs: ctrl.currentRuns())
        case .transcribing:
            break
        }
    }
}

/// `inputAccessoryView` живёт по системным правилам UIKit, а не SwiftUI —
/// один и тот же `UIHostingController` назначается ВСЕМ блочным `UITextView`
/// экрана (не по одному на блок): когда фокус переходит между блоками,
/// аксессуар не пересоздаётся, клавиатура просто продолжает показывать тот
/// же самый view — то самое «единым целым с клавиатурой», которое просил
/// владелец, а не отдельный слой, которому есть куда «уехать». Высота
/// фиксированная — лента не переносится по строкам, только скроллится по
/// горизонтали, а штатного моста «SwiftUI intrinsic size → inputAccessoryView»
/// в UIKit нет.
@MainActor
final class NoteKeyboardAccessoryHost {
    static let height: CGFloat = 52

    private let hosting: UIHostingController<NoteKeyboardAccessoryBar>
    var view: UIView { hosting.view }

    init(viewModel: NoteEditorViewModel, focus: NoteEditorFocusState) {
        hosting = UIHostingController(rootView: NoteKeyboardAccessoryBar(viewModel: viewModel, focus: focus))
        hosting.view.backgroundColor = .clear
        hosting.view.frame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: Self.height)
        hosting.view.autoresizingMask = [.flexibleWidth]
    }
}

/// `UITextView`, перехватывающий Backspace на пустом выделении в позиции 0 —
/// штатный `shouldChangeTextIn` на «нечего удалять в начале» делегат не
/// зовёт вовсе, поэтому единственный надёжный способ поймать «слияние с
/// предыдущим блоком» — переопределить сам `deleteBackward()`.
final class NoteUITextView: UITextView {
    var onBackspaceAtStart: (() -> Void)?

    override func deleteBackward() {
        if selectedRange.location == 0 && selectedRange.length == 0 {
            onBackspaceAtStart?()
            return
        }
        super.deleteBackward()
    }

    // Авторост высоты внутри SwiftUI-стека: `isScrollEnabled = false` не
    // сам по себе не публикует новый `intrinsicContentSize` при переносе
    // строк — считаем его явно от ширины и инвалидируем на каждый layout
    // (стандартный приём для growing UITextView в SwiftUI).
    override var intrinsicContentSize: CGSize {
        let fitting = sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude))
        return CGSize(width: UIView.noIntrinsicMetric, height: max(fitting.height, 22))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        invalidateIntrinsicContentSize()
    }
}

struct NoteBlockTextView: UIViewRepresentable {
    let blockID: UUID
    var runs: [RichRun]
    let blockKind: BlockKind
    let controller: NoteBlockTextController
    /// Один и тот же `NoteKeyboardAccessoryHost.view` на все блоки экрана —
    /// см. заголовочный комментарий над `NoteEditorFocusState`.
    let accessoryView: UIView?
    /// Кегль в обход типа блока — нужен ячейке таблицы (шапка полужирная).
    var baseFontOverride: UIFont?
    /// `true` — Enter вставляет перенос прямо в это поле, а не разбивает
    /// блок надвое: у ячейки таблицы «следующего блока» не существует, и
    /// вторая строка внутри неё уедет на сервер как `hardBreak`, ровно как
    /// это делает Shift+Enter в вебе.
    var literalNewline = false

    var onChange: (UUID, [RichRun]) -> Void
    var onFocus: (UUID, NoteBlockTextController) -> Void
    var onBlur: (UUID) -> Void
    var onMarksChange: (UUID, Set<InlineMark>) -> Void
    var onSplit: (UUID, Int) -> Void
    var onBackspaceAtStart: (UUID) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> NoteUITextView {
        let tv = NoteUITextView()
        tv.backgroundColor = .clear
        tv.isScrollEnabled = false
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.delegate = context.coordinator
        tv.font = baseFontOverride ?? NoteRichText.baseFont(for: blockKind)
        tv.tintColor = UIColor(Color.tfRed)
        tv.dataDetectorTypes = []
        tv.attributedText = NoteRichText.attributedString(runs: runs, blockKind: blockKind, base: baseFontOverride)
        tv.inputAccessoryView = accessoryView
        tv.onBackspaceAtStart = { [weak coordinator = context.coordinator] in
            guard let coordinator else { return }
            coordinator.parent.onBackspaceAtStart(coordinator.parent.blockID)
        }
        controller.textView = tv
        controller.blockKind = blockKind
        controller.baseFontOverride = baseFontOverride
        context.coordinator.lastBlockKind = blockKind
        return tv
    }

    func updateUIView(_ uiView: NoteUITextView, context: Context) {
        context.coordinator.parent = self
        controller.blockKind = blockKind
        controller.baseFontOverride = baseFontOverride
        // `accessoryHost` создаётся в `.task` экрана — на самый первый рендер
        // первой строки может ещё не быть готов (`accessoryView == nil`),
        // патчим здесь, как только появится.
        if uiView.inputAccessoryView !== accessoryView {
            uiView.inputAccessoryView = accessoryView
            if uiView.isFirstResponder { uiView.reloadInputViews() }
        }
        let kindChanged = context.coordinator.lastBlockKind != blockKind
        context.coordinator.lastBlockKind = blockKind
        let expected = NoteRichText.attributedString(runs: runs, blockKind: blockKind, base: baseFontOverride)

        if kindChanged {
            // Смена типа блока (параграф → заголовок и т.п.) обязана
            // перерисоваться, ДАЖЕ если поле сейчас в фокусе (иначе кегль
            // заголовка не применится, пока человек не выйдет из блока).
            let saved = uiView.selectedRange
            uiView.attributedText = expected
            uiView.selectedRange = NSRange(location: min(saved.location, expected.length), length: 0)
            if uiView.isFirstResponder {
                uiView.typingAttributes = NoteRichText.attributes(for: RichRun(text: ""), base: controller.baseFont)
            }
        } else if !uiView.isFirstResponder, uiView.attributedText.string != expected.string {
            // Блок сейчас НЕ редактируется — внешняя правка (АИ вставил
            // текст, загрузка документа) синкается свободно. Пока человек
            // печатает в этом же textView, содержимое не трогаем — иначе
            // курсор скачет на каждый ре-рендер SwiftUI.
            uiView.attributedText = expected
        }
    }

    /// Высота по ПРЕДЛОЖЕННОЙ ширине, а не по `bounds.width` прошлого
    /// layout-прохода, как считает `intrinsicContentSize`. Обычному блоку
    /// хватало и его: ширина у всех одна и меняется редко. Ячейке таблицы —
    /// нет: её колонка узкая и своя, на первом проходе `bounds.width` ещё
    /// нулевая, и строка с переносом получала высоту в одну строку —
    /// вторая строка уезжала под нижнюю кромку таблицы.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: NoteUITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0, width < .greatestFiniteMagnitude else { return nil }
        let fitting = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(fitting.height, 22))
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: NoteBlockTextView
        var lastBlockKind: BlockKind = .paragraph

        init(parent: NoteBlockTextView) { self.parent = parent }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.onFocus(parent.blockID, parent.controller)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.onBlur(parent.blockID)
        }

        func textViewDidChange(_ textView: UITextView) {
            textView.invalidateIntrinsicContentSize()
            parent.onChange(parent.blockID, NoteRichText.runs(from: textView.attributedText))
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            parent.onMarksChange(parent.blockID, parent.controller.activeMarks)
        }

        /// Перехватывает Enter — блок дальше решает сам (список/цитата/
        /// заголовок/параграф ведут себя по-разному, ViewModel §«Split»).
        /// Блок кода — исключение: перенос строки литеральный, внутри
        /// одного блока (спека и модель документа соседа это подтверждают).
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if parent.literalNewline { return true }
            if case .codeBlock = parent.blockKind { return true }
            if text == "\n" {
                parent.onSplit(parent.blockID, range.location)
                return false
            }
            return true
        }
    }
}
