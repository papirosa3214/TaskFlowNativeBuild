import SwiftUI

/// Живая строка «чем агент занят прямо сейчас» в карточке задачи.
///
/// Текст приходит готовым с сервера (`GET /api/tasks/:id/activity`): там он
/// собирается тремя слоями — шаг, типизация действия и пересказ локальной
/// моделью. Клиент печатает его как есть и ничего не достраивает: сырые пути
/// и команды владелец видеть не хочет («правит он что? файл правит, какую...
/// что это такое вообще?» — 25.08.2026), поэтому даже в раскрытом списке
/// показываем присланную формулировку, а не `target`.
///
/// Пустую строку экран не рисует вовсе (`activity.isActive`) — гаснет сама,
/// как только агент отдал задачу или просрочил аренду.
struct TaskAgentActivityView: View {
    let activity: ApiTaskActivity

    @State private var isExpanded = false

    private var recent: [ApiTaskActivityAction] {
        // Свежие сверху, и не больше пяти: это врезка в карточке, а не журнал.
        activity.actions.suffix(5).reversed()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            header

            if isExpanded && !recent.isEmpty {
                VStack(alignment: .leading, spacing: TFSpacing.sm) {
                    ForEach(recent) { action in
                        HStack(alignment: .top, spacing: TFSpacing.sm) {
                            Circle()
                                .fill(Color.tfDim)
                                .frame(width: 4, height: 4)
                                .padding(.top, 7)
                            Text(action.text ?? action.target)
                                .tfText(.meta)
                                .foregroundStyle(Color.tfSub)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.leading, TFSpacing.md)
            }
        }
        .padding(TFSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tfCard, in: RoundedRectangle(cornerRadius: TFRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: TFRadius.lg)
                .strokeBorder(Color.tfStroke, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            guard !recent.isEmpty else { return }
            withAnimation(.easeInOut(duration: TFDuration.fast)) { isExpanded.toggle() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Агент сейчас: \(activity.text ?? "")")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: TFSpacing.sm) {
            // Та же крутилка, что у идущего шага, — один язык для «идёт работа».
            TFSubtaskStatusRing(.running)
                .frame(width: 21, height: 21)

            VStack(alignment: .leading, spacing: 2) {
                Text("Агент работает")
                    .tfText(.caption)
                    .foregroundStyle(Color.tfDim)
                Text(activity.text ?? "")
                    .tfText(.action)
                    .foregroundStyle(Color.tfText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !recent.isEmpty {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.tfDim)
                    .padding(.top, 4)
            }
        }
    }
}
