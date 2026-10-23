import SwiftUI

// История запусков рутины: «когда — что вышло». Для созданной карточки —
// переход в неё; для пропуска и ошибки — причина (дизайн, п. 2.6).
struct RoutineRunsScreen: View {
    let schedule: ApiSchedule
    @State private var model = RoutineRunsViewModel()

    var body: some View {
        list
            .listStyle(.plain)
            .tfNativeHeader("История запусков", displayMode: .inline)
            .task { await model.load(scheduleID: schedule.id) }
            .refreshable { await model.load(scheduleID: schedule.id) }
    }

    @ViewBuilder
    private var list: some View {
        List {
            if let error = model.errorMessage {
                Section {
                    TFErrorBanner(error, variant: .block)
                    Button("Повторить") { Task { await model.load(scheduleID: schedule.id) } }
                        .tfText(.action)
                        .foregroundStyle(Color.tfText)
                }
                .listRowSeparator(.hidden)
            }
            if model.isLoading && model.runs.isEmpty {
                Section {
                    TFLoading(.inline)
                }
                .listRowSeparator(.hidden)
            } else if model.runs.isEmpty {
                Section {
                    TFEmptyState(text: "Запусков ещё не было")
                        .listRowSeparator(.hidden)
                }
            } else {
                ForEach(model.runs) { run in
                    if let taskID = run.taskId {
                        NavigationLink {
                            TaskFormScreen(taskID: taskID, isPushedInNavigationStack: true)
                        } label: {
                            RoutineRunRow(run: run, timezone: schedule.timezone)
                        }
                    } else {
                        RoutineRunRow(run: run, timezone: schedule.timezone)
                    }
                }
            }
        }
    }
}

private struct RoutineRunRow: View {
    let run: ApiScheduleRun
    let timezone: String

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.xs) {
            HStack {
                Text(RoutineFormat.runStatusTitle(run.status))
                    .tfText(.row)
                    .foregroundStyle(Color.tfText)
                Spacer(minLength: 0)
                Text(whenText)
                    .tfText(.meta)
                    .foregroundStyle(Color.tfSub)
            }
            if let detail = run.detail, !detail.isEmpty {
                Text(detail)
                    .tfText(.action)
                    .foregroundStyle(Color.tfSub)
            }
        }
        .padding(.vertical, TFSpacing.md)
        .frame(minHeight: TFHitTarget.min)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(RoutineFormat.runStatusTitle(run.status)), \(whenText)")
    }

    private var whenText: String {
        guard let date = DateFormats.iso8601(run.runAt) else { return run.runAt }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = TimeZone(identifier: timezone) ?? .current
        formatter.dateFormat = "dd.MM, HH:mm"
        return formatter.string(from: date)
    }
}
