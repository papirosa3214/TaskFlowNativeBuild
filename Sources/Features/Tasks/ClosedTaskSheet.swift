import SwiftUI

/// Карточка закрытой задачи — одна и та же для выполненной и отменённой.
///
/// Владелец 01.11.2026: «Абсолютно одинаковый должен быть формат этой карточки,
/// единственная пометка — отменённая либо выполненная». Поэтому здесь только
/// то, что нужно, чтобы вспомнить задачу («была вот такая»), и два действия:
/// вернуть в работу либо удалить навсегда. Полной карточки здесь нет — её
/// закрытая задача не показывает (владелец: «больше никакой информации грузить
/// по этим карточкам не надо»).
struct ClosedTaskSheet: View {
    @Environment(\.dismiss) private var dismiss
    let task: ApiTask
    let isBusy: Bool
    let onRestore: () -> Void
    let onDelete: () -> Void
    /// Заголовок листа — «Задача в архиве» для архивной карточки.
    var title: String = "Задача в архиве"

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(task.title)
                        .tfText(.title)
                        .foregroundStyle(Color.tfText)
                    if let description = task.description, !description.isEmpty {
                        Text(.init(description))
                            .tfText(.row)
                            .foregroundStyle(Color.tfText)
                            .textSelection(.enabled)
                    }
                    LabeledContent("Проект", value: task.projectName ?? "Без проекта")
                    LabeledContent("Состояние", value: "В архиве")
                    LabeledContent("Результат", value: TaskVisibility.outcomeLabel(task))
                    if let created = task.createdAt {
                        LabeledContent("Создана", value: archiveDate(created))
                    }
                    if task.status == .completed, let completed = task.completedAt {
                        LabeledContent("Выполнена", value: archiveDate(completed))
                    }
                    if let date = task.archivedAt {
                        LabeledContent("В архиве с", value: archiveDate(date))
                    }
                }
                Section {
                    Button("Восстановить", systemImage: "arrow.uturn.backward") {
                        onRestore()
                    }
                    Button("Удалить окончательно", systemImage: "trash", role: .destructive) {
                        onDelete()
                    }
                }
                .disabled(isBusy)
            }
            .tfScreenBackground()
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }

    private func archiveDate(_ raw: String) -> String {
        DateFormats.sqliteUTC(raw)?.formatted(date: .abbreviated, time: .shortened) ?? raw
    }
}
