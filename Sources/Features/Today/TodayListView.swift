import SwiftUI

// Вид «Список» — ровно сегодняшний день, одна секция с дата-заголовком.
// Владелец 09.09.2026: «в списке сегодня я вижу только сегодня… открыл и
// больше ни на что не отвлекался». «Просрочено» и «Ждут вас» переехали
// целиком в «Доску» — там же к ним добавились «Предстоящие».
// `AppleCalendarEvents` (события календаря устройства) — вне спеки Волны 1
// (`spec/NATIVE-PARTS.md` относит интеграцию с системным календарём к
// более поздней волне), здесь не рисуется.
struct TodayListView: View {
    let todayTasks: [ApiTask]
    let today: String
    let onOpen: (ApiTask) -> Void
    let onComplete: (ApiTask) -> Void
    let onDelete: (ApiTask) -> Void

    private var sections: [TodaySectionInfo] {
        TodaySectionInfo.list(today: todayTasks, todayDate: today)
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
            Section {
                ForEach(todayTasks) { task in
                    TodayTaskRow(task: task, overdue: false,
                                 onOpen: { onOpen(task) }, onComplete: { onComplete(task) },
                                 onDelete: { onDelete(task) })
                }
            } header: {
                header(.today)
            }
        }
    }

    @ViewBuilder
    private func header(_ kind: TodaySectionKind) -> some View {
        let secs = sections
        if let index = secs.firstIndex(where: { $0.kind == kind }) {
            let info = secs[index]
            HStack(spacing: 6) {
                if let icon = info.icon {
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundStyle(info.color)
                }
                Text(info.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(info.color)
            }
            .padding(.horizontal, TFSpacing.lg)
            .padding(.top, 8)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Состав секций

enum TodaySectionKind: Equatable { case today }

struct TodaySectionInfo: Equatable {
    let kind: TodaySectionKind
    let title: String
    let icon: String?
    let color: Color

    /// Единственное место, где решается состав секций. С 09.09.2026 в списке
    /// она ровно одна — сегодняшний день; «Просрочено» и «Ждут вас» живут
    /// колонками на доске.
    static func list(today: [ApiTask], todayDate: String) -> [TodaySectionInfo] {
        guard !today.isEmpty else { return [] }
        return [.init(kind: .today, title: TodayDate.formatDueLabel(todayDate),
                      icon: nil, color: .tfSub)]
    }
}
