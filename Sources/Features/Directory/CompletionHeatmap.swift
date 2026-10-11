import SwiftUI

struct CompletionDay: Identifiable {
    var id: Date { date }
    let date: Date
    let count: Int
}

enum CompletionCalendar {
    static func days(dates: [Date], now: Date = .now, calendar: Calendar = .current) -> [CompletionDay] {
        let today = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: today)
        let monday = calendar.date(byAdding: .day, value: -((weekday + 5) % 7), to: today)!
        let start = calendar.date(byAdding: .day, value: -175, to: monday)!
        let counts = Dictionary(grouping: dates, by: { calendar.startOfDay(for: $0) }).mapValues(\.count)
        return (0..<182).map {
            let date = calendar.date(byAdding: .day, value: $0, to: start)!
            return CompletionDay(date: date, count: counts[date, default: 0])
        }
    }
}

struct CompletionHeatmap: View {
    var depth: CGFloat = 0
    @Environment(TaskStore.self) private var store
    @State private var selected: Date?
    @State private var sceneWidth: CGFloat = 0
    @Environment(RealtimeClient.self) private var realtime
    @State private var reviewDates: [String: Date] = [:]
    @State private var archiveError = false
    private var days: [CompletionDay] {
        CompletionCalendar.days(dates: Array(reviewDates.values))
    }
    private var historyRevision: String {
        "\(realtime.connectionRevision):" + realtime.taskRevisions.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: ",")
    }

    private func shade(_ count: Int) -> Color {
        switch count {
        case 0: return Color.tfStroke
        case 1: return Color.tfRed.mix(with: .black, by: 0.7)
        case 2...3: return Color.tfRed.mix(with: .black, by: 0.45)
        case 4...6: return Color.tfRed.mix(with: .black, by: 0.2)
        default: return Color.tfRed
        }
    }

    var body: some View {
        let values = days
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geometry in
                let pitch = (geometry.size.width + 3) / 26
                ForEach(0..<26, id: \.self) { week in
                    let date = values[week * 7].date
                    let month = Calendar.current.component(.month, from: date)
                    let previous = week == 0 ? -1 : Calendar.current.component(.month, from: values[(week - 1) * 7].date)
                    if month != previous {
                        Text(date.formatted(.dateTime.month(.abbreviated)))
                            .font(.caption).foregroundStyle(Color.tfSub)
                            .fixedSize().offset(x: CGFloat(week) * pitch)
                    }
                }
            }.frame(height: 16)
            GeometryReader { geometry in
                HeatmapScene(values: values, depth: depth, selected: $selected)
                    .frame(width: geometry.size.width, height: geometry.size.width * 7 / 26 + depth * 200)
            }
                .frame(height: sceneWidth * 7 / 26 + depth * 200)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { sceneWidth = $0 }
                .accessibilityIdentifier("overview.heatmap")
                .accessibilityValue(depth > 0.99 ? "Объёмная" : depth < 0.01 ? "Плоская" : "Переход")
            HStack(spacing: 5) {
                Text("Меньше")
                ForEach([0, 1, 2, 4, 7], id: \.self) { value in
                    RoundedRectangle(cornerRadius: 2).fill(shade(value)).frame(width: 10, height: 10)
                }
                Text("Больше")
                Spacer(minLength: 0)
            }.font(.caption2).foregroundStyle(Color.tfSub)
            if archiveError {
                Button("История недоступна · Повторить") { Task { await loadArchive() } }.font(.caption)
            }
        }
        .popover(isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) {
            if let day = values.first(where: { $0.date == selected }) {
                Text(day.date.formatted(date: .abbreviated, time: .omitted) + " · на проверку \(day.count)")
                    .padding().presentationCompactAdaptation(.popover)
            }
        }
        .task(id: historyRevision) { await loadArchive() }
    }
    private struct ReviewHistory: Decodable {
        struct Entry: Decodable {
            let task_id: String
            let submitted_at: String
        }
        let entries: [Entry]
    }
    private func loadArchive() async {
        do {
            let response: ReviewHistory = try await APIClient().request(.get, "/stats/review-history")
            reviewDates = Dictionary(uniqueKeysWithValues: response.entries.compactMap { entry in
                DateFormats.sqliteUTC(entry.submitted_at).map { (entry.task_id, $0) }
            })
            archiveError = false
        } catch is CancellationError { }
        catch { archiveError = true }
    }
}

/// Orthographic projection of the same daily cells; height follows actual counts.
private struct HeatmapScene: View, Animatable {
    let values: [CompletionDay]
    var depth: CGFloat
    @Binding var selected: Date?
    var animatableData: CGFloat {
        get { depth }
        set { depth = newValue }
    }

    private func color(_ count: Int) -> Color {
        switch count {
        case 0: return .tfStroke
        case 1: return Color.tfRed.mix(with: .black, by: 0.7)
        case 2...3: return Color.tfRed.mix(with: .black, by: 0.45)
        case 4...6: return Color.tfRed.mix(with: .black, by: 0.2)
        default: return .tfRed
        }
    }
    private func polygon(_ points: [CGPoint]) -> Path {
        Path { path in
            path.addLines(points)
            path.closeSubpath()
        }
    }
    private func cells(in size: CGSize) -> [(day: CompletionDay, top: [CGPoint], base: [CGPoint])] {
        let t = min(1, max(0, depth))
        let pitch = (size.width + 3) / 26
        let planeHeight = pitch * 7 - 3
        let side = pitch - 3 + 1.4 * t
        let yaw = CGFloat.pi / 4 * t
        let tilt = CGFloat.pi * 0.30 * t
        func raw(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> CGPoint {
            let xx = x * cos(yaw) - y * sin(yaw)
            let yy = (x * sin(yaw) + y * cos(yaw)) * cos(tilt) - z * sin(tilt)
            return CGPoint(x: xx, y: yy)
        }
        var bounds = [raw(0, 0, 0), raw(size.width, 0, 0), raw(0, planeHeight, 0), raw(size.width, planeHeight, 0)]
        // Fit actual columns, without reserving height for nonexistent peaks.
        for week in 0..<26 {
            for row in 0..<7 {
                let count = values[week * 7 + row].count
                let height = count == 0 ? 0 : min(64, 4 + sqrt(CGFloat(count)) * 11) * t
                let x = CGFloat(week) * pitch, y = CGFloat(row) * pitch
                bounds.append(contentsOf: [raw(x,y,height), raw(x+side,y,height), raw(x+side,y+side,height), raw(x,y+side,height)])
            }
        }
        let minX = bounds.map(\.x).min()!, maxX = bounds.map(\.x).max()!
        let minY = bounds.map(\.y).min()!, maxY = bounds.map(\.y).max()!
        let scale = min(size.width / max(1, maxX - minX), size.height / max(1, maxY - minY))
        func project(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> CGPoint {
            let p = raw(x, y, z)
            return CGPoint(x: (p.x - (minX + maxX) / 2) * scale + size.width / 2,
                           y: (p.y - (minY + maxY) / 2) * scale + size.height / 2)
        }
        return (0..<182).map { slot in
            let week = slot % 26, row = slot / 26
            let day = values[week * 7 + row]
            let x = CGFloat(week) * pitch, y = CGFloat(row) * pitch
            let height = day.count == 0 ? 0 : min(64, 4 + sqrt(CGFloat(day.count)) * 11) * t
            let corners = [(x,y),(x+side,y),(x+side,y+side),(x,y+side)]
            return (day, corners.map { project($0.0, $0.1, height) }, corners.map { project($0.0, $0.1, -2.5 * t) })
        }.sorted { $0.base.map(\.y).max()! < $1.base.map(\.y).max()! }
    }
    var body: some View {
        Canvas { context, size in
            for cell in cells(in: size) {
                let top = cell.top, base = cell.base
                let shade = color(cell.day.count)
                if depth > 0.001 {
                    let right = polygon([top[1],top[2],base[2],base[1]])
                    let front = polygon([top[2],top[3],base[3],base[2]])
                    context.fill(right, with: .color(shade.mix(with: .black, by: 0.48)))
                    context.fill(front, with: .color(shade.mix(with: .black, by: 0.26)))
                    context.stroke(right, with: .color(.black.opacity(0.24 * depth)), lineWidth: 0.6)
                    context.stroke(front, with: .color(.white.opacity(0.09 * depth)), lineWidth: 0.5)
                }
                if depth < 0.001 {
                    context.fill(Path(roundedRect: CGRect(x: top[0].x, y: top[0].y, width: top[1].x-top[0].x, height: top[3].y-top[0].y), cornerRadius: 2), with: .color(shade))
                } else {
                    context.fill(polygon(top), with: .color(shade))
                    context.stroke(polygon(top), with: .color(.white.opacity(0.14 * depth)), lineWidth: 0.65)
                }
            }
        }
        .contentShape(Rectangle())
        .overlay {
            GeometryReader { geometry in
                Color.clear.contentShape(Rectangle()).onTapGesture { location in
                    if let cell = cells(in: geometry.size).reversed().first(where: { polygon($0.top).contains(location) }),
                       cell.day.date <= Calendar.current.startOfDay(for: .now) {
                        selected = cell.day.date
                    }
                }
            }
        }
        .accessibilityRepresentation {
            VStack {
                Text(depth > 0.99 ? "Объёмная тепловая карта" : "Плоская тепловая карта")
                    .accessibilityIdentifier("overview.heatmap.mode")
                ForEach(0..<182, id: \.self) { slot in
                    let day = values[(slot % 26) * 7 + slot / 26]
                    Button { selected = day.date } label: {
                        Text(day.date.formatted(date: .abbreviated, time: .omitted) + ": на проверку \(day.count)")
                    }
                    .disabled(day.date > Calendar.current.startOfDay(for: .now))
                    .accessibilityIdentifier("overview.heatmap.cell.\(slot)")
                }
            }
        }
    }
}
