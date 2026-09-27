import SwiftUI

/// Карточка-тикет сводки стороннего сервиса в списке — компактная превью-
/// строка, визуально ОТДЕЛЬНАЯ от карточки-задачи. Тап открывает полный
/// разбор в `NotificationTicketDetailSheet` (нативное окно снизу на всю
/// высоту, `.tfBottomSheet`) — владелец 27.09.2026: «как в карточку задачи
/// должен проваливаться», не разворачивать текст инлайн в списке.
struct NotificationTicketCard: View {
    let summary: ServiceTicketSummary
    let detail: ServiceTicketDetail?
    let onOpenTask: (String) -> Void
    let onTapResolutionItem: (ServiceTicketResolutionItem) -> Void

    @State private var showDetail = false

    private var isAlarm: Bool { detail?.isAlarm ?? (summary.level == "error") }

    var body: some View {
        Button {
            showDetail = true
        } label: {
            TFCard(padding: TFSpacing.md) {
                VStack(alignment: .leading, spacing: TFSpacing.sm) {
                    header
                    metaRow
                    if let snippet = detail?.notWorkingText {
                        Text(snippet).tfText(.row).foregroundStyle(Color.tfSub).lineLimit(1)
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
        .buttonStyle(TFTapScaleStyle())
        .tfBottomSheet(isPresented: $showDetail, title: detail?.title ?? summary.title) {
            NotificationTicketDetailSheet(
                summary: summary,
                detail: detail,
                onOpenTask: { taskId in
                    showDetail = false
                    onOpenTask(taskId)
                },
                onTapResolutionItem: { item in
                    showDetail = false
                    onTapResolutionItem(item)
                }
            )
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
                .tfText(.title).foregroundStyle(Color.tfText)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Компактная строка пилюль вместо 4 строк «ключ: значение» — источник
    /// и уровень читаются мгновенно по цвету/тексту, время — относительное
    /// («2 ч назад», как везде в приложении — `DirectoryDate.relative`),
    /// абсолютную метку `ts` смотреть незачем на карточке-превью.
    private var metaRow: some View {
        let level = detail?.level ?? summary.level
        return HStack(spacing: TFSpacing.xs) {
            TFPill(detail?.from ?? summary.source, color: Color.tfDim)
            TFPill(level, color: NotificationTicketStyle.levelColor(level))
            Spacer(minLength: TFSpacing.xs)
            if let date = NotificationTicketStyle.parseTicketDate(summary.ts) {
                Text(DirectoryDate.relative(date)).tfText(.row).foregroundStyle(Color.tfDim)
            }
        }
    }
}

/// Общее между компактной карточкой и полным разбором — цвет уровня и
/// разбор даты `.110` (локальное время без зоны, не GMT ISO8601).
enum NotificationTicketStyle {
    static func parseTicketDate(_ raw: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.timeZone = .current
        return formatter.date(from: raw)
    }

    static func levelColor(_ level: String) -> Color {
        switch level {
        case "error": return Color.tfRed
        case "warning": return Color.tfOrange
        default: return Color.tfBlue
        }
    }

    /// `AttributedString(markdown:)` с фолбэком на буквальный `Text` при
    /// ошибке парсинга — не `Text(LocalizedStringKey:)`: `.inlineOnlyPreservingWhitespace`
    /// рендерит `**bold**`/`*italic*` без риска сломанной разметки исказить
    /// текст, а провал парсинга просто показывает исходную строку как есть.
    static func markdownText(_ raw: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: raw,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        }
        return Text(raw)
    }
}
