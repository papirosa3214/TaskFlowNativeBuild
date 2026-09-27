import SwiftUI

/// Карточка-тикет сводки стороннего сервиса — визуально ОТДЕЛЬНАЯ от
/// карточки-задачи. Строки "Итог по устранению" — текстовые сноски
/// (серая неактивная / красная активная), НЕ inline-кнопки.
struct NotificationTicketCard: View {
    let summary: ServiceTicketSummary
    let detail: ServiceTicketDetail?
    let onOpenTask: (String) -> Void
    let onTapResolutionItem: (ServiceTicketResolutionItem) -> Void

    var body: some View {
        TFCard(padding: TFSpacing.md) {
            VStack(alignment: .leading, spacing: TFSpacing.sm) {
                Text(detail?.title ?? summary.title).tfText(.action).fontWeight(.semibold)
                metaRow

                if let summaryText = detail?.summaryText, !summaryText.isEmpty {
                    // `Text(LocalizedStringKey:)` рендерит `**жирный**`/`*курсив*` из
                    // сырого markdown-блока сводки — обычный `Text(String)` этого не
                    // делает и показывает звёздочки буквально.
                    Text(LocalizedStringKey(summaryText)).tfText(.meta).foregroundStyle(Color.tfSub)
                } else {
                    Text(LocalizedStringKey(summary.snippet)).tfText(.meta).foregroundStyle(Color.tfSub)
                }
                // `detail.notWorkingText` НЕ рендерится отдельным блоком — он уже
                // часть `summaryText` выше (тот же фрагмент "## Сводка" целиком,
                // включая "Не отработали в штатном режиме"); отдельная секция
                // дублировала бы этот же текст дважды. Красная обводка карточки
                // (ниже) — единственный визуальный сигнал тревоги поверх текста.

                if let taskId = detail?.diagnosticTaskId {
                    Button { onOpenTask(taskId) } label: {
                        Text("Карточка диагностики →").tfText(.meta).foregroundStyle(Color.tfSub)
                    }
                    .buttonStyle(TFTapScaleStyle())
                }

                if let items = detail?.resolutionItems, !items.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Итог по устранению").tfText(.meta).foregroundStyle(Color.tfDim)
                        ForEach(items) { item in
                            resolutionRow(item)
                        }
                    }
                }
            }
        }
        .overlay {
            if detail?.isAlarm == true || summary.level == "error" {
                RoundedRectangle(cornerRadius: TFRadius.xl, style: .continuous)
                    .strokeBorder(Color.tfRed, lineWidth: 1.5)
            }
        }
    }

    @ViewBuilder
    private func resolutionRow(_ item: ServiceTicketResolutionItem) -> some View {
        switch item.status {
        case .fixed:
            Button {
                if let taskId = item.taskId { onOpenTask(taskId) }
            } label: {
                Text("\(item.problem) — (исправлено)").tfText(.meta).foregroundStyle(Color.tfDim)
            }
            .buttonStyle(TFTapScaleStyle())
            .disabled(item.taskId == nil)
        case .unresolved, .needsDecision:
            Button {
                onTapResolutionItem(item)
            } label: {
                Text(resolutionRowText(item)).tfText(.meta).foregroundStyle(Color.tfRed).underline()
            }
            .buttonStyle(TFTapScaleStyle())
        }
    }

    private func resolutionRowText(_ item: ServiceTicketResolutionItem) -> String {
        switch item.status {
        case .fixed: return "\(item.problem) — (исправлено)"
        case .unresolved(let reason): return "\(item.problem) — (не исправлено: \(reason))"
        case .needsDecision: return "\(item.problem) — (не исправлено, нужно ваше решение)"
        }
    }

    private var metaRow: some View {
        let d = detail
        return VStack(alignment: .leading, spacing: 2) {
            metaLine("когда", d?.when ?? summary.ts)
            metaLine("от кого", d?.from ?? summary.source)
            metaLine("уровень", d?.level ?? summary.level)
            metaLine("тревога", (d?.isAlarm ?? summary.hasTriage) ? "да" : "нет")
        }
    }

    private func metaLine(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text("\(label):").tfText(.meta).foregroundStyle(Color.tfDim)
            Text(value).tfText(.meta).foregroundStyle(Color.tfSub)
        }
    }
}
