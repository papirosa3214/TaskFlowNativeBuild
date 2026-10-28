import ReplayKit
import LiveKit

/// The SDK transports video over the app-group socket into the existing call.
/// Its uploader ignores ReplayKit microphone samples; appAudio is disabled by the receiver.
final class SampleHandler: LKSampleHandler, @unchecked Sendable {
    override func connectionDidClose(error: Error?) {
        finishBroadcastWithError(NSError(domain: "TaskFlow.Broadcast", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Соединение с разговором закрыто. Начните голосовой разговор с Помощником в TaskFlow."]))
    }
}
