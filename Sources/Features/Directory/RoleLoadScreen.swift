import SwiftUI

struct RoleLoadScreen: View {
    @Environment(RealtimeClient.self) private var realtime
    @Environment(\.scenePhase) private var scenePhase
    @State private var window = "24h"
    @State private var data: RoleLoad?
    @State private var error: String?
    private struct TaskRef: Identifiable { let id: String }
    @State private var selectedTask: TaskRef?
    private let width: CGFloat = 1000

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TFErrorBanner(error)
                if let data {
                    if data.roles.isEmpty {
                        Text("Нет включённых ролей — откройте «Команду».")
                    } else {
                        legend
                        chart(data)
                        if data.attempts.isEmpty && data.active_now.isEmpty && data.open_slots.isEmpty {
                            Text("За выбранный период рабочего времени нет.").foregroundStyle(Color.tfSub)
                        }
                    }
                } else if error == nil {
                    ProgressView().frame(maxWidth: .infinity)
                }
                ContextObservabilitySection(window: window) { selectedTask = TaskRef(id: $0) }
            }
            .padding(16)
        }
        .background(Color.tfBackground)
        .tfNativeHeader("Загрузка ролей", displayMode: .inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Период", selection: $window) {
                        Text("Сутки").tag("24h")
                        Text("3 дня").tag("3d")
                        Text("Неделя").tag("week")
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                }
                .accessibilityLabel("Период графика")
                .accessibilityIdentifier("role-load.period-menu")
            }
        }
        .taskCardSheet(item: $selectedTask)
        .task(id: "\(window):\(scenePhase):\(realtime.connectionRevision):\(realtime.rolesRevision):\(realtime.jobsRevision)") {
            guard scenePhase == .active else { return }
            await load()
            // Пока экран видим: страховка для серверов без полного WS покрытия attempts.
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
                await load()
            }
        }
    }

    // Владелец 12.10.2026: цветов на графике стало много — подписать, что какой значит.
    private static let legendItems: [(Color, String)] = [
        (.tfGreen, "Идёт сейчас"),
        (.tfSub, "Завершено"),
        (.tfRed, "Сбой"),
        (.tfOrange, "Заблокировано или без исполнителя"),
        (.tfPurple, "Починка поломки"),
    ]

    private var legend: some View {
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                  alignment: .leading, spacing: 6) {
            ForEach(Self.legendItems, id: \.1) { color, title in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3).fill(color.opacity(0.3))
                        .overlay { RoundedRectangle(cornerRadius: 3).stroke(color, lineWidth: 1) }
                        .frame(width: 14, height: 14)
                    Text(title).font(.caption).foregroundStyle(Color.tfSub)
                }
            }
        }
        .accessibilityIdentifier("role-load.legend")
    }

    private func load() async {
        do {
            let result: RoleLoad = try await APIClient().request(.get, "/coordination/role-load", query: [URLQueryItem(name: "window", value: window)])
            try Task.checkCancellation()
            data = result
            error = nil
        } catch is CancellationError {} catch {
            self.error = "Не удалось загрузить занятость ролей. Потяните вниз, чтобы повторить."
        }
    }

    /// Высота строки роли: дорожки (по одной на ряд одновременных задач)
    /// плюс блок слотов без исполнителя и запас под ось.
    private func height(_ row: RoleLoadLayout.RoleRow) -> CGFloat {
        CGFloat(max(1, row.lanes.count)) * RoleLoadLayout.laneStep
            + CGFloat(row.open.count) * 28 + 30
    }

    private func chart(_ data: RoleLoad) -> some View {
        let layout = RoleLoadLayout.build(data, width: width)
        return HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                Text("Роль").tfText(.meta).frame(width: 36, height: 32)
                ForEach(layout) { row in
                    VStack(spacing: 2) {
                        Text(row.title).tfText(.body).lineLimit(1)
                        Text(row.isBusy ? "Занята сейчас" : "Свободна")
                            .tfText(.caption).lineLimit(1)
                            .foregroundStyle(row.isBusy ? Color.tfBlue : Color.tfSub)
                    }
                    .frame(width: height(row) - 8)
                    .rotationEffect(.degrees(-90))
                    .frame(width: 36, height: height(row))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(row.title)
                    .accessibilityValue(row.isBusy ? "Занята сейчас" : "Свободна")
                    .accessibilityIdentifier("role-load.label.\(row.id)")
                }
            }
            ScrollView(.horizontal) {
                VStack(spacing: 0) {
                    axis(data)
                    ForEach(layout) { row in
                        ZStack(alignment: .topLeading) {
                            Rectangle().fill(Color.tfStroke).frame(height: 1)
                            ForEach(0..<5) { tick in
                                Rectangle().fill(Color.tfStroke).frame(width: 1).offset(x: width * CGFloat(tick) / 4)
                            }
                            Rectangle().fill(Color.tfBlue).frame(width: 1).offset(x: width * data.fraction(data.now))
                            ForEach(Array(row.lanes.enumerated()), id: \.offset) { laneIndex, lane in
                                ForEach(lane.contours) { contour in
                                    contour(contour, laneIndex: laneIndex)
                                }
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(row.open) { slot in
                                    Button { selectedTask = TaskRef(id: slot.id) } label: {
                                        Label("Без исполнителя · \(slot.task_title)", systemImage: "flag")
                                            .tfText(.meta).lineLimit(1).padding(.horizontal, 8).frame(height: 28)
                                            .foregroundStyle(Color.tfOrange).background(Color.tfOrange.opacity(0.15))
                                            .clipShape(RoundedRectangle(cornerRadius: 5))
                                    }.buttonStyle(.plain)
                                }
                            }
                            .offset(y: CGFloat(max(1, row.lanes.count)) * RoleLoadLayout.laneStep)
                        }
                        .frame(width: width, height: height(row))
                    }
                }
                .frame(width: width)
            }
            .accessibilityIdentifier("role-load.timeline")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("role-load.chart")
        .accessibilityValue(data.window)
    }

    private func axis(_ data: RoleLoad) -> some View {
        ZStack(alignment: .leading) {
            ForEach(0..<5) { tick in
                if let start = RoleLoad.date(data.from), let end = RoleLoad.date(data.to) {
                    let date = start.addingTimeInterval(end.timeIntervalSince(start) * Double(tick) / 4)
                    Text(date.formatted(window == "24h" ? .dateTime.hour().minute() : .dateTime.day().month().hour()))
                        .tfText(.caption)
                        .frame(width: 120, alignment: tick == 4 ? .trailing : .leading)
                        .offset(x: width * CGFloat(tick) / 4 - (tick == 4 ? 120 : 0))
                }
            }
        }.frame(width: width, height: 32, alignment: .leading)
    }

    /// Контур одной задачи: рамка — весь интервал работы по задаче (внутри
    /// видно простои), заливка — фактические заходы. Подпись — короткий номер
    /// «МАК-ДДММ-ЧЧММ», по нему карточка опознаётся прямо на графике.
    private func contour(_ item: RoleLoadLayout.Contour, laneIndex: Int) -> some View {
        let top = CGFloat(laneIndex) * RoleLoadLayout.laneStep
        let label = item.number ?? item.title
        return VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .tfText(.micro)
                .lineLimit(1)
                .frame(width: max(40, item.end - item.start), alignment: .leading)
            ZStack(alignment: .topLeading) {
                // Рамка контура: весь интервал по задаче (пустоты — простой).
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    .foregroundStyle(Color.tfSub.opacity(0.6))
                    .frame(width: max(4, item.end - item.start), height: RoleLoadLayout.barHeight)
                // Заливка: фактические заходы.
                ForEach(item.segments) { segment in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color(segment.tone).opacity(segment.tone == .live ? 0.5 : 0.85))
                        .frame(width: max(3, segment.end - segment.start), height: RoleLoadLayout.barHeight - 6)
                        .overlay {
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(color(segment.tone), lineWidth: segment.tone == .live ? 2 : 1)
                        }
                        .offset(x: segment.start - item.start, y: 3)
                }
            }
            .frame(width: max(4, item.end - item.start), height: RoleLoadLayout.barHeight, alignment: .topLeading)
        }
        .offset(x: item.start, y: top)
        .frame(width: width, height: RoleLoadLayout.laneStep, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.number.map { "\($0) · \(item.title)" } ?? item.title)
        .accessibilityIdentifier("role-load.contour.\(item.taskID)")
        .onTapGesture { selectedTask = TaskRef(id: item.taskID) }
    }

    private func color(_ tone: RoleLoadLayout.Tone) -> Color {
        switch tone {
        case .done: .tfSub
        case .failed: .tfRed
        case .blocked: .tfOrange
        case .service: .tfPurple
        case .live: .tfGreen
        }
    }
}
