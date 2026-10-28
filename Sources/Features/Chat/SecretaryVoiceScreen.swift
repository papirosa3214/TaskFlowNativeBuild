import SwiftUI
import AVFoundation
import LiveKit

/// Голосовой разговор с Помощником владельца через LiveKit (Задача 5 плана Супер
/// Помощник владельца). Состояния `.speaking`/`.listening` запитаны событиями комнаты
/// через `RoomDelegate` (Задача 6). `.thinking` не используется отдельно —
/// Gemini Live отвечает почти без паузы, различимой паузы «думает» на живой
/// проверке не искали отдельного сигнала под неё (см. журнал плана).
enum SecretaryVoiceState: Equatable {
    case connecting
    case listening
    case thinking
    case speaking
    case failed(String)
}

@MainActor
@Observable
final class SecretaryVoiceViewModel {
    private(set) var presentation = SecretaryVoicePresentation()
    var state: SecretaryVoiceState = .connecting
    /// Громкость 0…1 — владельца (микрофон) и Помощника владельца (его дорожка).
    var micLevel: Double = 0
    var agentLevel: Double = 0

    private var room: Room?
    private var connectionID: UUID?
    private let api = APIClient()
    private var agentIdentity: Participant.Identity?
    @ObservationIgnored private lazy var micMeter = AudioLevelMeter { [weak self] in self?.micLevel = $0 }
    @ObservationIgnored private lazy var agentMeter = AudioLevelMeter { [weak self] in self?.agentLevel = $0 }

    func start(chatID: String) async {
        guard presentation.begin(chatID: chatID) else { return }
        state = .connecting
        let connectionID = UUID()
        self.connectionID = connectionID
        let room = Room()
        self.room = room
        do {
            room.add(delegate: self)
            let token = try await api.secretaryVoiceToken(voice: .current, chatID: chatID)
            guard self.connectionID == connectionID else { return }
            try await room.connect(url: token.url, token: token.token)
            guard self.connectionID == connectionID else { await room.disconnect(); return }
            try await room.localParticipant.setMicrophone(enabled: true)
            guard self.connectionID == connectionID else { await room.disconnect(); return }
            if let mic = room.localParticipant.firstAudioPublication?.track as? LocalAudioTrack {
                mic.add(audioRenderer: micMeter)
            }
            state = .listening
        } catch {
            guard self.connectionID == connectionID else { return }
            state = .failed(error.localizedDescription)
        }
    }

    func minimize() { presentation.minimize() }
    func expand() { presentation.expand() }

    func stop() async {
        connectionID = nil
        presentation.end()
        let previousRoom = room
        room = nil
        agentIdentity = nil
        micLevel = 0
        agentLevel = 0
        previousRoom?.remove(delegate: self)
        await previousRoom?.disconnect()
    }

    /// Тап по кольцу — оборвать ответ Помощника владельца (RPC `interrupt` в воркере).
    func interrupt() {
        guard state == .speaking, let agentIdentity, let room else { return }
        Task { _ = try? await room.localParticipant.performRpc(destinationIdentity: agentIdentity, method: "interrupt", payload: "") }
    }
}

extension SecretaryVoiceViewModel: RoomDelegate {
    nonisolated func room(_ room: Room, didUpdateSpeakingParticipants participants: [Participant]) {
        let agentSpeaking = participants.contains { $0.identity != room.localParticipant.identity }
        Task { @MainActor in
            guard self.room === room else { return }
            if case .failed = self.state { return }
            self.state = agentSpeaking ? .speaking : .listening
        }
    }

    nonisolated func room(_ room: Room, participant: RemoteParticipant, didSubscribeTrack publication: RemoteTrackPublication) {
        guard let track = publication.track as? RemoteAudioTrack else { return }
        let identity = participant.identity
        Task { @MainActor in
            guard self.room === room else { return }
            self.agentIdentity = identity
            track.add(audioRenderer: self.agentMeter)
        }
    }

    nonisolated func room(_ room: Room, didDisconnectWithError error: LiveKitError?) {
        Task { @MainActor in
            guard self.room === room else { return }
            self.state = .failed(error?.localizedDescription ?? "соединение разорвано")
        }
    }
}

/// Отдельная граница наблюдения: громкость не инвалидирует корневую навигацию.
struct SecretaryVoiceFloatingControl: View {
    let viewModel: SecretaryVoiceViewModel
    let onOpenChat: () -> Void

    private var status: String {
        switch viewModel.state {
        case .connecting: "Подключение"
        case .listening, .thinking: "Слушает"
        case .speaking: "Говорит"
        case .failed: "Соединение прервано"
        }
    }

    var body: some View {
        SecretaryVoiceMiniPlayer(
            level: viewModel.state == .speaking ? viewModel.agentLevel : viewModel.micLevel,
            status: status,
            isFailed: { if case .failed = viewModel.state { return true }; return false }(),
            onExpand: { viewModel.expand() },
            onOpenChat: onOpenChat,
            onEnd: { Task { await viewModel.stop() } }
        )
    }
}

/// Громкость звукового потока для анимации: RMS и пик буфера в децибелах →
/// тот же масштаб 0…1 и то же сглаживание, что у записи голосовых
/// (`VoiceWaveform`), чтобы полоски везде вели себя одинаково.
final class AudioLevelMeter: NSObject, AudioRenderer, @unchecked Sendable {
    private let onLevel: @MainActor (Double) -> Void
    private var smoothed: Double = 0
    private var lastEmit: CFTimeInterval = 0

    init(onLevel: @escaping @MainActor (Double) -> Void) {
        self.onLevel = onLevel
    }

    func render(pcmBuffer: AVAudioPCMBuffer) {
        let frames = Int(pcmBuffer.frameLength)
        guard frames > 0 else { return }
        var sum: Float = 0, peak: Float = 0
        if let data = pcmBuffer.floatChannelData?[0] {
            for i in 0..<frames { let v = abs(data[i]); sum += v * v; peak = max(peak, v) }
        } else if let data = pcmBuffer.int16ChannelData?[0] {
            for i in 0..<frames { let v = abs(Float(data[i]) / Float(Int16.max)); sum += v * v; peak = max(peak, v) }
        } else { return }
        let rms = sqrt(sum / Float(frames))
        let raw = VoiceWaveform.microphoneLevel(
            averageDecibels: 20 * log10(max(rms, 1e-6)),
            peakDecibels: 20 * log10(max(peak, 1e-6))
        )
        smoothed = VoiceWaveform.smoothedLevel(previous: smoothed, raw: raw)
        let now = CACurrentMediaTime()
        guard now - lastEmit > 0.04 else { return }
        lastEmit = now
        let level = smoothed
        Task { @MainActor in onLevel(level) }
    }
}

/// «Сдвиньте, чтобы завершить»: красный кружок с трубкой тянется вправо,
/// дотянул почти до края — звонок завершён, отпустил раньше — вернулся.
private struct HangUpSlider: View {
    let onHangUp: () -> Void

    @State private var offset: CGFloat = 0
    @State private var isDone = false
    private let knob: CGFloat = 60
    private let inset: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            let maxOffset = max(geo.size.width - knob - inset * 2, 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.tfCard)
                Text("Сдвиньте, чтобы завершить")
                    .tfText(.body)
                    .foregroundStyle(Color.tfSub)
                    .frame(maxWidth: .infinity)
                    .padding(.leading, knob)
                    .opacity(1 - Double(offset / maxOffset) * 1.5)
                Circle()
                    .fill(Color.tfRedSolid)
                    .frame(width: knob, height: knob)
                    .overlay {
                        Image(systemName: "phone.down.fill")
                            .font(.system(size: TFIconSize.md))
                            .foregroundStyle(Color.tfPaper)
                    }
                    .offset(x: inset + offset)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard !isDone else { return }
                                offset = min(max(value.translation.width, 0), maxOffset)
                            }
                            .onEnded { _ in
                                guard !isDone else { return }
                                if offset > maxOffset * 0.75 {
                                    isDone = true
                                    withAnimation(.spring(duration: 0.2)) { offset = maxOffset }
                                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                                    onHangUp()
                                } else {
                                    withAnimation(.spring(duration: 0.3, bounce: 0.3)) { offset = 0 }
                                }
                            }
                    )
            }
        }
        .frame(maxWidth: 320)
        .frame(height: knob + inset * 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Завершить разговор")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onHangUp() }
    }
}

struct SecretaryVoiceScreen: View {
    @Bindable var viewModel: SecretaryVoiceViewModel
    let onOpenChat: () -> Void

    var body: some View {
        VStack(spacing: TFSpacing.xl) {
            HStack {
                TFIconButton("chevron.down", label: "Свернуть голосовой разговор") { viewModel.minimize() }
                    .accessibilityIdentifier("voice.minimize")
                    .hintAnchor(HintAnchorID.voiceMinimize)
                Spacer()
                Text("Голосовой разговор").tfText(.title)
                Spacer()
                TFIconButton("text.bubble", label: "Открыть переписку") { onOpenChat() }
                    .accessibilityIdentifier("voice.open-chat")
            }
            Spacer()
            SecretaryMicRing(level: voiceLevel, isFailed: isFailed)
                .frame(maxWidth: 340)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { viewModel.interrupt() }
                .accessibilityElement()
                .accessibilityLabel(accessibilityText)
                .accessibilityAddTraits(viewModel.state == .speaking ? .isButton : [])
                .accessibilityHint(viewModel.state == .speaking ? "Перебить Помощника владельца" : "")
            caption
                .frame(minHeight: 44, alignment: .top)
            Spacer()
            // Завершить звонок — свайп внизу, под большим пальцем, а не
            // крестик сверху (владелец 26.09.2026).
            HangUpSlider { Task { await viewModel.stop() } }
                .accessibilityIdentifier("voice.end")
        }
        .padding(TFSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.tfBackground.ignoresSafeArea())
        .navigationBarBackButtonHidden()
    }

    private var voiceLevel: Double {
        switch viewModel.state {
        case .speaking: viewModel.agentLevel
        case .listening, .thinking: viewModel.micLevel
        case .connecting, .failed: 0
        }
    }

    private var isFailed: Bool {
        if case .failed = viewModel.state { return true }
        return false
    }

    @ViewBuilder
    private var caption: some View {
        switch viewModel.state {
        case .connecting:
            Text("Подключаюсь…").tfText(.body).foregroundStyle(Color.tfSub)
        case .failed(let message):
            Text("Не получилось: \(message)").tfText(.body).foregroundStyle(Color.tfRed)
                .multilineTextAlignment(.center)
        case .listening, .thinking, .speaking:
            EmptyView()
        }
    }

    private var accessibilityText: String {
        switch viewModel.state {
        case .connecting: "Подключаюсь"
        case .listening, .thinking: "Помощник владельца слушает"
        case .speaking: "Помощник владельца говорит"
        case .failed(let message): "Не получилось: \(message)"
        }
    }
}
