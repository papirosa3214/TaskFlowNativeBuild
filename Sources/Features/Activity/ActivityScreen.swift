import Charts
import SwiftUI

// «Выполненные задачи» — снимок с сервера: в какой день сколько задач
// выполнено (владелец 13.11.2026: «статистика — фото с сервера… чисто по
// дням, в какой день сколько задач, и всё»). Телефон ничего не считает и
// задачи для подсчёта не грузит: `ClosedTasksStore` хранит снимок и
// спрашивает у сервера только изменившиеся дни.
struct ActivityScreen: View {
    @State private var store = ClosedTasksStore.shared
    /// Сколько последних дней на графике.
    private static let chartDays = 30

    private var days: [(day: String, count: Int)] {
        store.snapshot.days.map { ($0.key, $0.value) }.sorted { $0.day > $1.day }
    }

    var body: some View {
        List {
            Group {
                TFErrorBanner(store.errorMessage, variant: .inline)
                if days.isEmpty {
                    if store.isLoading {
                        TFLoading(.block)
                    } else {
                        TFEmptyState(icon: "chart.bar", text: "Выполненных задач пока нет.")
                            .padding(.horizontal, TFSpacing.xs)
                    }
                } else {
                    summary
                    chart
                    TFSectionHeader("По дням")
                    ForEach(days, id: \.day) { entry in
                        dayRow(entry.day, entry.count)
                    }
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .tfScreenBackground()
        .tfNativeHeader("Выполненные задачи", displayMode: .inline)
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
        .accessibilityIdentifier("activity.daily")
    }

    private var total: Int { store.snapshot.days.values.reduce(0, +) }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(total)")
                .tfText(.title)
                .foregroundStyle(Color.tfText)
            Text("выполнено за всё время")
                .tfText(.meta)
                .foregroundStyle(Color.tfSub)
        }
        .padding(.horizontal, TFSpacing.screenHorizontal)
        .padding(.vertical, TFSpacing.sm)
    }

    /// Последние 30 дней столбиками, пустые дни — нулём.
    private var chart: some View {
        let today = Date()
        let points: [(date: Date, count: Int)] = (0..<Self.chartDays).reversed().compactMap { offset in
            guard let date = Calendar.current.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return (date, store.snapshot.days[Self.key(date)] ?? 0)
        }
        return Chart(points, id: \.date) { point in
            BarMark(x: .value("День", point.date, unit: .day),
                    y: .value("Задач", point.count))
                .foregroundStyle(Color.tfRed)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 7)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date.formatted(.dateTime.day().month(.abbreviated))).tfText(.caption)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let count = value.as(Int.self) { Text("\(count)").tfText(.caption) }
                }
            }
        }
        .frame(height: 170)
        .padding(.horizontal, TFSpacing.screenHorizontal)
        .padding(.bottom, TFSpacing.md)
        .accessibilityLabel("Выполненные задачи за \(Self.chartDays) дней")
    }

    private func dayRow(_ day: String, _ count: Int) -> some View {
        HStack {
            Text(Self.title(day))
                .tfText(.row)
                .foregroundStyle(Color.tfText)
            Spacer(minLength: TFSpacing.sm)
            Text("\(count)")
                .tfText(.row)
                .foregroundStyle(Color.tfSub)
                .monospacedDigit()
        }
        .padding(.horizontal, TFSpacing.screenHorizontal)
        .padding(.vertical, TFSpacing.sm)
    }

    /// День «YYYY-MM-DD» (по Москве, как считает сервер).
    private static func key(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Moscow")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func title(_ day: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(identifier: "Europe/Moscow")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: day) else { return day }
        return date.formatted(.dateTime.day().month(.wide).year())
    }
}
