import SwiftUI

struct RoutineOccurrenceRow: View {
    let occurrence: RoutineOccurrence
    var compact = false
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: TFSpacing.xs) {
                Image(systemName: occurrence.status == "scheduled" ? "clock.arrow.circlepath" : "bolt.circle")
                VStack(alignment: .leading, spacing: TFSpacing.xs) {
                    Text(occurrence.title).tfText(compact ? .micro : .action).lineLimit(compact ? 1 : 2)
                    if !compact {
                        Text("\(occurrence.timeLabel) · \(occurrence.timezone) · \(status)")
                            .tfText(.caption).foregroundStyle(Color.tfSub)
                    }
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.tfText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, compact ? 0 : TFSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Автоматизация: \(occurrence.title), \(occurrence.timeLabel), \(status)")
        .accessibilityIdentifier("routine.occurrence.\(occurrence.id)")
    }

    private var status: String {
        switch occurrence.status {
        case "scheduled": "По расписанию"
        case "created": "Запуск"
        case "skipped": "Пропущено"
        case "error", "failed": "Ошибка"
        default: occurrence.status
        }
    }
}

/// Future entry opens the automation; an execution opens its real task.
struct RoutineOccurrenceDestination: View {
    let occurrence: RoutineOccurrence
    @State private var schedule: ApiSchedule?
    @State private var error: String?
    @State private var cardTaskID: String?

    var body: some View {
        Group {
            if let taskId = occurrence.taskId {
                TFLoading(.block)
                    .onAppear { cardTaskID = taskId }
                    .taskCardSheet(taskID: $cardTaskID)
            } else if let schedule {
                RoutineFormScreen(schedule: schedule)
            } else if let error {
                TFErrorBanner(error, variant: .block)
            } else {
                TFLoading(.block)
            }
        }
        .task {
            guard occurrence.taskId == nil else { return }
            do {
                let response: ApiScheduleResponse = try await APIClient().request(.get, "/schedules/\(occurrence.scheduleId)")
                schedule = response.schedule
            } catch { self.error = error.localizedDescription }
        }
    }
}
