import SwiftUI

struct ChatExecutionModePicker: View {
    let mode: ChatExecutionMode
    let isSaving: Bool
    let onSelect: (ChatExecutionMode) -> Void

    var body: some View {
        Picker("Способ выполнения", selection: Binding(get: { mode }, set: onSelect)) {
            ForEach(ChatExecutionMode.allCases, id: \.self) { choice in
                Text(choice.title).tag(choice)
            }
        }
        .pickerStyle(.segmented)
        .disabled(isSaving)
        .accessibilityIdentifier("chat.execution-mode")
        .hintAnchor(HintAnchorID.chatExecutionMode)
    }
}
