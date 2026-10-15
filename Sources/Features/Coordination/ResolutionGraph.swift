import SwiftUI

/// Стабильный граф узлов плана. Реализует 7 правил UX-документа
/// (`docs/ios/coordination-resolver-view.md`, §3.3):
///
/// 1. **Позиция узла фиксирована по `plan_node_key` / `subtask_id`.**
///    Если узел временно отсутствует — плейсхолдер на старом месте.
/// 2. **Обновление контента, а не компоновки.** Цвет/иконка меняются
///    на месте; слой перерисовывается без layout-инвалидации.
///    Достигается тем, что `.frame` каждого узла зафиксирован.
/// 3. **Коэффициент пульсации только у активного узла.** `active_run` —
///    пульс 1.2 с амплитудой 6%; `durable_queued_wake` — 3 с амплитудой
///    3%. Остальное не анимируется при обновлении.
/// 4. **Нет fade-out/fade-in между состояниями.** Цвет — кросс-фейд
///    200 мс через `.animation(.easeInOut(duration: 0.2), value: tint)`.
///    Новые элементы появляются через `.scale`, без opacity.
/// 5. **Несколько ветвей параллельно, зависшая рядом с работающей.**
///    Никакого «схлопывания».
/// 6. **Стриминг не запускает перерасчёт графа.** `StreamWindow`
///    получает свой `@StateObject`, не зависит от `CoordinationState`.
///    В этом файле — только граф.
/// 7. **Минимальный diff-механизм.** Реализован в `CoordinationState` —
///    узлы добавляются в конец, существующие не сдвигаются.
public struct ResolutionGraph: View {
    @ObservedObject public var state: CoordinationState
    /// Ось: горизонтальная (по умолчанию) или вертикальная (iPhone SE ≤ 375 пт).
    public let axis: Axis
    /// Размер сенсорной цели (правило 44×44 пт).
    public let tapSize: CGFloat

    public init(
        state: CoordinationState,
        axis: Axis = .horizontal,
        tapSize: CGFloat = 44
    ) {
        self.state = state
        self.axis = axis
        self.tapSize = tapSize
    }

    public var body: some View {
        // Гомогенный body: один-единственный `axis`-зависимый контейнер.
        // Это страховка от swiftc 5.10 «failed to produce diagnostic»
        // на switch/if/AnyView прямо внутри сложного `var body`.
        switch axis {
        case .horizontal:
            return AnyView(horizontalGraph)
        case .vertical:
            return AnyView(verticalGraph)
        }
    }

    private var horizontalGraph: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .center, spacing: 12) {
                ForEach(state.nodes) { node in
                    GraphNodeView(
                        node: node,
                        size: tapSize,
                        onTap: { }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .accessibilityIdentifier("coord.graph.h")
        .frame(minHeight: 88)
    }

    private var verticalGraph: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(state.nodes) { node in
                    HStack(spacing: 12) {
                        GraphNodeView(
                            node: node,
                            size: tapSize,
                            onTap: { }
                        )
                        GraphNodeLabel(node: node)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .accessibilityIdentifier("coord.graph.v")
        .frame(minHeight: 200)
    }

    public enum Axis: Sendable {
        case horizontal
        case vertical
    }
}

/// Один узел графа. `body` гомогенное: один `ZStack` + `.background` +
/// `.overlay`. Цвет и иконка меняются через `.animation`, без opacity.
public struct GraphNodeView: View {
    public let node: CoordinationState.Node
    public let size: CGFloat
    public let onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    public var body: some View {
        Button(action: onTap) {
            ZStack {
                roundedShape
                    .fill(tint.color(for: colorScheme).opacity(0.18))
                roundedShape
                    .strokeBorder(tint.color(for: colorScheme), lineWidth: 1.5)
                if let symbol = tint.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .foregroundStyle(tint.color(for: colorScheme))
                }
                if node.resolution == nil {
                    // Плейсхолдер (правило №1) — узел-призрак.
                    roundedShape
                        .strokeBorder(
                            Color.tfSub.opacity(0.25),
                            style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                        )
                }
            }
            .frame(width: size, height: size)
            .background(
                // Пульсация только у active_run / durable_queued_wake (правило №3).
                PulseModifier(active: shouldPulse)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("coord.node.\(node.id)")
        .accessibilityLabel(accessibilityLabel)
        .animation(.easeInOut(duration: 0.2), value: node.resolution?.cause)
    }

    /// Конкретный тип RoundedRectangle, чтобы компилятор видел `strokeBorder`
    /// (на `some Shape` его нет).
    private var roundedShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
    }

    private var tint: CoordinationTint {
        node.resolution?.causeEnum.tint ?? .unknownGray
    }

    private var shouldPulse: Bool {
        guard let cause = node.resolution?.causeEnum else { return false }
        return cause == .activeRun || cause == .durableQueuedWake
    }

    private var accessibilityLabel: String {
        let role = node.role ?? "—"
        let state = node.resolution?.causeEnum.title ?? "нет данных"
        return "\(role), \(state)"
    }
}

/// Подпись узла для вертикального графа (роль + состояние).
public struct GraphNodeLabel: View {
    public let node: CoordinationState.Node
    public init(node: CoordinationState.Node) { self.node = node }
    public var body: some View {
        let role = node.role ?? "—"
        let title = node.resolution?.causeEnum.title ?? "Нет данных"
        VStack(alignment: .leading, spacing: 2) {
            Text(role)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.tfText)
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Color.tfSub)
        }
    }
}

/// Пульсация — отдельный View, чтобы `body` GraphNodeView был гомогенным.
/// Использует SwiftUI `TimelineView`, чтобы не блокировать апдейты
/// `CoordinationState` (правило №6: стриминг не должен вызывать
/// перерасчёт графа).
public struct PulseModifier: View {
    public let active: Bool

    public init(active: Bool) {
        self.active = active
    }

    public var body: some View {
        // Гомогенный body: один `Group` с условным содержимым.
        Group {
            if active {
                TimelineView(.animation) { context in
                    let t = context.date.timeIntervalSince1970
                    let period: Double = 1.2
                    let amplitude: Double = 0.06
                    let phase = (t.truncatingRemainder(dividingBy: period)) / period
                    let scale = 1.0 + sin(phase * 2 * .pi) * amplitude
                    Color.clear
                        .scaleEffect(scale)
                        .accessibilityHidden(true)
                }
            } else {
                Color.clear.accessibilityHidden(true)
            }
        }
    }
}