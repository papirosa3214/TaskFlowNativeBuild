import SwiftUI

/// Полоса работы хода у готового ответа и её содержимое отдельным окном.
///
/// Владелец 10.11.2026: «когда раскрываю — сразу на всю страничку открываются
/// все действия, а хочу листнуть — тут же сворачивается». Раскрытие в самой
/// ленте растягивало строку на тысячи пунктов и теряло состояние при
/// пересборке строки. Теперь работа открывается окном: у него своя прокрутка,
/// высота ограничена, сворачивать нечего — строка ленты не меняется вовсе.
struct RoleWorkBar: View {
    let message: RoleChatMessage
    /// Тело шага по id — грузится, когда шаг раскрыли внутри окна.
    var stepDetailLoader: ((String) async -> RoleChatLiveStep?)?

    @State private var presented = false

    private var items: [RoleChatLiveItem] {
        message.steps?.itemsWithoutAnswerText(of: message) ?? []
    }

    var body: some View {
        WorkActionsBar(items: items, stepDetailLoader: stepDetailLoader)
    }
}

/// Полоса «Действия» готовая к нажатию: свёрнутая работа хода, которая
/// открывается окном. Одна на комнату роли и на сессию владельца — у обоих
/// ход собран из одних и тех же `RoleChatLiveItem`.
struct WorkActionsBar: View {
    let items: [RoleChatLiveItem]
    /// Тело шага по id — грузится, когда шаг раскрыли внутри окна.
    var stepDetailLoader: ((String) async -> RoleChatLiveStep?)?

    @State private var presented = false

    private var stepCount: Int {
        items.filter(\.isStep).count
    }

    private var thinkingSeconds: Int {
        items.reduce(0) { sum, item in
            if case .thinking(let thinking) = item { return sum + (thinking.durationSeconds ?? 0) }
            return sum
        }
    }

    private var summary: String {
        RoleWorkFooter.summary(stepCount: stepCount, thinkingSeconds: thinkingSeconds)
    }

    var body: some View {
        // Строка списка — по канону дизайн-системы (`TFListRow`): шеврон и
        // высота нажатия от него, своих рисованных строк не заводим.
        TFListRow(icon: "square.stack.3d.up", iconTint: .tfDim, iconStyle: .plain,
                  title: "Действия",
                  subtitle: summary.isEmpty ? nil : summary,
                  subtitleStyle: .caption,
                  verticalPadding: TFSpacing.sm, horizontalPadding: 0,
                  minHeight: TFHitTarget.min, chevron: .shown) {
            presented = true
        }
        .accessibilityHint("Открыть ход работы")
        .tfSheet(isPresented: $presented) {
            RoleWorkSheet(items: items, stepDetailLoader: stepDetailLoader)
        }
    }
}

/// Ход работы в своём окне: прокрутка внутри, шторка открывается на середину
/// экрана и растягивается вверх, если шагов много.
struct RoleWorkSheet: View {
    let items: [RoleChatLiveItem]
    var stepDetailLoader: ((String) async -> RoleChatLiveStep?)?

    var body: some View {
        NavigationStack {
            ScrollView {
                RoleLiveItemsList(items: items,
                                  isStreaming: false,
                                  stepDetailLoader: stepDetailLoader,
                                  ungrouped: true)
                    .padding(.horizontal, TFSpacing.lg)
                    .padding(.vertical, TFSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .tfScreenBackground()
            .navigationTitle("Работа")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @Environment(\.dismiss) private var dismiss
}
