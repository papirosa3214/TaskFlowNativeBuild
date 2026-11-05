import SwiftUI

/// Создание задачи — один сценарий на всё приложение:
/// короткая форма (`QuickAddTaskView`) → ⤢ «Открыть полную форму» →
/// большая карточка (`TaskFormScreen(expandingFrom:)`).
///
/// Прозрачный `fullScreenCover`, а не `.sheet`: шторка с фокусом в поле
/// резервирует место под клавиатуру и раздувается почти на весь экран, а фон
/// и капсулу короткой формы рисует сама `QuickAddTaskView` (так же, как в
/// `RootShellView`). Черновик между формами передаётся один и тот же —
/// введённое не теряется.
private struct TaskComposerDraft: Identifiable {
    let id = UUID()
    let viewModel: TaskFormViewModel
}

private struct TaskCreateFlowModifier: ViewModifier {
    @Binding var isPresented: Bool

    @State private var draft: TaskComposerDraft?
    @State private var pendingExpand: TaskFormViewModel?
    @State private var expanded: TaskComposerDraft?

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: $draft, onDismiss: {
                if let viewModel = pendingExpand {
                    pendingExpand = nil
                    expanded = TaskComposerDraft(viewModel: viewModel)
                } else {
                    isPresented = false
                }
            }) { item in
                QuickAddTaskView(
                    viewModel: item.viewModel,
                    onSaved: { isPresented = false },
                    onExpand: {
                        pendingExpand = item.viewModel
                        draft = nil
                    }
                )
                .presentationBackground(.clear)
            }
            .tfSheet(item: $expanded, onDismiss: { isPresented = false }) { item in
                NavigationStack {
                    TaskFormScreen(expandingFrom: item.viewModel)
                }
                .taskCardSheetPresentation()
            }
            .onChange(of: isPresented) { _, now in
                guard now, draft == nil, expanded == nil else { return }
                draft = TaskComposerDraft(viewModel: TaskFormViewModel(taskID: nil))
            }
    }
}

extension View {
    /// Единая точка создания задачи: короткая форма с переходом в большую.
    func taskCreateFlow(isPresented: Binding<Bool>) -> some View {
        modifier(TaskCreateFlowModifier(isPresented: isPresented))
    }
}
