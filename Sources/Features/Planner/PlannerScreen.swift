import SwiftUI

// Обёртка для использования String в .sheet(item:) — стандартный String не Identifiable.
private struct IdentifiableDate: Identifiable, Equatable {
    let id: String
}

/// Календарь рутин: «Неделя» и «Месяц». Открывается из «Моих рутин»
/// (владелец 28.10.2026: «там смотрим исключительно рутины, проекты уже не
/// смотрим»). Раньше это был общий экран «Планирования» с разделами
/// «Сегодня», «Три дня», задачами и фильтрами; владелец 06.11.2026 оставил
/// из планирования только эти два календаря, остальное удалено.
public struct UpcomingScreen: View {
    @Environment(TaskStore.self) private var taskStore
    @Environment(ProjectStore.self) private var projectStore
    @Environment(RealtimeClient.self) private var realtime

    @State private var routinePlanner = RoutinePlanner()
    @State private var loadedRoutineRevision: Int?
    @State private var selectedOccurrence: RoutineOccurrence?

    /// Владелец 28.10.2026: в календаре только «Неделя» и «Месяц».
    /// Сохранённое у владельца старое значение (`today`, `threeDays`) молча
    /// ведёт на неделю.
    enum ViewMode: String, CaseIterable { case week, month }

    @AppStorage("plannerSection") private var upcomingLayoutRaw = ViewMode.week.rawValue
    private var view: ViewMode {
        get { ViewMode(rawValue: upcomingLayoutRaw) ?? .week }
        nonmutating set { upcomingLayoutRaw = newValue.rawValue }
    }

    @State private var openDay: String?

    @State private var gridMonday = UpcomingDate.mondayOf(UpcomingDate.todayString())
    /// Опциональный: до первого появления экрана и до прихода первого
    /// `onVisibleMonthChange` — пусто. Без этого View запоминал бы месяц
    /// на момент своей инициализации (запуск в августе → в сентябре всё
    /// ещё показывает август).
    @State private var gridMonth: (year: Int, month: Int)? = nil
    private let monthGridInitialMonday = UpcomingDate.mondayOf(UpcomingDate.todayString())

    /// Видимые проекты бывшего «Планирования» (ключ `plannerVisibleProjects`).
    /// Рутины с проектом вне этого списка в календаре не показываются — так
    /// было и до удаления планирования; меню выбора в календаре рутин не
    /// показывалось и раньше.
    private let plannerVisibleProjectIds: Set<String> = Set(
        UserDefaults.standard.stringArray(forKey: "plannerVisibleProjects") ?? []
    )
    /// Пустое хранилище имеет два смысла: на новой установке проекты ещё не
    /// выбирались и надо показать всё; после явного снятия всех галочек пустой
    /// список означает «только беспроектные».
    private let plannerProjectsConfigured =
        UserDefaults.standard.object(forKey: "plannerVisibleProjects") != nil

    /// В шапке — текущий месяц видимого диапазона.
    private var navigationTitle: String {
        switch view {
        case .week:
            return UpcomingDate.monthsNom[UpcomingDate.weekMonth(monday: gridMonday).month]
        case .month:
            return UpcomingDate.monthsNom[(gridMonth ?? UpcomingDate.yearMonth(today)).month]
        }
    }

    public init() {}

    // 15.09.2026: см. карточку задачи — тип экрана стирается на границе,
    // чтобы цепочка обёрток не копила неразворачиваемый обобщённый тип.
    public var body: some View { AnyView(bodyContent) }

    @ViewBuilder private var bodyContent: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tfNativeHeader(navigationTitle, displayMode: .inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 0) {
                    viewSwitcherMenu.tfPlannerWideControl()
                }
            }
        }
        .tfScreenBackground()
        .tfSheet(item: Binding(get: { openDay.map(IdentifiableDate.init) }, set: { _ in openDay = nil })) { day in
            daySheet(date: day.id)
        }
        .tfSheet(item: $selectedOccurrence, onDismiss: { Task { await loadRoutineCalendar() } }) { occurrence in
            NavigationStack { RoutineOccurrenceDestination(occurrence: occurrence) }
        }
        // Календарь рутин — по событиям сокета, а не опросом раз в 30 с.
        // Пачку событий схлопывает пауза: следующее событие отменяет её.
        .task(id: "\(routineRangeAnchor):\(routineRevision)") {
            if loadedRoutineRevision != nil, routineRevision != loadedRoutineRevision {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
            }
            loadedRoutineRevision = routineRevision
            await loadRoutineCalendar()
        }
        .onAppear {
            // Сбрасываем заголовок на месяц «сегодня» каждый раз при появлении
            // экрана (а не только при первом создании View — иначе View,
            // созданный в августе, остаётся с августом и в сентябре).
            gridMonth = UpcomingDate.yearMonth(UpcomingDate.todayString())
        }
    }

    @ViewBuilder
    private var content: some View {
        if taskStore.isLoading {
            TFLoading(.block)
        } else if let error = taskStore.errorMessage {
            TFErrorBanner(error, variant: .block).padding(.horizontal, TFSpacing.screenHorizontal)
        } else {
            if let error = routinePlanner.error {
                TFErrorBanner(error, variant: .inline).padding(.horizontal, TFSpacing.screenHorizontal)
            }
            switch view {
            case .week:
                UpcomingWeekView(
                    monday: gridMonday,
                    occurrences: routineOccurrences, onRoutineTap: { selectedOccurrence = $0 },
                    onDayTap: { openDay = $0 },
                    onPickDate: { gridMonday = UpcomingDate.mondayOf($0) },
                    onPrevWeek: { gridMonday = UpcomingDate.addDays(gridMonday, -7) },
                    onNextWeek: { gridMonday = UpcomingDate.addDays(gridMonday, 7) }
                )
                .refreshable { await refreshPlanner() }
            case .month:
                UpcomingMonthView(
                    initialMonday: monthGridInitialMonday,
                    initialMonth: UpcomingDate.yearMonth(UpcomingDate.todayString()),
                    occurrences: routineOccurrences, onRoutineTap: { selectedOccurrence = $0 },
                    onDayTap: { openDay = $0 },
                    onVisibleMonthChange: { y, m in gridMonth = (y, m) }
                )
                .refreshable { await refreshPlanner() }
            }
        }
    }

    private func refreshPlanner() async {
        await taskStore.load(silent: true)
        await projectStore.load()
        await loadRoutineCalendar()
    }

    /// Нативная шторка: свой `NavigationStack` ради toolbar (крестик слева,
    /// «Готово» справа), системный хендл вместо самодельного (просьба
    /// владельца 03.09.2026 — «пусть Apple сама сделает скругление и
    /// открытие-закрытие»).
    @ViewBuilder
    private func daySheet(date openDay: String) -> some View {
        NavigationStack {
            UpcomingDaySheetContent(
                date: openDay,
                occurrences: routineOccurrences.filter { $0.day() == openDay },
                onRoutineTap: { occurrence in
                    self.openDay = nil
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(400))
                        selectedOccurrence = occurrence
                    }
                }
            )
            .padding(.horizontal, TFSpacing.screenHorizontal)
            // Тот же фон, что заливает себе карточка задачи
            // (`TaskFormScreen`): без него шторка дня оставалась прозрачной и
            // выглядела светлее соседней (владелец 10.09.2026). Это не свой
            // `presentationBackground` поверх системного — просто заливка
            // содержимого, системный хром шторки не трогаем.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .tfScreenBackground()
            .tfNativeHeader(UpcomingDaySheetTitle.text(openDay), displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { self.openDay = nil } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Закрыть")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { self.openDay = nil } label: {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel("Готово")
                }
            }
        }
        .presentationDragIndicator(.visible)
        .presentationDetents([.medium, .large])
        // В половинном состоянии жест уходит списку, а не шторке: тянешь —
        // листается, а поднять на весь экран можно за хендл (владелец
        // 10.09.2026: «как в других местах»).
        .presentationContentInteraction(.scrolls)
    }

    /// Системное меню разделов: «Неделя» и «Месяц».
    private var viewSwitcherMenu: some View {
        Menu {
            Picker("Раздел", selection: Binding(
                get: { view },
                set: { view = $0 }
            )) {
                Label("Неделя", systemImage: "calendar.day.timeline.leading").tag(ViewMode.week)
                Label("Месяц", systemImage: "calendar").tag(ViewMode.month)
            }
            .pickerStyle(.inline)
        } label: {
            TFPlannerToolbarIcon(systemName: "calendar", tint: .tfText)
        }
        .accessibilityLabel("Выбрать раздел планирования")
        .accessibilityIdentifier("planner.view-switcher")
    }

    // MARK: - Данные

    private var today: String { UpcomingDate.todayString() }

    private var routineRangeAnchor: String {
        switch view {
        case .week: return gridMonday
        case .month:
            let month = gridMonth ?? UpcomingDate.yearMonth(today)
            return String(format: "%04d-%02d-01", month.year, month.month + 1)
        }
    }

    private var routineOccurrences: [RoutineOccurrence] {
        RoutineScheduleProjection.visible(routinePlanner.occurrences, projects: effectivePlannerVisibleProjectIds)
    }

    /// Статус вхождения рутины берётся из её задачи, поэтому календарь
    /// перечитывается и по событиям задач.
    private var routineRevision: Int {
        realtime.staleRevision + realtime.taskRevisions.values.reduce(0, +)
    }

    private func loadRoutineCalendar() async {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let anchor = formatter.date(from: routineRangeAnchor),
              let from = Calendar.current.date(byAdding: .day, value: -7, to: anchor),
              let until = Calendar.current.date(byAdding: .day, value: 63, to: anchor) else { return }
        await routinePlanner.load(from: from, until: until)
    }

    private var effectivePlannerVisibleProjectIds: Set<String> {
        guard plannerProjectsConfigured else {
            // Сторы могут прийти не одновременно: не скрываем рутины, пока
            // список проектов ещё не успел загрузиться.
            return Set(projectStore.projects.map(\.id))
                .union(taskStore.tasks.compactMap(\.projectId))
        }
        return plannerVisibleProjectIds
    }
}

extension View {
    /// Кнопка в шапке «Планирования» — шире общей `tfPlannerToolbarControl`
    /// (32×32): владелец 10.09.2026 просил «пилюлю чуть пошире, чтобы удобно
    /// было пальцем нажимать». Общий размер из `TFNativeHeader.swift` не
    /// трогаем — он одинаковый на всех остальных экранах.
    func tfPlannerWideControl() -> some View {
        frame(width: 44, height: 34)
    }
}

/// Заголовок `DaySheet` — «20 августа», отдельно от общей `UpcomingDate`,
/// т.к. нужен только шапке шторки (сама шторка использует общий `TFBottomSheetContent`).
enum UpcomingDaySheetTitle {
    static func text(_ date: String) -> String {
        let (_, month) = UpcomingDate.yearMonth(date)
        let weekday = UpcomingDate.weekdaysFull[UpcomingDate.monFirst(UpcomingDate.jsWeekday(date))].lowercased()
        return "\(UpcomingDate.day(date)) \(UpcomingDate.monthsGen[month]), \(weekday)"
    }
}
