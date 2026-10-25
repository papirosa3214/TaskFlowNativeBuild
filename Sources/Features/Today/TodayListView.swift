import SwiftUI

// Все категории задач и расписание рутин в одной прокрутке с закрепляемыми заголовками.
struct TodayListView: View {
    let tab: TodayListTab
    let waitingTasks: [ApiTask]
    let overdueTasks: [ApiTask]
    let todayTasks: [ApiTask]
    let upcomingTasks: [ApiTask]
    let poolTasks: [ApiTask]
    let today: String
    var routineOccurrences: [RoutineOccurrence] = []
    var onOpenRoutine: (RoutineOccurrence) -> Void = { _ in }
    let onOpen: (ApiTask) -> Void
    let onComplete: (ApiTask) -> Void
    let onDelete: (ApiTask) -> Void
    /// Заголовок секции, которая сейчас закреплена у верхней кромки, — он
    /// уезжает в шапку экрана. Пусто, когда лента в самом начале или секция
    /// всего одна: тогда в шапке остаётся название вкладки.
    var onPinnedSectionChange: (String) -> Void = { _ in }
    /// Верхняя кромка прокрутки в координатах экрана — та высота, на которой
    /// заголовок секции прилипает. Приходит от владельца прокрутки: изнутри
    /// её не вычислить, а константой брать нельзя — замер показал 122pt там,
    /// где «безопасная зона плюс навбар» давали 113pt.
    var pinEdge: CGFloat = 0
    /// true — свайп действия строки начинается только в крайних зонах.
    /// Включается только в «Планировании»; обычный экран «Сегодня» сохраняет
    /// свайп по всей ширине строки.
    var swipeOnlyAtEdges: Bool = false
    var horizontalEdgeZone: CGFloat = HorizontalPanZones.defaultEdgeWidth

    @Environment(SessionStore.self) private var session
    @Environment(TaskStore.self) private var taskStore
    @State private var swipeActionError: String?
    /// Верх каждого заголовка в координатах экрана. Считается, какой из них
    /// сейчас прилип к кромке: владелец 15.09.2026 просил, чтобы подзаголовки
    /// не были захардкожены, а «когда они подходят, появлялись в центре» —
    /// то есть в шапке всегда стоит та секция, которую он сейчас читает.
    ///
    /// Лежит в ссылочном хранилище, а НЕ в `@State`: запись идёт на каждый
    /// кадр прокрутки, и запись в `@State` инвалидировала весь экран — с
    /// пересборкой секций заново на каждом кадре. В шапку название попадает
    /// через `onPinnedSectionChange` — состояние шапки у родителя.
    @State private var sectionTops = SectionTops()

    /// Москва — зона календарных дат в приложении. Создаётся один раз, а не
    /// на каждое вхождение рутины в списке.
    private static let moscow = TimeZone(identifier: "Europe/Moscow")!

    /// Верхние границы секций — вне состояния SwiftUI.
    private final class SectionTops {
        private let lock = NSLock()
        private var storage: [String: CGFloat] = [:]

        var snapshot: [String: CGFloat] {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }

        func set(_ top: CGFloat, for id: String) {
            lock.lock()
            defer { lock.unlock() }
            storage[id] = top
        }
    }

    private let apiClient = APIClient()

    private var sections: [TodayListSection] {
        TodayListSection.sections(
            tab: tab,
            waiting: waitingTasks,
            overdue: overdueTasks,
            today: todayTasks,
            upcoming: upcomingTasks,
            pool: poolTasks,
            todayDate: today,
            occurrences: routineOccurrences
        )
    }

    var body: some View {
        let visible = sections
        List {
            TFErrorBanner(swipeActionError, variant: .inline)
                .padding(.horizontal, TFSpacing.lg)

                ForEach(visible) { section in
                    Section {
                        ForEach(section.occurrences) { occurrence in
                            VStack(alignment: .leading, spacing: 0) {
                                Text(occurrence.day(in: Self.moscow) ?? "")
                                    .tfText(.caption).foregroundStyle(Color.tfSub)
                                RoutineOccurrenceRow(occurrence: occurrence) { onOpenRoutine(occurrence) }
                            }
                            .padding(.horizontal, TFSpacing.lg)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                        }
                        ForEach(section.tasks) { task in
                            row(task, overdue: section.marksOverdue)
                                .listRowInsets(EdgeInsets())
                        }
                    } header: {
                        // Единственная секция вкладки заголовка не получает:
                        // он дублировал бы название самой вкладки в шапке.
                        // Исключение — секции, которым подпись нужна всегда
                        // (см. `TodayListSection.showsHeader`).
                        if section.showsHeader(among: visible) {
                            header(section)
                                .background(sectionTopReader(section, visible: visible))
                        }
                    }
                }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    /// Замеряет верх заголовка секции в координатах экрана.
    private func sectionTopReader(_ section: TodayListSection, visible: [TodayListSection]) -> some View {
        GeometryReader { proxy in
            Color.clear
                .onGeometryChange(for: CGFloat.self) { _ in
                    proxy.frame(in: .global).minY
                } action: { top in
                    // Считаем по свежему снимку: присвоенное значение в этом
                    // же проходе ещё содержит прошлое.
                    sectionTops.set(top, for: section.id)
                    reportPinnedSection(with: visible)
                }
        }
    }

    /// Прилипший заголовок стоит ровно у кромки прокрутки, а те, что ниже,
    /// ещё не дошли. Значит текущая секция — самая нижняя из тех, чей верх
    /// уже не ниже кромки. Пока до кромки не дошла ни одна, в шапке остаётся
    /// название вкладки.
    private func reportPinnedSection(with visible: [TodayListSection]) {
        let tops = sectionTops.snapshot
        guard visible.count > 1, pinEdge > 0 else {
            onPinnedSectionChange("")
            return
        }
        // Закреплённый заголовок стоит ровно на верхней кромке прокрутки,
        // ушедшие наверх — выше неё, не дошедшие — ниже. Значит нужен
        // последний из тех, кто кромку уже достиг. Допуск в пару точек:
        // у прилипшего заголовка верх подрагивает на доли точки.
        let edge = pinEdge + 2
        let passed = visible.filter { (tops[$0.id] ?? .greatestFiniteMagnitude) <= edge }
        onPinnedSectionChange(passed.last?.title ?? "")
    }

    private func row(_ task: ApiTask, overdue: Bool) -> some View {
        let swipeAction = TodayTaskSwipeAction.action(
            for: task,
            isOwner: session.currentUser?.role == .owner,
            currentUserID: session.currentUser?.id
        )
        return TodayTaskRow(task: task, overdue: overdue,
                            onOpen: { onOpen(task) },
                            onDelete: { onDelete(task) },
                            swipeAction: swipeAction,
                            swipeOnlyAtEdges: swipeOnlyAtEdges,
                            horizontalEdgeZone: horizontalEdgeZone,
                            onSwipeAction: {
                                guard let swipeAction else { return }
                                Task { await perform(swipeAction, for: task) }
                            })
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

            }
        } catch is CancellationError {
            // Экран пересобрался (смена формата «Список»/«Один день» и
            // т.п.) быстрее, чем действие успело доехать — запрос отменился
            // штатно, показывать баннер не о чем.
        } catch {
            swipeActionError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func header(_ section: TodayListSection) -> some View {
        HStack(spacing: 6) {
            if let icon = section.icon {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(section.color)
            }
            // Владелец 26.10.2026: подзаголовки «Планирования» — те же, что
            // подзаголовки карточки задачи («Задача», «План», «Лента
            // активности»). В карточке это `taskSectionHeader(_:)`
            // (`TaskFormScreen.swift`): `.tfText(.taskTitle)` — системный
            // шрифт, 20 pt, semibold, цвет `tfText` (белый в тёмной теме).
            // Решение 12.10.2026 («заголовки как везде», 13 pt `tfSub`)
            // владелец 26.10.2026 отменил.
            Text(section.title)
                .tfText(.taskTitle)
                .foregroundStyle(Color.tfText)
                .textCase(nil)
        }
        .padding(.horizontal, TFSpacing.lg)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Подложка прозрачная — по просьбе владельца 26.10.2026 (то же, что
        // он просил 03.09.2026 и как у заголовков диапазонов в
        // `UpcomingListView.dateHeader(_:)`): закреплённый заголовок не
        // должен резать ленту чёрной полосой. Непрозрачная подложка
        // `Color.tfBackground` проскочила в ревизии списка 24.10.2026
        // (`9b284a62`), когда заголовки переехали из `LazyVStack` в `List`.
    }
}

// MARK: - Состав секций

struct TodayListSection: Identifiable, Equatable {
    let id: String
    let title: String
    let icon: String?
    let color: Color
    let tasks: [ApiTask]
    /// Строки рисуются «просроченными» — красная дата, как было на доске.
    let marksOverdue: Bool
    /// Заголовок секции нужен даже тогда, когда она в ленте единственная.
    /// Владелец 18.10.2026: «Предстоящие» — подзаголовок вкладки «Сегодня»,
    /// ровно как «Просрочено» во вкладке «Ждут вас»; без подзаголовка задачи
    /// стояли прямо под названием вкладки и читались как сегодняшние.
    let alwaysShowsHeader: Bool
    var occurrences: [RoutineOccurrence] = []

    /// Единственная секция вкладки заголовок не получает: он дублировал бы
    /// название самой вкладки в шапке. Секции с `alwaysShowsHeader` — всегда.
    func showsHeader(among visible: [TodayListSection]) -> Bool {
        visible.count > 1 || alwaysShowsHeader
    }

    static func == (lhs: TodayListSection, rhs: TodayListSection) -> Bool {
        lhs.id == rhs.id && lhs.tasks == rhs.tasks && lhs.occurrences == rhs.occurrences
    }

    /// Единственное место, где решается состав вкладок. Наборы задач сюда
    /// приходят уже посчитанными и дедуплицированными в `TodayComputation`
    /// («Ждут вас» вычтены из остальных) — пересчитывать их здесь нельзя,
    /// иначе одна задача покажется в двух секциях.
    static func sections(
        tab: TodayListTab,
        waiting: [ApiTask],
        overdue: [ApiTask],
        today: [ApiTask],
        upcoming: [ApiTask],
        pool: [ApiTask],
        todayDate: String,
        occurrences: [RoutineOccurrence] = []
    ) -> [TodayListSection] {
        var all: [TodayListSection]
        switch tab {
        case .inbox:
            // «Входящие — это и есть без даты, они не распределены»
            // (владелец 15.09.2026).
            all = [.init(id: "pool", title: "Входящие", icon: nil,
                         color: .tfSub, tasks: pool, marksOverdue: false,
                         alwaysShowsHeader: false)]
        case .attention:
            all = [
                .init(id: "waiting", title: "Ждут вас", icon: nil,
                      color: .tfSub, tasks: waiting, marksOverdue: false,
                      alwaysShowsHeader: false),
                .init(id: "overdue", title: "Просрочено", icon: nil,
                      color: .tfRed, tasks: overdue, marksOverdue: true,
                      alwaysShowsHeader: false)
            ]
        case .today:
            all = [
                .init(id: "pool", title: "Входящие", icon: nil,
                      color: .tfSub, tasks: pool, marksOverdue: false, alwaysShowsHeader: true),
                .init(id: "waiting", title: "Ждут вас", icon: nil,
                      color: .tfSub, tasks: waiting, marksOverdue: false, alwaysShowsHeader: true),
                .init(id: "overdue", title: "Просроченные", icon: nil,
                      color: .tfRed, tasks: overdue, marksOverdue: true, alwaysShowsHeader: true),
                .init(id: "today", title: TodayDate.formatDueLabel(todayDate), icon: nil,
                      color: .tfSub, tasks: today, marksOverdue: false,
                      alwaysShowsHeader: true),
                .init(id: "upcoming", title: "Предстоящие", icon: nil,
                      color: .tfSub, tasks: upcoming, marksOverdue: false,
                      alwaysShowsHeader: true)
            ]
        }
        if tab == .today {
            let zone = TimeZone(identifier: "Europe/Moscow")!
            // Только будущие виртуальные появления; исполненные — обычные задачи из стора.
            for occurrence in RoutineScheduleProjection.visible(occurrences, projects: nil) {
                guard occurrence.taskId == nil, occurrence.status == "scheduled",
                      let day = occurrence.day(in: zone), day >= todayDate else { continue }
                let sectionID = day == todayDate ? "today" : "upcoming"
                if let index = all.firstIndex(where: { $0.id == sectionID }) {
                    all[index].occurrences.append(occurrence)
                }
            }
        }
        return all.filter { !$0.tasks.isEmpty || !$0.occurrences.isEmpty }
    }
}
