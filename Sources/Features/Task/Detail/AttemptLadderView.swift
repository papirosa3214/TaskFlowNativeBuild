import SwiftUI

struct AttemptLadderView: View {
    let ladder: AttemptLadder
    let agentState: AgentState?

    private var isEscalated: Bool {
        ladder.currentStep > 1 || agentState == .blocked
    }

    var body: some View {
        HStack(spacing: 6) {
            Text("\(ladder.currentStep)/\(ladder.totalSteps)")
                .monospacedDigit()
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(tint.opacity(0.14), in: Capsule())
            Image(systemName: "arrow.right")
                .imageScale(.small)
            Text(ladder.currentModel ?? "Модель не указана")
                .lineLimit(1)
        }
        .tfText(.caption)
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.secondarySystemBackground), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Попытка \(ladder.currentStep) из \(ladder.totalSteps), \(ladder.currentModel ?? "модель не указана")")
    }

    private var tint: Color { isEscalated ? .orange : .secondary }
}
