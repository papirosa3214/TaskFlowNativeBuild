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

    @Environment(SessionStore.self) private var session
    @Environment(TaskStore.self) private var taskStore
    @State private var swipeActionError: String?

    private let apiClient = APIClient()

    private var sections: [TodaySectionInfo] {
        TodaySectionInfo.list(today: todayTasks, todayDate: today)
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
            TFErrorBanner(swipeActionError, variant: .inline)
                .padding(.horizontal, TFSpacing.lg)
            Section {
                ForEach(todayTasks) { task in
                    let swipeAction = TodayTaskSwipeAction.action(
                        for: task,
                        isOwner: session.currentUser?.role == .owner
                    )
                    TodayTaskRow(task: task, overdue: false,
                                 onOpen: { onOpen(task) },
                                 onDelete: { onDelete(task) },
                                 swipeAction: swipeAction,
                                 onSwipeAction: {
                                    guard let swipeAction else { return }
                                    Task { await perform(swipeAction, for: task) }
                                 })
                }
            } header: {
                header(.today)
            }
        }
    }

    private func perform(_ action: TodayTaskSwipeAction, for task: ApiTask) async {
        swipeActionError = nil
        do {
            switch action {
            case .complete:
                onComplete(task)
            case .acceptReview:
                try await apiClient.approveCurrentTaskVersion(taskID: task.id)
                _ = try await apiClient.setTaskAgentState(id: task.id, state: nil)
                _ = try await apiClient.patchTask(id: task.id, fields: ["status": .string("completed")])
                await taskStore.load(silent: true)
            case .markReadyForPickup:
                _ = try await apiClient.patchTask(id: task.id, fields: ["ready_for_pickup": .bool(true)])
                await taskStore.load(silent: true)
            }
        } catch {
            swipeActionError = (error as? APIError)?.errorDescription ?? error.localizedDescription
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
                    .tfText(.title)
                    .fontWeight(.semibold)
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
