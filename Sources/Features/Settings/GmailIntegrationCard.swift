import SwiftUI

/// Содержимое карточки Gmail на экране «Интеграции»: подключённые адреса и
/// белый список отправителей. Что Помощник владельца может делать с почтой, решает
/// сервер; здесь только список адресов.
struct GmailIntegrationCard: View {
    @Environment(\.openURL) private var openURL
    @State private var accounts: [MailAccount] = []
    @State private var trusted: [MailTrustedSender] = []
    @State private var newAddress = ""
    @State private var newTrusted = ""
    @State private var busy = false
    @State private var errorMessage: String?
    private let api = APIClient()

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            Text("Помощник владельца читает почту, готовит черновики, убирает письма в архив и спам. Отправляет только на эти адреса. Удалять письма и писать посторонним не может.")
                .tfText(.caption).foregroundStyle(Color.tfDim)
            TFErrorBanner(errorMessage, variant: .block)

            ForEach(accounts) { account in
                row(title: account.title, subtitle: account.connected ? "Подключён" : "Ждёт авторизации",
                    identifier: "gmail.account.\(account.id)") {
                    Task { await run { try await api.deleteMailAccount(id: account.id) } }
                }
            }
            if accounts.isEmpty && !busy {
                Text("Адресов пока нет.").tfText(.action).foregroundStyle(Color.tfSub)
            }
            TFTextField("Адрес Gmail", text: $newAddress, icon: "envelope")
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.emailAddress)
                .accessibilityIdentifier("gmail.newAddress")
            TFButton("Добавить и авторизовать", icon: "link", variant: .secondary, isEnabled: !busy) {
                Task { await connect() }
            }
            .accessibilityIdentifier("gmail.connect")
            TFButton("Обновить список", icon: "arrow.clockwise", variant: .secondary, isEnabled: !busy) {
                Task { await load() }
            }
            .accessibilityIdentifier("gmail.reload")

            Text("Белый список отправителей").tfText(.body).foregroundStyle(Color.tfSub)
                .padding(.top, TFSpacing.sm)
            Text("Письма с этих адресов Помощник владельца читает напрямую. Письма остальных — только в пересказе. Свои подключённые адреса доверенные всегда.")
                .tfText(.caption).foregroundStyle(Color.tfDim)
            ForEach(trusted) { sender in
                row(title: sender.address, subtitle: nil, identifier: "gmail.trusted.\(sender.address)") {
                    Task { await run { trusted = try await api.deleteMailTrustedSender(address: sender.address).items } }
                }
            }
            TFTextField("Адрес отправителя", text: $newTrusted, icon: "checkmark.shield")
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.emailAddress)
                .accessibilityIdentifier("gmail.newTrusted")
            TFButton("Добавить в белый список", icon: "plus", variant: .secondary, isEnabled: !busy && !trimmed(newTrusted).isEmpty) {
                Task {
                    await run {
                        trusted = try await api.addMailTrustedSender(address: trimmed(newTrusted)).items
                        newTrusted = ""
                    }
                }
            }
            .accessibilityIdentifier("gmail.addTrusted")
        }
        .task { await load() }
    }

    private func row(title: String, subtitle: String?, identifier: String, onDelete: @escaping () -> Void) -> some View {
        HStack(spacing: TFSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).tfText(.action).foregroundStyle(Color.tfText).lineLimit(1)
                if let subtitle {
                    Text(subtitle).tfText(.caption).foregroundStyle(Color.tfDim)
                }
            }
            Spacer()
            TFIconButton("trash", label: "Убрать \(title)", action: onDelete)
        }
        .padding(.vertical, TFSpacing.xs)
        .accessibilityIdentifier(identifier)
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func load() async {
        await run {
            async let fetchedAccounts = api.mailAccounts()
            async let fetchedTrusted = api.mailTrustedSenders()
            accounts = try await fetchedAccounts.items
            trusted = try await fetchedTrusted.items
        }
    }

    private func connect() async {
        await run {
            let link = try await api.addMailAccount(alias: trimmed(newAddress))
            newAddress = ""
            if let url = URL(string: link.url) { openURL(url) }
        }
    }

    /// Одно действие с сервером: блокирует кнопки, показывает ошибку, затем обновляет адреса.
    private func run(_ action: () async throws -> Void) async {
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            try await action()
            if let refreshed = try? await api.mailAccounts() { accounts = refreshed.items }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Не удалось выполнить действие с почтой."
        }
    }
}
