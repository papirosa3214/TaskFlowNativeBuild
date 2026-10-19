import SwiftUI
import Observation

/// Один снимок подключений для «Интеграций» и профиля Помощника владельца.
/// Адреса — существующий Gmail API, возможности — серверный каталог роли.
@MainActor @Observable
final class ExternalAppAccessStore {
    static let shared = ExternalAppAccessStore()
    var accounts: [MailAccount] = []
    var mailError: String?
    private var mailLoaded = false
    var thingsStatus = "Не проверено"
    var thingsDetail = "Обнови доступность подключения."
    var thingsReadable = false
    var loading = false
    var catalogError: String?
    private var tools: [RoleToolDetail] = []
    private let api = APIClient()

    var gmailStatus: String {
        if !mailLoaded { return "Не проверено" }
        if mailError != nil { return "Не удалось проверить" }
        if accounts.contains(where: \.connected) { return "Подключён" }
        return accounts.isEmpty ? "Не подключён" : "Нужна авторизация"
    }
    var gmailDetail: String {
        if !mailLoaded { return "Обнови состояние подключения." }
        if let mailError { return mailError }
        return accounts.isEmpty ? "Добавь адрес в «Интеграциях»." : accounts.map(\.title).joined(separator: " · ")
    }
    func capabilities(for app: String) -> [RoleToolDetail] {
        tools.filter { app == "gmail" ? $0.name.hasPrefix("taskflow_mail_") : $0.name == "taskflow_things3" }
    }

    func reloadMail() async {
        defer { mailLoaded = true }
        do {
            accounts = try await api.mailAccounts().items
            mailError = nil
        } catch {
            accounts = []
            mailError = "Сервер не вернул состояние Gmail. Повтори обновление."
        }
    }

    func refresh() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        async let mail: Void = reloadMail()
        do {
            let profile = try await api.role(id: "secretary")
            tools = profile.operationsDetail ?? []
            catalogError = profile.operationsDetail == nil ? "Сервер не вернул описания операций общего каталога." : nil
        } catch {
            tools = []
            catalogError = "Не удалось загрузить возможности Помощника владельца."
        }
        await checkThings()
        await mail
    }

    private func checkThings() async {
        thingsReadable = false
        do {
            let machines: [RemoteMachine] = try await api.request(.get, "/machines")
            let macs = machines.filter {
                $0.revokedAt == nil && ["darwin", "macos", "mac"].contains($0.platform?.lowercased() ?? "")
            }
            guard let machine = macs.first(where: \.online) else {
                thingsStatus = "Mac не в сети"
                thingsDetail = "Для доступа Помощника владельца нужен подключённый Mac с Things 3."
                return
            }
            let body: [String: JSONValue] = [
                "op": .string("things3"),
                "args": .object(["tool": .string("things_projects"), "arguments": .object([:])])
            ]
            let response: ThingsAccessProbe = try await api.request(.post, "/machines/\(machine.id)/ops", body: body)
            thingsReadable = response.readAvailable
            thingsStatus = thingsReadable ? "Доступен" : "Нет доступа"
            thingsDetail = thingsReadable
                ? "\(machine.имяДляЧеловека) · чтение проверено"
                : "\(machine.имяДляЧеловека) в сети, но Things 3 не подтвердил чтение. Проверь доступ хоста к Things на Mac."
        } catch {
            thingsStatus = "Не удалось проверить"
            thingsDetail = "Проверка Things 3 через сервер завершилась ошибкой. Повтори обновление."
        }
    }
}

struct ExternalAppAccessDetails: View {
    let app: String
    var showsAccounts = true
    @State private var store = ExternalAppAccessStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            if app == "gmail" && showsAccounts {
                ForEach(store.accounts) { account in
                    Text("\(account.title) · \(account.connected ? "Подключён" : "Нужна авторизация")")
                        .tfText(.action).foregroundStyle(Color.tfSub)
                }
            }
            if app == "things" {
                Text(store.thingsDetail).tfText(.action).foregroundStyle(Color.tfSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Возможности Помощника владельца").tfText(.body).foregroundStyle(Color.tfText)
            if let error = store.catalogError {
                Text(error).tfText(.action).foregroundStyle(Color.tfSub)
            } else if store.capabilities(for: app).isEmpty {
                Text("Доступные действия не объявлены сервером.").tfText(.action).foregroundStyle(Color.tfSub)
            } else {
                ForEach(store.capabilities(for: app)) { tool in
                    Text(tool.description ?? tool.name)
                        .tfText(.action).foregroundStyle(Color.tfSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Link("Документация \(app == "gmail" ? "Gmail" : "Things 3")", destination: URL(string: app == "gmail"
                ? "https://support.google.com/mail/" : "https://culturedcode.com/things/support/articles/2803573/")!)
                .tfText(.action)
        }
    }
}

struct ExternalAppAccessSection: View {
    @State private var store = ExternalAppAccessStore.shared
    @State private var expanded: Set<String> = []
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            SettingsCapsLabel("Внешние приложения")
                .padding(.horizontal, TFSpacing.screenHorizontal)
            TFCard(padding: TFSpacing.md) {
                VStack(alignment: .leading, spacing: TFSpacing.md) {
                    appRow("gmail", title: "Gmail", icon: "envelope", status: store.gmailStatus, detail: store.gmailDetail)
                    TFDivider()
                    appRow("things", title: "Things 3", icon: "checkmark.square", status: store.thingsStatus, detail: store.thingsDetail)
                    TFButton(store.loading ? "Проверка…" : "Обновить доступность", icon: "arrow.clockwise", variant: .secondary, isEnabled: !store.loading) {
                        Task { await store.refresh() }
                    }
                    NavigationLink {
                        IntegrationsScreen()
                    } label: {
                        TFListRow(icon: "link", iconStyle: .plain, title: "Управление подключениями", trailing: AnyView(Image(systemName: "chevron.right").foregroundStyle(Color.tfDim)))
                    }
                    .buttonStyle(.plain)
                    Text("Те же подключения показаны в Настройках → Интеграции.")
                        .tfText(.caption).foregroundStyle(Color.tfDim)
                }
            }
            .padding(.horizontal, TFSpacing.screenHorizontal)
        }
        .hintAnchor(HintAnchorID.roleExternalApps)
        .task { await store.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.refresh() } }
        }
    }

    private func appRow(_ app: String, title: String, icon: String, status: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            TFListRow(icon: icon, iconStyle: .plain, title: title, subtitle: detail,
                trailing: AnyView(Text(status).tfText(.caption).foregroundStyle(Color.tfSub)), titleStyle: .body)
            TFButton(expanded.contains(app) ? "Скрыть возможности" : "Показать возможности", icon: "list.bullet", variant: .secondary) {
                if expanded.contains(app) { expanded.remove(app) } else { expanded.insert(app) }
            }
            .accessibilityIdentifier("role.externalApps.\(app)")
            if expanded.contains(app) { ExternalAppAccessDetails(app: app) }
        }
    }
}
