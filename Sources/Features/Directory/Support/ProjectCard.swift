import SwiftUI

// Строка проекта — владелец 11.10.2026: «давай проекты отображать плоско, а
// между ними просто разделительные линии». Раньше здесь была карточка
// (`TFCard` со скруглением) в ряд из полутора десятков; теперь это плоский
// список строк, разделённых тонкими линиями, — так список читается как список,
// а не как стопка плиток.
//
// Общие числа приходят готовыми из `GET /api/projects` (`task_count`,
// `completed_count`, `overdue_count`, `last_activity_at`, `docs_count`).
// Разбиение активных задач на review/blocked/остальные берётся из уже
// загруженного общего `TaskStore`: отдельного запроса на каждый проект нет,
// а realtime-изменение задачи сразу перерисовывает соответствующую строку.
//
// Цвет проекта живёт теперь в СЕКЦИОННЫХ ПОЛОСКАХ (владелец 11.10.2026:
// «не рисовать точки, вот как раз будут полоски эти цветными»). Точка у
// названия убрана вместе с ней — цвет и раньше был единственной пёстрой деталью
// в списке («как клоуна нарядил», 08.09.2026), но хотя бы в одной точке; теперь
// он размазан по полоскам и не спорит с текстом.
struct ProjectCard: View {
    let project: ApiProject
    let tasks: [ApiTask]

    init(project: ApiProject, tasks: [ApiTask] = []) {
        self.project = project
        self.tasks = tasks
    }

    private var accent: Color { Color(hex: project.color ?? TFHexDefault.unassigned) }
    private var status: ProjectTaskStatusSummary {
        ProjectTaskStatusSummary(project: project, tasks: tasks)
    }
    private var total: Int { status.total }
    private var completed: Int { status.completed }
    private var overdue: Int { project.overdueCount ?? 0 }
    private var docs: Int { project.docsCount ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            header
            progress.accessibilityIdentifier("projects.progress.\(project.id)")
            statusLine
            if hasMetadata {
                metrics
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, TFSpacing.md)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: TFSpacing.sm) {
            Text(project.name)
                .tfText(.title)
                .foregroundStyle(Color.tfText)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: TFSpacing.sm)
            // Процент выполнения — напротив названия (просьба владельца
            // 11.10.2026). Та же доля, что рисуют полоски ниже, но числом:
            // доли двух-трёх секций на глаз не сравнить, а «62 %» сравнивается
            // сразу. Моноширинные цифры, иначе колонка процентов прыгает.
            Text("\(percent)%")
                .font(.system(.headline, design: .default).monospacedDigit())
                .foregroundStyle(Color.tfSub)
                .layoutPriority(1)
            if project.pinned {
                Image(systemName: "pin.fill")
                    .tfText(.caption)
                    .foregroundStyle(Color.tfDim)
                    .accessibilityLabel("Закреплён")
            }
        }
    }

    /// Сколько «шашек» в секционной полосе. 12 — чтобы разница между соседними
    /// проектами читалась глазом (одна шашка ≈ 8 % работы), но ряд из
    /// полутора десятков строк не превращался в ��адугу из квадратиков.
    private static let segments = 12

    /// Секционные прямоугольники вместо капсулы (владелец 11.10.2026: «не
    /// полоску, а секционные полоски… прямоугольнички»). Залитые — цветом
    /// проекта, незалитые — нейтральной линией, как прежний фон капсулы.
    ///
    /// Почему секциями, а не сплошной заливкой: по сплошной полосе не видно,
    /// где кончается работа первых задач и начинаются последние, а процент рядом
    /// с названием считается глазом хуже, чем по шашкам.
    private var progress: some View {
        HStack(spacing: 3) {
            ForEach(0..<Self.segments, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(i < filledSegments ? accent : Color.tfStroke)
            }
        }
        .frame(height: 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Выполнено \(completed) из \(total)")
        .accessibilityValue("\(percent)%")
    }

    private var filledSegments: Int {
        guard total > 0 else { return 0 }
        return min(Self.segments, Int((fraction * Double(Self.segments)).rounded()))
    }

    private var percent: Int { Int((fraction * 100).rounded()) }

    private var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }

    /// Главная сводка — без фонов и слов: системная иконка и число одним
    /// цветом. Порядок постоянный, поэтому карточки легко сравнивать глазами;
    /// полные названия остаются доступны VoiceOver.
    private var statusLine: some View {
        HStack(spacing: 10) {
            statusMetric("tray.full", value: status.total, color: .tfText, label: "Всего задач")
            statusMetric("checkmark.circle.fill", value: status.completed, color: .tfGreen, label: "Выполнено")
            stateMetric(.review, value: status.review, label: "На проверке")
            stateMetric(.blocked, value: status.blocked, label: "Заблокировано")
            statusMetric("clock", value: status.pending, color: .tfDim, label: "Ещё не начаты")
            stateMetric(.running, value: status.inWork, label: "В работе")
            stateMetric(.stale, value: status.stale, label: "Пропали")
            Spacer(minLength: 0)
        }
    }

    private func stateMetric(_ kind: ProjectStatusIcon.Kind, value: Int, label: String) -> some View {
        HStack(spacing: 4) {
            ProjectStatusIcon(kind: kind, size: 13)
            Text("\(value)").monospacedDigit().foregroundStyle(Color.tfText)
        }.font(.caption).accessibilityElement(children: .ignore)
            .accessibilityLabel(label).accessibilityValue("\(value)")
    }

    private func statusMetric(_ icon: String, value: Int, color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .accessibilityHidden(true)
            Text("\(value)")
                .monospacedDigit()
        }
        .tfText(.caption)
        .foregroundStyle(Color.tfReadableText(color))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(value)")
    }

    /// Вторичная строка: просрочка, документы, последнее движение. Пункты
    /// без содержания не печатаются — нули здесь только создают шум.
    private var metrics: some View {
        HStack(spacing: TFSpacing.xs) {
            if overdue > 0 {
                metric("\(overdue) просрочено", color: .tfRed)
            }
            if docs > 0 {
                if overdue > 0 { separator }
                metric("\(docs) \(ProjectCard.docWord(docs))", color: .tfSub)
            }
            if let idle = idleText {
                if overdue > 0 || docs > 0 { separator }
                metric(idle, color: .tfDim)
            }
            Spacer(minLength: 0)
        }
    }

    private var hasMetadata: Bool {
        overdue > 0 || docs > 0 || idleText != nil
    }

    // Строка ролей («Разработчик · 5   Дизайнер · 2…») убрана 27.09.2026 по
    // просьбе владельца: ролей в проекте больше, чем влезает в строку, видны
    // две — остальные не узнать, информация бесполезная.

    private var separator: some View {
        Text("·")
            .tfText(.caption)
            .foregroundStyle(Color.tfDim)
    }

    private func metric(_ text: String, color: Color) -> some View {
        Text(text)
            .tfText(.caption)
            .foregroundStyle(Color.tfReadableText(color))
            .lineLimit(1)
    }

    /// «5 дн. назад» — по последнему движению задач, а не по дате создания
    /// проекта: карточка отвечает на «сколько он уже висит», и проект,
    /// заведённый год назад, но живой вчера, висящим не считается.
    ///
    /// Пусто у проекта совсем без задач: «никогда» рядом с пустым проектом
    /// выглядит упрёком, хотя сказать там просто нечего.
    private var idleText: String? {
        guard let date = DateFormats.sqliteUTC(project.lastActivityAt) else { return nil }
        return RelativeTime.relative(from: date)
    }

    /// «1 документ / 2 документа / 5 документов» — тот же приём, что
    /// `DirectoryPluralize.taskWord`, только слово другое.
    static func docWord(_ n: Int) -> String {
        let mod100 = n % 100
        if mod100 >= 11 && mod100 <= 14 { return "документов" }
        switch n % 10 {
        case 1: return "документ"
        case 2...4: return "документа"
        default: return "документов"
        }
    }
}

/// Статусы в сервере двухуровневые: `status` отвечает только за active /
/// completed, а `agent_state` уточняет активную задачу. Поэтому «в работе» —
/// активные задачи за вычетом review и blocked; сюда входят и реально
/// запущенные (`in_progress`), и ещё не взятые в работу задачи.
struct ProjectTaskStatusSummary {
    let total: Int
    let completed: Int
    let review: Int
    let blocked: Int
    let inWork: Int
    let pending: Int
    let stale: Int

    init(project: ApiProject, tasks: [ApiTask]) {
        let scoped = tasks.filter { $0.projectId == project.id }
        let active = project.taskCount ?? scoped.count { $0.status == .active }
        completed = project.completedCount ?? scoped.count { $0.status == .completed }
        review = scoped.count { $0.status == .active && $0.agentState == .review }
        blocked = scoped.count { $0.status == .active && $0.agentState == .blocked }
        stale = scoped.count { $0.status == .active && $0.agentState == .inProgress && $0.agentStale == true }
        inWork = scoped.count { $0.status == .active && $0.agentState == .inProgress && $0.agentStale != true }
        pending = max(0, active - review - blocked - inWork - stale)
        total = active + completed
    }
}

#Preview("Строки проектов") {
    ScrollView {
        VStack(spacing: TFSpacing.sm) {
            ProjectCard(project: ApiProject(
                id: "1", name: "TaskFlow — NewTodoist", color: "#e44332", ownerId: nil,
                createdAt: "2026-06-01 10:00:00", position: 0, pinned: true,
                notesFolderId: 3, taskCount: 5, completedCount: 59, overdueCount: 1,
                lastActivityAt: "2026-09-07 13:47:10", docsCount: 4
            ))
            ProjectCard(project: ApiProject(
                id: "2", name: "Домашний сервер", color: "#4A9FD8", ownerId: nil,
                createdAt: "2026-05-01 10:00:00", position: 1, pinned: false,
                notesFolderId: nil, taskCount: 2, completedCount: 42, overdueCount: 0,
                lastActivityAt: "2026-09-03 09:14:27", docsCount: 0
            ))
            ProjectCard(project: ApiProject(
                id: "3", name: "Пустой проект", color: nil, ownerId: nil,
                createdAt: "2026-09-08 10:00:00", position: 2, pinned: false,
                notesFolderId: nil, taskCount: 0, completedCount: 0, overdueCount: 0,
                lastActivityAt: nil, docsCount: 0
            ))
        }
        .padding(TFSpacing.screenHorizontal)
    }
    .background(Color.tfBackground)
}
