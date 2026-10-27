import SwiftUI

/// One entry point for existing assistant session capabilities.
struct ChatSessionPanel: View {
 let chat: RoleChat
 @Bindable var choice: ChatModelChoice
 let workspace: ChatWorkspaceChoice
 let context: ChatContextSnapshot?
 let controls: ChatComposerControlStore
 let isWorking: Bool
 let onRefresh: () async -> Void
 let onRename: (String) async -> Void
 let onNewSession: () -> Void
 let onCompact: () async -> Void
 let onResetContext: () async -> Void
 let onClose: () async -> Void
 let onSelectCommand: (ChatSlashCommand) -> Void
 @Environment(\.dismiss) private var dismiss
 @State private var title = ""
 @State private var showsCommands = false
 @State private var showsContext = false
 @State private var confirmsReset = false
 @State private var actionRunning = false

 var body: some View {
  NavigationStack {
   Form {
    Section("Сессия") {
     TextField("Название", text: $title)
      .onSubmit { Task { await onRename(title) } }
     Button("Сохранить название") { Task { await onRename(title) } }
      .disabled(title == (chat.title ?? ""))
     LabeledContent("Состояние", value: chat.closedAt != nil ? "Закрыта" : isWorking ? "Работает" : "Готова")
    }
    Section {
     Picker("Модель чата", selection: Binding(get: { choice.selected ?? "" }, set: { model in
      Task { await choice.selectModel(model.isEmpty ? nil : model) }
     })) {
      Text("По умолчанию").tag("")
      ForEach(RoleModelOption.grouped(choice.options)) { group in
       Section(group.provider) {
        ForEach(group.models) { option in Text(option.title).tag(option.id) }
       }
      }
     }
     .accessibilityIdentifier("chat.session.model")
     if !choice.availableThinkingLevels.isEmpty {
      Picker("Размышления", selection: Binding(get: { choice.thinkingLevel ?? "" }, set: { level in
       Task { await choice.selectThinking(level.isEmpty ? nil : level) }
      })) {
       Text("По настройке роли").tag("")
       ForEach(choice.availableThinkingLevels, id: \.self) { level in
        Text(choice.effectiveOption?.thinkingLevelLabels?[level] ?? ChatSessionPreferences.thinkingTitle(level)).tag(level)
       }
      }
      .accessibilityIdentifier("chat.session.thinking")
     }
     if let name = choice.effectiveTitle { LabeledContent("Выбрана", value: name) }
     if choice.isSaving { ProgressView("Сохранение") }
     if let error = choice.errorText {
      Text(error).foregroundStyle(.red)
      Button("Повторить загрузку") { Task { await onRefresh() } }
     }
    } header: { Text("Модель и размышления") }
      footer: { Text("Настройки сохраняются для этой сессии и действуют со следующего сообщения.") }
    Section("Рабочее пространство") {
     ChatWorkspaceMenu(choice: workspace) {
      LabeledContent("Папка", value: workspace.selected ?? "По умолчанию")
     }
     Button { showsContext = true } label: {
      LabeledContent("Контекст", value: context?.summary ?? "Нет замера")
     }
     Button("Навыки и инструменты", systemImage: "wrench.and.screwdriver") { showsCommands = true }
    }
    Section {
     Button("Новая сессия", systemImage: "plus.bubble") {
      dismiss()
      onNewSession()
     }
     Button("Сжать контекст", systemImage: "arrow.down.right.and.arrow.up.left") {
      Task { await perform(onCompact) }
     }
     Button("Сбросить контекст", systemImage: "arrow.counterclockwise") { confirmsReset = true }
     if !chat.isPermanentRoom {
      Button("Закрыть сессию", systemImage: "archivebox") {
       Task { await perform(onClose); dismiss() }
      }
     }
    } footer: { Text("Новая сессия создаёт отдельный разговор. Сброс контекста оставляет историю в текущем разговоре.") }
   }
   .disabled(choice.isSaving || actionRunning)
   .navigationTitle("Сессия")
   .navigationBarTitleDisplayMode(.inline)
   .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
   .sheet(isPresented: $showsContext) {
    ChatContextSheet(snapshot: context, roleName: nil, loadError: controls.errorText,
       onRefresh: { Task { await onRefresh() } })
   }
   .sheet(isPresented: $showsCommands) {
    ChatCommandPicker(commands: controls.commands, errorText: controls.errorText,
       onRefresh: { Task { await onRefresh() } }, onSelect: { command in
        dismiss()
        onSelectCommand(command)
       })
   }
   .confirmationDialog("Сбросить контекст этой сессии?", isPresented: $confirmsReset, titleVisibility: .visible) {
    Button("Сбросить контекст") { Task { await perform(onResetContext) } }
    Button("Отмена", role: .cancel) {}
   } message: { Text("История останется в чате. Помощник начнёт новый контекст.") }
  }
  .task { title = chat.title ?? "" }
 }
 private func perform(_ action: () async -> Void) async {
  guard !actionRunning else { return }
  actionRunning = true
  defer { actionRunning = false }
  await action()
 }
}
