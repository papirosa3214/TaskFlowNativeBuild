import SwiftUI

extension EnvironmentValues {
    /// Действие кнопки «Продолжить»; `nil` — слот уже не заблокирован, кнопки нет.
    @Entry var continueSlotPlan: (@MainActor @Sendable () async throws -> Void)? = nil
}

/// План решения заблокированного слота (владелец 05.11.2026). Роль присылает его
/// блоком ```plan, под ним кнопка — как Play у команды.
struct ResolutionPlanBlock: View {
    let plan: String
    @Environment(\.continueSlotPlan) private var continueAction
    @State private var running = false
    @State private var started = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            Label("План решения", systemImage: "list.number")
                .tfText(.meta)
                .foregroundStyle(Color.tfSub)
            Text(plan.trimmingCharacters(in: .whitespacesAndNewlines))
                .tfText(.body)
                .foregroundStyle(Color.tfChatText)
                .textSelection(.enabled)
            if started {
                Label("Этап продолжает работу", systemImage: "checkmark")
                    .tfText(.action)
                    .foregroundStyle(Color.tfSub)
            } else if let continueAction {
                Button {
                    Task { @MainActor in
                        running = true
                        defer { running = false }
                        do {
                            try await continueAction()
                            started = true
                            error = nil
                        } catch {
                            self.error = error.localizedDescription
                        }
                    }
                } label: {
                    Label("Продолжить", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.primary)
                .disabled(running)
                .accessibilityIdentifier("chat-plan-continue")
            }
            if let error {
                Text(error).tfText(.action).foregroundStyle(Color.tfCoral)
            }
        }
        .padding(TFSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Тёмная подложка без рамки — как остальные блоки чата (06.11.2026).
        .background(Color.tfFieldDark, in: RoundedRectangle(cornerRadius: TFRadius.md))
    }
}
