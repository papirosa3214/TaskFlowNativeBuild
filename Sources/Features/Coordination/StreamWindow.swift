import SwiftUI

/// Окно стриминга сообщений по теме карточки.
///
/// UX-документ §4 — окно фиксированной высоты с **внутренней** прокруткой:
///   - 38% высоты экрана, минимум 200 пт, максимум 360 пт;
///   - отдельный заголовок 28 пт со счётчиком непрочитанных;
///   - снизу поле ввода 44 пт, при фокусе клавиатура перекрывает
///     Action bar, но не сам Stream window.
///
/// Правило №6 (стабильность графа): стриминг имеет собственный
/// `@StateObject` и **никак не зависит от `CoordinationState`**, чтобы
/// новые сообщения не вызывали перерасчёт графа.
public struct StreamWindow<RowContent: View>: View {
    public let title: String
    public let unread: Int
    /// Минимальная и максимальная высота. По умолчанию 200…360 пт, как в
    /// UX-документе; вызывающий может зажать в iPad-формате.
    public let minHeight: CGFloat
    public let maxHeight: CGFloat
    public let composer: AnyView
    public let rows: () -> RowContent

    public init(
        title: String = "Поток",
        unread: Int = 0,
        minHeight: CGFloat = 200,
        maxHeight: CGFloat = 360,
        @ViewBuilder composer: () -> AnyView,
        @ViewBuilder rows: @escaping () -> RowContent
    ) {
        self.title = title
        self.unread = unread
        self.minHeight = minHeight
        self.maxHeight = maxHeight
        self.composer = composer()
        self.rows = rows
    }

    public var body: some View {
        // Гомогенный body: один VStack (заголовок + список + композер).
        TFCard(padding: 0, surface: .card, radius: TFRadius.md) {
            VStack(spacing: 0) {
                header
                // Внутренний список — единственный источник скролла в окне.
                // Жест снизу вверх **внутри** Stream window прокручивает только
                // сообщения (критерий QA №4).
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: TFSpacing.sm) {
                        rows()
                    }
                    .padding(.horizontal, TFSpacing.md)
                    .padding(.vertical, TFSpacing.sm)
                }
                .frame(maxHeight: .infinity)
                .accessibilityIdentifier("coord.stream.list")
                composer
            }
            .frame(minHeight: minHeight, maxHeight: maxHeight)
        }
        .overlay(
            RoundedRectangle(cornerRadius: TFRadius.md)
                .strokeBorder(Color.tfSub.opacity(0.25), lineWidth: TFBorder.width)
        )
        .accessibilityIdentifier("coord.stream.window")
    }

    private var header: some View {
        TFCard(padding: 0, surface: .card2, radius: nil) {
            HStack(spacing: TFSpacing.sm) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .tfTypeFont(size: 12, weight: .semibold)
                    .foregroundStyle(Color.tfSub)
                Text(title)
                    .tfText(.action).fontWeight(.semibold)
                    .foregroundStyle(Color.tfText)
                Spacer(minLength: 4)
                if unread > 0 {
                    Text("\(unread)")
                        .tfText(.caption).fontWeight(.bold)
                        .foregroundStyle(Color.tfPaper)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.tfRed)
                        .clipShape(Capsule())
                        .accessibilityIdentifier("coord.stream.unread")
                }            }
            .padding(.horizontal, TFSpacing.md)
            .frame(height: 28)
        }
        .overlay(
            Rectangle()
                .frame(height: TFBorder.width)
                .foregroundStyle(Color.tfSub.opacity(0.25)),
            alignment: .bottom
        )
    }
}

/// Чип состояния доставки одного сообщения.
///
/// UX-документ §4.2 — 4 основных состояния + 2 вспомогательных:
///   - **Принято** — `chat_messages.id` создан, нет inbox'а.
///   - **В очереди** — `slot_topic_inbox.delivered_at IS NULL`.
///   - **Обрабатывается** — `attempts.ended_at IS NULL`.
///   - **Ошибка** — `role_run_jobs.status='dead'` или classified failure.
///   - **Доставлено** — inbox есть, попытки ещё нет.
///   - **Результат принят** — `attempts.outcome ∈ {completed, approved}`.
public struct MessageDeliveryChip: View {
    public enum DeliveryState: String, Sendable, Equatable {
        case accepted
        case queued
        case processing
        case delivered
        case completed
        case failed
    }

    public let state: DeliveryState
    /// Сколько минут сообщение «застряло» в очереди. Если > 0 — добавляется
    /// тихий счётчик «3 мин в очереди» (UX-документ §4.2).
    public let queuedMinutes: Int

    @Environment(\.colorScheme) private var colorScheme

    public init(state: DeliveryState, queuedMinutes: Int = 0) {
        self.state = state
        self.queuedMinutes = queuedMinutes
    }

    public var body: some View {
        let tint = color(for: state)
        HStack(spacing: 4) {
            Image(systemName: symbol(for: state))
                .tfTypeFont(size: 11, weight: .semibold)
            Text(text)
                .tfText(.caption)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .foregroundStyle(tint)
        .background(tint.opacity(0.12))
        .clipShape(Capsule())
        // Кросс-фейд 180 мс при смене состояния (UX §4.2 — чипы не мигают).
        .animation(.easeInOut(duration: 0.18), value: state)
        .accessibilityIdentifier("coord.stream.chip.\(state.rawValue)")
        .accessibilityLabel(text)
    }

    /// Видимый текст чипа. `internal` (а не `private`) — нужен тестам
    /// (`Tests/CoordinationTests.swift`).
    var text: String {
        switch state {
        case .accepted: return "отправлено"
        case .queued:
            if queuedMinutes > 0 { return "\(queuedMinutes) мин в очереди" }
            return "в очереди"
        case .processing: return "в работе"
        case .delivered: return "доставлено"
        case .completed: return "принято"
        case .failed: return "не доставлено"
        }
    }

    private func color(for state: DeliveryState) -> Color {
        switch state {
        case .accepted: return Color.tfSub
        case .queued: return Color(red: 0.40, green: 0.65, blue: 0.92)
        case .processing: return Color.tfRed
        case .delivered: return Color.tfSub
        case .completed: return Color(red: 0.30, green: 0.62, blue: 0.36)
        case .failed: return Color(red: 0.62, green: 0.10, blue: 0.10)
        }
    }

    private func symbol(for state: DeliveryState) -> String {
        switch state {
        case .accepted: return "paperplane"
        case .queued: return "tray.full"
        case .processing: return "ellipsis.circle"
        case .delivered: return "checkmark"
        case .completed: return "checkmark.seal"
        case .failed: return "exclamationmark.triangle"
        }
    }
}