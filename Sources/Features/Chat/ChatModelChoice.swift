import Foundation
import SwiftUI
import Observation

/// Model and thinking preferences belong to the assistant conversation on the server.
@MainActor
@Observable
final class ChatModelChoice {
 private(set) var options: [RoleModelOption] = []
 private(set) var current: String?
 private(set) var selected: String?
 private(set) var thinkingLevel: String?
 private(set) var isSaving = false
 private(set) var isReady = false
 private(set) var errorText: String?
 private var key: String?
 private var chatID: String?
 private var usesSessionPreferences = false
 private var revision = 0
 private let api = APIClient()

 var isAvailable: Bool { !options.isEmpty }
 var effectiveOption: RoleModelOption? { options.first { $0.id == (selected ?? current) } }
 var availableThinkingLevels: [String] { effectiveOption?.availableThinkingLevels ?? [] }
 var effectiveTitle: String? { effectiveOption?.title ?? selected ?? current }
 var title: String { selected == nil ? "Модель" : effectiveTitle ?? "Модель" }
 /// Уровень размышлений сервер умеет хранить для чата — только тогда его и
 /// показываем (владелец 29.10.2026: «мозг, где можно выбирать модели с
 /// уровнем рассуждений»).
 var supportsThinkingLevels: Bool { usesSessionPreferences }

 func load(chat: RoleChat) async {
  revision += 1
  let version = revision
  isReady = false
  errorText = nil
  // Роль в чате: ровно одна — к ней привязан выбор модели. В комнате ролей
  // их несколько, там своя схема (кольца контекста; владелец 29.10.2026:
  // «в чате с помощником там немножечко другая схема»).
  let roles = chat.composerRoleKeys
  guard roles.count == 1, let role = roles.first else { options = []; return }
  chatID = chat.id
  key = "roleChat.model." + chat.createdBy + "." + chat.id
  do {
   let result = try await api.roleModels(role: role)
   guard revision == version else { return }
   options = result.models
   current = RoleModelOption.resolveSelection(result.current, in: options) ?? result.current
   // Выбор модели и уровень размышлений хранит сервер — для любого личного
   // чата с ролью (29.10.2026). Если сервер их не дал (чат не личный) —
   // остаётся прежний выбор на устройстве, без уровня размышлений.
   var state: ChatSessionPreferences? = nil
   do { state = try await api.request(.get, "/chats/\(chat.id)/session-preferences") } catch { state = nil }
   if let state {
    usesSessionPreferences = true
    selected = state.model
    thinkingLevel = state.thinkingLevel
    // Перенос прежнего выбора с устройства — один раз; дальше выбор хранит
    // сервер.
    if !state.configured, let legacy = key.flatMap({ UserDefaults.standard.string(forKey: $0) }),
       let resolved = RoleModelOption.resolveSelection(legacy, in: options) {
     await save(model: resolved, thinking: nil)
     guard errorText == nil else { return }
    }
   } else {
    usesSessionPreferences = false
    selected = RoleModelOption.resolveSelection(key.flatMap { UserDefaults.standard.string(forKey: $0) }, in: options)
    thinkingLevel = nil
   }
   isReady = true
  } catch {
   guard revision == version else { return }
   errorText = error.localizedDescription
  }
 }

 func selectModel(_ model: String?) async {
  guard model != selected else { return }
  let option = options.first { $0.id == (model ?? current) }
  let compatible = ChatSessionPreferences.validThinking(thinkingLevel, available: option?.availableThinkingLevels ?? [])
  await save(model: model, thinking: compatible)
 }
 func selectThinking(_ level: String?) async {
  guard level == nil || availableThinkingLevels.contains(level!) else { return }
  await save(model: selected, thinking: level)
 }
 private func save(model: String?, thinking: String?) async {
  guard !isSaving else { return }
  isSaving = true
  errorText = nil
  defer { isSaving = false }
  if usesSessionPreferences {
   guard let chatID else { return }
   let version = revision
   do {
    let state: ChatSessionPreferences = try await api.request(.put, "/chats/\(chatID)/session-preferences",
        body: ["model": model.map(JSONValue.string) ?? .null,
               "thinkingLevel": thinking.map(JSONValue.string) ?? .null])
    guard version == revision else { return }
    selected = state.model
    thinkingLevel = state.thinkingLevel
    isReady = true
   } catch { if version == revision { errorText = error.localizedDescription } }
  } else {
   selected = model
   thinkingLevel = nil
   if let key { UserDefaults.standard.set(model, forKey: key) }
  }
 }
}

/// «Мозг» в панели ввода: открывает список моделей с описаниями, галочкой,
/// звёздочками избранного и строкой «Усилия» (владелец 29.10.2026, образец
/// из другого приложения). Раньше это был выпадающий список без описаний.
struct ChatModelMenu<MenuLabel: View>: View {
 @Bindable var choice: ChatModelChoice
 @ViewBuilder let label: () -> MenuLabel
 @State private var showsPicker = false

 var body: some View {
  Button { showsPicker = true } label: { label() }
   .buttonStyle(.plain)
   .disabled(choice.isSaving)
   .accessibilityIdentifier("chat.model")
   .accessibilityLabel("Модель: " + choice.title)
   .sheet(isPresented: $showsPicker) {
    ChatModelPickerSheet(choice: choice)
   }
 }
}
