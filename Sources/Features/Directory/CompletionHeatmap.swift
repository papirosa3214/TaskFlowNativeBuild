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
    @Environment(TaskStore.self) private var store
    @State private var selected: Date?
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
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 26), spacing: 3) {
                ForEach(0..<182, id: \.self) { slot in
                    let day = values[(slot % 26) * 7 + slot / 26]
                    let future = day.date > Calendar.current.startOfDay(for: .now)
                    Button { selected = day.date } label: {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(shade(day.count))
                            .aspectRatio(1, contentMode: .fit)
                    }
                    .buttonStyle(.plain).disabled(future)
                    .accessibilityIdentifier("overview.heatmap.cell.\(slot)")
                    .accessibilityLabel(day.date.formatted(date: .abbreviated, time: .omitted) + ": на проверку \(day.count)")
                }
            }
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
