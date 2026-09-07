import SwiftUI

// Карточка проекта — владелец 08.09.2026: «список обычный такой голимый, а
// хочется, чтобы прям карточка была, с адекватной информацией: как давно
// висит, сколько задач выполнено, сколько вообще было поставлено».
//
// Числа приходят готовыми из `GET /api/projects` (`completed_count`,
// `overdue_count`, `last_activity_at`, `docs_count` — добавлены в тот же день
// на сервере). Считать их здесь нельзя: пришлось бы тянуть задачи каждого
// проекта отдельным запросом, а проектов полтора десятка.
//
// Оформление — по эталону «Модели и голоса» (владелец 03.09.2026 просил
// причёсывать экраны под него): без цветных плашек и заливок. Цвет проекта
// живёт ровно в одной точке у названия; полоса прогресса и весь текст —
// нейтральные. Первая версия красила ещё и полосу, и список из полутора
// десятков проектов превращался в радугу (владелец 08.09.2026: «всё
// приложение минималистичное, а тут как клоуна нарядил»).
struct ProjectCard: View {
    let project: ApiProject

    private var accent: Color { Color(hex: project.color ?? TFHexDefault.unassigned) }
    private var active: Int { project.taskCount ?? 0 }
    private var completed: Int { project.completedCount ?? 0 }
    private var total: Int { active + completed }
    private var overdue: Int { project.overdueCount ?? 0 }
    private var docs: Int { project.docsCount ?? 0 }

    var body: some View {
        TFCard {
            VStack(alignment: .leading, spacing: TFSpacing.md) {
                header
                if total > 0 {
                    progress
                }
                metrics
                if !project.agents.isEmpty {
                    agentsLine
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        // Выравнивание по верху: у имени в две строки точка, центрированная
        // по всему блоку, съезжала на межстрочный интервал. Отступ 6pt ставит
        // её по центру ПЕРВОЙ строки (17pt title).
        HStack(alignment: .top, spacing: TFSpacing.sm) {
            Circle()
                .fill(accent)
                .frame(width: 8, height: 8)
                .padding(.top, 7)
            // Две строки, а не одна: в карточке место есть, а имена вроде
            // «Аудит фактической схемы мультиагентов TaskFlow» на одной
            // строке обрезаются до неразличимости (проверено кадром 08.09.2026).
            Text(project.name)
                .tfText(.title)
                .foregroundStyle(Color.tfText)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: TFSpacing.sm)
            if project.pinned {
                Image(systemName: "pin.fill")
                    .tfText(.caption)
                    .foregroundStyle(Color.tfDim)
                    .padding(.top, 3)
                    .accessibilityLabel("Закреплён")
            }
        }
    }

    /// Полоса «сделано из всего». Доля считается от ВСЕХ задач проекта
    /// (активные + выполненные), а не от активных: вопрос владельца — «сколько
    /// вообще было поставлено и сколько из этого закрыто».
    ///
    /// Полоса НЕЙТРАЛЬНАЯ, не цвета проекта: владелец 08.09.2026, увидев
    /// список из полутора десятков разноцветных полос, — «всё приложение
    /// минималистичное, а тут как клоуна нарядил». Цвет проекта остаётся
    /// только точкой у названия, как метка, а не как заливка.
    private var progress: some View {
        VStack(alignment: .leading, spacing: TFSpacing.xs) {
            Capsule()
                .fill(Color.tfStroke)
                .frame(height: 6)
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        Capsule()
                            .fill(Color.tfSub)
                            .frame(width: geo.size.width * fraction)
                    }
                }
                .accessibilityLabel("Выполнено \(completed) из \(total)")
            Text("\(completed) из \(total) выполнено")
                .tfText(.caption)
                .foregroundStyle(Color.tfSub)
        }
    }

    private var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }

    /// Нижняя строка: активные, просрочка, документы, последнее движение.
    /// Пункты без содержания не печатаются вовсе — пустое «0 просрочено» шумит
    /// ровно там, где всё в порядке.
    private var metrics: some View {
        HStack(spacing: TFSpacing.xs) {
            metric(remainderText, color: .tfSub)
            if overdue > 0 {
                separator
                metric("\(overdue) просрочено", color: .tfRed)
            }
            if docs > 0 {
                separator
                metric("\(docs) \(ProjectCard.docWord(docs))", color: .tfSub)
            }
            if let idle = idleText {
                separator
                metric(idle, color: .tfDim)
            }
            Spacer(minLength: 0)
        }
    }

    /// Кто сейчас в проекте работает — просьба владельца 08.09.2026. Строкой,
    /// а не аватарами: аватары агентов на карточке проекта — это ещё один ряд
    /// цветных кружков там, где список и так должен читаться спокойно.
    /// Имя без числа задач, пока агент один; с числом — когда их несколько и
    /// видно, кто тянет основную часть.
    private var agentsLine: some View {
        HStack(spacing: TFSpacing.xs) {
            Image(systemName: "cpu")
                .tfText(.caption)
                .foregroundStyle(Color.tfDim)
            Text(agentsText)
                .tfText(.caption)
                .foregroundStyle(Color.tfDim)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
    }

    private var agentsText: String {
        let agents = project.agents
        if agents.count == 1, let only = agents.first { return only.name }
        return agents.map { "\($0.name) · \($0.tasks)" }.joined(separator: "   ")
    }

    /// Не «9 задач», а «осталось 9»: над этой строкой уже стоит «16 из 25
    /// выполнено», и голое число задач рядом с ним читается как «всего их 9».
    private var remainderText: String {
        if total == 0 { return "пока нет задач" }
        if active == 0 { return "все задачи закрыты" }
        return "осталось \(active)"
    }

    private var separator: some View {
        Text("·")
            .tfText(.caption)
            .foregroundStyle(Color.tfDim)
    }

    private func metric(_ text: String, color: Color) -> some View {
        Text(text)
            .tfText(.caption)
            .foregroundStyle(color)
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

#Preview("Карточки проектов") {
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
