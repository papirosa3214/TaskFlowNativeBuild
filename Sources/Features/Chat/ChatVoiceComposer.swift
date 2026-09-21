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

    var body: some View {
        ZStack {
            if !isRecording, preview == nil { inputAnchor }
            else { inputAnchor.opacity(0.01).allowsHitTesting(false) }
            composerVisual
        }
        .onDisappear {
            voice.cancel()
            player.stop()
        }
    }

    @ViewBuilder private var composerVisual: some View {
        if let preview { previewComposer(preview) }
        else if isRecording { recordingComposer }
        else { idleComposer }
    }

    private var inputAnchor: some View {
        HStack(spacing: 12) {
            Color.clear.frame(width: 36, height: 36)
            HStack(spacing: 0) {
                TextField(placeholder, text: $text, axis: .vertical)
                    .focused($isTextFieldFocused)
                    .lineLimit(1...4)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.send)
                    .onSubmit(onSendText)
                    .accessibilityIdentifier("chat.message")
                Spacer(minLength: 48)
                if canSendText {
                    Button(action: onSendText) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 20, weight: .medium))
                            .frame(width: 36, height: 36)
                    }
                    .accessibilityLabel("Отправить")
                    .accessibilityIdentifier("chat.send")
                }
            }
            .padding(.horizontal, 20)
            .frame(minHeight: 52)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .zIndex(1)
    }

    private var idleComposer: some View {
        HStack(spacing: 12) {
            Button(action: onAttachment) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(.thinMaterial, in: Circle())
            }
            .tint(.primary)
            .accessibilityLabel("Добавить вложение")
            HStack {
                Spacer()
                Image(systemName: "waveform")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
                    .onLongPressGesture(minimumDuration: 0.18, perform: startVoiceRecording)
                    .opacity(canSendText ? 0 : 1)
            }
            .padding(.horizontal, 20)
            .frame(height: 52)
            .background(.thinMaterial, in: Capsule())
            .matchedGeometryEffect(id: "voiceComposerPill", in: composerNamespace)
            .accessibilityLabel("Удерживайте для начала записи")
        }
        .padding(.horizontal).padding(.vertical, 10)
    }

    private var recordingComposer: some View {
        HStack(spacing: 16) {
            WaveformView(levels: voice.recorderWaveform, color: .red)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
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
        .background(.thinMaterial, in: Capsule())
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
                    .frame(width: 36, height: 36)
                    .background(.thinMaterial, in: Circle())
            }
            .tint(.primary)
            .buttonStyle(.plain)
            .accessibilityLabel("Удалить запись")
            HStack(spacing: 12) {
                Button { try? player.toggle(url: message.audioURL) } label: {
                    Image(systemName: player.playingURL == message.audioURL ? "pause.fill" : "play.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel("Воспроизвести запись")
                WaveformView(levels: message.waveform, color: .secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                Text(durationText(message.duration)).font(.body.monospacedDigit()).foregroundStyle(.secondary)
                Button(action: sendPreview) {
                    if isSendingVoice { ProgressView().frame(width: 36, height: 36) }
                    else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 36, height: 36)
                    }
                }
                .disabled(isSendingVoice)
                .accessibilityLabel("Отправить голосовое сообщение")
            }
            .padding(.leading, 6).padding(.trailing, 4).padding(.vertical, 4)
            .background(.thinMaterial, in: Capsule())
        }
        .padding(.horizontal).padding(.vertical, 10)
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
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
        isTextFieldFocused = true
        withAnimation(reduceMotion ? .linear(duration: 0.12) : .spring(duration: 0.32, bounce: 0)) {
            isRecording = true
        }
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
