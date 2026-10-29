import SwiftUI

/// One entry point for existing assistant session capabilities.
///
/// С 29.10.2026 панель — общее окно сессии в чате с ролью: левая круглая
/// кнопка в новой панели ввода открывает её вместо выпадающего меню, а
/// то, что было в меню (вложения, режим работы), переехало сюда.
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
 /// Вложения: фото, файл, камера — раньше были в меню действий чата.
 var onAttachmentSource: ((ChatAttachmentSource) -> Void)? = nil
 /// Режим работы: Работа, Планирование, Цель, Исследование.
 var workMode: Binding<RoleChatWorkMode>? = nil
 var availableWorkModes: [RoleChatWorkMode] = [.work]
 @Environment(\.dismiss) private var dismiss
 @State private var title = ""
 @State private var showsCommands = false
 @State private var showsContext = false
 @State private var showsModelPicker = false
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
     Button { showsModelPicker = true } label: {
      LabeledContent("Модель чата", value: choice.effectiveTitle ?? "По умолчанию")
     }
     .tint(.primary)
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
     // Обычный цвет текста вместо синего (владелец 27.10.2026).
     Button { showsContext = true } label: {
      LabeledContent("Контекст", value: context?.summary ?? "Нет замера")
     }
     .tint(.primary)
     Button("Навыки и инструменты", systemImage: "wrench.and.screwdriver") { showsCommands = true }
      .tint(.primary)
    }
    // Вложения и режим работы — из меню действий чата (владелец 29.10.2026:
    // «в полосках то, что там есть, просто добавь в эту страничку»).
    if let onAttachmentSource {
     Section("Вложения") {
      Button { onAttachmentSource(.photo) } label: { Label("Фото", systemImage: "photo.on.rectangle") }
       .tint(.primary)
      Button { onAttachmentSource(.file) } label: { Label("Файл", systemImage: "doc") }
       .tint(.primary)
      Button { onAttachmentSource(.camera) } label: { Label("Камера", systemImage: "camera") }
       .tint(.primary)
     }
    }
    if let workMode {
     Section {
      Picker("Режим работы", selection: workMode) {
       ForEach(availableWorkModes, id: \.self) { mode in
        Label(mode.title, systemImage: mode.symbol).tag(mode)
       }
      }
      .pickerStyle(.inline)
      .accessibilityIdentifier("chat.session.workMode")
     } header: { Text("Режим работы") }
      footer: { Text("Режим определяет, как роль будет работать над задачей.") }
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
    .tint(.primary)
   }
   .disabled(choice.isSaving || actionRunning)
   .navigationTitle("Сессия")
   .navigationBarTitleDisplayMode(.inline)
   .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
   .sheet(isPresented: $showsContext) {
    ChatContextSheet(snapshot: context, roleName: nil, loadError: controls.errorText,
       onRefresh: { Task { await onRefresh() } })
   }
   .sheet(isPresented: $showsModelPicker) {
    ChatModelPickerSheet(choice: choice)
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
