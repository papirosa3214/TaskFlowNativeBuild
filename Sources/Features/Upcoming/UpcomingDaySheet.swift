import SwiftUI

// Раскрытый день — spec/SCREENS-1.md §3.6. Две формы одного и того же
// набора данных: `DayStrip` (внутри месячной сетки, полосой между неделями)
// и `DaySheetContent` (нижняя шторка недельного вида).

/// Полоса раскрытого дня в месячной сетке — между его неделей и следующей.
/// Кнопки «Свернуть» нет намеренно: повторный тап по тому же дню закрывает
/// (решение владельца, зафиксировано в спеке §3.6).
struct UpcomingDayStrip: View {
    let date: String
    let tasks: [ApiTask]
    let onTaskTap: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                let (_, month) = UpcomingDate.yearMonth(date)
                Text("\(UpcomingDate.day(date)) \(UpcomingDate.monthsGen[month]),")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.tfText)
                Text(UpcomingDate.weekdaysFull[UpcomingDate.monFirst(UpcomingDate.jsWeekday(date))])
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.tfText)
            }

            if tasks.isEmpty {
                Text("Ничего не запланировано")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.tfDim)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(tasks, id: \.id) { task in
                            UpcomingDayListRow(task: task, checkboxSize: 13, titleSize: 13, timeSize: 11) {
                                onTaskTap(task.id)
                            }
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.tfCard)
    }
}

/// Содержимое нижней шторки раскрытого дня — открывается и в НЕДЕЛЬНОМ, и в
/// МЕСЯЧНОМ виде (spec §3.6). Заголовок и «Готово» рисует не этот файл, а
/// `NavigationStack`/toolbar в `UpcomingScreen.daySheet` — нативная шапка
/// шторки, не самодельная (см. LOCK-051/052 в AGENT-WORK-SCOPES.md).
struct UpcomingDaySheetContent: View {
    let date: String
    let tasks: [ApiTask]
    let onTaskTap: (String) -> Void

    var body: some View {
        Group {
            if tasks.isEmpty {
                Text("На этот день ничего не запланировано")
                    .tfText(.action)
                    .foregroundStyle(Color.tfDim)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                VStack(spacing: 6) {
                    ForEach(tasks, id: \.id) { task in
                        UpcomingDayListRow(task: task, checkboxSize: 16, titleSize: 14, timeSize: 12) {
                            onTaskTap(task.id)
                        }
                    }
                }
                .padding(.bottom, TFSpacing.lg)
            }
        }
    }
}
