import SwiftUI

/// На каких моделях работает контекст ролей.
struct ContextModelsRows: View {
    let models: ContextObservability.Models

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.xs) {
            TFInfoRow(label: "Эмбеддинг", value: models.embedding)
            TFInfoRow(label: "JEV", value: models.jev ?? "Не задана")
            TFInfoRow(label: "Наблюдатель памяти", value: models.observer ?? "Не задана")
        }
    }
}

/// Контекст по задаче (владелец 05.11.2026): участвовал ли каждый источник и чем закончился.
/// Энричеры и эмбеддинги работают незаметно, и без этого их поломку не увидеть.
struct TaskContextSection: View {
    let context: TaskContextObservability
    @State private var isExpanded = false

    private var failed: Int { context.summary.filter { $0.failed > 0 }.count }
    private var worked: Int { context.summary.filter { $0.succeeded > 0 }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            TFPlainSectionTitle("Контекст и модели")
            if context.summary.isEmpty {
                Text("По этой задаче контекст не собирался. Учёт ведётся с \(ContextObservability.dateText(context.trackingSince)).")
                    .tfText(.action)
                    .foregroundStyle(Color.tfSub)
            } else {
                DisclosureGroup(isExpanded: $isExpanded) {
                    VStack(alignment: .leading, spacing: TFSpacing.sm) {
                        ContextModelsRows(models: context.models)
                        ForEach(context.summary) { source in sourceRow(source) }
                    }
                    .padding(.top, TFSpacing.xs)
                } label: {
                    HStack(spacing: TFSpacing.sm) {
                        Text("Сработало источников: \(worked)").tfText(.body).foregroundStyle(Color.tfText)
                        if failed > 0 {
                            Text("со сбоями: \(failed)").tfText(.meta).foregroundStyle(Color.tfOrange)
                        }
                    }
                }
                .tint(Color.tfDim)
                .accessibilityIdentifier("coord.context")
            }
        }
    }

    private func sourceRow(_ source: TaskContextObservability.Source) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(source.kind == "jev" ? "JEV · " : "")\(ContextObservability.title(source.scenario))")
                .tfText(.body)
                .foregroundStyle(Color.tfText)
            Text("Сработал \(source.succeeded) · пропущен \(source.skipped) · сбоев \(source.failed)")
                .tfText(.action)
                .foregroundStyle(source.failed > 0 ? Color.tfOrange : Color.tfSub)
            if source.failed > 0 || source.succeeded == 0, let reason = source.lastReason {
                Text(ContextObservability.outcome(reason: reason, status: "skipped")).tfText(.caption).foregroundStyle(Color.tfDim)
            }
            if let note = ContextObservability.note(source.scenario) {
                Text(note).tfText(.caption).foregroundStyle(Color.tfDim)
            }
        }
        .padding(.top, TFSpacing.xs)
    }
}

/// Источник контекста в панели этапа: чем закончилось его последнее срабатывание.
struct StageContextRow: View {
    let source: TaskContextObservability.StageSource

    private var tint: Color {
        switch source.status {
        case "ok": .tfGreen
        case "error", "timeout": .tfOrange
        default: .tfDim
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: TFSpacing.sm) {
                Text("\(source.kind == "jev" ? "JEV · " : "")\(ContextObservability.title(source.scenario))")
                    .tfText(.body)
                    .foregroundStyle(Color.tfText)
                Spacer(minLength: 0)
                Text(ContextObservability.outcome(reason: source.reason, status: source.status))
                    .tfText(.caption)
                    .foregroundStyle(tint)
                    .multilineTextAlignment(.trailing)
            }
            ForEach(Array(source.details.prefix(5).enumerated()), id: \.offset) { _, detail in
                Text(detail).tfText(.action).foregroundStyle(Color.tfSub).lineLimit(2)
            }
        }
    }
}
