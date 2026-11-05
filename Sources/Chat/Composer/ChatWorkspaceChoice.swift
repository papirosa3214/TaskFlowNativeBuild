import Foundation
import SwiftUI
import Observation

/// Рабочая папка в окне ввода чата с ролью (владелец 27.10.2026: «как во всех
/// других системах»). Выбор хранится на сервере за чатом и действует со
/// следующего хода роли.
@MainActor
@Observable
final class ChatWorkspaceChoice {
    private(set) var state: ChatWorkspaceState?
    private var chatID: String?
    private let api = APIClient()

    var isAvailable: Bool { !(state?.options.isEmpty ?? true) }
    var title: String { state?.title ?? "Папка" }
    var selected: String? { state?.selected }

    /// Рабочая папка есть в личном чате с одной ролью — у любой роли, а не
    /// только у Помощника (владелец 29.10.2026: «с другими всеми ролями
    /// должна быть именно та схема — мозг и папка»). В комнате ролей выбор
    /// папки не показывается: там своя схема (кольца контекста).
    func load(chat: RoleChat) async {
        guard chat.composerRoleKeys.count == 1 else {
            state = nil
            return
        }
        chatID = chat.id
        state = try? await api.request(.get, "/chats/\(chat.id)/workspace")
    }

    /// Содержимое папки для шторки; nil — папки нет или сервер недоступен.
    func browse(_ path: String) async -> ChatFolderListing? {
        guard let chatID else { return nil }
        return try? await api.request(.get, "/chats/\(chatID)/workspace/browse",
                                      query: [URLQueryItem(name: "path", value: path)])
    }

    func select(_ name: String?) async {
        guard let chatID else { return }
        if let updated: ChatWorkspaceState = try? await api.request(
            .put, "/chats/\(chatID)/workspace", body: ["name": name ?? ""]
        ) {
            state = updated
        }
    }
}

/// Чип открывает шторку снизу с обзором папок (владелец 27.10.2026: «как
/// обычный состав папок — выходить в корень, заходить в папку, выходить»).
struct ChatWorkspaceMenu<MenuLabel: View>: View {
    @Bindable var choice: ChatWorkspaceChoice
    @ViewBuilder let label: () -> MenuLabel
    @State private var isPresented = false

    var body: some View {
        Button { isPresented = true } label: { label() }
            .buttonStyle(.plain)
            .accessibilityIdentifier("chat.workspace")
            .accessibilityLabel("Рабочая папка: " + choice.title)
            .tfSheet(isPresented: $isPresented) {
                ChatWorkspaceBrowser(choice: choice)
                    .presentationDetents([.medium, .large])
            }
    }
}

/// Один список: внутри папки — её папки, строка «Наверх» ведёт к родителю,
/// внизу — выбрать текущую. Без стопки экранов: заходишь и выходишь на месте.
private struct ChatWorkspaceBrowser: View {
    @Bindable var choice: ChatWorkspaceChoice
    @Environment(\.dismiss) private var dismiss
    @State private var path = ""
    @State private var listing: ChatFolderListing?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            List {
                if let parent = listing?.parent {
                    Button { open(parent) } label: {
                        Label("Наверх", systemImage: "arrow.turn.left.up")
                            .foregroundStyle(Color.tfText)
                    }
                }
                ForEach(listing?.entries ?? []) { entry in
                    Button { open(entry.path) } label: {
                        TFListRow(
                            icon: "folder.fill",
                            iconStyle: .plain,
                            title: entry.name,
                            trailing: entry.path == choice.selected
                                ? AnyView(Image(systemName: "checkmark").foregroundStyle(Color.tfText))
                                : nil,
                            horizontalPadding: 0,
                            chevron: .shown
                        )
                        .contentShape(Rectangle())
                    }
                }
                if !isLoading, listing?.entries.isEmpty ?? true {
                    Text(listing == nil ? "Папка недоступна" : "Внутри папок нет")
                        .foregroundStyle(Color.tfSub)
                }
            }
            .tfScreenBackground()
            .overlay { if isLoading && listing == nil { ProgressView() } }
            .tfNativeHeader(listing?.title ?? "Проекты", displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("По умолчанию") {
                        Task { await choice.select(nil); dismiss() }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !path.isEmpty {
                    TFButton(path == choice.selected ? "Выбрана: \(path)" : "Работать в «\(path)»",
                             icon: "folder", variant: .secondary, isEnabled: path != choice.selected) {
                        Task { await choice.select(path); dismiss() }
                    }
                    .padding(TFSpacing.lg)
                }
            }
        }
        .task {
            // Открываем там, где выбрано сейчас; нет выбора — корень проектов.
            await load(choice.selected ?? "")
        }
    }

    private func open(_ next: String) {
        Task { await load(next) }
    }

    private func load(_ next: String) async {
        isLoading = true
        defer { isLoading = false }
        if let result = await choice.browse(next) {
            listing = result
            path = result.path
        } else if listing == nil, let root = await choice.browse("") {
            listing = root
            path = ""
        }
    }
}
