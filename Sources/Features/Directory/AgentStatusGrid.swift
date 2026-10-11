import SwiftUI

struct AgentStatusGrid: View {
    @Environment(TaskStore.self) private var taskStore
    var body: some View {
        HStack(spacing: 8) {
            statusTile(route: .agentWork(focus: .inProgress), title: "В работе", count: workingCount, kind: .running)
            statusTile(route: .agentWork(focus: .review), title: "На проверке", count: reviewCount, kind: .review)
            statusTile(route: .agentWork(focus: .blocked), title: "Заблокированы", count: blockedCount, kind: .blocked)
            statusTile(route: .agentWork(focus: .stale), title: "Пропали", count: staleCount, kind: .stale)
        }
    }
    private func statusTile(route: AppRoute, title: String, count: Int, kind: ProjectStatusIcon.Kind) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: 8) {
                ProjectStatusIcon(kind: kind)
                Text("\(count)").monospacedDigit().foregroundStyle(Color.tfText)
            }.frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(count)")
        .accessibilityIdentifier("projects.status.\(title)")
    }

    private var workingCount: Int {
        taskStore.agentWorkTasks.count { $0.status == .active && $0.agentState == .inProgress && $0.agentStale != true }
    }
    private var reviewCount: Int {
        taskStore.agentWorkTasks.count { $0.status == .active && $0.agentState == .review }
    }
    private var blockedCount: Int {
        taskStore.agentWorkTasks.count { $0.status == .active && $0.agentState == .blocked }
    }
    private var staleCount: Int {
        taskStore.agentWorkTasks.count { $0.status == .active && $0.agentState == .inProgress && $0.agentStale == true }
    }
}

struct ProjectStatusIcon: View {
    enum Kind { case running, review, blocked, stale }
    let kind: Kind

    /// Значок статуса — по кеглю строки, в которой он живёт, а не отдельной
    /// рамкой 21pt (владелец 11.10.2026: «глазки и треугольники совсем
    /// здоровые»). Раньше значок был больше собственного текста с цифрой и
    /// в строке карточки проекта читался как самостоятельный элемент.
    var size: CGFloat = 14

    var body: some View {
        Group {
            switch kind {
            case .running:
                // Владелец 11.10.2026: «крутилку замени на то, что и было, типа
                // плей в кружочке». На этом месте стоял
                // `TFSubtaskStatusRing(.running)` — вращающиеся 12 точек.
                // Тот же значок «в работе», что уже стоит в фильтре проектов
                // (`ProjectFilter.inWork`): play.circle.fill.
                Image(systemName: "play.circle.fill")
                    .foregroundStyle(Color.tfTeal)
            case .review:
                // Фигура и цвет как у `TFSubtaskStatusRing(.review)`, но своего
                // кегля: тот жёстко зашит на 21pt (`TFCheckbox.swift:138`) и
                // перебивал внешний `.frame`, из-за чего в строке карточки
                // значок был больше цифры рядом. Сам `TFSubtaskStatusRing` не
                // трогаем — он общий для чекбоксов подзадач.
                Image(systemName: "eye")
                    .foregroundStyle(Color.tfBlue)
            case .blocked:
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(Color.tfOrange)
            case .stale:
                ZStack {
                    Image(systemName: "triangle")
                    Image(systemName: "xmark").font(.system(size: size * 0.4, weight: .bold)).offset(y: size * 0.1)
                }.foregroundStyle(Color.tfRed)
            }
        }
        .font(.system(size: size))
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
