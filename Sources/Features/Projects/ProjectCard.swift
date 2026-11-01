import SwiftUI

// Строка проекта — владелец 11.10.2026: «давай проекты отображать плоско, а
// между ними просто разделительные линии». Раньше здесь была карточка
// (`TFCard` со скруглением) в ряд из полутора десятков; теперь это плоский
// список строк, разделённых тонкими линиями, — так список читается как список,
// а не как стопка плиток.
//
// Числа задач, процент и полоска считаются по одному снимку TaskStore.
// Серверные агрегаты проекта могут отставать от realtime, поэтому не
// смешиваются с этим снимком. Документы/просрочка/дата — из GET /api/projects.
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
                // Было сырое `.system(.headline)` (17) — ступень `.title` даёт
                // тот же кегль и вес, но живёт в шкале (LOCK-TYPOGRAPHY-UNIFY).
                .tfText(.title)
                .monospacedDigit()
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

    /// Пять подписанных ярлычков: смысл понятен без расшифровки значков.
    /// FlowLayout переносит их целиком при узком экране или крупном шрифте.
    private var statusLine: some View {
        FlowLayout(spacing: TFSpacing.sm) {
            statusMetric(value: status.total, color: .tfSub, label: "Всего")
            statusMetric(value: status.inWork, color: .tfTeal, label: "В работе")
            statusMetric(value: status.blocked, color: .tfOrange, label: "Заблокировано")
            statusMetric(value: status.review, color: .tfPurple, label: "На проверке")
            statusMetric(value: status.pending, color: .tfSub, label: "Ожидают")
        }
    }

    private func statusMetric(value: Int, color: Color, label: String) -> some View {
        TFPill("\(label) \(value)", color: color)
            .monospacedDigit()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label == "Всего" ? "Всего задач" : label)
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

/// Один снимок для всех пяти ярлычков и прогресса. Выполненные входят в
/// знаменатель, но не в четыре взаимоисключающих состояния открытых задач.
/// Используем тот же effective state, что и фильтры списка задач.
struct ProjectTaskStatusSummary {
    let total: Int
    let completed: Int
    let review: Int
    let blocked: Int
    let inWork: Int
    let pending: Int

    init(project: ApiProject, tasks: [ApiTask]) {
        let scoped = tasks.filter { $0.projectId == project.id && !$0.isArchived }
        total = scoped.count
        completed = scoped.count { $0.status == .completed }
        review = scoped.count { ProjectTaskFilter.review.matches($0) }
        blocked = scoped.count { ProjectTaskFilter.blocked.matches($0) }
        inWork = scoped.count { ProjectTaskFilter.working.matches($0) }
        pending = scoped.count { ProjectTaskFilter.waiting.matches($0) }
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
    .tfScreenBackground()
}
