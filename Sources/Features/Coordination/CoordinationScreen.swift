import SwiftUI

/// Экран карточки по контракту координации V2. Склеивает ReasonStrip,
/// стабильный граф, StreamWindow и ActionBar. Источник правды —
/// `CoordinationState`. Авто-обновление каждые 30 с.
///
/// Этот View НЕ заменяет существующий `TaskDetailScreen` — он
/// отрисовывается поверх него как раздел «Координация», чтобы
/// `TaskDetailScreen` продолжил работать в старом режиме, а новые
/// состояния по V2 поднялись рядом.
public struct CoordinationScreen: View {
    @ObservedObject public var state: CoordinationState
    /// Карточка, для которой запрашиваем `Resolution`.
    public let taskId: String
    /// Сколько секунд между обновлениями. UX-документ §4.3 — 30 с по
    /// умолчанию. Push-нотификации вынесены в открытый вопрос №1.
    public let refreshIntervalSeconds: Double

    @State private var streamUnread: Int = 0
    @State private var showDetails: Bool = false
    @State private var showActionConfirm: CoordinationAction?

    public init(
        state: CoordinationState,
        taskId: String,
        refreshIntervalSeconds: Double = 30
    ) {
        self.state = state
        self.taskId = taskId
        self.refreshIntervalSeconds = refreshIntervalSeconds
    }

    public var body: some View {
        VStack(spacing: 0) {
            reasonStripRow
            // Стабильный граф — отдельный источник обновления, не зависит
            // от StreamWindow (правило №6).
            ResolutionGraph(state: state, axis: graphAxis)
                .frame(maxHeight: 120)
                .padding(.horizontal, TFSpacing.md)
                .padding(.top, TFSpacing.sm)
            // Окно стриминга — 38% от высоты экрана, но не меньше 200 и
            // не больше 360 пт (UX §4.1). На узком iPhone ≤ 375 пт окно
            // переходит в вертикальный режим.
            StreamWindow(
                title: "Поток",
                unread: streamUnread,
                minHeight: streamMinHeight,
                maxHeight: streamMaxHeight
            ) {
                AnyView(StreamComposerPlaceholder())
            } rows: {
                // Реальный список сообщений — отдельный `@StateObject`,
                // чтобы стриминг не дёргал `CoordinationState` (правило №6).
                // Здесь — заглушка с примером; в продакшене рядом живёт
                // `ChatMessagesViewModel`.
                ForEach(0..<3) { idx in
                    StreamMessageRow(
                        text: "Сообщение \(idx + 1)",
                        delivery: idx == 0 ? .completed : (idx == 1 ? .processing : .queued),
                        queuedMinutes: idx == 2 ? 2 : 0
                    )
                }
            }
            .padding(.horizontal, TFSpacing.md)
            .padding(.top, TFSpacing.sm)
            ActionBar(
                resolution: currentResolution,
                blockedByVersionMismatch: isVersionMismatch
            ) { action in
                if action.confirmRequired {
                    showActionConfirm = action
                } else {
                    state.onAction?(action)
                }
            }
            .padding(.bottom, TFSpacing.xs)
        }
        .background(Color(.systemBackground))
        // `.task(id:)` вместо `.task` + `onChange`: SwiftUI сам отменяет прежний
        // цикл при смене задачи — раньше опрос шёл в двух циклах одновременно
        // (и не отменялся при уходе с экрана).
        .task(id: taskId) { await initialLoad() }
        .sheet(isPresented: $showDetails) {
            ResolutionDetailsSheet(resolution: currentResolution)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .alert(
            "Подтвердите действие",
            isPresented: Binding(
                get: { showActionConfirm != nil },
                set: { if !$0 { showActionConfirm = nil } }
            ),
            presenting: showActionConfirm
        ) { action in
            Button("Выполнить", role: .destructive) {
                state.onAction?(action)
                showActionConfirm = nil
            }
            Button("Отмена", role: .cancel) { showActionConfirm = nil }
        } message: { action in
            Text("\(action.label) — действие изменит состояние карточки.")
        }
    }

    private var reasonStripRow: some View {
        ReasonStrip(
            resolution: currentResolution,
            loadState: state.loadState,
            lastUpdatedAt: state.lastUpdatedAt,
            onShowDetails: { showDetails = true },
            onRefresh: { Task { await refresh() } }
        )
        .padding(.horizontal, TFSpacing.md)
        .padding(.top, TFSpacing.sm)
    }

    /// Текущая «фокусная» `Resolution` — приоритет отдан активной/зависшей
    /// ветви, иначе — первая в массиве.
    private var currentResolution: APIClient.CoordinationResolution? {
        if let id = state.stalledNodeId, let r = state.resolution(forSubtaskId: id) {
            return r
        }
        return state.nodes.compactMap { $0.resolution }.first
    }

    private var isVersionMismatch: Bool {
        if case .versionMismatch = state.loadState { return true }
        return false
    }

    private var graphAxis: ResolutionGraph.Axis {
        // Узкий iPhone ≤ 375 пт → вертикальный граф (UX §8).
        UIScreen.main.bounds.width <= 375
            ? .vertical
            : .horizontal
    }

    private var streamMinHeight: CGFloat {
        // На узком iPhone Stream window занимает ровно 38% экрана,
        // ограничено снизу 200 пт.
        UIScreen.main.bounds.width <= 375 ? 200 : 240
    }

    private var streamMaxHeight: CGFloat {
        // На Max/Plus — 36%, чтобы не разрастаться (UX §8).
        UIScreen.main.bounds.width >= 430 ? 320 : 360
    }

    private func initialLoad() async {
        // Цикл авто-обновления каждые `refreshIntervalSeconds`.
        // Состояние `.loading` выставляется в `apply(...)`/`applyFailure(...)`
        // — прямого setter у `loadState` нет (это инвариант стора).
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(nanoseconds: UInt64(refreshIntervalSeconds * 1_000_000_000))
        }
    }

    private func refresh() async {
        do {
            let items = try await APIClient().fetchTaskResolutions(taskId: taskId)
            let v = items.first?.contractVersion
            state.apply(resolutions: items, contractVersion: v)
        } catch {
            state.applyFailure((error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription)
        }
    }
}

/// Заглушка композера — реальный ввод реализован в чате, здесь нужен
/// только слот нужной высоты (44 пт по UX §4.1).
public struct StreamComposerPlaceholder: View {
    public init() {}
    public var body: some View {
        HStack(spacing: TFSpacing.sm) {
            Image(systemName: "paperclip")
                .foregroundStyle(Color.tfSub)
            Text("Написать…")
                .foregroundStyle(Color.tfSub)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, TFSpacing.md)
        .frame(height: 44)
        .background(Color.tfCard2)
        .overlay(
            Rectangle()
                .frame(height: TFBorder.width)
                .foregroundStyle(Color.tfSub.opacity(0.25)),
            alignment: .top
        )
        .accessibilityIdentifier("coord.stream.composer")
    }
}

/// Пример строки сообщения в StreamWindow. Поле `text` (не `body`,
/// чтобы не конфликтовать с `var body: some View` в SwiftUI).
public struct StreamMessageRow: View {
    public let text: String
    public let delivery: MessageDeliveryChip.DeliveryState
    public let queuedMinutes: Int
    public init(text: String, delivery: MessageDeliveryChip.DeliveryState, queuedMinutes: Int = 0) {
        self.text = text
        self.delivery = delivery
        self.queuedMinutes = queuedMinutes
    }
    public var body: some View {
        HStack(alignment: .top, spacing: TFSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .tfText(.action)
                    .foregroundStyle(Color.tfText)
                MessageDeliveryChip(state: delivery, queuedMinutes: queuedMinutes)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

/// Детальный sheet по тапу на ReasonStrip — показывает полный `Resolution`.
public struct ResolutionDetailsSheet: View {
    public let resolution: APIClient.CoordinationResolution?
    public init(resolution: APIClient.CoordinationResolution?) {
        self.resolution = resolution
    }
    public var body: some View {
        NavigationStack {
            ScrollView {
                if let r = resolution {
                    VStack(alignment: .leading, spacing: TFSpacing.md) {
                        detailRow("Причина", r.causeEnum.title)
                        detailRow("Подсказка", r.causeEnum.hint)
                        detailRow("Действие", r.actionEnum.label)
                        detailRow("Исполнитель", r.assignee.kind + " · " + r.assignee.key)
                        if let notes = r.notes, !notes.isEmpty {
                            detailRow("Заметки", notes)
                        }
                        if !r.evidence.isEmpty {
                            detailRow("Доказательства",
                                      r.evidence.map { "\($0.kind): \($0.ref)" }.joined(separator: "\n"))
                        }
                        if !r.links.isEmpty {
                            detailRow("Связи",
                                      r.links.map { "\($0.kind): \($0.ref)" }.joined(separator: "\n"))
                        }
                        detailRow("Версия контракта", r.contractVersion)
                    }
                    .padding()
                } else {
                    Text("Нет данных")
                        .padding()
                }
            }
            .navigationTitle("Детали координации")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    private func detailRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(Color.tfSub)
            Text(value).tfText(.action).foregroundStyle(Color.tfText)
        }
    }
}