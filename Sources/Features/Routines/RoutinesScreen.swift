import SwiftUI

// «Мои рутины» — список рутин (крон-задач).
// Экран по макетам дизайна (заметка «Рутины и расписание TaskFlow», п. 2.6):
// строка рутины, свайп по строке — пауза, запуск сейчас, удаление; тап по
// строке — задание и настройки; история доступна внутри редактора. Отдельная вкладка не заводится: вкладок у
// клиента четыре, «Мои рутины» — строка на «Обзоре».
struct RoutinesScreen: View {
    @State private var model = RoutinesViewModel()
    @State private var pendingDelete: ApiSchedule?
    @State private var isCreating = false
    @State private var isShowingPlan = false

    var body: some View {
        list
            .listStyle(.plain)
            .tint(Color.tfText)
            .tfNativeHeader("Мои рутины", displayMode: .inline)
            .toolbar {
                // Владелец 28.10.2026: вместо плюса — троеточие, а внутрь
                // переехали календарь и создание рутины. Календарь здесь как
                // раз тот самый «План», который переехал в рутины.
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            isShowingPlan = true
                        } label: {
                            Label("Календарь", systemImage: "calendar")
                        }
                        .accessibilityIdentifier("routines.calendar")
                        Button {
                            isCreating = true
                        } label: {
                            Label("Новая рутина", systemImage: "plus")
                        }
                        .accessibilityIdentifier("routines.create")
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("Ещё")
                    .accessibilityIdentifier("routines.more")
                }
            }
            .navigationDestination(isPresented: $isCreating) {
                RoutineFormScreen()
            }
            .navigationDestination(isPresented: $isShowingPlan) {
                UpcomingScreen(routinesOnly: true)
            }
            .task { await model.load() }
            .refreshable { await model.load() }
            .alert("Удалить рутину?", isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            )) {
                Button("Удалить", role: .destructive) {
                    if let schedule = pendingDelete {
                        Task { await model.delete(schedule) }
                    }
                    pendingDelete = nil
                }
                Button("Отмена", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("Задачи, которые рутина уже создала, останутся на месте.")
            }
    }

    @ViewBuilder
    private var list: some View {
        List {
            if let notice = model.notice {
                Section {
                    Text(notice)
                        .tfText(.action)
                        .foregroundStyle(Color.tfSub)
                }
                .listRowSeparator(.hidden)
            }
            if let error = model.errorMessage {
                Section {
                    TFErrorBanner(error, variant: .block)
                    Button("Повторить") { Task { await model.load() } }
                        .tfText(.action)
                        .foregroundStyle(Color.tfText)
                }
                .listRowSeparator(.hidden)
            }
            if model.isLoading && model.schedules.isEmpty {
                ForEach(0..<3, id: \.self) { _ in
                    RoutineRowSkeleton()
                        .listRowSeparator(.hidden)
                }
            } else if model.schedules.isEmpty {
                Section {
                    TFEmptyState(
                        icon: "arrow.triangle.2.circlepath",
                        text: "Рутин пока нет",
                        description: "Рутина сама создаёт задачу в заданное время",
                        actionTitle: "Создать рутину"
                    ) {
                        isCreating = true
                    }
                    .listRowSeparator(.hidden)
                }
            } else {
                ForEach(model.schedules) { schedule in
                    NavigationLink {
                        RoutineFormScreen(schedule: schedule)
                    } label: {
                        RoutineRow(schedule: schedule, roleTitle: model.roleTitle(for: schedule.taskPayload.assigneeId))
                    }
                    .accessibilityIdentifier("routines.row.\(schedule.id)")
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button {
                            Task { await model.setPaused(schedule, paused: !schedule.isPaused) }
                        } label: {
                            Label(schedule.isPaused ? "Возобновить" : "Пауза", systemImage: schedule.isPaused ? "play" : "pause")
                        }
                        .accessibilityLabel(schedule.isPaused ? "Возобновить" : "Пауза")
                        .tint(schedule.isPaused ? Color.tfGreen : Color.tfSub)
                        Button {
                            Task { await model.runNow(schedule) }
                        } label: {
                            Label("Запустить сейчас", systemImage: "play.circle")
                        }
                        .accessibilityLabel("Запустить сейчас")
                        .tint(Color.tfBlue)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            pendingDelete = schedule
                        } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                        // Нейтральный `.tint(Color.tfText)` у списка иначе
                        // перекрашивает и смахивание: кнопка удаления выходила
                        // белым кружком вместо красной (владелец 23.10.2026).
                        // Цвет тот же, что у свайпа-удаления в списках задач.
                        .accessibilityLabel("Удалить")
                        .tint(Color.tfSwipeDelete)
                    }
                }
            }
        }
    }
}

/// Строка рутины: название, правило, следующий запуск.
private struct RoutineRow: View {
    let schedule: ApiSchedule
    /// Имя роли-исполнителя (по ключу из шаблона рутины).
    let roleTitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.xs) {
            HStack(spacing: TFSpacing.sm) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.tfDim)
                Text(schedule.title)
                    .tfText(.taskTitle)
                    .foregroundStyle(Color.tfText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if schedule.isPaused {
                    Text("На паузе")
                        .tfText(.caption)
                        .foregroundStyle(Color.tfSub)
                        .padding(.horizontal, TFSpacing.sm)
                        .padding(.vertical, TFSpacing.xs)
                        .background(Color.tfCard2)
                        .clipShape(RoundedRectangle(cornerRadius: TFRadius.pill))
                }
            }
            Text(ruleSummary)
                .tfText(.action)
                .foregroundStyle(Color.tfSub)
                .lineLimit(2)
            HStack(alignment: .firstTextBaseline) {
                Text("След. запуск")
                    .tfText(.caption)
                    .foregroundStyle(Color.tfDim)
                Spacer(minLength: TFSpacing.sm)
                Text(nextRunText)
                    .tfText(.meta)
                    .foregroundStyle(Color.tfText)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.vertical, TFSpacing.md)
        .frame(minHeight: TFHitTarget.min)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    /// Правило и время — той же формулировкой, что в вебе: подпись правила с
    /// сервера плюс время запуска.
    private var ruleSummary: String {
        let label = RoutineFormat.ruleLabel(for: schedule)
        let base = schedule.ruleKind == "interval" ? label : "\(label) в \(schedule.timeLocal)"
        if let roleTitle, !roleTitle.isEmpty {
            return "\(base) · \(roleTitle)"
        }
        return base
    }

    private var nextRunText: String {
        if schedule.isPaused {
            if let last = RoutineFormat.lastRunLabel(lastRunAt: schedule.lastRunAt, timezone: schedule.timezone) {
                return "Последний запуск: \(last)"
            }
            return "На паузе"
        }
        return RoutineFormat.nextRunLabel(nextRunAt: schedule.nextRunAt, timezone: schedule.timezone) ?? "—"
    }

    private var accessibilityText: String {
        var parts = [schedule.title, RoutineFormat.ruleLabel(for: schedule)]
        parts.append(nextRunText)
        if schedule.isPaused { parts.append("на паузе") }
        return parts.joined(separator: ", ")
    }
}

/// Скелет строки на время загрузки — три строки без скачка высоты.
private struct RoutineRowSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            RoundedRectangle(cornerRadius: TFRadius.sm)
                .fill(Color.tfCard2)
                .frame(height: 18)
            RoundedRectangle(cornerRadius: TFRadius.sm)
                .fill(Color.tfCard2)
                .frame(height: 14)
            RoundedRectangle(cornerRadius: TFRadius.sm)
                .fill(Color.tfCard2)
                .frame(height: 12)
        }
        .padding(.vertical, TFSpacing.md)
        .accessibilityLabel("Загрузка рутин")
    }
}
