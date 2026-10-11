import SwiftUI
import UIKit

enum ChatComposerKeyboardDismissGesture {
    static func shouldDismiss(translation: CGSize) -> Bool {
        translation.height >= 38 && translation.height > abs(translation.width) * 1.2
    }
}

/// Три пункта меню «+» (владелец 26.09.2026): фото из галереи, файл,
/// снимок камерой прямо на месте. «Из базы знаний» и отдельная пилюля для
/// квик-реплаев в том же разговоре обсуждались и отклонены владельцем.
enum ChatAttachmentSource {
    case photo, file, camera
}

/// Тот же трёхсостоянийный композер, что в VoiceMessageLabScreen.
struct ChatVoiceComposer: View {
    @Binding var text: String
    let placeholder: String
    let canSendText: Bool
    @Bindable var voice: RoleChatVoiceController
    let onAttachmentSource: (ChatAttachmentSource) -> Void
    let onSendText: () -> Void
    /// Отправка уже набранного текста (используется, когда голосовое поле
    /// в экспериментальном режиме отправляет расшифровку, а не голос).
    var onSendTranscribedText: ((String) -> Void)? = nil
    let onSendVoice: (VoiceMessage) async -> Bool
    let onDiscardVoice: (VoiceMessage) -> Void
    var workMode: Binding<RoleChatWorkMode>? = nil
    var availableModes: [RoleChatWorkMode] = [.work, .plan]
    /// Роли, которым можно написать в этом чате — для кнопки-собачки.
    /// Владелец 11.10.2026: «чтобы я мог точечно писать, сразу же выбрать,
    /// кому я хочу написать из агентов… ее все время от руки писать не охоту».
    /// Пусто — кнопка не рисуется (например, в 1:1-чате или в другом
    /// композере, который список не передаёт).
    var mentionCandidates: [RoleChatMember] = []
    /// Список ролей для кнопки «@» у ЭКСПЕРИМЕНТАЛЬНОГО поля. Старый вид
    /// композера кнопку не показывает — там владелец её не просил, а места
    /// в строке нет: там и так плюс, поле, режим и отправка.
    private var showsMentionButton: Bool {
        experimentalPromptBox && !mentionCandidates.isEmpty
    }
    var isResponding = false
    var isStopping = false
    var onStop: (() -> Void)? = nil

    @AppStorage("chat.experimentalPromptBox") private var experimentalPromptBox = true
    @State private var player = VoicePlayer()
    @State private var isRecording = false
    @State private var preview: VoiceMessage?
    @State private var sendAfterTranscription = false
    @State private var isSendingVoice = false
    @FocusState private var isTextFieldFocused: Bool
    @Namespace private var composerNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Единая высота элементов композера: круглая кнопка вложений и капсула —
    /// одной высоты (владелец 21.09.2026: «у всех величины одинаковые всегда,
    /// не одна маленькая, другая большая»). Владелец 25.09.2026: состояние
    /// покоя было слишком высоким — снижено до `TFChatComposer.elementHeight`
    /// (та же высота, что у остальных элементов композера, напр. адресата в
    /// `ChatComposer.swift`); авто-рост под длинный текст не затронут —
    /// им управляет `.lineLimit(1...4)` у `TextField`, не эта константа.
    private let composerHeight: CGFloat = TFChatComposer.elementHeight

    var body: some View {
        ZStack {
            // Поле не удаляется при морфинге, поэтому клавиатура остаётся на месте.
            if experimentalPromptBox { promptComposer } else { idleComposer }
            if isRecording {
                if experimentalPromptBox { promptRecordingComposer } else { recordingComposer }
            }
            if let preview {
                // Владелец 10.10.2026: «я уже наговорил и мне пора отправлять —
                // он переделывается опять в старое поле». Превью рендерилось
                // единственным старым видом, и экспериментальное поле
                // возвращалось назад ровно в момент отправки. У превью своя
                // ветка на каждый режим.
                if experimentalPromptBox {
                    promptPreviewComposer(preview)
                } else {
                    previewComposer(preview)
                }
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 16)
                .onEnded { value in
                    guard ChatComposerKeyboardDismissGesture.shouldDismiss(translation: value.translation) else { return }
                    isTextFieldFocused = false
                }
        )
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.environment["TASKFLOW_PROMPT_BOX_PREVIEW"] == "1" {
                experimentalPromptBox = true
            }
            #endif
        }
        .onDisappear {
            voice.cancel()
            player.stop()
        }
    }

    private var idleComposer: some View {
        HStack(spacing: 12) {
            Group {
                if isResponding, let onStop {
                    Button(action: onStop) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.primary)
                            .frame(width: composerHeight, height: composerHeight)
                            .voiceCircleSurface()
                    }
                    .buttonStyle(.plain)
                    .disabled(isStopping)
                    .accessibilityLabel("Остановить ответ роли")
                    .accessibilityIdentifier("chat.stop")
                } else {
                    Menu {
                        Toggle("Экспериментальное поле", isOn: $experimentalPromptBox)
                        Button { onAttachmentSource(.photo) } label: {
                            Label("Фото", systemImage: "photo.on.rectangle")
                        }
                        Button { onAttachmentSource(.file) } label: {
                            Label("Файл", systemImage: "doc")
                        }
                        Button { onAttachmentSource(.camera) } label: {
                            Label("Камера", systemImage: "camera")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.primary)
                            .frame(width: composerHeight, height: composerHeight)
                            .voiceCircleSurface()
                    }
                    .tint(.primary)
                    .accessibilityLabel("Добавить вложение")
                    .accessibilityIdentifier("chat.attachment")
                }
            }
            .opacity(isRecording || preview != nil ? 0 : 1)
            HStack(spacing: 8) {
                TextField(isRecording || preview != nil ? "" : placeholder, text: $text, axis: .vertical)
                    .lineLimit(1...4)
                    .frame(maxWidth: .infinity, minHeight: composerHeight, alignment: .leading)
                    .contentShape(Rectangle())
                    .textInputAutocapitalization(.sentences)
                    .focused($isTextFieldFocused)
                    .onSubmit(onSendText)
                    .foregroundStyle(isRecording || preview != nil ? Color.clear : Color.primary)
                    .accessibilityIdentifier("chat.message")
                if let workMode {
                    Menu {
                        Picker("Режим работы", selection: workMode) {
                            ForEach(availableModes, id: \.self) { mode in
                                Label(mode.title, systemImage: mode.symbol).tag(mode)
                            }
                        }
                    } label: {
                        Image(systemName: workMode.wrappedValue.symbol)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Color.tfReadableSecondary)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("chat.mode")
                    .accessibilityLabel("Режим работы: " + workMode.wrappedValue.title)
                }
                if canSendText {
                    actionButton("paperplane.fill", label: "Отправить", identifier: "chat.send", tint: Color.tfRed, action: onSendText)
                } else {
                    Image(systemName: "waveform")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color.tfReadableSecondary)
                        .frame(width: 36, height: 36)
                        .frame(width: workMode == nil ? composerHeight * 2 : 36, height: composerHeight, alignment: .trailing)
                        .contentShape(Rectangle())
                        .onLongPressGesture(minimumDuration: 0.18, perform: startVoiceRecording)
                        .accessibilityLabel("Удерживайте для начала записи")
                        .accessibilityIdentifier("chat.voice")
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: composerHeight)
            .voiceCapsuleSurface()
            .opacity(isRecording || preview != nil ? 0 : 1)
            .matchedGeometryEffect(id: "voiceComposerPill", in: composerNamespace)
        }
        .padding(.horizontal).padding(.vertical, 10)
    }

    private var promptAttachmentMenu: some View {
        Menu {
            Button { onAttachmentSource(.photo) } label: { Label("Фото", systemImage: "photo.on.rectangle") }
            Button { onAttachmentSource(.file) } label: { Label("Файл", systemImage: "doc") }
            Button { onAttachmentSource(.camera) } label: { Label("Камера", systemImage: "camera") }
            Divider()
            Toggle("Экспериментальное поле", isOn: $experimentalPromptBox)
        } label: {
            Image(systemName: "paperclip").frame(width: 44, height: 44)
        }
        .accessibilityLabel("Добавить вложение")
        .accessibilityIdentifier("chat.attachment")
    }

    private var promptComposer: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(isRecording || preview != nil ? "" : placeholder, text: $text, axis: .vertical)
                .lineLimit(2...5)
                .textInputAutocapitalization(.sentences)
                .focused($isTextFieldFocused)
                .onSubmit(onSendText)
                .foregroundStyle(isRecording || preview != nil ? Color.clear : Color.white)
                .accessibilityIdentifier("chat.message")
                .padding(.horizontal, 10).padding(.top, 10)
            HStack(spacing: 4) {
                promptAttachmentMenu
                if let workMode {
                    Menu {
                        Picker("Режим работы", selection: workMode) {
                            ForEach(availableModes, id: \.self) { mode in
                                Label(mode.title, systemImage: mode.symbol).tag(mode)
                            }
                        }
                    } label: {
                        Image(systemName: workMode.wrappedValue.symbol).frame(width: 44, height: 44)
                    }
                    .accessibilityIdentifier("chat.mode")
                    .accessibilityLabel("Режим работы: " + workMode.wrappedValue.title)
                }
                Spacer(minLength: 0)
                if canSendText {
                    actionButton("arrow.up", label: "Отправить", identifier: "chat.send", tint: .black, action: onSendText)
                        .background(.white, in: Circle())
                } else if isResponding, let onStop {
                    actionButton("stop.fill", label: "Остановить ответ роли", identifier: "chat.stop", tint: .white, action: onStop)
                        .disabled(isStopping)
                } else {
                    Image(systemName: "mic.fill")
                        .foregroundStyle(.black)
                        .frame(width: 40, height: 40)
                        .background(.white, in: Circle())
                        .contentShape(Circle())
                        .onTapGesture { startVoiceRecording() }
                        .accessibilityLabel("Начать запись")
                        .accessibilityIdentifier("chat.voice")
                }
                // Собачка — ПОСЛЕ отправки («молнии»), владелец 11.10.2026:
                // «после молнии надо ставить». Серенькая, как скрепка и
                // режим работы, — без белого круга, который есть только у
                // действий-команд (микрофон, отправка).
                if showsMentionButton {
                    mentionButton
                }
            }
            .foregroundStyle(.gray)
        }
        .padding(8)
        .background(Color(white: 0.125), in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.white.opacity(0.12)))
        .opacity(isRecording || preview != nil ? 0 : 1)
        .matchedGeometryEffect(id: "voiceComposerPill", in: composerNamespace)
        .padding(.horizontal).padding(.vertical, 10)
    }

    /// Собачка у отправки (владелец 11.10.2026: «после молнии надо ставить,
    /// чтобы он тоже был таким вот сереньким»). По тапу — список ролей чата;
    /// выбор подставляет упоминание в текст и сразу возвращает фокус в поле.
    /// Вид рядовой, как скрепка и режим: серый, размером с ними, без белого
    /// круга — белый круг в этом поле означает действие-команду.
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
            Image(systemName: "at").frame(width: 44, height: 44)
        }
        .accessibilityLabel("Выбрать адресата")
        .accessibilityIdentifier("chat.mention")
    }

    /// «@Имя » в конец черновика. Пробел в конце — как у набранного руками
    /// упоминания в `RoleChatsScreen.insertMention`: без него продолжение
    /// набора слилось бы с именем, и подсказка адресатов не закрылась бы.
    /// Пустое поле получает упоминание без ведущего пробела.
    private func insertMention(_ member: RoleChatMember) {
        let needsSpace = !text.isEmpty && !text.hasSuffix(" ")
        text += (needsSpace ? " " : "") + "@\(member.name) "
        isTextFieldFocused = true
    }

    private var promptRecordingComposer: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                Circle().fill(.red).frame(width: 8, height: 8)
                Text(recordingDuration).font(.body.monospacedDigit().weight(.medium)).foregroundStyle(.white)
            }
            VoiceRecordingWaveformView(levels: voice.recorderWaveform, elapsed: recordingElapsed,
                                       color: .gray, peakColor: .white, maxHeight: 30)
                .frame(width: 180, height: 36)
            HStack {
                Spacer()
                Button(action: stopVoiceRecording) {
                    Image(systemName: "stop.circle").font(.system(size: 25))
                        .foregroundStyle(.red).frame(width: 44, height: 44)
                        .background(.white, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Остановить запись")
            }
        }
        .padding(14)
        .background(Color(white: 0.125), in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.red, lineWidth: 1))
        .matchedGeometryEffect(id: "voiceComposerPill", in: composerNamespace)
        .padding(.horizontal).padding(.vertical, 10)
        .transition(.opacity)
    }

    private var recordingComposer: some View {
        HStack(spacing: 16) {
            VoiceRecordingWaveformView(
                levels: voice.recorderWaveform, elapsed: recordingElapsed,
                color: .red.mix(with: .black, by: 0.55), peakColor: .red
            )
                .frame(maxWidth: .infinity)
                .frame(height: 32)
            Text(recordingDuration).font(.title3.monospacedDigit()).foregroundStyle(.red)
            Button(action: stopVoiceRecording) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.red)
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Остановить запись")
        }
        .padding(.horizontal, 18).padding(.vertical, 8)
        .frame(minHeight: composerHeight)
        .voiceCapsuleSurface()
        .matchedGeometryEffect(id: "voiceComposerPill", in: composerNamespace)
        .padding(.horizontal).padding(.vertical, 10)
        .transition(.opacity)
    }

    /// Превью записи в оформлении экспериментального поля (владелец
    /// 10.10.2026). Тот же тёмный фон и та же кнопка отправки, что у нового
    /// поля, — иначе перед отправкой интерфейс выглядит старым.
    private func promptPreviewComposer(_ message: VoiceMessage) -> some View {
        VStack(spacing: 12) {
            if let transcript = readyTranscript(message) {
                Text(transcript)
                    .font(.body)
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("chat.voice.transcript")
            } else if message.transcript == .pending {
                HStack(spacing: 8) {
                    ProgressView().tint(.white)
                    Text("Расшифровываю…").font(.footnote).foregroundStyle(.gray)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 12) {
                Button(action: discardPreview) {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Удалить запись")
                .accessibilityIdentifier("chat.voice.discard")
                WaveformView(levels: message.waveform, color: .gray)
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                Text(durationText(message.duration))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.gray)
                if isSendingVoice {
                    ProgressView().frame(width: 40, height: 40)
                } else {
                    Button(action: sendPreview) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.black)
                            .frame(width: 40, height: 40)
                            .background(.white, in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Отправить")
                    .accessibilityIdentifier("chat.voice.send")
                }
            }
            .foregroundStyle(.white)
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

    private func previewComposer(_ message: VoiceMessage) -> some View {
        HStack(spacing: 12) {
            Button(action: discardPreview) {
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: composerHeight, height: composerHeight)
                    .voiceCircleSurface()
            }
            .tint(.primary)
            .buttonStyle(.plain)
            .accessibilityLabel("Удалить запись")
            HStack(spacing: 12) {
                actionButton(
                    player.playingURL == message.audioURL ? "pause.fill" : "play.fill",
                    label: "Воспроизвести запись"
                ) { try? player.toggle(url: message.audioURL) }
                WaveformView(levels: message.waveform, color: .secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                Text(durationText(message.duration)).font(.body.monospacedDigit()).foregroundStyle(Color.tfReadableSecondary)
                if isSendingVoice {
                    ProgressView().frame(width: 36, height: 36)
                } else {
                    actionButton("arrow.up", label: "Отправить голосовое сообщение", tint: .accentColor, action: sendPreview)
                }
            }
            .padding(.leading, 6).padding(.trailing, 4).padding(.vertical, 4)
            .frame(minHeight: composerHeight)
            .voiceCapsuleSurface()
        }
        .padding(.horizontal).padding(.vertical, 10)
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }

    /// Кнопки ВНУТРИ пилюли — плоские: без своего стекла/кружка, лежат прямо на
    /// поверхности капсулы (владелец 21.09.2026: «не надо кругляшок в кругляшке,
    /// там задвоение/затроение материала»). Как в прототипе: только иконка.
    private func actionButton(
        _ symbol: String, label: String, identifier: String? = nil,
        tint: Color = .primary, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier ?? label)
    }

    private var recordingElapsed: TimeInterval {
        guard case let .recording(elapsed, _) = voice.recordingState else { return 0 }
        return elapsed
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
        // После смены ветки повторно удерживаем фокус того же поля.
        DispatchQueue.main.async { isTextFieldFocused = true }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
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
        guard voice.phase == .recording else { return }
        isTextFieldFocused = true
        withAnimation(reduceMotion ? .linear(duration: 0.12) : .spring(duration: 0.32, bounce: 0)) {
            isRecording = false
            preview = voice.finish()
        }
        guard let message = preview else { return }
        Task {
            let transcript = await voice.transcribe(message)
            guard preview?.id == message.id else { return }
            preview?.transcript = transcript
            voice.complete()
            if sendAfterTranscription { await deliverPreview() }
        }
    }

    private func discardPreview() {
        guard let message = preview else { return }
        player.stop()
        onDiscardVoice(message)
        try? VoiceRecorder.cancelRecordingFile(at: message.audioURL)
        sendAfterTranscription = false
        voice.complete()
        withAnimation(reduceMotion ? .linear(duration: 0.12) : .spring(duration: 0.32, bounce: 0)) {
            preview = nil
        }
    }

    private func sendPreview() {
        guard let preview else { return }
        if preview.transcript == .pending {
            sendAfterTranscription = true
            isSendingVoice = true
        } else {
            Task { await deliverPreview() }
        }
    }

    private func deliverPreview() async {
        guard let message = preview else { return }
        isSendingVoice = true

        // Владелец 10.10.2026: «в рамках этого экспериментального поля
        // отправляется не голос, а сразу текст». Голосовое сообщение в чат
        // уходит только в старом режиме — там галочка выключена.
        if experimentalPromptBox, let transcript = readyTranscript(message), !transcript.isEmpty {
            sendAfterTranscription = false
            withAnimation(reduceMotion ? .linear(duration: 0.12) : .spring(duration: 0.32, bounce: 0)) {
                preview = nil
            }
            isSendingVoice = false
            player.stop()
            voice.complete()
            if let onSendTranscribedText {
                onSendTranscribedText(transcript)
            } else {
                // Запасной путь: кладём в поле и отправляем как обычный текст.
                text = transcript
                onSendText()
            }
            return
        }

        let accepted = await onSendVoice(message)
        isSendingVoice = false
        sendAfterTranscription = false
        if accepted {
            player.stop()
            withAnimation(reduceMotion ? .linear(duration: 0.12) : .spring(duration: 0.32, bounce: 0)) {
                preview = nil
            }
        }
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
    @State private var mode: RoleChatWorkMode = .work
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
                ChatVoiceComposer(text: $text, placeholder: "Сообщение", canSendText: !text.isEmpty,
                                  voice: voice, onAttachmentSource: { _ in }, onSendText: { text = "" },
                                  onSendVoice: { _ in false }, onDiscardVoice: { _ in },
                                  workMode: $mode, availableModes: RoleChatWorkMode.allCases,
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
