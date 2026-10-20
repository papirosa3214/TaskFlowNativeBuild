import SwiftUI

struct WebhooksScreen: View {
    @State private var hooks: [TaskFlowWebhook] = []
    @State private var loading = false
    @State private var error: String?
    @State private var adding = false
    @State private var editing: TaskFlowWebhook?
    @State private var deleting: TaskFlowWebhook?
    @State private var testingID: String?
    @State private var testMessage: String?
    private let api = APIClient()

    var body: some View {
        List {
            if let error { Section { Text(error).foregroundStyle(.red) } }
            if loading && hooks.isEmpty { ProgressView("Загрузка…") }
            if !loading && error == nil && hooks.isEmpty {
                ContentUnavailableView("Вебхуков пока нет", systemImage: "arrow.triangle.branch",
                    description: Text("Добавьте приёмник событий передачи работы."))
            }
            ForEach(hooks) { hook in
                Section {
                    Button { editing = hook } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(hook.name).tfText(.title)
                            Text(hook.url).tfText(.meta).foregroundStyle(Color.tfSub)
                            Text(hook.enabled ? "Включён" : "Выключен").tfText(.meta)
                        }
                    }
                    if let at = hook.lastDeliveryAt { LabeledContent("Доставлено", value: at) }
                    if let at = hook.wakeConfirmedAt {
                        LabeledContent("Запуск подтверждён", value: at)
                    } else { Text("Запуск оркестратора не подтверждён").foregroundStyle(Color.tfSub) }
                    if let at = hook.wake?.lastWakeAt {
                        LabeledContent("Поставлено в очередь Codex", value: at)
                    }
                    if let wakeError = hook.wake?.lastWakeError { Text(wakeError).foregroundStyle(.red) }
                    if let lastError = hook.lastError { Text(lastError).foregroundStyle(.red) }
                    Button(testingID == hook.id ? "Проверка…" : "Проверить доставку") {
                        Task { await test(hook) }
                    }.disabled(testingID != nil).accessibilityIdentifier("webhooks.test.\(hook.id)")
                    Button("Удалить вебхук", role: .destructive) { deleting = hook }
                }
            }
        }
        .tfScreenBackground()
        .tfNativeHeader("Вебхуки")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { adding = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Добавить вебхук").accessibilityIdentifier("webhooks.add")
            }
        }
        .sheet(isPresented: $adding) {
            WebhookEditor(hook: nil) { await load() }
        }
        .sheet(item: $editing) { hook in WebhookEditor(hook: hook) { await load() } }
        .confirmationDialog("Удалить вебхук?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Удалить", role: .destructive) {
                guard let hook = deleting else { return }
                Task {
                    do { try await api.deleteWebhook(id: hook.id); deleting = nil; await load() }
                    catch { self.error = error.localizedDescription }
                }
            }
        }
        .alert("Проверка вебхука", isPresented: Binding(
            get: { testMessage != nil }, set: { if !$0 { testMessage = nil } })) {
            Button("Готово", role: .cancel) { testMessage = nil }
        } message: { Text(testMessage ?? "") }
        .task { await load() }
        .refreshable { await load() }
    }

    @MainActor private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do { hooks = try await api.webhooks() }
        catch { self.error = error.localizedDescription }
    }
    @MainActor private func test(_ hook: TaskFlowWebhook) async {
        testingID = hook.id
        defer { testingID = nil }
        do { testMessage = try await api.testWebhook(id: hook.id).message; await load() }
        catch { testMessage = error.localizedDescription }
    }
}

private struct WebhookEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ProjectStore.self) private var projects
    let hook: TaskFlowWebhook?
    let saved: () async -> Void
    @State private var name = ""
    @State private var url = ""
    @State private var secret = ""
    @State private var enabled = true
    @State private var selected: Set<String> = ["plan_subtask_started", "step_outcome", "review_recorded", "plan_rework_created", "subtask_blocked", "plan_subtask_stalled_blocked"]
    @State private var projectID = "c2fcbcdb-951f-449f-a1bd-123ea2a46a58"
    @State private var saving = false
    @State private var error: String?
    @State private var threadID = "01a120f9-1266-7331-a4ca-81f6da2a698b"
    private let events = [
        ("plan_subtask_started", "Передача работы агенту"),
        ("step_outcome", "Результат этапа"),
        ("review_recorded", "Вердикт проверки"),
        ("plan_rework_created", "Возврат на доработку"),
        ("subtask_blocked", "Блокировка этапа"),
        ("plan_subtask_stalled_blocked", "Остановка без результата")
    ]

    var body: some View {
        NavigationStack {
            Form {
                if let error { Section { Text(error).foregroundStyle(.red) } }
                Section("Приёмник") {
                    TextField("Название", text: $name).accessibilityIdentifier("webhooks.name")
                    TextField("Адрес вебхука", text: $url).keyboardType(.URL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("webhooks.url")
                    SecureField(hook == nil ? "Ключ приёмника" : "Новый ключ (необязательно)", text: $secret)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    HStack {
                        Text("Включён")
                        Spacer()
                        TFToggle(isOn: $enabled)
                    }
                }
                Section("События") {
                    ForEach(events, id: \.0) { event in
                        HStack {
                            Text(event.1)
                            Spacer()
                            TFToggle(isOn: Binding(get: { selected.contains(event.0) }, set: {
                                if $0 { selected.insert(event.0) } else { selected.remove(event.0) }
                            }))
                        }
                    }
                }
                Section("Оркестратор Codex") {
                    TextField("ID чата", text: $threadID)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("webhooks.thread")
                }
                Section("Задачи") {
                    Picker("Проект", selection: $projectID) {
                        Text("Все проекты").tag("")
                        if !projects.projects.contains(where: { $0.id == projectID }) && !projectID.isEmpty {
                            Text(projectID == "c2fcbcdb-951f-449f-a1bd-123ea2a46a58" ? "TaskFlow - NewTodoist" : "Выбранный проект").tag(projectID)
                        }
                        ForEach(projects.projects) { project in Text(project.name).tag(project.id) }
                    }
                }
            }
            .navigationTitle(hook == nil ? "Добавить вебхук" : "Изменить вебхук")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Сохранение…" : "Сохранить") { Task { await save() } }
                        .disabled(saving || name.trimmingCharacters(in: .whitespaces).isEmpty || selected.isEmpty || !validURL)
                        .accessibilityIdentifier("webhooks.save")
                }
            }
            .task {
                if let hook {
                    name = hook.name; url = hook.url; enabled = hook.enabled
                    selected = Set(hook.eventKinds); projectID = hook.projectID ?? ""
                    threadID = hook.wake?.codexThreadID ?? ""
                }
                if projects.projects.isEmpty { await projects.load() }
            }
        }
    }
    private var validURL: Bool {
        guard let value = URL(string: url.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return ["https", "http"].contains(value.scheme?.lowercased() ?? "") && value.host != nil
    }
    @MainActor private func save() async {
        saving = true; error = nil
        defer { saving = false }
        do {
            try await APIClient().saveWebhook(id: hook?.id, body: WebhookSettingsBody(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                url: url.trimmingCharacters(in: .whitespacesAndNewlines),
                secret: secret.isEmpty ? nil : secret, enabled: enabled,
                eventKinds: selected.sorted(), projectID: projectID.isEmpty ? nil : projectID,
                wake: threadID.isEmpty ? nil : .init(codexThreadID: threadID, lastWakeAt: nil, lastWakeError: nil)))
            secret = ""; await saved(); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
