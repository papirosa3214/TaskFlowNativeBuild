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
      .tint(.primary)
      .accessibilityIdentifier("chat.session.thinking")
     }
     if choice.isSaving { TFLoading(.inline) }
     if let error = choice.errorText {
      Text(error).foregroundStyle(.red)
      Button("Повторить загрузку") { Task { await onRefresh() } }
     }
    } header: { Text("Модель и размышления") }
    Section("Рабочее пространство") {
     ChatWorkspaceMenu(choice: workspace) {
      LabeledContent("Рабочая папка", value: workspace.selected ?? "По умолчанию")
     }
     // Контекст — теми же полосками, что в панели ввода: общая и по
     // составляющим. Нажатие открывает окно разбора (владелец 29.10.2026).
     Button { showsContext = true } label: { contextRow }
      .tint(.primary)
      .accessibilityIdentifier("chat.session.context")
     Button("Навыки и инструменты", systemImage: "wrench.and.screwdriver") { showsCommands = true }
      .tint(.primary)
    }
    // Вложения — блоками в ряд (владелец 29.10.2026: «фото, файл, камера в
    // самом начале сделано прикольно»).
    if let onAttachmentSource {
     Section("Вложения") {
      HStack(spacing: TFSpacing.sm) {
       ForEach(ChatSessionAttachment.allCases) { attachment in
        Button { onAttachmentSource(source(for: attachment)) } label: {
         VStack(spacing: TFSpacing.xs) {
          Image(systemName: attachment.symbol)
           .tfTypeFont(size: 18, weight: .medium)
           .foregroundStyle(Color.tfText)
           .frame(width: 38, height: 38)
           .background(Color.white.opacity(0.08),
                       in: RoundedRectangle(cornerRadius: 10, style: .continuous))
          Text(attachment.title)
           .tfText(.caption)
           .foregroundStyle(Color.tfText)
         }
         .frame(maxWidth: .infinity)
         .padding(.vertical, TFSpacing.xs)
         .background(Color.tfCard2, in: RoundedRectangle(cornerRadius: TFRadius.md, style: .continuous))
         .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("chat.session.attachment.\(attachment.rawValue)")
       }
      }
      .listRowInsets(EdgeInsets(top: TFSpacing.sm, leading: TFSpacing.md, bottom: TFSpacing.sm, trailing: TFSpacing.md))
     }
    }
    // Способ выполнения — двумя блоками (владелец 31.10.2026). Стоит рядом
    // с режимом работы: и то и другое отвечает на «как роль работает».
    if let executionMode {
     Section {
      HStack(spacing: TFSpacing.sm) {
       ForEach(ChatExecutionMode.allCases, id: \.self) { mode in
        executionModeBlock(mode, selection: executionMode)
       }
      }
      .listRowInsets(EdgeInsets(top: TFSpacing.sm, leading: TFSpacing.md, bottom: TFSpacing.sm, trailing: TFSpacing.md))
     } header: { Text("Способ выполнения") }
      footer: { Text("«В чате» — разговор здесь. «По карточке» — роль ведёт задачу: создаёт карточки, подзадачи и отмечает шаги.") }
    }
    // Режимы работы — четырьмя блоками (владелец 29.10.2026: «4 блока
    // поставить, режима работы, как минимум»).
    if let workMode {
     Section("Режим работы") {
      LazyVGrid(columns: [GridItem(.flexible(), spacing: TFSpacing.sm),
                           GridItem(.flexible(), spacing: TFSpacing.sm)],
                spacing: TFSpacing.sm) {
       ForEach(workModes, id: \.self) { mode in
        workModeBlock(mode, selection: workMode)
       }
      }
      .listRowInsets(EdgeInsets(top: TFSpacing.sm, leading: TFSpacing.md, bottom: TFSpacing.sm, trailing: TFSpacing.md))
     }
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

 /// Контекст: полоска общая и полоски по составляющим — как в панели ввода.
 @ViewBuilder private var contextRow: some View {
  VStack(alignment: .leading, spacing: TFSpacing.xs) {
   HStack {
    Text("Контекст")
     .tfText(.body)
     .foregroundStyle(Color.tfText)
    Spacer(minLength: TFSpacing.sm)
    Text(context?.summary ?? "Нет замера")
     .tfText(.caption)
     .foregroundStyle(Color.tfSub)
   }
   if let snapshot = context, snapshot.fraction != nil {
    ChatContextBar(snapshot: snapshot).frame(height: 10)
   }
  }
  .contentShape(Rectangle())
 }

 /// Блок способа выполнения: значок, название, строка пояснения и отметка.
 /// Стоит рядом с блоком режима работы и выглядит так же — только ниже
 /// названия ещё одна строка с пояснением.
 private func executionModeBlock(_ mode: ChatExecutionMode,
                                 selection: Binding<ChatExecutionMode>) -> some View {
  let isSelected = selection.wrappedValue == mode
  return Button {
   selection.wrappedValue = mode
  } label: {
   VStack(alignment: .leading, spacing: TFSpacing.xs) {
    HStack {
     Image(systemName: mode.symbol)
      .tfTypeFont(size: 16, weight: .medium)
      .foregroundStyle(isSelected ? Color.tfText : Color.tfSub)
     Spacer(minLength: 0)
     if isSelected {
      Image(systemName: "checkmark")
       .tfTypeFont(size: 13, weight: .semibold)
       .foregroundStyle(Color.tfText)
     }
    }
    Text(mode.title)
     .tfText(.body)
     .foregroundStyle(Color.tfText)
    Text(mode.summary)
     .tfText(.caption)
     .foregroundStyle(Color.tfDim)
     .fixedSize(horizontal: false, vertical: true)
   }
   .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
   .padding(TFSpacing.md)
   .background(Color.tfCard2, in: RoundedRectangle(cornerRadius: TFRadius.md, style: .continuous))
   .contentShape(Rectangle())
  }
  .buttonStyle(.plain)
  .disabled(!canChangeExecutionMode)
  .accessibilityIdentifier("chat.session.executionMode.\(mode.rawValue)")
 }

 /// Блок режима работы: значок, название и отметка выбранного.
 private func workModeBlock(_ mode: RoleChatWorkMode, selection: Binding<RoleChatWorkMode>) -> some View {
  let isSelected = selection.wrappedValue == mode
  let isEnabled = mode != .deepResearch || allowsResearch
  return Button {
   selection.wrappedValue = mode
  } label: {
   VStack(alignment: .leading, spacing: TFSpacing.xs) {
    HStack {
     Image(systemName: mode.symbol)
      .tfTypeFont(size: 16, weight: .medium)
      .foregroundStyle(isSelected ? Color.tfText : Color.tfSub)
     Spacer(minLength: 0)
     if isSelected {
      Image(systemName: "checkmark")
       .tfTypeFont(size: 13, weight: .semibold)
       .foregroundStyle(Color.tfText)
     }
    }
    Text(mode.title)
     .tfText(.body)
     .foregroundStyle(isEnabled ? Color.tfText : Color.tfDim)
    if mode == .deepResearch && !allowsResearch {
     Text("Только у Исследователя и Помощника")
      .tfText(.caption)
      .foregroundStyle(Color.tfDim)
    }
   }
   .frame(maxWidth: .infinity, alignment: .leading)
   .padding(TFSpacing.md)
   .background(Color.tfCard2, in: RoundedRectangle(cornerRadius: TFRadius.md, style: .continuous))
   .contentShape(Rectangle())
  }
  .buttonStyle(.plain)
  .disabled(!isEnabled)
  .accessibilityIdentifier("chat.session.workMode.\(mode.rawValue)")
 }
}
