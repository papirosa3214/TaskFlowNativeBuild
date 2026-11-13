import SwiftUI
import Observation

@MainActor @Observable
final class SecretsViewModel {
    var secrets: [BrokerSecret] = []
    var loaded = false
    var loading = false
    var error: String?
    private let api = APIClient()

    func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            secrets = try await api.secrets().sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            error = nil
        } catch { self.error = error.localizedDescription }
        loaded = true
    }

    func delete(_ secret: BrokerSecret) async {
        do {
            try await api.deleteSecret(id: secret.id)
            secrets.removeAll { $0.id == secret.id }
        } catch { self.error = error.localizedDescription }
    }
}

/// Настройки → Сервер → «Секреты»: ключи облачных сервисов в хранилище
/// секретов. Агенты пользуются ими через брокер и значений не видят;
/// здесь владелец записывает и смотрит их сам.
struct SecretsScreen: View {
    @State private var model = SecretsViewModel()
    @State private var editing: SecretEditorTarget?
    @State private var deleting: BrokerSecret?

    var body: some View {
        List {
            if let error = model.error {
                Section {
                    Text(error).foregroundStyle(Color.tfSub)
                        .accessibilityIdentifier("secrets-error")
                    Button("Обновить") { Task { await model.load() } }
                }
            }
            if model.loading && !model.loaded { TFLoading(.inline) }
            if model.loaded && model.secrets.isEmpty && model.error == nil {
                Section {
                    Text("Ключей пока нет").foregroundStyle(Color.tfSub)
                }
            }
            if !model.secrets.isEmpty {
                Section {
                    ForEach(model.secrets) { secret in
                        NavigationLink {
                            SecretDetailScreen(secret: secret) { await model.load() }
                        } label: {
                            VStack(alignment: .leading, spacing: TFSpacing.xs) {
                                Text(secret.name)
                                    .tfText(.body)
                                    .foregroundStyle(Color.tfText)
                                Text(secret.displayOrigin)
                                    .tfText(.action)
                                    .foregroundStyle(Color.tfSub)
                            }
                        }
                        .tfSettingsListRow()
                        .swipeActions {
                            Button("Удалить", role: .destructive) { deleting = secret }
                        }
                    }
                } footer: {
                    Text("Агенты пользуются ключами через хранилище и значений не видят.")
                }
            }
        }
        .tfSettingsListChrome()
        .tfScreenBackground()
        .tfNativeHeader("Секреты", displayMode: .inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editing = .new } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Добавить ключ")
                    .accessibilityIdentifier("secrets-add")
            }
        }
        .refreshable { await model.load() }
        .task { await model.load() }
        .tfSheet(item: $editing) { target in
            SecretEditor(target: target) { await model.load() }
        }
        .confirmationDialog(
            "Удалить ключ «\(deleting?.name ?? "")»?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) {
                if let secret = deleting { Task { await model.delete(secret) } }
            }
        } message: {
            Text("Агенты, которым он выдан, перестанут им пользоваться.")
        }
    }
}

enum SecretEditorTarget: Identifiable {
    case new
    case replace(BrokerSecret)

    var id: String {
        switch self {
        case .new: "new"
        case .replace(let secret): secret.id
        }
    }
}

private struct SecretDetailScreen: View {
    let secret: BrokerSecret
    let onChanged: () async -> Void
    @State private var value: String?
    @State private var revealing = false
    @State private var error: String?
    @State private var replacing: SecretEditorTarget?
    private let api = APIClient()

    var body: some View {
        List {
            Section {
                LabeledContent("Название", value: secret.name)
                LabeledContent("Сервис", value: secret.displayOrigin)
                LabeledContent("Заголовок", value: secret.headerName)
                LabeledContent("Идентификатор", value: secret.id)
            }
            Section {
                if let value {
                    Text(value)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .accessibilityIdentifier("secret-value")
                    Button("Скопировать") { SafePasteboard.copySecret(value) }
                    Button("Скрыть") { self.value = nil }
                } else if revealing {
                    TFLoading(.inline)
                } else {
                    Button("Показать значение") { Task { await reveal() } }
                        .accessibilityIdentifier("secret-reveal")
                }
            } header: { Text("Значение") }
            if let error { Section { Text(error).foregroundStyle(Color.tfCoral) } }
            Section {
                Button("Заменить значение") { replacing = .replace(secret) }
            }
        }
        .tfNativeHeader(secret.name, displayMode: .inline)
        .tfSheet(item: $replacing) { target in
            SecretEditor(target: target) {
                value = nil
                await onChanged()
            }
        }
    }

    private func reveal() async {
        revealing = true
        defer { revealing = false }
        do { value = try await api.revealSecret(id: secret.id); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

private struct SecretEditor: View {
    let target: SecretEditorTarget
    let onSaved: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var origin = ""
    @State private var headerName = "Authorization"
    @State private var value = ""
    @State private var saving = false
    @State private var error: String?
    private let api = APIClient()

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !origin.trimmingCharacters(in: .whitespaces).isEmpty
            && !value.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Название, например OpenAI", text: $name)
                    TextField("Адрес API, например api.openai.com/v1", text: $origin)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Заголовок", text: $headerName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Заголовок — Authorization (ключ уйдёт как Bearer) или свой, начинающийся с X-.")
                }
                Section("Значение") {
                    SecureField("Ключ или токен", text: $value)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("secret-editor-value")
                }
                if let error { Section { Text(error).foregroundStyle(Color.tfCoral) } }
            }
            .disabled(saving)
            .navigationTitle(isNew ? "Новый ключ" : "Замена ключа")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { TFLoading(.inline) }
                    else {
                        Button("Сохранить") { Task { await save() } }
                            .disabled(!canSave)
                            .accessibilityIdentifier("secret-editor-save")
                    }
                }
            }
            .onAppear {
                if case .replace(let secret) = target {
                    name = secret.name
                    origin = secret.displayOrigin
                    headerName = secret.headerName
                }
            }
        }
    }

    private var isNew: Bool {
        if case .new = target { return true }
        return false
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let id: String
        switch target {
        case .new: id = BrokerSecret.makeID(from: name)
        case .replace(let secret): id = secret.id
        }
        do {
            try await api.saveSecret(
                id: id,
                name: name.trimmingCharacters(in: .whitespaces),
                origin: origin.trimmingCharacters(in: .whitespaces),
                headerName: headerName.trimmingCharacters(in: .whitespaces),
                value: value
            )
            await onSaved()
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
