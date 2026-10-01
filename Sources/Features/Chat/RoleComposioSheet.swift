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
            ZStack {
                Color.tfBackground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: TFSpacing.lg) {
                        Text(role.title).tfText(.action).foregroundStyle(Color.tfSub)
                        TFTextField("Найти сервис", text: $search, icon: "magnifyingglass")
                            .accessibilityIdentifier("composio.search")
                            .onSubmit { Task { await load(initial: false) } }
                        if let settings {
                            TFCard {
                                VStack(alignment: .leading, spacing: TFSpacing.md) {
                                    settingToggle("Инструменты Composio", value: $enabled)
                                    TFDivider()
                                    settingToggle("Весь каталог", value: $wholeCatalog).disabled(!enabled)
                                    Text(settings.available ? "Composio доступен" : (settings.error ?? "Composio недоступен"))
                                        .tfText(.caption).foregroundStyle(Color.tfSub)
                                    Text("В планировании доступны только инструменты чтения. Аккаунты общие для ваших ролей.")
                                        .tfText(.caption).foregroundStyle(Color.tfDim)
                                    if !wholeCatalog { Text("Выбрано: \(selected.count)").tfText(.caption) }
                                }
                            }
                            TFSectionHeader("Сервисы")
                            LazyVStack(spacing: TFSpacing.sm) {
                                ForEach(settings.catalog) { toolkit in toolkitCard(toolkit) }
                            }
                            if settings.catalog.isEmpty {
                                Text("Ничего не найдено. Попробуйте другое название сервиса.")
                                    .tfText(.action).foregroundStyle(Color.tfSub)
                            }
                        } else if busy { TFLoading(.block) }
                        TFErrorBanner(error, variant: .block)
                        TFCard(padding: 0) {
                            TFListRow(icon: "arrow.clockwise", iconStyle: .plain,
                                      title: "Обновить подключение", action: { Task { await load(initial: settings == nil) } })
                        }
                    }
                    .padding(TFSpacing.lg)
                }
                .disabled(busy)
            }
            .tfNativeHeader("Composio", displayMode: .inline)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: TFSpacing.md) {
                    TFButton("Отмена", variant: .secondary) { dismiss() }
                        .accessibilityIdentifier("composio.cancel")
                    TFButton("Сохранить", icon: "checkmark", isEnabled: !busy && settings != nil) {
                        Task { await save() }
                    }
                }
                .padding(.horizontal, TFSpacing.lg)
                .padding(.vertical, TFSpacing.md)
                .background(Color.tfBackground)
            }
            .task { await load(initial: true) }
        }
    }

    private func settingToggle(_ title: String, value: Binding<Bool>) -> some View {
        HStack {
            Text(title).tfText(.body).foregroundStyle(Color.tfText)
            Spacer()
            TFToggle(isOn: value).accessibilityLabel(title)
        }
    }

    private func toolkitCard(_ toolkit: ComposioToolkit) -> some View {
        TFCard(padding: 0) {
            VStack(spacing: 0) {
                TFListRow(icon: "puzzlepiece.extension", iconStyle: .plain,
                          title: toolkit.name,
                          subtitle: toolkit.noAuth ? "Без авторизации" : toolkit.connected ? "Аккаунт подключён" : "Аккаунт не подключён",
                          trailing: wholeCatalog ? nil : AnyView(Image(systemName: selected.contains(toolkit.slug) ? "checkmark.square.fill" : "square").foregroundStyle(Color.tfSub)),
                          action: wholeCatalog ? nil : { if selected.contains(toolkit.slug) { selected.remove(toolkit.slug) } else { selected.insert(toolkit.slug) } })
                if !toolkit.connected && !toolkit.noAuth {
                    TFDivider(inset: TFSpacing.lg)
                    TFListRow(icon: "link", iconStyle: .plain, title: "Подключить аккаунт", action: { Task { await connect(toolkit.slug) } })
                }
            }
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
