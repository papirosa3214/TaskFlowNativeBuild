import SwiftUI
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
    private let room = Room()
    private let api = APIClient()

    func start() async {
        do {
            room.add(delegate: self)
            let token = try await api.secretaryVoiceToken()
            try await room.connect(url: token.url, token: token.token)
            try await room.localParticipant.setMicrophone(enabled: true)
            state = .listening
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func stop() async {
        await room.disconnect()
    }
}

extension SecretaryVoiceViewModel: RoomDelegate {
    func room(_ room: Room, didUpdateSpeakingParticipants participants: [Participant]) {
        let agentSpeaking = participants.contains { $0.identity != room.localParticipant.identity }
        state = agentSpeaking ? .speaking : .listening
    }

    func room(_ room: Room, didDisconnectWithError error: LiveKitError?) {
        state = .failed(error?.localizedDescription ?? "соединение разорвано")
    }
}

struct SecretaryVoiceScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = SecretaryVoiceViewModel()

    var body: some View {
        VStack(spacing: TFSpacing.lg) {
            Spacer()
            stateLabel
            Spacer()
            Button("Закрыть") { Task { await viewModel.stop(); dismiss() } }
                .buttonStyle(TFTapScaleStyle())
        }
        .padding(TFSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.tfBackground.ignoresSafeArea())
        .task { await viewModel.start() }
    }

    @ViewBuilder
    private var stateLabel: some View {
        switch viewModel.state {
        case .connecting: Text("Подключаюсь…").tfText(.title).foregroundStyle(Color.tfSub)
        case .listening: Text("Слушаю").tfText(.title).foregroundStyle(Color.tfText)
        case .thinking: Text("Секретарь думает…").tfText(.title).foregroundStyle(Color.tfSub)
        case .speaking: Text("Секретарь говорит").tfText(.title).foregroundStyle(Color.tfRed)
        case .failed(let message):
            Text("Не получилось: \(message)").tfText(.title).foregroundStyle(Color.tfRed)
        }
    }
}
