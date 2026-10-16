import SwiftUI

/// Единственная шторка карточки задачи для всех списков приложения.
///
/// Владелец 16.10.2026: «это абсолютно один и тот же элемент, а работает
/// по-разному». Каждый экран писал свой `.sheet { TaskFormScreen }` со своими
/// настройками — правку свайпа (`.resizes`) получили только «Проекты», а
/// календарь, «Сегодня», чаты и прочие остались со старой шторкой: свайп
/// листал содержимое и цеплялся за «потяни, чтобы обновить», свернуть было
/// нельзя. Теперь поведение задаётся здесь одним местом.
extension View {
    /// Шторка карточки по идентификатору задачи. `nil` — закрыта.
    func taskCardSheet(taskID: Binding<String?>, onDismiss: (() -> Void)? = nil) -> some View {
        sheet(item: Binding(
            get: { taskID.wrappedValue.map(TaskCardSheetID.init) },
            set: { taskID.wrappedValue = $0?.id }
        ), onDismiss: onDismiss) { ref in
            NavigationStack { TaskFormScreen(taskID: ref.id) }
                .taskCardSheetPresentation()
        }
    }

    /// То же для экранов, где открытая задача хранится обёрткой `Identifiable`.
    func taskCardSheet<Item: Identifiable>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil) -> some View where Item.ID == String {
        taskCardSheet(taskID: Binding(
            get: { item.wrappedValue?.id },
            set: { if $0 == nil { item.wrappedValue = nil } }
        ), onDismiss: onDismiss)
    }

    /// Оформление шторки карточки — для мест, где шторку строит не
    /// `taskCardSheet` (например, отладочный маршрут).
    func taskCardSheetPresentation() -> some View {
        self
            .presentationDetents([.medium, .large])
            // Свайп сначала двигает саму шторку (до полного экрана и до
            // закрытия), прокрутка содержимого — потом.
            .presentationContentInteraction(.resizes)
            .presentationDragIndicator(.visible)
            .presentationBackground(Color.tfSheetBackground)
    }
}

private struct TaskCardSheetID: Identifiable { let id: String }
