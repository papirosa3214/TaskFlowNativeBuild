import SwiftUI

struct AgentStatusGrid: View {
    @Environment(TaskStore.self) private var taskStore
    // MARK: - Сетка 2×2 статусов агентов — числа считаются на клиенте (spec §5.3)

    // Раньше вся плашка заливалась цветом (`tint.opacity(bgOpacity)`) — просьба
    // владельца 03.09.2026: «не всю плашку цветом закрашивай, а только
    // иконку» — плюс своя раскладка цветов по смыслу (в работе — зелёная,
    // на проверке — синяя, заблокировано — оранжевая, пропали — красная) и
    // цифра остаётся нейтральной, красится только иконка.
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: TFSpacing.sm), GridItem(.flexible())], spacing: TFSpacing.sm) {
            // Каждая плитка открывает сводку СРАЗУ на своём состоянии
            // (09.09.2026): до этого все четыре вели в один и тот же полный
            // список, и выбор ничего не значил.
            statusTile(route: .agentWork(focus: .inProgress), title: "В работе", count: workingCount,
                       icon: "waveform.path.ecg", tint: .tfGreen)
            statusTile(route: .agentWork(focus: .review), title: "На проверке", count: reviewCount,
                       icon: "checkmark", tint: .tfBlue)
            statusTile(route: .agentWork(focus: .blocked), title: "Заблокированы", count: blockedCount,
                       icon: "flag", tint: .tfOrange)
            statusTile(route: .agentWork(focus: .stale), title: "Пропали", count: staleCount,
                       icon: "cpu", tint: .tfRed)
        }
    }

    private func statusTile(route: AppRoute, title: String, count: Int, icon: String, tint: Color) -> some View {
        let active = count > 0
        return NavigationLink(value: route) {
            TFCard(padding: TFSpacing.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .tfText(.caption)
                            .foregroundStyle(Color.tfSub)
                            .lineLimit(1)
                        Text("\(count)")
                            .tfText(.taskTitle)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.tfText)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundStyle(active ? tint : Color.tfDim)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(TFTapScaleStyle())
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
        taskStore.agentWorkTasks.count { $0.agentState == .inProgress && $0.agentStale == true }
    }
}
