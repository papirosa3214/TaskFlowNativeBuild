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
                    // `markdownText` рендерит `**жирный**`/`*курсив*` из сырого
                    // markdown-блока сводки, но безопасно: `LocalizedStringKey`
                    // прогоняло бы через markdown-парсер ЛЮБОЙ будущий текст
                    // (одиночная звёздочка, подчёркивание в `autonomy_110`,
                    // обратные кавычки), а не только уже пофикшенный случай
                    // `**bold**` (Important #5 финального ревью).
                    markdownText(summaryText).tfText(.meta).foregroundStyle(Color.tfSub)
                } else {
                    markdownText(summary.snippet).tfText(.meta).foregroundStyle(Color.tfSub)
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
            // Симметрично ветке `.fixed`: тап должен реально открывать модалку
            // (комментарий уйдёт в задачу `taskId`) — если ни у пункта, ни у
            // тикета в целом (fallback `detail?.diagnosticTaskId`, та же
            // логика, что использует `NotificationsScreen` при выборе
            // `taskId` для модалки) нет ссылки на задачу, строка дизейблится
            // и гаснет, а не остаётся тапабельной без эффекта (Important #3
            // финального ревью).
            let canResolve = item.taskId != nil || detail?.diagnosticTaskId != nil
            Button {
                onTapResolutionItem(item)
            } label: {
                Text(resolutionRowText(item)).tfText(.meta)
                    .foregroundStyle(canResolve ? Color.tfRed : Color.tfDim)
                    .underline(canResolve)
            }
            .buttonStyle(TFTapScaleStyle())
            .disabled(!canResolve)
        }
    }

    /// `AttributedString(markdown:)` с фолбэком на буквальный `Text` при
    /// ошибке парсинга — не `Text(LocalizedStringKey:)` (см. Important #5
    /// выше): `.inlineOnlyPreservingWhitespace` рендерит `**bold**`/`*italic*`
    /// без риска сломанной разметки крашнуть или искажать текст, а провал
    /// парсинга просто показывает исходную строку как есть.
    private func markdownText(_ raw: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: raw,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        }
        return Text(raw)
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
