import SwiftUI

struct WebhooksScreen: View {
    let onStatusUpdate: ([TaskFlowWebhook]?) -> Void
    @State private var hooks: [TaskFlowWebhook] = []
    @State private var loading = false
    @State private var error: String?
    @State private var adding = false
    @State private var editing: TaskFlowWebhook?
    @State private var deleting: TaskFlowWebhook?
    @State private var testingID: String?
    @State private var testMessage: String?
    private let api = APIClient()

    init(onStatusUpdate: @escaping ([TaskFlowWebhook]?) -> Void = { _ in }) {
        self.onStatusUpdate = onStatusUpdate
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TFSpacing.xl) {
                TFCard {
                    VStack(alignment: .leading, spacing: TFSpacing.sm) {
                        Text("Что делает вебхук?").tfText(.title).foregroundStyle(Color.tfText)
                        Text("Он отправляет выбранные события TaskFlow на адрес внешнего сервиса, который умеет принимать HTTP-запросы. Здесь настраиваются подписки и проверяется доставка.")
                            .tfText(.action).foregroundStyle(Color.tfSub)
                    }
                }

                TFErrorBanner(error, variant: .block)

                VStack(alignment: .leading, spacing: TFSpacing.sm) {
                    TFSectionHeader("Приёмники")
                    if loading && hooks.isEmpty {
                        TFCard { Text("Загрузка вебхуков…").tfText(.action).foregroundStyle(Color.tfSub) }
                    } else if !loading && error == nil && hooks.isEmpty {
                        TFCard {
                            VStack(alignment: .leading, spacing: TFSpacing.md) {
                                Text("Подписок пока нет").tfText(.title).foregroundStyle(Color.tfText)
                                Text("Чтобы начать, нажми «+» и укажи название и URL приёмника. Затем выбери события TaskFlow, которые нужно ему отправлять.")
                                    .tfText(.action).foregroundStyle(Color.tfSub)
                                TFButton("Добавить приёмник", icon: "plus", variant: .secondary) { adding = true }
                            }
                        }
                    } else if !hooks.isEmpty {
                        ForEach(hooks) { hook in hookCard(hook) }
                    }
                }
            }
            .padding(.horizontal, TFSpacing.screenHorizontal)
            .padding(.top, TFSpacing.sm)
            .padding(.bottom, TFSpacing.xl * 2)
        }
        .tfScreenBackground()
        .tfNativeHeader("Вебхуки")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { adding = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Добавить вебхук").accessibilityIdentifier("webhooks.add")
                    .hintAnchor(HintAnchorID.webhooksAdd)
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

    private func hookCard(_ hook: TaskFlowWebhook) -> some View {
        TFCard(padding: 0) {
            VStack(spacing: 0) {
                Button { editing = hook } label: {
                    TFListRow(
                        icon: "arrow.triangle.branch",
                        iconStyle: .plain,
                        title: hook.name,
                        subtitle: hook.url,
                        trailing: AnyView(HStack(spacing: TFSpacing.sm) {
                            Text(hook.enabled ? "Включён" : "Выключен")
                                .tfText(.action)
                                .foregroundStyle(hook.enabled ? Color.tfGreen : Color.tfSub)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.tfDim)
                        }),
                        titleStyle: .action,
                        verticalPadding: TFSpacing.md
                    )
                }
                .buttonStyle(.plain)

                TFDivider(inset: TFSpacing.lg)
                VStack(alignment: .leading, spacing: TFSpacing.sm) {
                    detailRow("События", value: "\(hook.eventKinds.count)")
                    if let status = hook.lastDeliveryStatus {
                        detailRow("Последний ответ", value: "HTTP \(status)", color: status >= 400 ? .tfCoral : .tfGreen)
                    }
                    if let at = hook.lastDeliveryAt { detailRow("Последняя доставка", value: at) }
                    if let count = hook.deliveryCount { detailRow("Доставок", value: "\(count)") }
                    if let at = hook.wakeConfirmedAt { detailRow("Запуск Codex подтверждён", value: at) }
                    else if hook.wake != nil { detailRow("Запуск Codex", value: "не подтверждён") }
                    if let at = hook.wake?.lastWakeAt { detailRow("Поставлено в очередь", value: at) }
                    if let wakeError = hook.wake?.lastWakeError { errorRow(wakeError) }
                    if let lastError = hook.lastError { errorRow(lastError) }

                    TFButton(
                        testingID == hook.id ? "Проверка…" : "Проверить доставку",
                        icon: "paperplane",
                        variant: .secondary,
                        isEnabled: testingID == nil
                    ) {
                        Task { await test(hook) }
                    }
                    .accessibilityIdentifier("webhooks.test.\(hook.id)")
                    .hintAnchor(HintAnchorID.webhookTest)

                    TFButton("Удалить вебхук", icon: "trash", variant: .outline) { deleting = hook }
                }
                .padding(.horizontal, TFSpacing.lg)
                .padding(.vertical, TFSpacing.md)
            }
        }
    }

    private func detailRow(_ title: String, value: String, color: Color = .tfSub) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: TFSpacing.sm) {
            Text(title).tfText(.action).foregroundStyle(Color.tfSub)
            Spacer(minLength: TFSpacing.sm)
            Text(value).tfText(.action).foregroundStyle(color).multilineTextAlignment(.trailing)
        }
    }

    private func errorRow(_ message: String) -> some View {
        HStack(alignment: .top, spacing: TFSpacing.sm) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Color.tfCoral)
            Text(message).tfText(.action).foregroundStyle(Color.tfCoral)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @MainActor private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do {
            hooks = try await api.webhooks()
            onStatusUpdate(hooks)
        } catch {
            self.error = error.localizedDescription
            onStatusUpdate(nil)
        }
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
                Section {
                    TextField("Название", text: $name).accessibilityIdentifier("webhooks.name")
                    TextField("Адрес вебхука", text: $url).keyboardType(.URL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("webhooks.url")
                        .hintAnchor(HintAnchorID.webhookURL)
                    SecureField(hook == nil ? "Ключ приёмника" : "Новый ключ (необязательно)", text: $secret)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    HStack {
                        Text("Включён")
                        Spacer()
                        TFToggle(isOn: $enabled).accessibilityLabel("Включён")
                    }
                } header: {
                    Text("Приёмник")
                } footer: {
                    Text("Укажи URL сервиса, который принимает HTTP-запросы. Общий ключ нужен, если приёмник проверяет подпись.")
                }
                Section {
                    ForEach(events, id: \.0) { event in
                        HStack {
                            Text(event.1)
                            Spacer()
                            TFToggle(isOn: Binding(get: { selected.contains(event.0) }, set: {
                                if $0 { selected.insert(event.0) } else { selected.remove(event.0) }
                            }))
                            .accessibilityLabel(event.1)
                        }
                    }
                } header: {
                    Text("События TaskFlow")
                        .hintAnchor(HintAnchorID.webhookEvents)
                } footer: {
                    Text("При каждом выбранном событии TaskFlow отправит отдельный запрос этому приёмнику.")
                }
                Section {
                    TextField("ID чата", text: $threadID)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("webhooks.thread")
                        .hintAnchor(HintAnchorID.webhookCodexThread)
                } header: {
                    Text("Передача в Codex")
                } footer: {
                    Text("Если указан ID чата, событие дополнительно передаётся в эту ветку Codex. По умолчанию уже введён ID чата — проверь, что это нужный чат.")
                }
                Section {
                    Picker("Проект", selection: $projectID) {
                        Text("Все проекты").tag("")
                        if !projects.projects.contains(where: { $0.id == projectID }) && !projectID.isEmpty {
                            Text(projectID == "c2fcbcdb-951f-449f-a1bd-123ea2a46a58" ? "TaskFlow - NewTodoist" : "Выбранный проект").tag(projectID)
                        }
                        ForEach(projects.projects) { project in Text(project.name).tag(project.id) }
                    }
                    .hintAnchor(HintAnchorID.webhookProject)
                } header: {
                    Text("Фильтр по проекту")
                } footer: {
                    Text("По умолчанию выбран TaskFlow - NewTodoist. «Все проекты» отправляет события из любого проекта.")
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
                        .hintAnchor(HintAnchorID.webhookSave)
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
