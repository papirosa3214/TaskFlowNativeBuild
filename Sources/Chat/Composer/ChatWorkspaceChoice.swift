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
    @State private var presentationDetent: PresentationDetent = .medium

    var body: some View {
        Button { presentationDetent = .medium; isPresented = true } label: { label() }
            .buttonStyle(.plain)
            .accessibilityIdentifier("chat.workspace")
            .accessibilityLabel("Рабочая папка: " + choice.title)
            .tfSheet(isPresented: $isPresented) {
                ChatWorkspaceBrowser(choice: choice)
                    .presentationDetents([.medium, .large], selection: $presentationDetent)
                    .presentationDragIndicator(.visible)
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
                Section {
                    if let parent = listing?.parent {
                        Button { open(parent) } label: {
                            folderRow("Наверх", symbol: "arrow.turn.left.up")
                        }
                        .buttonStyle(.plain)
                        .tfSettingsListRow(background: .clear)
                    }
                    ForEach(listing?.entries ?? []) { entry in
                        Button { open(entry.path) } label: {
                            folderRow(entry.name, selected: entry.path == choice.selected)
                        }
                        .buttonStyle(.plain)
                        .tfSettingsListRow(background: .clear)
                        .accessibilityAddTraits(entry.path == choice.selected ? .isSelected : [])
                    }
                    if !isLoading, listing?.entries.isEmpty ?? true {
                        Text(listing == nil ? "Папка недоступна" : "Внутри папок нет")
                            .tfText(.body)
                            .foregroundStyle(Color.tfSub)
                            .frame(minHeight: 40)
                            .tfSettingsListRow(background: .clear)
                    }
                }
                if !path.isEmpty {
                    Section {
                        Button {
                            Task { await choice.select(path); dismiss() }
                        } label: {
                            Text(path == choice.selected ? "Выбрана: \(path)" : "Работать в «\(path)»")
                                .tfText(.body)
                                .foregroundStyle(path == choice.selected ? Color.tfSub : Color.tfText)
                                .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(path == choice.selected)
                        .tfSettingsListRow(background: .clear)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .listSectionSpacing(TFSpacing.sm)
            .environment(\.defaultMinListRowHeight, 40)
            .tfScreenBackground()
            .overlay { if isLoading && listing == nil { ProgressView() } }
            .navigationTitle(listing?.title ?? "Проекты")
            .navigationBarTitleDisplayMode(.inline)
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
        }
        .environment(\.tfTypeSettingsEnabled, true)
        .task {
            // Открываем там, где выбрано сейчас; нет выбора — корень проектов.
            await load(choice.selected ?? "")
        }
    }

    private func folderRow(_ title: String, selected: Bool = false, symbol: String = "checkmark") -> some View {
        HStack(spacing: TFSpacing.sm) {
            Image(systemName: symbol)
                .tfTypeFont(size: TFIconSize.xs, weight: .semibold)
                .foregroundStyle(Color.tfText)
                .frame(width: 18, height: 40)
                .opacity(selected || symbol != "checkmark" ? 1 : 0)
                .accessibilityHidden(!selected && symbol == "checkmark")
            Text(title)
                .tfText(.body)
                .foregroundStyle(Color.tfText)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right") // design-system-guard: ignore — владелец 07.11: компоновка строки как у выбора модели
                .tfTypeFont(size: TFIconSize.xs, weight: .semibold)
                .foregroundStyle(Color.tfSub)
        }
        .frame(minHeight: 40)
        .contentShape(Rectangle())
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
