import SwiftUI

/// `AttemptLadderView` — спек 1.2, 1.2.10 (UI-индикатор ступени, раздел 3.4 / R9).
/// Карточка задачи показывает «1/3 → Sonnet», «2/3 → Opus», «3/3 → blocked» —
/// текущую ступень лесенки, общее число ступеней и имя модели. Сервер уже
/// возвращает `attempt_ladder` в `GET /api/tasks/:id` (закоммичено в
/// `taskflow-server` 1.2.8 — `attemptLadderForTask(taskId)`).
///
/// Зеркало веб-бэйджа `AttemptLadderBadge.tsx`: цвет нейтральный в работе,
/// `tfOrange` при эскалации (current_step > 1) или блокировке. Если поле
/// отсутствует — тихо возвращаем `EmptyView` (старые задачи, созданные до
/// спек 1.2, лесенки не имеют).
///
/// Чистый SwiftUI без рамок/фонов/материалов/имитаций — правило владельца
/// для нативных компонентов (AGENTS.md §«Нативные компоненты»). Цвет —
/// единственный визуальный канал, как у `TFPriorityArrows`/`TFReadyFlag`.
public struct AttemptLadderView: View {
    let ladder: ApiAttemptLadder
    /// Передаётся из родителя, чтобы при `blocked` тоже раскрасить в
    /// `tfOrange` (по спек 1.2 R9 «оранжевый при блокировке / смене
    /// ступени»). У самой лесенки нет этого сигнала — `history` хранит
    /// только исходы попыток, не финальное состояние задачи.
    let agentState: AgentState?

    public init(ladder: ApiAttemptLadder, agentState: AgentState? = nil) {
        self.ladder = ladder
        self.agentState = agentState
    }

    /// Эскалация — карточка уже не на первой ступени, либо задача в
    /// `blocked` (потолок лесенки, дальше только владелец решает).
    /// Тон совпадает с веб-вариантом (`amber-500` → `tfOrange`).
    private var escalated: Bool {
        ladder.currentStep > 1 || agentState == .blocked
    }

    /// Короткое имя модели для показа. Сервер отдаёт алиасы из
    /// `attempt_policies.from_model` (`haiku`/`sonnet`/`opus`) — те же,
    /// что в вебе. Если сервер не прислал — «модель не указана», как в
    /// `AttemptLadderBadge.tsx`. Регистр — первый символ в верхнем,
    /// остальное без изменений («opus», «OPUS» — оставляем как есть,
    /// регистр чувствителен к провайдеру).
    private var modelLabel: String {
        guard let model = ladder.currentModel, !model.isEmpty else { return "модель не указана" }
        return model.prefix(1).uppercased() + model.dropFirst()
    }

    public var body: some View {
        HStack(spacing: 4) {
            Text("\(ladder.currentStep)/\(ladder.totalSteps)")
            Image(systemName: "arrow.right")
                .accessibilityHidden(true)
            Text(modelLabel)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(escalated ? Color.tfOrange : Color.tfSub)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    /// VoiceOver: «Попытка 2 из 3, Opus, эскалация» — отдельным
    /// `accessibilityLabel` с тем же текстом, что у веб-варианта
    /// (`AttemptLadderBadge.tsx`, `aria-label="Попытка 2 из 3, Opus"`),
    /// плюс слово «эскалация» при `escalated` — это и есть та самая
    /// интонация, которой добивался владелец на спек 1.2 R9.
    private var accessibilityLabel: String {
        var parts: [String] = ["Попытка \(ladder.currentStep) из \(ladder.totalSteps)"]
        parts.append(modelLabel)
        if escalated { parts.append("эскалация") }
        return parts.joined(separator: ", ")
    }
}
