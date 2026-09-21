import SwiftUI
import UIKit

/// Тот же трёхсостоянийный композер, что в VoiceMessageLabScreen.
struct ChatVoiceComposer: View {
    @Binding var text: String
    let placeholder: String
    let canSendText: Bool
    @Bindable var voice: RoleChatVoiceController
    let onAttachment: () -> Void
    let onSendText: () -> Void
    let onSendVoice: (VoiceMessage) async -> Bool
    let onDiscardVoice: (VoiceMessage) -> Void

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
    /// не одна маленькая, другая большая»).
    private let composerHeight: CGFloat = 52

    var body: some View {
        ZStack {
            // Поле не удаляется при морфинге, поэтому клавиатура остаётся на месте.
            idleComposer
            if isRecording { recordingComposer }
            if let preview { previewComposer(preview) }
        }
        .onDisappear {
            voice.cancel()
            player.stop()
        }
    }

    private var idleComposer: some View {
        HStack(spacing: 12) {
            Button(action: onAttachment) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: composerHeight, height: composerHeight)
                    .voiceCircleSurface()
            }
            .buttonStyle(.plain)
            .opacity(isRecording || preview != nil ? 0 : 1)
            .accessibilityLabel("Добавить вложение")
            HStack(spacing: 8) {
                TextField(isRecording || preview != nil ? "" : placeholder, text: $text, axis: .vertical)
                    .lineLimit(1...4)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.send)
                    .focused($isTextFieldFocused)
                    .onSubmit(onSendText)
                    .foregroundStyle(isRecording || preview != nil ? Color.clear : Color.primary)
                    .accessibilityIdentifier("chat.message")
                if canSendText {
                    actionButton("arrow.up", label: "Отправить", identifier: "chat.send", tint: .accentColor, action: onSendText)
                        .opacity(isRecording || preview != nil ? 0 : 1)
                } else {
                    Image(systemName: "waveform")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                        .onLongPressGesture(minimumDuration: 0.18, perform: startVoiceRecording)
                        .accessibilityLabel("Удерживайте для начала записи")
                        .opacity(isRecording || preview != nil ? 0 : 1)
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: composerHeight)
            .voiceCapsuleSurface()
            // Пока идёт запись или открыто превью, капсулу покоя прячем ЦЕЛИКОМ
            // (вместе с её стеклом), иначе её подложка просвечивает под капсулой
            // записи/превью — «задвоение» (владелец 21.09.2026).
            .opacity(isRecording || preview != nil ? 0 : 1)
            .matchedGeometryEffect(id: "voiceComposerPill", in: composerNamespace)
        }
        .padding(.horizontal).padding(.vertical, 10)
    }

    private var recordingComposer: some View {
        HStack(spacing: 16) {
            WaveformView(levels: voice.recorderWaveform, color: .red)
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
                Text(durationText(message.duration)).font(.body.monospacedDigit()).foregroundStyle(.secondary)
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

/// На iOS 26 стекло рисует система; для iOS 18–25 остаётся материал.
private extension View {
    @ViewBuilder func voiceCircleSurface() -> some View {
        if #available(iOS 26.0, *) { glassEffect(.regular, in: .circle) }
        else { background(.thinMaterial, in: Circle()) }
    }

    @ViewBuilder func voiceCapsuleSurface() -> some View {
        if #available(iOS 26.0, *) { glassEffect(.regular, in: .capsule) }
        else { background(.thinMaterial, in: Capsule()) }
    }
}

/// Системная нижняя safe area следует за клавиатурой, как в QuickAddTaskView.
extension View {
    @ViewBuilder func chatComposerBar<BarContent: View>(@ViewBuilder content: () -> BarContent) -> some View {
        if #available(iOS 26.0, *) {
            safeAreaBar(edge: .bottom, content: content)
        } else {
            safeAreaInset(edge: .bottom, content: content)
        }
    }
}
