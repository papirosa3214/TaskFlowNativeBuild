import SwiftUI

/// Правка одного быстрого действия: всплывающее окошечко снизу вверх
/// (владелец 29.10.2026: «щелкнув по какому-то из квадратиков, у меня откроется
/// снизу вверх такое всплывающее окошечко, где я напишу название этого промта и
/// дальше уже какой-то конкретный промпт»).
struct RoleChatQuickActionEditor: View {
    /// Штатное название и промпт карточки — подсказка, что было.
    let stockCommand: RoleChatStarterCommand
    /// Текущие значения полей.
    let initial: RoleChatQuickActionOverride
    /// Сохранение правки.
    let onSave: (RoleChatQuickActionOverride) -> Void
    /// Возврат карточки к штатной.
    let onReset: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var prompt: String
    @FocusState private var nameFocused: Bool

    init(stockCommand: RoleChatStarterCommand,
         initial: RoleChatQuickActionOverride,
         onSave: @escaping (RoleChatQuickActionOverride) -> Void,
         onReset: @escaping () -> Void) {
        self.stockCommand = stockCommand
        self.initial = initial
        self.onSave = onSave
        self.onReset = onReset
        _name = State(initialValue: initial.name ?? stockCommand.title)
        _prompt = State(initialValue: initial.prompt ?? stockCommand.prompt)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Название", text: $name, axis: .vertical)
                        .lineLimit(1...2)
                        .focused($nameFocused)
                        .accessibilityIdentifier("chat.quickAction.name")
                    TextField("Промпт", text: $prompt, axis: .vertical)
                        .lineLimit(3...8)
                        .accessibilityIdentifier("chat.quickAction.prompt")
                } header: {
                    Text("Быстрое действие")
                } footer: {
                    Text("Название видно на карточке, промпт подставляется в поле ввода. Пустые поля вернут штатный вариант.")
                }
                Section {
                    Button("Вернуть штатный вариант") {
                        onReset()
                        dismiss()
                    }
                    .tint(.primary)
                    .accessibilityIdentifier("chat.quickAction.reset")
                } footer: {
                    Text("Штатно: «\(stockCommand.title)»")
                }
            }
            .tint(.primary)
            .navigationTitle("Быстрое действие")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        onSave(RoleChatQuickActionOverride(name: name, prompt: prompt))
                        dismiss()
                    }
                    .accessibilityIdentifier("chat.quickAction.save")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task { nameFocused = true }
    }
}
