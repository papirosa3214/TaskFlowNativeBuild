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
        let start = calendar.date(byAdding: .day, value: -77, to: monday)!
        let counts = Dictionary(grouping: dates, by: { calendar.startOfDay(for: $0) }).mapValues(\.count)
        return (0..<84).map {
            let date = calendar.date(byAdding: .day, value: $0, to: start)!
            return CompletionDay(date: date, count: counts[date, default: 0])
        }
    }
}

struct CompletionHeatmap: View {
    @Environment(TaskStore.self) private var store
    @State private var selected: Date?
    @State private var archive: [ApiTask] = []
    @State private var archiveError = false
    private var days: [CompletionDay] {
        var seen = Set<String>()
        let dates = (store.tasks + archive).filter { seen.insert($0.id).inserted && $0.status == .completed }
            .compactMap(\.completedAtDate)
        return CompletionCalendar.days(dates: dates)
    }
    var body: some View {
        let values = days
        TFCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Активность").font(.headline)
                    Spacer()
                    Text("12 недель").font(.caption).foregroundStyle(Color.tfSub)
                }
                HStack(alignment: .top, spacing: 4) {
                    VStack(spacing: 4) {
                        ForEach(["Пн", "", "Ср", "", "Пт", "", "Вс"].indices, id: \.self) { index in
                            Text(["Пн", "", "Ср", "", "Пт", "", "Вс"][index])
                                .font(.system(size: 9)).frame(height: 17)
                        }
                    }.foregroundStyle(Color.tfSub)
                    ForEach(0..<12, id: \.self) { week in
                        VStack(spacing: 4) {
                            ForEach(0..<7, id: \.self) { weekday in
                                let day = values[week * 7 + weekday]
                                let future = day.date > Calendar.current.startOfDay(for: .now)
                                Button { selected = day.date } label: {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(day.count == 0 ? Color.tfStroke : Color.tfGreen.opacity(0.25 + min(1, Double(day.count) / 6) * 0.75))
                                        .frame(height: 17)
                                        .opacity(future ? 0.2 : 1)
                                }
                                .buttonStyle(.plain)
                                .disabled(future)
                                .accessibilityLabel(day.date.formatted(date: .abbreviated, time: .omitted) + ": выполнено \(day.count)")
                            }
                        }.frame(maxWidth: .infinity)
                    }
                }
                if let day = values.first(where: { $0.date == selected }) {
                    Text(day.date.formatted(date: .abbreviated, time: .omitted) + " · выполнено \(day.count)").font(.caption).foregroundStyle(Color.tfSub)
                } else {
                    Text("Выполненные задачи по дням").font(.caption).foregroundStyle(Color.tfSub)
                }
                if archiveError {
                    Button("Не удалось загрузить архив · Повторить") { Task { await loadArchive() } }.font(.caption)
                }
            }
        }
        .accessibilityIdentifier("overview.completion-heatmap")
        .task { await loadArchive() }
    }
    private func loadArchive() async {
        do { archive = try await APIClient().tasks(archived: true); archiveError = false }
        catch is CancellationError { }
        catch { archiveError = true }
    }
}
