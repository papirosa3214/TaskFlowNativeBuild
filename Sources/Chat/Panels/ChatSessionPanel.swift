import SwiftUI

/// Окно сессии в чате с ролью.
///
/// С 29.10.2026 это общее окно: левая круглая кнопка новой панели ввода
/// открывает его вместо выпадающего меню, и то, что было в меню (вложения,
/// режим работы), переехало сюда.
///
/// Замечания владельца (29.10.2026), которые здесь учтены:
/// - никакого синего: всё в обычном цвете текста;
/// - сверху — одна аккуратная строка с названием, без «Сохранить название»,
///   без «Состояние» и без повторов «Готово»;
/// - вложения — блоками (фото, файл, камера), а не списком;
/// - режимы работы — четырьмя блоками;
/// - контекст — такими же полосками, как в панели ввода, с раскрытием в
///   окно разбора.
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
 /// Способ выполнения: «В чате» или «По карточке».
 ///
 /// Владелец 31.10.2026: «в настройках, где сессия… нужно вставить
 /// переключатель, где режим чата и где режим задачи». Раньше он был только
 /// в меню панели ввода и у Помощника пропадал совсем; здесь он есть у всех
 /// ролей, включая Помощника.
 var executionMode: Binding<ChatExecutionMode>? = nil
 /// Пока идёт сохранение или отправка — блоки не переключаются.
 var canChangeExecutionMode: Bool = true
 /// Роли чата — по ним решается, доступно ли глубокое исследование.
 var chatRoles: [String] = []
 @Environment(\.dismiss) private var dismiss
 @State private var title = ""
 @State private var showsCommands = false
 @State private var showsContext = false
 @State private var showsModelPicker = false
 @State private var confirmsReset = false
 @State private var actionRunning = false

 /// Режимы работы: все четыре блоком. Глубокое исследование сервер
 /// принимает только у Исследователя и Помощника — у остальных блок остаётся
 /// видимым, но нажать его нельзя.
 private var workModes: [RoleChatWorkMode] {
  ChatSessionWorkModePolicy.allModes
 }

 private var allowsResearch: Bool {
  ChatSessionWorkModePolicy.allowsResearch(roles: chatRoles)
 }

 var body: some View {
  NavigationStack {
   Form {
    // Название — одна строка, без кнопки «Сохранить» и без «Состояние»
    // (владелец 29.10.2026: «лучше уж одну аккуратненькую полянку… просто
    // оставить линию, подчёркнутую»).
    Section {
     TextField("Название", text: $title)
      .onSubmit { Task { await onRename(title) } }
      .sessionFormRow()
    }
    Section {
     Button { showsModelPicker = true } label: {
      LabeledContent("Модель чата", value: choice.effectiveTitle ?? "По умолчанию")
     }
     .tint(.primary)
     .sessionFormRow()
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
      .tint(.primary)
      .sessionFormRow()
      .accessibilityIdentifier("chat.session.thinking")
     }
     if choice.isSaving { TFLoading(.inline).sessionFormRow() }
     if let error = choice.errorText {
      Text(error).foregroundStyle(.red).sessionFormRow()
      Button("Повторить загрузку") { Task { await onRefresh() } }
       .sessionFormRow()
     }
    } header: { Text("Модель и размышления") }
    // Три одинаковые строки без одинокой иконки у инструментов (владелец
    // 03.11.2026: «с иконкой своей, когда остальные ее не имели»).
    Section("Рабочее пространство") {
     ChatWorkspaceMenu(choice: workspace) {
      LabeledContent("Рабочая папка", value: workspace.selected ?? "По умолчанию")
     }
     .sessionFormRow()
     // Контекст — теми же полосками, что в панели ввода: общая и по
     // составляющим. Нажатие открывает окно разбора (владелец 29.10.2026).
     Button { showsContext = true } label: { contextRow }
      .tint(.primary)
      .sessionFormRow()
      .accessibilityIdentifier("chat.session.context")
     Button { showsCommands = true } label: {
      Text("Навыки и инструменты")
       .tfText(.body)
       .foregroundStyle(Color.tfText)
       .frame(maxWidth: .infinity, alignment: .leading)
       .contentShape(Rectangle())
     }
     .tint(.primary)
     .sessionFormRow()
     .accessibilityIdentifier("chat.session.commands")
    }
    // Вложения — три равных плитки в ряд (владелец 29.10.2026; правка
    // 03.11.2026: без лишней высоты и мелкого тонкого подписей).
    if let onAttachmentSource {
     Section("Вложения") {
      HStack(spacing: TFSpacing.xs) {
       ForEach(ChatSessionAttachment.allCases) { attachment in
        Button { onAttachmentSource(source(for: attachment)) } label: {
         VStack(spacing: 2) {
          Image(systemName: attachment.symbol)
           .tfTypeFont(size: 16, weight: .semibold)
           .foregroundStyle(Color.tfText)
           .frame(width: 30, height: 30)
           .background(Color.primary.opacity(0.08),
                       in: RoundedRectangle(cornerRadius: TFRadius.sm, style: .continuous))
          Text(attachment.title)
           .tfText(.action)
           .foregroundStyle(Color.tfText)
           .lineLimit(1)
         }
         .frame(maxWidth: .infinity)
         .padding(.vertical, TFSpacing.xs)
         .sessionChoiceSurface(selected: false)
         .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("chat.session.attachment.\(attachment.rawValue)")
       }
      }
      .sessionFormRow()
     }
    }
    // Способ выполнения — две равные плитки (владелец 31.10.2026; правка
    // 03.11.2026: одна высота, один шрифт, без пустоты вокруг).
    if let executionMode {
     Section {
      HStack(alignment: .top, spacing: TFSpacing.xs) {
       ForEach(ChatExecutionMode.allCases, id: \.self) { mode in
        executionModeBlock(mode, selection: executionMode)
       }
      }
      .sessionFormRow()
     } header: { Text("Способ выполнения") }
      footer: { Text("«В чате» — разговор здесь. «По карточке» — роль ведёт задачу.") }
    }
    // Режимы работы — симметричная сетка 2×2 (владелец 29.10.2026; правка
    // 03.11.2026: по центру, равные клетки, без гигантских полей).
    if let workMode {
     Section("Режим работы") {
      LazyVGrid(columns: [GridItem(.flexible(), spacing: TFSpacing.xs),
                           GridItem(.flexible(), spacing: TFSpacing.xs)],
                spacing: TFSpacing.xs) {
       ForEach(workModes, id: \.self) { mode in
        workModeBlock(mode, selection: workMode)
       }
      }
      .sessionFormRow()
     }
    }
    Section {
     Button("Новая сессия", systemImage: "plus.bubble") {
      dismiss()
      onNewSession()
     }
     .sessionFormRow()
     Button("Сжать контекст", systemImage: "arrow.down.right.and.arrow.up.left") {
      Task { await perform(onCompact) }
     }
     .sessionFormRow()
     Button("Сбросить контекст", systemImage: "arrow.counterclockwise") { confirmsReset = true }
      .sessionFormRow()
     if !chat.isPermanentRoom {
      Button("Закрыть сессию", systemImage: "archivebox") {
       Task { await perform(onClose); dismiss() }
      }
      .sessionFormRow()
     }
    } footer: { Text("Новая сессия создаёт отдельный разговор. Сброс контекста оставляет историю.") }
    .tint(.primary)
   }
   // Владелец 03.11.2026: отступы меню нормальные, не гигантские.
   .listSectionSpacing(TFSpacing.sm)
   .environment(\.defaultMinListRowHeight, 34)
   .tfScreenBackground()
   // Обычный цвет текста вместо синего (владелец 29.10.2026).
   .tint(.primary)
   .disabled(choice.isSaving || actionRunning)
   .navigationTitle("Сессия")
   .navigationBarTitleDisplayMode(.inline)
   .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() }.tint(.primary) } }
   .sheet(isPresented: $showsContext) {
    ChatContextSheet(snapshot: context, roleName: nil, loadError: controls.errorText,
       onRefresh: { Task { await onRefresh() } })
   }
   .sheet(isPresented: $showsModelPicker) {
    ChatModelPickerSheet(choice: choice)
   }
   .sheet(isPresented: $showsCommands) {
    ChatCommandPicker(commands: controls.commands, errorText: controls.errorText,
       onRefresh: { Task { await onRefresh() } }) { command in
        dismiss()
        onSelectCommand(command)
       }
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

 private func source(for attachment: ChatSessionAttachment) -> ChatAttachmentSource {
  switch attachment {
  case .photo: .photo
  case .file: .file
  case .camera: .camera
  }
 }

 /// Контекст: заголовок как у соседних строк + полоски под ним.
 @ViewBuilder private var contextRow: some View {
  VStack(alignment: .leading, spacing: TFSpacing.xs) {
   HStack(alignment: .firstTextBaseline) {
    Text("Контекст")
     .tfText(.body)
     .foregroundStyle(Color.tfText)
    Spacer(minLength: TFSpacing.sm)
    Text(context?.summary ?? "Нет замера")
     .tfText(.body)
     .foregroundStyle(Color.tfSub)
     .multilineTextAlignment(.trailing)
   }
   if let snapshot = context, snapshot.fraction != nil {
    ChatContextBar(snapshot: snapshot).frame(height: 8)
   }
  }
  .contentShape(Rectangle())
 }

 /// Блок способа выполнения: две колонки одной высоты, один кегль текста.
 private func executionModeBlock(_ mode: ChatExecutionMode,
                                 selection: Binding<ChatExecutionMode>) -> some View {
  let isSelected = selection.wrappedValue == mode
  return Button {
   selection.wrappedValue = mode
  } label: {
   VStack(alignment: .leading, spacing: 2) {
    HStack(spacing: TFSpacing.xs) {
     Image(systemName: mode.symbol)
      .tfTypeFont(size: 15, weight: .semibold)
      .foregroundStyle(Color.tfText)
      .frame(width: 18, alignment: .center)
     Spacer(minLength: 0)
     Image(systemName: "checkmark")
      .tfTypeFont(size: 12, weight: .semibold)
      .foregroundStyle(Color.tfText)
      .opacity(isSelected ? 1 : 0)
      .accessibilityHidden(!isSelected)
    }
    Text(mode.title)
     .tfText(.body)
     .foregroundStyle(Color.tfText)
     .lineLimit(1)
    Text(mode.summary)
     .tfText(.action)
     .foregroundStyle(Color.tfSub)
     .fixedSize(horizontal: false, vertical: true)
     .frame(maxWidth: .infinity, alignment: .leading)
   }
   .padding(TFSpacing.xs)
   .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
   .sessionChoiceSurface(selected: isSelected)
   .contentShape(Rectangle())
  }
  .buttonStyle(.plain)
  .disabled(!canChangeExecutionMode)
  .accessibilityIdentifier("chat.session.executionMode.\(mode.rawValue)")
 }

 /// Блок режима работы: клетка 2×2 по центру, галочка в углу не ломает ось.
 private func workModeBlock(_ mode: RoleChatWorkMode, selection: Binding<RoleChatWorkMode>) -> some View {
  let isSelected = selection.wrappedValue == mode
  let isEnabled = mode != .deepResearch || allowsResearch
  return Button {
   selection.wrappedValue = mode
  } label: {
   VStack(spacing: 2) {
    Image(systemName: mode.symbol)
     .tfTypeFont(size: 16, weight: .semibold)
     .foregroundStyle(isEnabled ? Color.tfText : Color.tfSub)
     .frame(height: 18)
    Text(mode.title)
     .tfText(.body)
     .foregroundStyle(isEnabled ? Color.tfText : Color.tfSub)
     .lineLimit(1)
     .minimumScaleFactor(0.85)
    if mode == .deepResearch && !allowsResearch {
     Text("Только у Исследователя и Помощника")
      .tfText(.action)
      .foregroundStyle(Color.tfSub)
      .multilineTextAlignment(.center)
      .lineLimit(2)
      .minimumScaleFactor(0.9)
    }
   }
   .frame(maxWidth: .infinity, minHeight: 56)
   .padding(.horizontal, TFSpacing.xs)
   .padding(.vertical, TFSpacing.xs)
   .sessionChoiceSurface(selected: isSelected)
   .overlay(alignment: .topTrailing) {
    Image(systemName: "checkmark")
     .tfTypeFont(size: 11, weight: .semibold)
     .foregroundStyle(Color.tfText)
     .padding(TFSpacing.xs)
     .opacity(isSelected ? 1 : 0)
     .accessibilityHidden(!isSelected)
   }
   .contentShape(Rectangle())
  }
  .buttonStyle(.plain)
  .disabled(!isEnabled)
  .accessibilityIdentifier("chat.session.workMode.\(mode.rawValue)")
 }
}

private extension View {
 /// Компактная строка Form: меньше полей, чем системные по умолчанию
 /// (владелец 03.11.2026: «не гигантские» отступы).
 func sessionFormRow() -> some View {
  self.listRowInsets(EdgeInsets(
   top: 6, leading: TFSpacing.md,
   bottom: 6, trailing: TFSpacing.md
  ))
 }

 /// Плитка выбора внутри секции Form: лёгкая заливка и тонкая обводка у
 /// выбранной — без второго тяжёлого «карточного» слоя и без дыр по краям.
 func sessionChoiceSurface(selected: Bool) -> some View {
  self
   .background(
    RoundedRectangle(cornerRadius: TFRadius.md, style: .continuous)
     .fill(selected ? Color.tfCard2 : Color.primary.opacity(0.06))
   )
   .overlay(
    RoundedRectangle(cornerRadius: TFRadius.md, style: .continuous)
     .strokeBorder(selected ? Color.tfText.opacity(0.28) : Color.clear, lineWidth: 1)
   )
 }
}
