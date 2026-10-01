import SwiftUI

struct RoleComposioSheet: View {
    let role: RoleProfile
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var settings: RoleComposio?
    @State private var enabled = false
    @State private var wholeCatalog = true
    @State private var selected = Set<String>()
    @State private var search = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if let settings {
                    Section(role.title) {
                        Toggle("Инструменты Composio", isOn: $enabled)
                        Toggle("Весь каталог", isOn: $wholeCatalog)
                            .disabled(!enabled)
                        Text(settings.available ? "Composio доступен" : (settings.error ?? "Composio недоступен"))
                        Text("В планировании доступны только инструменты чтения. Подключённые аккаунты общие для ваших ролей.")
                        if !wholeCatalog { Text("Выбрано: \(selected.count)") }
                    }
                    Section("Сервисы") {
                        ForEach(settings.catalog) { toolkit in
                            VStack(alignment: .leading) {
                                if wholeCatalog {
                                    Text(toolkit.name)
                                } else {
                                    Toggle(toolkit.name, isOn: Binding(
                                        get: { selected.contains(toolkit.slug) },
                                        set: { if $0 { selected.insert(toolkit.slug) } else { selected.remove(toolkit.slug) } }
                                    ))
                                }
                                if toolkit.connected || toolkit.noAuth {
                                    Text(toolkit.noAuth ? "Без авторизации" : "Аккаунт подключён")
                                        .font(.caption)
                                } else {
                                    Button("Подключить аккаунт") { Task { await connect(toolkit.slug) } }
                                }
                            }
                        }
                        if settings.catalog.isEmpty { Text("Ничего не найдено. Попробуйте другое название сервиса.") }
                    }
                } else if busy {
                    ProgressView("Загрузка Composio…")
                }
                if let error { Section { Text(error) } }
                Button("Обновить подключение") { Task { await load(initial: settings == nil) } }
            }
            .disabled(busy)
            .searchable(text: $search, prompt: "Найти сервис")
            .onSubmit(of: .search) { Task { await load(initial: false) } }
            .navigationTitle("Composio")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { Task { await save() } }.disabled(busy || settings == nil)
                }
            }
            .task { await load(initial: true) }
        }
    }

    private func load(initial: Bool) async {
        busy = true
        defer { busy = false }
        do {
            let result = try await APIClient().roleComposio(role: role.role, search: search)
            settings = result
            if initial {
                enabled = result.enabled
                wholeCatalog = result.toolkits == nil
                selected = Set(result.toolkits ?? [])
            }
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func save() async {
        busy = true
        defer { busy = false }
        do {
            try await APIClient().saveRoleComposio(role: role.role, enabled: enabled, toolkits: wholeCatalog ? nil : selected.sorted())
            dismiss()
        } catch { self.error = error.localizedDescription }
    }

    private func connect(_ toolkit: String) async {
        busy = true
        defer { busy = false }
        do {
            let result = try await APIClient().authorizeRoleComposio(role: role.role, toolkit: toolkit)
            guard let url = URL(string: result.url), url.scheme == "https" else {
                error = "Composio не вернул ссылку подключения"
                return
            }
            openURL(url)
        } catch { self.error = error.localizedDescription }
    }
}
