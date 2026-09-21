import SwiftUI
import UIKit
import PhotosUI

struct VoiceComposerPresentation: Equatable {
    enum State: Equatable { case idle, recording, preview }
    enum Action: Equatable { case startByHolding, stop, send }
    let action: Action
    init(state: State) {
        switch state {
        case .idle: action = .startByHolding
        case .recording: action = .stop
        case .preview: action = .send
        }
    }
}

struct VoiceMessageLabScreen: View {
    @Bindable var model: VoiceMessageLabModel
    @State private var player = VoicePlayer()
    @State private var isRecording = false
    @State private var isPhotoPickerPresented = false
    @State private var isFileImporterPresented = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var typedText = ""
    @FocusState private var isTextFieldFocused: Bool
    @Namespace private var composerNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .trailing, spacing: 12) {
                        ForEach(model.messages.reversed()) { message in
                            VoiceMessageBubble(message: message, player: player).id(message.id)
                        }
                    }.padding()
                }
                .defaultScrollAnchor(.bottom)
                .navigationTitle("Голосовые")
                .navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .bottom) { composer }
                .onChange(of: model.messages.count) { _, _ in
                    if let id = model.messages.first?.id { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
        }
        .photosPicker(isPresented: $isPhotoPickerPresented, selection: $selectedPhoto, matching: .any(of: [.images, .videos]))
        .fileImporter(isPresented: $isFileImporterPresented, allowedContentTypes: [.item]) { _ in }
    }

    @ViewBuilder private var composer: some View {
        ZStack {
            if !isRecording, model.draft == nil { inputAnchor }
            else { inputAnchor.opacity(0.01).allowsHitTesting(false) }
            composerVisual
        }
    }

    @ViewBuilder private var composerVisual: some View {
        if let draft = model.draft { previewComposer(draft) }
        else if isRecording { recordingComposer }
        else { idleComposer }
    }

    private var inputAnchor: some View {
        HStack(spacing: 12) {
            Color.clear.frame(width: 36, height: 36)
            HStack(spacing: 0) {
                TextField("", text: $typedText)
                    .focused($isTextFieldFocused)
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled(false)
                Spacer(minLength: 48)
            }
            .padding(.horizontal, 20)
            .frame(height: 52)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .zIndex(1)
    }

    private var idleComposer: some View {
        HStack(spacing: 12) {
            Menu {
                Button("Фото или видео", systemImage: "photo.on.rectangle") { isPhotoPickerPresented = true }
                Button("Файл", systemImage: "folder") { isFileImporterPresented = true }
                Button("Камера", systemImage: "camera") {}
            } label: {
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
            WaveformView(levels: model.recorderWaveform, color: .red)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            Text(recordingDuration).font(.title3.monospacedDigit()).foregroundStyle(.red)
            Button {
                withAnimation(reduceMotion ? .linear(duration: 0.12) : .spring(duration: 0.32, bounce: 0)) { isRecording = false }
                Task { await model.stopRecording() }
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.red)
                    .frame(width: 36, height: 36)
            }.accessibilityLabel("Остановить запись")
        }
        .padding(.horizontal, 18).padding(.vertical, 8).background(.thinMaterial, in: Capsule())
        .matchedGeometryEffect(id: "voiceComposerPill", in: composerNamespace)
        .padding(.horizontal).padding(.vertical, 10)
        .transition(.opacity)
    }

    private func previewComposer(_ draft: VoiceMessage) -> some View {
        HStack(spacing: 12) {
            Button { model.discardDraft() } label: {
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
                Button { try? player.toggle(url: draft.audioURL) } label: {
                    Image(systemName: player.playingURL == draft.audioURL ? "pause.fill" : "play.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                }
                WaveformView(levels: draft.waveform, color: .secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                Text(durationText(draft.duration)).font(.body.monospacedDigit()).foregroundStyle(.secondary)
                Button { model.sendDraft() } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 36, height: 36)
                }.accessibilityLabel("Отправить голосовое сообщение")
            }.padding(.leading, 6).padding(.trailing, 4).padding(.vertical, 4).background(.thinMaterial, in: Capsule())
        }
        .padding(.horizontal).padding(.vertical, 10)
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }

    private var recordingDuration: String {
        guard case let .recording(elapsed, _) = model.recordingState else { return "0:00" }
        return durationText(elapsed)
    }

    private func durationText(_ duration: TimeInterval) -> String {
        String(format: "%d:%02d", Int(duration) / 60, Int(duration) % 60)
    }

    private func startVoiceRecording() {
        guard !isRecording else { return }
        isTextFieldFocused = true
        withAnimation(reduceMotion ? .linear(duration: 0.12) : .spring(duration: 0.32, bounce: 0)) {
            isRecording = true
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            guard await model.startRecording() else {
                withAnimation(reduceMotion ? .linear(duration: 0.12) : .spring(duration: 0.2, bounce: 0)) {
                    isRecording = false
                }
                return
            }
        }
    }
}

private struct VoiceMessageBubble: View {
    let message: VoiceMessage
    let player: VoicePlayer
    @State private var showsTranscript = true
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button { try? player.toggle(url: message.audioURL) } label: {
                    Image(systemName: player.playingURL == message.audioURL ? "pause.fill" : "play.fill")
                        .font(.system(size: 20, weight: .medium))
                        .frame(width: 36, height: 36)
                        .background(.white, in: Circle())
                        .foregroundStyle(Color.accentColor)
                }
                WaveformView(levels: message.waveform, color: .white).frame(height: 30)
                Text(String(format: "%d:%02d", Int(message.duration) / 60, Int(message.duration) % 60)).monospacedDigit().font(.subheadline)
            }
            transcript
        }
        .padding(14).foregroundStyle(.white).background(Color.accentColor, in: RoundedRectangle(cornerRadius: 22, style: .continuous)).frame(maxWidth: 330, alignment: .trailing)
    }

    @ViewBuilder private var transcript: some View {
        switch message.transcript {
        case .pending: Label("Расшифровка…", systemImage: "waveform.badge.magnifyingglass").font(.subheadline).foregroundStyle(.white.opacity(0.78))
        case .failed: Text("Расшифровка недоступна").font(.subheadline).foregroundStyle(.white.opacity(0.78))
        case .ready(let text):
            VStack(alignment: .leading, spacing: 5) {
                Text(text)
                    .font(.body)
                    .lineLimit(showsTranscript ? nil : 2)
                    .textSelection(.enabled)
                if text.count > 120 { Button(showsTranscript ? "Скрыть" : "Показать ещё") { showsTranscript.toggle() }.font(.subheadline.weight(.semibold)).foregroundStyle(.white) }
            }
        }
    }
}

private struct WaveformView: View {
    let levels: [Double]
    let color: Color
    var body: some View {
        GeometryReader { geometry in
            let values = VoiceWaveform.sculptedSamples(
                from: VoiceWaveform.displaySamples(from: levels, slots: 48)
            )
            HStack(spacing: 2) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, level in
                    Capsule()
                        .fill(color)
                        .frame(
                            maxWidth: .infinity,
                            minHeight: 2,
                            maxHeight: geometry.size.height * CGFloat(0.07 + min(0.9, level) * 0.84)
                        )
                }
            }.frame(width: geometry.size.width, height: geometry.size.height)
        }.accessibilityHidden(true)
    }
}
