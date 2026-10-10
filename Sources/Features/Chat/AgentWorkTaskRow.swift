import SwiftUI
import SDWebImageSwiftUI

// Строка задачи для «Работы агента» — 1:1 живого `src/components/TaskRow.tsx`
// (общий компонент, которым и рендерится этот самый экран в вебе,
// `AgentWorkScreen.tsx`), а НЕ `TFTaskRow` из DesignSystem: тот — уже
// упрощённая по спеке версия (ARCHITECTURE.md «расходится спека с кодом —
// верить коду»), и здесь код с эталонного кадра (agent-work.png) требует
// три вещи, которых у TFTaskRow нет:
// 1. Аватар — КАРТИНКА агента (assignee_avatar_url), не только инициалы.
// 2. Значок перед статусом агента (веб: `Icon name="bot"`, здесь — `cpu`,
//    тем же символом уже подписан агент в приложении — AgentsScreen
//    roleInfoRow, плитка «Пропали» на Обзоре).
// 3. «Просрочено, {дата}» текстом с датой, не голое «Просрочено».
// Третий дубль пары «аватар с фото / инициалы» в проекте (после TFAvatar
// и приватного AgentAvatarView в AgentRow.swift) — кандидат на вынос в
// DesignSystem с параметром размера, в отчёте оркестратору.
private struct AgentWorkAvatarView: View {
    @AppStorage(TeamAvatarAppearance.storageKey) private var avatarAppearance = "current"
    @AppStorage(TeamAvatarAnimation.storageKey) private var avatarsAnimated = false
    let urlPath: String?
    let initials: String
    let tint: Color
    let size: CGFloat
    let userID: String?

    private var roleAppearance: TeamAvatarAppearance {
        TeamAvatarAppearance(rawValue: avatarAppearance) ?? .current
    }

    // `AnimatedImage` вместо `AsyncImage` — см. комментарий у AgentAvatarView
    // (AgentRow.swift), просьба владельца 03.09.2026, тот же приём.
    var body: some View {
        if RoleAvatarAsset.imageName(forUserID: userID, appearance: TeamAvatarAppearance(rawValue: avatarAppearance) ?? .current) != nil {
            bundledOrInitials
        } else if let urlPath, let url = URL(string: APIClient.baseURL.absoluteString + urlPath) {
            AnimatedImage(url: url, placeholder: { bundledOrInitials })
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .background(Color.tfCard2)
                .clipShape(RoundedRectangle(cornerRadius: TFRadius.md))
        } else {
            initialsCircle
        }
    }

    @ViewBuilder private var bundledOrInitials: some View {
        if let asset = RoleAvatarAsset.imageName(forUserID: userID, appearance: roleAppearance) {
            let loop = avatarsAnimated ? RoleAvatarAsset.loopName(forUserID: userID, appearance: roleAppearance) : nil
            TFRolePortrait(role: RoleAvatarAsset.role(forUserID: userID), imageAsset: asset,
                           loopName: loop, side: size)
        } else {
            initialsCircle
        }
    }

    private var initialsCircle: some View {
        Circle()
            .fill(tint)
            .frame(width: size, height: size)
            .overlay {
                Text(initials)
                    .font(.system(size: size * 0.43, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }
}

/// Статус агента плоским текстом — `AgentStateTag` (UI.tsx, вариант `plain`).
/// Отдельно от `TodayAgentStateTag` (Today — не моя папка): та версия
/// сознательно не печатает «· N мин назад» вовсе, а здесь, на экране,
/// который целиком про «когда агент последний раз подавал сигнал», это
/// главное число, поэтому суффикс восстановлен по вебу.
enum AgentWorkStateTag {
    static func icon(_ task: ApiTask) -> String? {
        task.agentState == nil ? nil : "cpu"
    }

    static func text(_ task: ApiTask) -> String? {
        guard let state = task.agentState else { return nil }
        let base = TFAgentStateTag.text(state, stale: task.agentStale == true)
        // Веб печатает «· N мин назад» ТОЛЬКО для in_progress (обоих —
        // и обычного, и «пропал»), у blocked/review суффикса нет (UI.tsx
        // `AgentStateTag`, компактная ветка не в счёт — этот экран не «плотный»).
        guard state == .inProgress, let heartbeat = task.agentHeartbeatAt,
              let date = DateFormats.sqliteUTC(heartbeat) else { return base }
        return "\(base) · \(RelativeTime.relative(from: date))"
    }

    static func color(_ task: ApiTask) -> Color {
        guard let state = task.agentState else { return .tfTeal }
        return TFAgentStateTag.color(state, stale: task.agentStale == true)
    }
}

/// Календарные подписи срока — тот же расчёт, что `TodayDate` (Today —
/// чужая папка, спека §4.1 требует счёт по МСК, дублируем локально по
/// тому же прецеденту, что и там: `lib/date.ts` иначе недоступен ни
/// оттуда, ни из Core (Core считает «сегодня» по таймзоне устройства).
enum AgentWorkDate {
    private static let moscow = TimeZone(identifier: "Europe/Moscow")!
    private static let monthsShort = ["янв", "фев", "мар", "апр", "мая", "июн", "июл", "авг", "сен", "окт", "ноя", "дек"]

    private static func todayString() -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = moscow
        let comps = calendar.dateComponents([.year, .month, .day], from: Date())
        return String(format: "%04d-%02d-%02d", comps.year ?? 1970, comps.month ?? 1, comps.day ?? 1)
    }

    private static func calendarDate(_ raw: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: raw)
    }

    private static func addDays(_ dateStr: String, _ days: Int) -> String {
        guard let date = calendarDate(dateStr) else { return dateStr }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        guard let shifted = calendar.date(byAdding: .day, value: days, to: date) else { return dateStr }
        let out = DateFormatter()
        out.calendar = Calendar(identifier: .gregorian)
        out.timeZone = TimeZone(identifier: "UTC")
        out.locale = Locale(identifier: "en_US_POSIX")
        out.dateFormat = "yyyy-MM-dd"
        return out.string(from: shifted)
    }

    /// Сколько суток до срока: 0 — сегодня, отрицательное — просрочено.
    static func daysUntil(_ dateStr: String) -> Int {
        guard let target = calendarDate(dateStr), let base = calendarDate(todayString()) else { return 0 }
        return Int((target.timeIntervalSince(base) / 86_400).rounded())
    }

    /// «Сегодня, 31 авг.» / «Завтра, 1 сен.» / «31 авг.» / «31 авг 2027».
    static func formatDueLabel(_ dateStr: String) -> String {
        guard let date = calendarDate(dateStr) else { return dateStr }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let comps = calendar.dateComponents([.day, .month, .year], from: date)
        guard let day = comps.day, let month = comps.month, let year = comps.year else { return dateStr }
        let monthName = monthsShort[max(0, min(11, month - 1))]
        let today = todayString()
        if dateStr == today { return "Сегодня, \(day) \(monthName)." }
        if dateStr == addDays(today, 1) { return "Завтра, \(day) \(monthName)." }
        let currentYear = Calendar(identifier: .gregorian).component(.year, from: Date())
        if year != currentYear { return "\(day) \(monthName) \(year)" }
        return "\(day) \(monthName)."
    }

    /// «осталось 3 дня» / «сегодня» / «завтра» / «просрочено на 2 дня».
    static func formatDaysLeft(_ dateStr: String) -> String {
        let d = daysUntil(dateStr)
        if d == 0 { return "сегодня" }
        if d == 1 { return "завтра" }
        if d == -1 { return "вчера" }
        let n = abs(d)
        let word: String
        let mod100 = n % 100
        if mod100 >= 11 && mod100 <= 14 {
            word = "дней"
        } else {
            switch n % 10 {
            case 1: word = "день"
            case 2, 3, 4: word = "дня"
            default: word = "дней"
            }
        }
        return d > 0 ? "осталось \(n) \(word)" : "просрочено на \(n) \(word)"
    }
}

/// Общая трёхстрочная раскладка списков; аватар сохраняет загрузку фото.
/// Без свайпа — строка кликабельна целиком.
struct AgentWorkTaskRow: View {
    let task: ApiTask
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            TFTaskRowContent(title: task.title, description: task.description, isDone: task.status == .completed) {
                if task.assigneeId != nil {
                    AgentWorkAvatarView(urlPath: task.assigneeAvatarUrl, initials: task.assigneeInitials ?? "?", tint: Color(hex: task.assigneeColor ?? TFHexDefault.unassigned), size: TFAvatar.Size.taskList.rawValue, userID: task.assigneeId)
                }
            } metadata: {
                TFTaskStructureIndicators(priority: TaskPriority(rawValue: task.priority), subtasksDone: task.subtasks.isEmpty ? nil : task.subtasks.count { $0.done }, subtasksTotal: task.subtasks.isEmpty ? nil : task.subtasks.count, childrenCount: task.childrenCount, hasCollaborationPlan: task.hasCollaborationPlan)
                if let due = task.dueDate {
                    TFDueChip(plain: AgentWorkDate.formatDueLabel(due), relative: AgentWorkDate.formatDaysLeft(due), days: AgentWorkDate.daysUntil(due), overdueText: "Просрочено, \(AgentWorkDate.formatDueLabel(due))", highlight: task.status == .active, forceOverdue: isOverdue)
                }
                if let status = AgentWorkStateTag.text(task) {
                    HStack(spacing: 3) {
                        if let icon = AgentWorkStateTag.icon(task) { Image(systemName: icon) }
                        Text(status)
                    }
                    .foregroundStyle(AgentWorkStateTag.color(task))
                    .layoutPriority(-1)
                }
                if task.agentState == .review, task.criticApproved == true { TFCriticApprovedMark() }
                if let project = task.projectName {
                    Text("#\(project)").foregroundStyle(Color.tfReadableText(Color(hex: task.projectColor ?? TFHexDefault.unassigned))).layoutPriority(-1)
                }
                ForEach(task.labels, id: \.id) { label in
                    TFLabelPill(label.name, color: Color(hex: label.color ?? TFHexDefault.unassigned)).layoutPriority(-1)
                }
            }
        }
        .buttonStyle(TFTapRowStyle())
    }

    private var isOverdue: Bool {
        guard let due = task.dueDate, task.status == .active else { return false }
        return AgentWorkDate.daysUntil(due) < 0
    }
}
