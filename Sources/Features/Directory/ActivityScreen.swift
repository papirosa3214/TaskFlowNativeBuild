import SwiftUI

// «Активность» — spec/SCREENS-2.md §12, `/activity`. Данные — целиком из
// уже прогретого `TaskStore.tasks` (тот же приём, что `OverviewScreen`):
// у сервера нет ни фильтра по периоду, ни по проекту/метке/исполнителю
// (`GET /tasks` отдаёт список целиком, spec/API.md §5.1) — весь подсчёт,
// группировка и фильтрация клиентские, портированы из живого
// `src/screens/ActivityScreen.tsx` (только чтение, спека сама формул не
// даёт). Заголовок компактный со стрелкой назад — по кадру `activity.png`,
// хотя §12 пишет «large»: кадр авторитетнее (ARCHITECTURE.md правило 3).
struct ActivityScreen: View {
    @Environment(TaskStore.self) private var taskStore

    @State private var period: ActivityPeriod = .week
    @State private var projectId: String?
    @State private var labelId: String?
    /// nil — все, "__none" — без исполнителя, иначе id пользователя.
    @State private var assigneeKey: String?
    @State private var route: AppRoute?

    private var today: String { DirectoryDate.todayKeyLocal() }
    private var yesterday: String { DirectoryDate.addDaysLocal(today, -1) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: TFSpacing.md) {
                TFErrorBanner(taskStore.errorMessage, variant: .inline)
                    .padding(.horizontal, TFSpacing.screenHorizontal)

                ActivityChart(tasks: filteredAllTasks, period: period)
                    .padding(.horizontal, TFSpacing.screenHorizontal)

                if !showTrueEmpty {
                    Text(summaryText)
                        .tfText(.action)
                        .foregroundStyle(Color.tfSub)
                        .padding(.horizontal, TFSpacing.screenHorizontal + 4)
                }

                if showTrueEmpty {
                    TFEmptyState(icon: "checkmark", text: "Пока ничего не выполнено")
                        .padding(.top, TFSpacing.xl)
                    Text("Задачи, которые вы отметите выполненными, появятся здесь — и их всегда можно будет вернуть в работу")
                        .tfText(.caption).foregroundStyle(Color.tfDim)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, TFSpacing.xl)
                        .frame(maxWidth: .infinity)
                } else if showFilteredEmpty {
                    filteredEmptyState
                } else {
                    ForEach(groups, id: \.key) { group in
                        VStack(alignment: .leading, spacing: TFSpacing.sm) {
                            Text(group.label).tfText(.action).foregroundStyle(Color.tfSub)
                                .padding(.horizontal, TFSpacing.screenHorizontal + 4)
                            VStack(spacing: TFSpacing.sm) {
                                ForEach(group.tasks, id: \.id) { task in
                                    completedRow(task)
                                }
                            }
                            .padding(.horizontal, TFSpacing.screenHorizontal)
                        }
                    }
                }
            }
            .padding(.top, TFSpacing.sm)
            .padding(.bottom, TFSpacing.xl)
        }
        .refreshable {
            await taskStore.load(silent: true)
        }
        .background(Color.tfBackground)
        // Штатная SwiftUI-шапка. Назад рисует сам NavigationStack; в toolbar
        // остаётся только фильтр. Было ручное `.toolbarBackground` — просьба
        // владельца 03.09.2026 («нативные кнопки, нативный фильтр везде
        // одним элементом») — `tfNativeHeader`, как на остальных экранах.
        .tfNativeHeader("Статистика")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                filterMenu
            }
        }
        .taskCardNavigation(route: $route)
    }

    // MARK: - Строка выполненной задачи

/// Владелец 11.10.2026: карточки закрытых задач переделаны в строку —
/// (1) без зачёркивания названия: зачёркнутый список читался как «остановленное»,
/// и было не видно, что именно надо вернуть в работу; (2) в одну строку вместо
/// двух — под названием не было тяжёлой красной полосы «Вернуть в работу» на всю
/// ширину; (3) возврат в работу — свайпом влево, как на экране «Архив», поэтому
/// взята та же самая `DirectoryTaskRow` со свайп-действием `.restore`.
/// Свайп вправо — в архив (дефолт самой строки, с подтверждением).
private func completedRow(_ task: ApiTask) -> some View {
    DirectoryTaskRow(
        index: nil,
        task: task,
        isOwner: true,
        onOpen: { route = .taskDetail(taskID: task.id) },
        onDelete: { Task { _ = await taskStore.delete(taskId: task.id) } },
        swipeAction: .restore,
        onSwipeAction: { Task { await restore(task) } },
        showsAvatar: false,
        strikesDoneTitle: false,
        timestamp: completionTime(task)
    )
}

    private func completionTime(_ task: ApiTask) -> String? {
        guard let raw = task.completedAt ?? (task.status == .completed ? task.updatedAt : nil),
              let date = DateFormats.sqliteUTC(raw) else { return nil }
        return DirectoryDate.timeLocal(date)
    }

    private func restore(_ task: ApiTask) async {
        await taskStore.patch(taskId: task.id, fields: ["status": .string("active")]) { _ in }
    }

    // MARK: - Пустое состояние «под фильтры ничего не подошло»

    private var filteredEmptyState: some View {
        TFEmptyState(
            icon: "list.bullet",
            text: "Под выбранные фильтры ничего не подошло. Попробуйте изменить период или сбросить фильтры.",
            actionTitle: "Сбросить фильтры",
            action: { resetFilters() }
        )
        .padding(.top, TFSpacing.xl)
        .padding(.horizontal, TFSpacing.xl)
        .frame(maxWidth: .infinity)
    }

    private func resetFilters() {
        projectId = nil
        labelId = nil
        assigneeKey = nil
        period = .week
    }

    // MARK: - Данные (портировано 1:1 из ActivityScreen.tsx)

    private var completed: [ApiTask] { taskStore.tasks.filter { $0.status == .completed } }

    private func completionDate(_ task: ApiTask) -> Date? {
        guard let raw = task.completedAt ?? (task.status == .completed ? task.updatedAt : nil) else { return nil }
        return DateFormats.sqliteUTC(raw)
    }

    /// Скользящее окно (сейчас − N дней), не календарный месяц/неделя —
    /// «неделя» значит «последние 7 дней».
    private var periodCutoff: Date {
        let now = Date()
        let cal = Calendar.current
        switch period {
        case .week: return cal.date(byAdding: .day, value: -7, to: now) ?? now
        case .month:
            let comps = cal.dateComponents([.year, .month], from: now)
            return cal.date(from: comps) ?? now
        case .quarter: return cal.date(byAdding: .day, value: -90, to: now) ?? now
        case .year:
            var comps = DateComponents(); comps.year = cal.component(.year, from: now); comps.month = 1; comps.day = 1
            return cal.date(from: comps) ?? now
        }
    }

    private func matchesFilters(_ t: ApiTask) -> Bool {
        if let projectId, t.projectId != projectId { return false }
        if let labelId, !t.labels.contains(where: { $0.id == labelId }) { return false }
        if assigneeKey == "__none" {
            if t.assigneeId != nil { return false }
        } else if let assigneeKey, t.assigneeId != assigneeKey {
            return false
        }
        return true
    }

    private var filtered: [ApiTask] {
        let cutoff = periodCutoff
        return completed.filter { t in
            guard matchesFilters(t) else { return false }
            guard let cd = completionDate(t) else { return true } // как в вебе: непарсимая дата не исключает задачу
            return cd >= cutoff
        }
    }

    private var groups: [(key: String, label: String, tasks: [ApiTask])] {
        var map: [String: [ApiTask]] = [:]
        for t in filtered {
            guard let cd = completionDate(t) else { continue }
            map[DirectoryDate.dayKeyLocal(cd), default: []].append(t)
        }
        for key in map.keys {
            map[key]?.sort { (completionDate($0) ?? .distantPast) > (completionDate($1) ?? .distantPast) }
        }
        let todayKey = today, yesterdayKey = yesterday
        return map.keys.sorted(by: >).map { key in
            (key: key, label: DirectoryDate.groupLabel(key, today: todayKey, yesterday: yesterdayKey), tasks: map[key] ?? [])
        }
    }

    /// Для графика — фильтр по проекту/метке/исполнителю, БЕЗ периода
    /// (график сам режет на бакеты) и БЕЗ статуса (нужны и active, и completed).
    private var filteredAllTasks: [ApiTask] { taskStore.tasks.filter(matchesFilters) }

    private var showTrueEmpty: Bool { completed.isEmpty }
    private var showFilteredEmpty: Bool { !completed.isEmpty && filtered.isEmpty }

    private var summaryText: String {
        let word: String
        switch period {
        case .week: word = "неделю"
        case .month: word = "месяц"
        case .quarter: word = "3 месяца"
        case .year: word = "год"
        }
        return "За \(word) выполнено \(filtered.count)"
    }

    // MARK: - Опции фильтров (из полного набора выполненных, не из уже отфильтрованных)

    private struct FilterOption: Identifiable { let id: String; let label: String; let color: Color }

    private var projectOptions: [FilterOption] {
        var seen = Set<String>()
        var result: [FilterOption] = []
        for t in completed {
            guard let pid = t.projectId, let name = t.projectName, !seen.contains(pid) else { continue }
            seen.insert(pid)
            result.append(FilterOption(id: pid, label: name, color: t.projectColor.map { Color(hex: $0) } ?? Color(hex: TFHexDefault.unassigned)))
        }
        return result.sorted { $0.label.localizedCompare($1.label) == .orderedAscending }
    }

    private var labelOptions: [FilterOption] {
        var seen = Set<String>()
        var result: [FilterOption] = []
        for t in completed {
            for l in t.labels where !seen.contains(l.id) {
                seen.insert(l.id)
                result.append(FilterOption(id: l.id, label: l.name, color: l.color.map { Color(hex: $0) } ?? Color(hex: TFHexDefault.unassigned)))
            }
        }
        return result.sorted { $0.label.localizedCompare($1.label) == .orderedAscending }
    }

    private struct AssigneeOption: Identifiable { let id: String; let name: String; let initials: String; let color: Color }

    private var assigneeOptions: (list: [AssigneeOption], hasUnassigned: Bool) {
        var seen = Set<String>()
        var result: [AssigneeOption] = []
        var hasUnassigned = false
        for t in completed {
            if let aid = t.assigneeId {
                if !seen.contains(aid) {
                    seen.insert(aid)
                    result.append(AssigneeOption(
                        id: aid, name: t.assigneeName ?? "Без имени",
                        initials: t.assigneeInitials ?? "?",
                        color: t.assigneeColor.map { Color(hex: $0) } ?? Color(hex: TFHexDefault.unassigned)
                    ))
                }
            } else {
                hasUnassigned = true
            }
        }
        return (result.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }, hasUnassigned)
    }

    // MARK: - Меню фильтров

    private var projectLabel: String { projectId.flatMap { id in projectOptions.first { $0.id == id }?.label } ?? "Все проекты" }
    private var labelLabel: String { labelId.flatMap { id in labelOptions.first { $0.id == id }?.label } ?? "Все метки" }
    private var assigneeLabel: String {
        if assigneeKey == "__none" { return "Без исполнителя" }
        if let key = assigneeKey { return assigneeOptions.list.first { $0.id == key }?.name ?? "Все исполнители" }
        return "Все исполнители"
    }

    /// Владелец 11.10.2026: фильтр открывался нижней панелью-шторкой — надо
/// было штатное меню-окошко, как на остальных экранах. Сделано тем же
/// приёмом, что меню «…» в «Команде» и «Памяти» (`Menu` в toolbar) и меню
/// фильтров в строке быстрого добавления: у выбранного значения галочка,
/// сброс — отдельным пунктом внизу, как было действием шторки.
    ///
    /// Секции, а не подменю: первая версия делала каждый фильтр вложенным
    /// `Menu` (подменю), и такой `Menu` в toolbar НЕ ОТРИСОВЫВАЛСЯ ВООБЩЕ —
    /// кнопка фильтра пропадала из шапки и не появлялась ни в кадре, ни в
    /// дереве доступности (проверено XCUITest, 11.10.2026). Секции верхнего
    /// уровня рисуются всегда.
    private var filterMenu: some View {
        Menu {
            Section("Период") {
                ForEach(ActivityPeriod.allCases) { p in
                    menuPick(p.label, selected: period == p) { period = p }
                }
            }

            Section("Проект · \(projectLabel)") {
                menuPick("Все проекты", selected: projectId == nil) { projectId = nil }
                ForEach(projectOptions) { opt in
                    menuPick(opt.label, selected: projectId == opt.id) { projectId = opt.id }
                }
                if projectOptions.isEmpty {
                    Text("Нет выполненных задач с проектом")
                }
            }

            Section("Метка · \(labelLabel)") {
                menuPick("Все метки", selected: labelId == nil) { labelId = nil }
                ForEach(labelOptions) { opt in
                    menuPick(opt.label, selected: labelId == opt.id) { labelId = opt.id }
                }
                if labelOptions.isEmpty {
                    Text("Нет выполненных задач с метками")
                }
            }

            Section("Исполнитель · \(assigneeLabel)") {
                menuPick("Все исполнители", selected: assigneeKey == nil) { assigneeKey = nil }
                ForEach(assigneeOptions.list) { a in
                    menuPick(a.name, selected: assigneeKey == a.id) { assigneeKey = a.id }
                }
                if assigneeOptions.hasUnassigned {
                    menuPick("Без исполнителя", selected: assigneeKey == "__none") { assigneeKey = "__none" }
                }
                if assigneeOptions.list.isEmpty && !assigneeOptions.hasUnassigned {
                    Text("Нет данных об исполнителях")
                }
            }

            Button("Сбросить фильтры", systemImage: "arrow.counterclockwise") { resetFilters() }
        } label: {
            TFPlannerToolbarIcon(systemName: "line.3.horizontal.decrease")
        }
        .accessibilityLabel("Фильтры")
        .accessibilityIdentifier("activity.filter-menu")
    }

    /// Пункт меню с галочкой у выбранного значения — как в меню фильтров
    /// строки быстрого добавления.
    private func menuPick(_ title: String, selected: Bool, set: @escaping () -> Void) -> some View {
        Button(action: set) {
            if selected { Label(title, systemImage: "checkmark") } else { Text(title) }
        }
    }
}
