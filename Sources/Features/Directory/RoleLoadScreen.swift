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
                Picker("Период", selection: $window) {
                    Text("Сутки").tag("24h")
                    Text("3 дня").tag("3d")
                    Text("Неделя").tag("week")
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("role-load.period")
                TFErrorBanner(error)
                if let data {
                    if data.roles.isEmpty {
                        Text("Нет включённых ролей — откройте «Команду».")
                    } else {
                        HStack(spacing: 14) {
                            Label("Заходы", systemImage: "rectangle.fill").foregroundStyle(Color.tfGreen)
                            Label("Сейчас", systemImage: "circle.fill").foregroundStyle(Color.tfBlue)
                            Label("Без исполнителя", systemImage: "flag").foregroundStyle(Color.tfOrange)
                        }
                        .font(.caption)
                        chart(data)
                        if data.attempts.isEmpty && data.active_now.isEmpty && data.open_slots.isEmpty {
                            Text("За выбранный период заходов нет.").foregroundStyle(Color.tfSub)
                        }
                    }
                } else if error == nil {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .padding(16)
        }
        .background(Color.tfBackground)
        .tfNativeHeader("Загрузка ролей", displayMode: .inline)
        .sheet(item: $selectedTask) { ref in
            NavigationStack { TaskFormScreen(taskID: ref.id) }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.tfSheetBackground)
        }
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

    private func height(_ row: RoleLoad.Row) -> CGFloat {
        CGFloat(max(1, row.attempts.count + row.active.count + row.open.count)) * 32 + 30
    }

    private func chart(_ data: RoleLoad) -> some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                Text("Роль").font(.caption).frame(width: 36, height: 32)
                ForEach(data.rows) { row in
                    VStack(spacing: 2) {
                        Text(row.title).font(.subheadline).lineLimit(1)
                        Text(row.active.isEmpty ? "Свободна" : "Занята сейчас")
                            .font(.caption2).lineLimit(1)
                            .foregroundStyle(row.active.isEmpty ? Color.tfSub : Color.tfBlue)
                    }
                    .frame(width: height(row) - 8)
                    .rotationEffect(.degrees(-90))
                    .frame(width: 36, height: height(row))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(row.title)
                    .accessibilityValue(row.active.isEmpty ? "Свободна" : "Занята сейчас")
                    .accessibilityIdentifier("role-load.label.\(row.id)")
                }
            }
            ScrollView(.horizontal) {
                VStack(spacing: 0) {
                    axis(data)
                    ForEach(data.rows) { row in
                        ZStack(alignment: .topLeading) {
                            Rectangle().fill(Color.tfStroke).frame(height: 1)
                            ForEach(0..<5) { tick in
                                Rectangle().fill(Color.tfStroke).frame(width: 1).offset(x: width * CGFloat(tick) / 4)
                            }
                            Rectangle().fill(Color.tfBlue).frame(width: 1).offset(x: width * data.fraction(data.now))
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(row.attempts) { attempt in
                                    bar(data, title: attempt.task_title, taskID: attempt.task_id,
                                        start: attempt.started_at, end: attempt.ended_at ?? data.now,
                                        color: attempt.active ? .tfBlue : tone(attempt.outcome), active: attempt.active)
                                }
                                ForEach(row.active) { slot in
                                    bar(data, title: slot.task_title, taskID: slot.task_id,
                                        start: slot.started_at ?? slot.heartbeat_at ?? data.now,
                                        end: data.now, color: .tfBlue, active: true)
                                }
                                ForEach(row.open) { slot in
                                    Button { selectedTask = TaskRef(id: slot.id) } label: {
                                        Label("Без исполнителя · \(slot.task_title)", systemImage: "flag")
                                            .font(.caption).lineLimit(1).padding(.horizontal, 8).frame(height: 28)
                                            .foregroundStyle(Color.tfOrange).background(Color.tfOrange.opacity(0.15))
                                            .clipShape(RoundedRectangle(cornerRadius: 5))
                                    }.buttonStyle(.plain)
                                }
                            }
                            .padding(.top, 4)
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
                        .font(.caption2)
                        .frame(width: 120, alignment: tick == 4 ? .trailing : .leading)
                        .offset(x: width * CGFloat(tick) / 4 - (tick == 4 ? 120 : 0))
                }
            }
        }.frame(width: width, height: 32, alignment: .leading)
    }

    private func bar(_ data: RoleLoad, title: String, taskID: String, start: String, end: String, color: Color, active: Bool) -> some View {
        let left = width * data.fraction(start)
        let barWidth = min(width - left, max(12, width * (data.fraction(end) - data.fraction(start))))
        return Button { selectedTask = TaskRef(id: taskID) } label: {
            RoundedRectangle(cornerRadius: 5).fill(color.opacity(0.3))
                .overlay { RoundedRectangle(cornerRadius: 5).stroke(color, lineWidth: active ? 2 : 1) }
                .overlay(alignment: .leading) { Text(title).font(.caption2).lineLimit(1).padding(.horizontal, 5) }
                .frame(width: max(4, barWidth), height: 28)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(active ? "Сейчас · " : "")\(title)")
        .accessibilityValue("\(start) — \(end)")
        .offset(x: left)
        .frame(width: width, height: 28, alignment: .leading)
    }
    private func tone(_ outcome: String?) -> Color {
        switch outcome {
        case "done": .tfGreen
        case "failed": .tfRed
        case "blocked": .tfOrange
        default: .tfDim
        }
    }
}
