import SwiftUI
import UIKit

/// Append recognized speech to the current draft without replacing mentions or manual edits.
enum ChatDictationDraft {
    static func appending(_ transcript: String, to draft: String) -> String {
        let words = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return draft }
        guard !draft.isEmpty else { return words }
        return draft + (draft.last?.isWhitespace == true ? "" : " ") + words
    }
}

/// Три пункта меню «+» (владелец 26.09.2026): фото из галереи, файл,
/// снимок камерой прямо на месте. «Из базы знаний» и отдельная пилюля для
/// квик-реплаев в том же разговоре обсуждались и отклонены владельцем.
enum ChatAttachmentSource {
    case photo, file, camera
}

/// Подпись под рамкой поля: папка у левого края, модель у правого
/// (владелец 27.10.2026). Обе раскладки поля ввода используют её одинаково.
private struct ChatWorkingCaptionInset: ViewModifier {
    let folder: String?
    let model: String?
    let shows: Bool

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if shows, folder != nil || model != nil {
                HStack(spacing: 8) {
                    if let folder { Text(folder).truncationMode(.middle) }
                    Spacer(minLength: 0)
                    if let model { Text(model).truncationMode(.tail) }
                }
                .tfText(.caption)
                .foregroundStyle(Color.tfDim)
                .lineLimit(1)
                .padding(.horizontal, 28)
                .padding(.bottom, 8)
                .accessibilityIdentifier("chat.workingCaption")
            }
        }
    }
}

/// Голосовой композер: панель ввода чата.
struct ChatVoiceComposer: View {
    @Binding var text: String
    let placeholder: String
    let canSendText: Bool
    @Bindable var voice: RoleChatVoiceController
    let onAttachmentSource: (ChatAttachmentSource) -> Void
    let onSendText: () -> Void
    let onSendVoice: (VoiceMessage) async -> Bool
    let onDiscardVoice: (VoiceMessage) -> Void
    var workMode: Binding<RoleChatWorkMode>? = nil
    var executionMode: Binding<ChatExecutionMode>? = nil
    var canChangeExecutionMode = true
    var availableModes: [RoleChatWorkMode] = [.work, .plan]
    /// Пилюля модели рядом с режимом; nil или пустой список — не рисуется.
    var modelChoice: ChatModelChoice? = nil
    /// Рабочая папка (чат с Помощником владельца); nil — чипа нет.
    var workspaceChoice: ChatWorkspaceChoice? = nil
    var sessionControls: AnyView? = nil
    /// Открыть панель сессии (владелец 29.10.2026: «в левую точку нужно
    /// добавить… как в чате с помощником, там называется она сессия»).
    /// nil — окна сессии в этом чате нет, и левая кнопка остаётся меню
    /// действий.
    var onOpenSession: (() -> Void)? = nil
    /// Вложения и режим работы — в панель сессии (владелец 29.10.2026: «в
    /// полосках то, что там есть, просто добавь в эту страничку»).
    var sessionAttachments: ((ChatAttachmentSource) -> Void)? = nil
    var sessionWorkMode: Binding<RoleChatWorkMode>? = nil
    var sessionAvailableWorkModes: [RoleChatWorkMode] = [.work]
    var onShowCommands: (() -> Void)? = nil
    /// Кольца контекста — в ряду ярлычков слева.
    var contextControls: AnyView? = nil
    /// Роли, которым можно написать в этом чате — для кнопки-собачки.
    /// Владелец 11.10.2026: «чтобы я мог точечно писать, сразу же выбрать,
    /// кому я хочу написать из агентов… ее все время от руки писать не охоту».
    /// Пусто — кнопка не рисуется (например, в 1:1-чате или в другом
    /// композере, который список не передаёт).
    var mentionCandidates: [RoleChatMember] = []
    /// Список ролей для кнопки «@» в единой панели чата.
    private var showsMentionButton: Bool {
        !mentionCandidates.isEmpty
    }
    var isResponding = false
    var isStopping = false
    var onStop: (() -> Void)? = nil
    var focus: FocusState<Bool>.Binding? = nil

    @State private var player = VoicePlayer()
    @State private var isRecording = false
    @State private var preview: VoiceMessage?
    @State private var isSendingVoice = false
    @FocusState private var isTextFieldFocused: Bool
    private var textFieldFocus: FocusState<Bool>.Binding { focus ?? $isTextFieldFocused }
    @Namespace private var composerNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Вид панели ввода: два варианта, переключаются в настройках
    /// (владелец 29.10.2026 — «свою панель ввода предложить, а мою туда
    /// закинуть, чтобы можно было переключать, если что»).
    @AppStorage(ChatComposerStyle.storageKey) private var composerStyleRaw = ChatComposerStyle.defaultStyle.rawValue
    private var composerStyle: ChatComposerStyle { ChatComposerStyle.resolve(composerStyleRaw) }

    @ViewBuilder private var executionModeMenu: some View {
        if let executionMode {
            Divider()
            Picker("", selection: executionMode) {
                ForEach(ChatExecutionMode.allCases, id: \.self) { choice in
                    Text(choice.title).tag(choice)
                }
            }
            .pickerStyle(.inline)
            .disabled(!canChangeExecutionMode)
        }
    }

    var body: some View {
        ZStack {
            promptComposer
                .allowsHitTesting(!isRecording && preview == nil)
                .accessibilityHidden(isRecording || preview != nil)
            if isRecording { promptRecordingComposer }
            if let preview { promptPreviewComposer(preview) }
        }
        .contentShape(Rectangle())
        .onDisappear {
            voice.cancel()
            player.stop()
        }
    }

    private var promptAttachmentMenu: some View {
        attachmentMenu(circle: false)
    }

    /// Меню действий чата. `circle` — круглая подложка: так кнопка выглядит
    /// в новой раскладке, где она стоит вне капсулы поля.
    private func attachmentMenu(circle: Bool) -> some View {
        Menu {
            Section("Вложения") {
                Button { onAttachmentSource(.photo) } label: { Label("Фото", systemImage: "photo.on.rectangle") }
                Button { onAttachmentSource(.file) } label: { Label("Файл", systemImage: "doc") }
                Button { onAttachmentSource(.camera) } label: { Label("Камера", systemImage: "camera") }
            }
            if let workMode {
                Section("Режим") {
                    Picker("Режим работы", selection: workMode) {
                        ForEach(availableModes, id: \.self) { mode in
                            Label(mode.title, systemImage: mode.symbol).tag(mode)
                        }
                    }
                }
            }
            executionModeMenu
            if let onShowCommands {
                Button("Навыки и инструменты", systemImage: "slash", action: onShowCommands)
            }
        } label: {
            if circle {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .frame(width: 40, height: 40)
                    .background(Color(white: 0.125), in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.12)))
            } else {
                promptIcon("slider.horizontal.3")
            }
        }
        .disabled(!canChangeExecutionMode)
        .accessibilityLabel("Действия чата" + (workMode.map { ": " + $0.wrappedValue.title } ?? ""))
        .accessibilityIdentifier("chat.actions")
        .hintAnchor(HintAnchorID.chatComposerActions)
    }

    /// Нынешняя раскладка: капсула, поле сверху, ряд действий под ним.
    private var stackedPromptPanel: some View {
        ChatPromptPanel(text: $text, placeholder: placeholder,
                        hidesText: isRecording || preview != nil,
                        focus: textFieldFocus, onSubmit: onSubmitText) {
            HStack(spacing: 0) {
                promptAttachmentMenu
                if showsMentionButton { mentionButton }
                // Режим не дублируется подписью: он виден в меню настроек слева.
                if let sessionControls {
                    sessionControls
                } else {
                    if let modelChoice, modelChoice.isAvailable {
                        // «Мозги» — размером как кольцо контекста и значок вложений
                        // (20 pt в поле 40), без своей подложки (владелец 27.10.2026).
                        ChatModelMenu(choice: modelChoice) {
                            HStack(spacing: 4) {
                                Image("ModelBrain")
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 20, height: 20)
                            }
                            .frame(minWidth: 40, minHeight: 40)
                            .contentShape(Rectangle())
                        }
                    }
                    if let workspaceChoice, workspaceChoice.isAvailable {
                        // Тот же вид, что у пилюли модели слева от неё.
                        ChatWorkspaceMenu(choice: workspaceChoice) {
                            HStack(spacing: 4) {
                                Image(systemName: "folder")
                                    .font(.system(size: 20, weight: .regular))
                                    .frame(width: 20, height: 20)
                            }
                            .frame(minWidth: 40, minHeight: 40)
                            .contentShape(Rectangle())
                        }
                        .padding(.leading, 4)
                    }
                    // Кольцо контекста — крайнее справа из ярлычков (владелец 27.10.2026).
                    if let contextControls { contextControls }
                }
                Spacer(minLength: 8)
                micButton
                sendButton
            }
            .foregroundStyle(Color.white.opacity(0.6))
        }
        .opacity(isRecording || preview != nil ? 0 : 1)
        .matchedGeometryEffect(id: "voiceComposerPill", in: composerNamespace)
        .padding(.horizontal).padding(.top, 10)
        .padding(.bottom, workingFolder == nil && workingModel == nil ? 10 : 2)
        .modifier(workingCaption)
    }

    /// Новая раскладка в покое (владелец 29.10.2026): всё в одну строку —
    /// круглое меню действий слева, капсула с полем и значками, круглый микрофон
    /// справа. Отправки в покое нет: текста ещё не написано, а место занял
    /// микрофон — на него нажимают, не поднимая клавиатуру.
    private var compactPromptPanel: some View {
        HStack(spacing: 8) {
            compactLeadingButton
            HStack(spacing: 4) {
                TextField(placeholder, text: $text, axis: .vertical)
                    .lineLimit(1...4)
                    .textInputAutocapitalization(.sentences)
                    .focused(textFieldFocus)
                    .onSubmit { onSubmitText() }
                    .foregroundStyle(Color.tfPaper)
                    .accessibilityIdentifier("chat.message")
                if showsMentionButton { mentionButton }
                // В новой панели в капсуле — только папка и мозги (владелец
                // 29.10.2026: «с краю останется только папочка и мозги»).
                // Сессия открывается с левой кнопки, поэтому отдельной кнопки
                // «Сессия» здесь не нужно.
                if let modelChoice, modelChoice.isAvailable {
                    ChatModelMenu(choice: modelChoice) {
                        HStack(spacing: 4) {
                            Image("ModelBrain")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                        }
                        .frame(minWidth: 40, minHeight: 40)
                        .contentShape(Rectangle())
                    }
                }
                if let workspaceChoice, workspaceChoice.isAvailable {
                    ChatWorkspaceMenu(choice: workspaceChoice) {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                                .font(.system(size: 20, weight: .regular))
                                .frame(width: 20, height: 20)
                        }
                        .frame(minWidth: 40, minHeight: 40)
                        .contentShape(Rectangle())
                    }
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 4)
            .padding(.vertical, 2)
            .frame(minHeight: 40)
            .background(Color(white: 0.125), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.white.opacity(0.12)))
            .foregroundStyle(Color.white.opacity(0.6))
            // В морфинг уходит сама капсула: кнопки по краям остаются на месте.
            .matchedGeometryEffect(id: "voiceComposerPill", in: composerNamespace)
            compactMicButton
        }
        .opacity(isRecording || preview != nil ? 0 : 1)
        .padding(.horizontal).padding(.top, 10)
        .padding(.bottom, workingFolder == nil && workingModel == nil ? 10 : 2)
        .modifier(workingCaption)
    }

    /// Левая кнопка в новой панели: открывает окно сессии, если оно есть в
    /// этом чате (владелец 29.10.2026). Иначе — прежнее меню действий.
    @ViewBuilder private var compactLeadingButton: some View {
        if let onOpenSession {
            Button(action: onOpenSession) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .frame(width: 36, height: 36)
                    .background(Color(white: 0.125), in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.12)))
                    .frame(width: 40, height: 40)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Сессия")
            .accessibilityIdentifier("chat.session")
            .hintAnchor(HintAnchorID.chatSession)
        } else {
            attachmentMenu(circle: true)
        }
    }

    /// Микрофон отдельной круглой кнопкой справа — на месте отправки, пока
    /// текста нет. Нажатие не ставит каретку: клавиатура не поднимается
    /// (владелец 29.10.2026).
    private var compactMicButton: some View {
        Button(action: startVoiceRecording) {
            Image(systemName: "mic")
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(Color.tfText)
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.12), in: Circle())
                .frame(width: 40, height: 40)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Начать диктовку")
        .accessibilityIdentifier("chat.voice")
        .hintAnchor(HintAnchorID.chatDictation)
    }

    /// Вид панели ввода в покое: однострочная, пока пользователь не начал
    /// ввод; дальше — привычная панель целиком (владелец 29.10.2026).
    private var composerLayout: ChatComposerLayout {
        ChatComposerLayoutPolicy.layout(style: composerStyle, hasExpanded: hasExpandedPanel)
    }

    /// Панель уже развернулась: пользователь начал ввод или вставил текст.
    /// Обратно не сжимается — сжатие отняло бы каретку посреди набора.
    @State private var hasExpandedPanel = false
    /// Развернуть панель и вернуть каретку в новое поле: после смены вью
    /// старое поле исчезает, и без этого каретка бы пропала.
    private func expandPanelKeepingFocus() {
        guard !hasExpandedPanel else { return }
        hasExpandedPanel = true
        DispatchQueue.main.async { textFieldFocus.wrappedValue = true }
    }

    /// Отправка по кнопке «вверх» на клавиатуре.
    private func onSubmitText() {
        guard !isRecording, preview == nil else { return }
        onSendText()
    }

    /// Кнопка диктовки — в обоих вариантах одна и та же.
    private var micButton: some View {
        Button(action: startVoiceRecording) {
            promptIcon("mic").contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Начать диктовку")
        .accessibilityIdentifier("chat.voice")
        .hintAnchor(HintAnchorID.chatDictation)
    }

    /// Отправка или остановка ответа — в обоих вариантах одна и та же.
    @ViewBuilder private var sendButton: some View {
        if isResponding, !canSendText, let onStop {
            Button(action: onStop) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 36, height: 36)
                    .background(.white, in: Circle())
                    .frame(width: 40, height: 40)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(isStopping)
            .accessibilityLabel("Остановить ответ роли")
            .accessibilityIdentifier("chat.stop")
        } else {
            Button(action: onSendText) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(canSendText ? 1 : 0.25), in: Circle())
                    .frame(width: 40, height: 40)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSendText)
            .accessibilityLabel("Отправить")
            .accessibilityIdentifier("chat.send")
        }
    }

    /// Подпись под рамкой: папка у левого края, модель у правого
    /// (владелец 27.10.2026).
    private var workingCaption: ChatWorkingCaptionInset {
        ChatWorkingCaptionInset(folder: workingFolder, model: workingModel,
                                shows: !isRecording && preview == nil)
    }

    @ViewBuilder private var promptComposer: some View {
        switch composerLayout {
        case .compact:
            compactPromptPanel
                // Касание поля — намерение писать: панель разворачивается в
                // привычную (владелец 29.10.2026 — два состояния панели).
                .onChange(of: textFieldFocus.wrappedValue) { _, focused in
                    if focused { expandPanelKeepingFocus() }
                }
        case .full:
            stackedPromptPanel
        }
    }

    /// Рабочая папка для подписи под рамкой; nil — не выбрана.
    private var workingFolder: String? {
        workspaceChoice?.selected.map { ($0 as NSString).lastPathComponent }
    }

    /// Модель, которой роль работает на деле; nil — не известна.
    private var workingModel: String? { modelChoice?.effectiveTitle }

    /// Выбор адресата рядом со скрепкой и режимом работы.
    private var mentionButton: some View {
        Menu {
            ForEach(mentionCandidates) { member in
                // Без иконки в строке: в меню она дублировала бы то самое
                // «@», ради которого меню и открыто. Плюс у ролей уже есть
                // свои аватары в шапке чата — здесь достаточно имени.
                Button { insertMention(member) } label: {
                    Text(member.name)
                }
            }
        } label: {
            promptIcon("at")
        }
        .accessibilityLabel("Выбрать адресата")
        .accessibilityIdentifier("chat.mention")
    }

    /// Значок нижней строки поля: один размер и одна зона нажатия у всех.
    private func promptIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 19, weight: .regular))
            .frame(width: 40, height: 40)
    }

    /// «@Имя » в конец черновика. Пробел в конце — как у набранного руками
    /// упоминания в `RoleChatsScreen.insertMention`: без него продолжение
    /// набора слилось бы с именем, и подсказка адресатов не закрылась бы.
    /// Пустое поле получает упоминание без ведущего пробела.
    private func insertMention(_ member: RoleChatMember) {
        let needsSpace = !text.isEmpty && !text.hasSuffix(" ")
        text += (needsSpace ? " " : "") + "@\(member.name) "
        // Упоминание вставлено по тапу на «@» — здесь каретка нужна.
        if ChatComposerLayoutPolicy.focusesField(.mentionInserted) {
            textFieldFocus.wrappedValue = true
        }
        hasExpandedPanel = true
    }

    private var promptRecordingComposer: some View {
        // Одна строка в том же поле: время, волна на всю ширину, стоп.
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Circle().fill(.red).frame(width: 8, height: 8)
                Text(recordingDuration).font(.callout.monospacedDigit()).foregroundStyle(Color.tfPaper)
            }
            VoiceRecordingWaveformView(level: recordingLevel, elapsed: recordingElapsed,
                                       color: .red.mix(with: .black, by: 0.55), peakColor: .red, maxHeight: 30)
                .frame(maxWidth: .infinity)
            Button(action: stopVoiceRecording) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 36, height: 36)
                    .background(.white, in: Circle())
                    .frame(width: 40, height: 40)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Остановить запись")
        }
        .padding(.leading, 16).padding(.trailing, 8)
        .frame(minHeight: 56)
        .padding(.vertical, 8)
        .background(Color(white: 0.125), in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.white.opacity(0.12)))
        .matchedGeometryEffect(id: "voiceComposerPill", in: composerNamespace)
        .padding(.horizontal).padding(.vertical, 10)
        .transition(.opacity)
    }

    /// Превью записи в оформлении панели чата (владелец
    /// 10.10.2026). Тот же тёмный фон и та же кнопка отправки, что у нового
    /// поля, — иначе перед отправкой интерфейс выглядит старым.
    private func promptPreviewComposer(_ message: VoiceMessage) -> some View {
        VStack(spacing: 12) {
            if let transcript = readyTranscript(message) {
                Text(transcript)
                    .font(.body)
                    .foregroundStyle(Color.tfPaper)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("chat.voice.transcript")
            } else if message.transcript == .pending {
                // Надпись — в нижней строке, на месте волны (владелец 20.10.2026).
                EmptyView()
            } else {
                Text("Не удалось распознать речь. Черновик сохранён — удалите запись и попробуйте ещё раз.")
                    .font(.callout).foregroundStyle(.gray)
                    .accessibilityIdentifier("chat.voice.transcription-error")
            }
            HStack(spacing: 12) {
                Button(action: discardPreview) {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.tfPaper)
                        .frame(width: 40, height: 40)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Удалить запись")
                .accessibilityIdentifier("chat.voice.discard")
                // Пока расшифровывается — ни серой волны, ни кнопки справа:
                // только «Расшифровываю…» на их месте (владелец 20.10.2026).
                let transcribing = message.transcript == .pending
                if transcribing {
                    HStack(spacing: 8) {
                        ProgressView().tint(.white)
                        Text("Расшифровываю…").tfText(.action).foregroundStyle(.gray)
                    }
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                } else {
                    WaveformView(levels: message.waveform, color: .gray)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                }
                Text(durationText(message.duration))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.gray)
                if transcribing {
                    EmptyView()
                } else if isSendingVoice {
                    ProgressView().frame(width: 40, height: 40)
                } else {
                    Button(action: sendPreview) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.black)
                            .frame(width: 40, height: 40)
                            .background(.white, in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Редактировать текст")
                    .accessibilityIdentifier("chat.voice.send")
                    .disabled(readyTranscript(message)?.isEmpty != false)
                }
            }
            .foregroundStyle(Color.tfPaper)
        }
        .padding(14)
        .background(Color(white: 0.125), in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.white.opacity(0.12)))
        .matchedGeometryEffect(id: "voiceComposerPill", in: composerNamespace)
        .padding(.horizontal).padding(.vertical, 10)
        .transition(.opacity)
    }

    /// Расшифровка, если она готова. Пустая строка — тоже nil: показать нечего.
    private func readyTranscript(_ message: VoiceMessage) -> String? {
        guard case let .ready(t) = message.transcript else { return nil }
        let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var recordingElapsed: TimeInterval {
        guard case let .recording(elapsed, _) = voice.recordingState else { return 0 }
        return elapsed
    }

    private var recordingLevel: Double {
        guard case let .recording(_, level) = voice.recordingState else { return 0 }
        return level
    }

    private var recordingDuration: String {
        guard case let .recording(elapsed, _) = voice.recordingState else { return "0:00" }
        return durationText(elapsed)
    }

    private func durationText(_ duration: TimeInterval) -> String {
        String(format: "%d:%02d", Int(duration) / 60, Int(duration) % 60)
    }

    private func startVoiceRecording() {
        guard !isRecording, preview == nil else { return }
        withAnimation(reduceMotion ? .linear(duration: 0.12) : .spring(duration: 0.32, bounce: 0)) {
            isRecording = true
        }
        // Каретку в поле не ставим: на неё реагирует клавиатура, а при
        // диктовке она владельцу не нужна (владелец 29.10.2026: «когда я
        // сразу на микрофон нажимаю, клавиатура не должна реагировать»).
        if ChatComposerLayoutPolicy.focusesField(.microphonePressed) {
            DispatchQueue.main.async { textFieldFocus.wrappedValue = true }
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #if DEBUG
        if ProcessInfo.processInfo.environment["TASKFLOW_DICTATION_PREVIEW"] == "1" { return }
        #endif
        Task {
            await voice.start()
            guard voice.phase == .recording else {
                withAnimation(reduceMotion ? .linear(duration: 0.12) : .spring(duration: 0.2, bounce: 0)) {
                    isRecording = false
                }
                return
            }
        }
    }

    private func stopVoiceRecording() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["TASKFLOW_DICTATION_PREVIEW"] == "1", isRecording {
            let message = VoiceMessage(audioURL: FileManager.default.temporaryDirectory.appendingPathComponent("dictation-preview.wav"), duration: 1)
            isRecording = false
            preview = message
            let result: TranscriptState = ProcessInfo.processInfo.environment["TASKFLOW_DICTATION_PREVIEW_FAIL"] == "1"
                ? .failed : .ready("Проверка диктовки.")
            Task { await receiveTranscription(result, for: message) }
            return
        }
        #endif
        guard voice.phase == .recording else { return }
        withAnimation(reduceMotion ? .linear(duration: 0.12) : .spring(duration: 0.32, bounce: 0)) {
            isRecording = false
            preview = voice.finish()
        }
        guard let message = preview else { return }
        Task {
            let transcript = await voice.transcribe(message)
            await receiveTranscription(transcript, for: message)
        }
    }

    private func receiveTranscription(_ transcript: TranscriptState, for message: VoiceMessage) async {
        guard preview?.id == message.id else { return }
        preview?.transcript = transcript
        voice.complete()
        if case .ready(let words) = transcript, !words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            placeTranscriptInDraft(words, from: message)
        }
    }

    private func placeTranscriptInDraft(_ words: String, from message: VoiceMessage) {
        guard preview?.id == message.id else { return }
        text = ChatDictationDraft.appending(words, to: text)
        isSendingVoice = false
        player.stop()
        voice.complete()
        withAnimation(reduceMotion ? .linear(duration: 0.12) : .spring(duration: 0.32, bounce: 0)) {
            preview = nil
        }
        onDiscardVoice(message)
        try? VoiceRecorder.cancelRecordingFile(at: message.audioURL)
        // Текст появился — панель разворачивается в обычную (владелец
        // 29.10.2026). Каретку в поле не ставим: расшифровка сама вставила
        // текст, клавиатура после диктовки не нужна.
        hasExpandedPanel = true
        if ChatComposerLayoutPolicy.focusesField(.transcriptionInserted) {
            textFieldFocus.wrappedValue = true
        }
    }

    private func discardPreview() {
        guard let message = preview else { return }
        player.stop()
        onDiscardVoice(message)
        try? VoiceRecorder.cancelRecordingFile(at: message.audioURL)
        voice.complete()
        withAnimation(reduceMotion ? .linear(duration: 0.12) : .spring(duration: 0.32, bounce: 0)) {
            preview = nil
        }
    }

    private func sendPreview() {
        guard let message = preview, message.transcript != .pending,
              let transcript = readyTranscript(message) else { return }
        placeTranscriptInDraft(transcript, from: message)
    }

}

// `voiceCircleSurface()`/`voiceCapsuleSurface()` переехали в
// `Sources/DesignSystem/Components/TFKeyboardPill.swift` (LOCK-254) — теперь
// нужны не только чату, но и панели форматирования Markdown.

/// Системная нижняя safe area следует за клавиатурой, как в QuickAddTaskView.
extension View {
    @ViewBuilder func chatComposerBar<BarContent: View>(@ViewBuilder content: () -> BarContent) -> some View {
        if #available(iOS 26.0, *) {
            safeAreaBar(edge: .bottom, content: content)
        } else {
            safeAreaInset(edge: .bottom, content: content)
        }
    }

    /// `safeAreaBar` (iOS 26+) сама включает системный blur-переход там, где
    /// лента сообщений уходит под панель ввода — визуально это подложка под
    /// композером и рядом стоящими квик-реплаями/подсказками (владелец
    /// 26.09.2026: «какая-то подложка/повидла», просил убрать). Это штатный
    /// `ScrollEdgeEffectStyle`, а не наш фон — выключается своим модификатором.
    /// На iOS до 26 `chatComposerBar` использует `safeAreaInset`, у которого
    /// такого эффекта нет вовсе — модификатор просто недоступен.
    @ViewBuilder func hideComposerScrollEdgeEffect() -> some View {
        if #available(iOS 26.0, *) { scrollEdgeEffectHidden(true, for: .bottom) }
        else { self }
    }
}

#if DEBUG
/// Exercises the production composer and renderer without a server session.
struct AgentChatComposerPreview: View {
    @State private var text = ""
    @State private var sentText = ""
    @State private var mode: RoleChatWorkMode = .work
    @State private var executionMode: ChatExecutionMode = .chat
    @State private var voice = RoleChatVoiceController()
    @State private var responding = ProcessInfo.processInfo.environment["TASKFLOW_PROMPT_BOX_PREVIEW"] != "1"
    @State private var stream = ""
    @State private var complete = false
    @State private var playbackComplete = false
    private let response = "Сначала изучу исходные данные и сравню независимые источники. Затем проверю противоречия, составлю план и отмечу критерии приёмки. Текст появляется постепенно и спокойно, а готовый ответ сохраняет своё место в ленте."
    private var smoothPreview: Bool { ProcessInfo.processInfo.environment["TASKFLOW_SMOOTH_STREAM_PREVIEW"] == "1" }
    private var previewItems: [RoleChatLiveItem] {
        if ProcessInfo.processInfo.environment["TASKFLOW_RICH_FAST_PREVIEW"] == "1" {
            let prefix = String(repeating: "Пояснение появляется плавно. ", count: 100)
            let html = "```html\n<title>Быстрый интерактив</title><button onclick=\"this.textContent='Нажато'\">Проверить HTML</button>\n```"
            let widget = "```widget\n{\"type\":\"card\",\"title\":\"Быстрый виджет\",\"subtitle\":\"Готов сразу\"}\n```"
            return [.text(prefix + "\n" + html + "\n" + widget + "\nХВОСТ ПОЯСНЕНИЯ")]
        }
        guard smoothPreview, !stream.isEmpty else { return [.text(stream)] }
        return [.text(stream)] + (0..<4).map {
            .step(RoleChatLiveStep(id: "smooth-\($0)", tool: "read", detail: "Файл \($0 + 1)", status: .done))
        } + [.text("Проверка завершена. Все действия показаны последовательно.")]
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    RoleLiveTurnBubble(
                        turn: RoleChatLiveTurn(chatID: "preview", userID: "role_researcher", name: "Исследователь", startedAt: nil,
                                               items: previewItems, thinking: nil),
                        showsName: false, isComplete: complete,
                        onPlaybackComplete: { playbackComplete = true }
                    )
                    .padding()
                    if playbackComplete { Text("Ответ показан").accessibilityIdentifier("chat.preview.complete") }
                }
                if ProcessInfo.processInfo.environment["TASKFLOW_DICTATION_PREVIEW"] == "1", !sentText.isEmpty {
                    Text(sentText).accessibilityIdentifier("chat.preview.sent-text")
                }
                ChatVoiceComposer(text: $text, placeholder: "Сообщение", canSendText: !text.isEmpty,
                                  voice: voice, onAttachmentSource: { _ in }, onSendText: { sentText = text; text = "" },
                                  onSendVoice: { _ in false }, onDiscardVoice: { _ in },
                                  workMode: $mode, executionMode: $executionMode, availableModes: RoleChatWorkMode.allCases,
                                  mentionCandidates: [RoleChatMember(id: "preview-role", name: "Архитектор", avatarColor: nil, avatarURL: nil, initials: nil, roleKey: "architect")],
                                  isResponding: responding, onStop: { responding = false })
            }
            .background(Color.tfBackground.ignoresSafeArea())
            .navigationTitle("Исследователь")
            .task {
                if smoothPreview {
                    stream = String(repeating: response + " ", count: 3)
                    complete = true
                    return
                }
                let words = response.split(separator: " ").map(String.init)
                for word in words {
                    do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
                    stream += (stream.isEmpty ? "" : " ") + word
                }
                complete = true
            }
        }
    }
}
#endif
