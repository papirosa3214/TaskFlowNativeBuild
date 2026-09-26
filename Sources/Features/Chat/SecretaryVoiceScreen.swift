import SwiftUI
import AVFoundation
import LiveKit

/// Голосовой разговор с Секретарём через LiveKit (Задача 5 плана Супер
/// Секретарь). Состояния `.speaking`/`.listening` запитаны событиями комнаты
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
    var state: SecretaryVoiceState = .connecting
    /// Громкость 0…1 — владельца (микрофон) и Секретаря (его дорожка).
    var micLevel: Double = 0
    var agentLevel: Double = 0

    private let room = Room()
    private let api = APIClient()
    private var agentIdentity: Participant.Identity?
    @ObservationIgnored private lazy var micMeter = AudioLevelMeter { [weak self] in self?.micLevel = $0 }
    @ObservationIgnored private lazy var agentMeter = AudioLevelMeter { [weak self] in self?.agentLevel = $0 }

    func start() async {
        do {
            room.add(delegate: self)
            let token = try await api.secretaryVoiceToken(voice: .current)
            try await room.connect(url: token.url, token: token.token)
            try await room.localParticipant.setMicrophone(enabled: true)
            if let mic = room.localParticipant.firstAudioPublication?.track as? LocalAudioTrack {
                mic.add(audioRenderer: micMeter)
            }
            state = .listening
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func stop() async {
        await room.disconnect()
    }

    /// Тап по полоскам — оборвать ответ Секретаря (RPC `interrupt` в воркере).
    func interrupt() {
        guard state == .speaking, let agentIdentity else { return }
        Task { _ = try? await room.localParticipant.performRpc(destinationIdentity: agentIdentity, method: "interrupt", payload: "") }
    }
}

extension SecretaryVoiceViewModel: RoomDelegate {
    nonisolated func room(_ room: Room, didUpdateSpeakingParticipants participants: [Participant]) {
        let agentSpeaking = participants.contains { $0.identity != room.localParticipant.identity }
        Task { @MainActor in
            if case .failed = self.state { return }
            self.state = agentSpeaking ? .speaking : .listening
        }
    }

    nonisolated func room(_ room: Room, participant: RemoteParticipant, didSubscribeTrack publication: RemoteTrackPublication) {
        guard let track = publication.track as? RemoteAudioTrack else { return }
        let identity = participant.identity
        Task { @MainActor in
            self.agentIdentity = identity
            track.add(audioRenderer: self.agentMeter)
        }
    }

    nonisolated func room(_ room: Room, didDisconnectWithError error: LiveKitError?) {
        Task { @MainActor in self.state = .failed(error?.localizedDescription ?? "соединение разорвано") }
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
    private let knob: CGFloat = 56
    private let inset: CGFloat = 4

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
                            .foregroundStyle(.white)
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
        .frame(height: knob + inset * 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Завершить разговор")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onHangUp() }
    }
}

struct SecretaryVoiceScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = SecretaryVoiceViewModel()

    var body: some View {
        VStack(spacing: TFSpacing.xl) {
            Spacer()
            VoiceBarsView(level: barsLevel, color: barsColor, isWaiting: viewModel.state == .connecting,
                          barWidth: 22, spacing: 14, maxHeight: 180)
                .frame(maxWidth: .infinity, minHeight: 240)
                .contentShape(Rectangle())
                .onTapGesture { viewModel.interrupt() }
                .accessibilityElement()
                .accessibilityLabel(accessibilityText)
                .accessibilityAddTraits(viewModel.state == .speaking ? .isButton : [])
                .accessibilityHint(viewModel.state == .speaking ? "Перебить Секретаря" : "")
            caption
                .frame(minHeight: 44, alignment: .top)
            Spacer()
            // Завершить звонок — свайп внизу, под большим пальцем, а не
            // крестик сверху (владелец 26.09.2026).
            HangUpSlider { dismiss() }
        }
        .padding(TFSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.tfBackground.ignoresSafeArea())
        .navigationBarBackButtonHidden()
        .task { await viewModel.start() }
        .onDisappear { Task { await viewModel.stop() } }
    }

    private var barsLevel: Double {
        switch viewModel.state {
        case .speaking: viewModel.agentLevel
        case .listening, .thinking: viewModel.micLevel
        case .connecting, .failed: 0
        }
    }

    private var barsColor: Color {
        switch viewModel.state {
        case .speaking: .tfRed
        case .listening, .thinking: .tfText
        case .connecting: .tfDim
        case .failed: .tfDim.opacity(0.4)
        }
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
        case .listening, .thinking: "Секретарь слушает"
        case .speaking: "Секретарь говорит"
        case .failed(let message): "Не получилось: \(message)"
        }
    }
}
