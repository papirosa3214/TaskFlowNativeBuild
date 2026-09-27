import SwiftUI

/// Карточка-тикет сводки стороннего сервиса — визуально ОТДЕЛЬНАЯ от
/// карточки-задачи. Строки "Итог по устранению" — текстовые сноски
/// (серая неактивная / красная активная), НЕ inline-кнопки.
///
/// Редизайн 27.09.2026 (владелец: «выглядит отвратительно» на первой
/// версии — сплошная стена текста без иерархии). По `ios-hig-design`:
/// компактная строка метаданных пилюлями вместо 4 строк «ключ: значение»;
/// тревога — не только цвет рамки (HIG: «never convey meaning through
/// color alone») + иконка рядом с заголовком; длинный текст сводки
/// схлопнут по умолчанию (превью 3 строки + раскрытие) — то, что реально
/// важно при тревоге («Не отработали...»), не тонет в длинном списке
/// «Работают в штатном режиме».
struct NotificationTicketCard: View {
    let summary: ServiceTicketSummary
    let detail: ServiceTicketDetail?
    let onOpenTask: (String) -> Void
    let onTapResolutionItem: (ServiceTicketResolutionItem) -> Void

    @State private var isExpanded = false

    private var isAlarm: Bool { detail?.isAlarm ?? (summary.level == "error") }
    private var bodyText: String {
        let text = detail?.summaryText
        return (text?.isEmpty == false ? text! : summary.snippet)
    }
    /// Короче трёх строк — разворачивать нечего, кнопка "Показать целиком" не нужна.
    private var needsDisclosure: Bool { bodyText.count > 180 }

    var body: some View {
        TFCard(padding: TFSpacing.md) {
            VStack(alignment: .leading, spacing: TFSpacing.sm) {
                header
                metaRow

                markdownText(bodyText)
                    .tfText(.meta)
                    .foregroundStyle(Color.tfSub)
                    .lineLimit(isExpanded || !needsDisclosure ? nil : 3)

                if needsDisclosure {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
                    } label: {
                        Text(isExpanded ? "Свернуть" : "Показать целиком")
                            .tfText(.meta)
                            .foregroundStyle(Color.tfBlue)
                    }
                    .buttonStyle(TFTapScaleStyle())
                }
                // `detail.notWorkingText` НЕ рендерится отдельным блоком — он уже
                // часть `bodyText` выше (тот же фрагмент "## Сводка" целиком,
                // включая "Не отработали в штатном режиме"); отдельная секция
                // дублировала бы этот же текст дважды.

                if let taskId = detail?.diagnosticTaskId {
                    linkRow("Карточка диагностики") { onOpenTask(taskId) }
                }

                if let items = detail?.resolutionItems, !items.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Итог по устранению", systemImage: "wrench.and.screwdriver")
                            .tfText(.meta).foregroundStyle(Color.tfDim)
                        ForEach(items) { item in
                            resolutionRow(item)
                        }
                    }
                }
            }
        }
        .overlay {
            if isAlarm {
                RoundedRectangle(cornerRadius: TFRadius.xl, style: .continuous)
                    .strokeBorder(Color.tfRed, lineWidth: 1.5)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: TFSpacing.xs) {
            if isAlarm {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.tfRed)
                    .imageScale(.small)
                    .accessibilityLabel("Тревога")
            }
            Text(detail?.title ?? summary.title)
                .tfText(.action).fontWeight(.semibold)
                .lineLimit(2)
        }
    }

    private func linkRow(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title).tfText(.meta).foregroundStyle(Color.tfSub)
                Spacer()
                Image(systemName: "chevron.right")
                    .imageScale(.small)
                    .foregroundStyle(Color.tfDim)
            }
        }
        .buttonStyle(TFTapScaleStyle())
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

    /// Компактная строка пилюль вместо 4 строк «ключ: значение» — источник
    /// и уровень читаются мгновенно по цвету/тексту, время — относительное
    /// («2 ч назад», как везде в приложении — `DirectoryDate.relative`),
    /// абсолютную метку `ts` смотреть незачем на карточке-превью.
    private var metaRow: some View {
        let level = detail?.level ?? summary.level
        return HStack(spacing: TFSpacing.xs) {
            TFPill(detail?.from ?? summary.source, color: Color.tfDim)
            TFPill(level, color: levelColor(level))
            Spacer(minLength: TFSpacing.xs)
            if let date = Self.parseTicketDate(summary.ts) {
                Text(DirectoryDate.relative(date)).tfText(.caption).foregroundStyle(Color.tfDim)
            }
        }
    }

    /// `ts`/`when` приходят как "2026-09-27T01:51:33" — локальное время
    /// без зоны (формат `.110`, см. спеку), не GMT ISO8601.
    private static func parseTicketDate(_ raw: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.timeZone = .current
        return formatter.date(from: raw)
    }

    private func levelColor(_ level: String) -> Color {
        switch level {
        case "error": return Color.tfRed
        case "warning": return Color.tfOrange
        default: return Color.tfBlue
        }
    }
}
