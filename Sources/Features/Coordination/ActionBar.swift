import SwiftUI

/// Действие относится к выбранному шагу и блокируется при устаревших данных.
public struct ActionBar: View {
    public let resolution: APIClient.CoordinationResolution?
    public let blockedByVersionMismatch: Bool
    public var enabled: Bool = true
    public let onAction: (CoordinationAction) -> Void

    public init(resolution: APIClient.CoordinationResolution?, blockedByVersionMismatch: Bool = false,
                enabled: Bool = true, onAction: @escaping (CoordinationAction) -> Void) {
        self.resolution = resolution
        self.blockedByVersionMismatch = blockedByVersionMismatch
        self.enabled = enabled
        self.onAction = onAction
    }
    public var body: some View {
        HStack {
            if blockedByVersionMismatch {
                Text("Версия сервера изменилась. Действия недоступны.").tfText(.meta)
            } else if let r = resolution, let label = r.controlLabel {
                Button(label) { onAction(r.actionEnum) }
                    .disabled(!enabled)
                    .accessibilityIdentifier("coord.action.btn")
            } else {
                Text("Для этого шага сейчас нет действия").tfText(.meta)
            }
            Spacer()
        }
        .padding()
        .accessibilityIdentifier("coord.action.bar")
    }
}
