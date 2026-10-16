import SwiftUI

/// Uses the same owner-only settings as the web client. The saved key is never returned.
struct JevSettingsScreen: View {
    @State private var settings: JevSettings?
    @State private var baseUrl = ""
    @State private var model = ""
    @State private var timeoutMs = ""
    @State private var apiKey = ""
    @State private var busy = false
    @State private var error: String?
    @State private var result: JevConnectionResult?
    @State private var confirmReset = false
    private let api = APIClient()

    private var dirty: Bool {
        guard let settings else { return false }
        return baseUrl != settings.baseUrl || model != settings.model
            || timeoutMs != String(settings.timeoutMs) || !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        List {
            Section {
                Text("Выбирает из готовых вариантов то, что подходит задаче. Не отвечает, выключен или не уверен — всё работает как без него.")
                    .tfText(.action).foregroundStyle(Color.tfSub)
            }
            if let error {
                Section {
                    Text(error).tfText(.body).foregroundStyle(Color.tfSub)
                        .accessibilityIdentifier("jev-error")
                    if settings == nil {
                        TFButton("Повторить", variant: .secondary, isEnabled: !busy) { Task { await load() } }
                    }
                }
            }
            if settings == nil && busy { ProgressView("Загрузка…") }
            if let settings {
                connection(settings)
                scenarios(settings)
                if settings.hasApiKey {
                    Section {
                        TFButton("Удалить ключ и сбросить", icon: "trash", variant: .outline, isEnabled: !busy) {
                            confirmReset = true
                        }.accessibilityIdentifier("jev-reset")
                    }
                }
            }
        }
        .tfScreenBackground()
        .tfNativeHeader("Оценщик JEV")
        .accessibilityIdentifier("jev-screen")
        .scrollDismissesKeyboard(.interactively)
        .task { await load() }
        .confirmationDialog("Удалить ключ и сбросить настройки JEV? Все сценарии выключатся.", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Удалить ключ и сбросить", role: .destructive) { Task { await reset() } }
            Button("Отмена", role: .cancel) {}
        }
    }

    private func connection(_ settings: JevSettings) -> some View {
        Section {
            TextField("Адрес API", text: $baseUrl)
                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityIdentifier("jev-url")
            TextField("Модель", text: $model)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityIdentifier("jev-model")
            TextField("Тайм-аут, мс", text: $timeoutMs)
                .keyboardType(.numberPad).accessibilityIdentifier("jev-timeout")
            SecureField(settings.hasApiKey ? "Ключ сохранён — новый заменит" : "Ключ API TypeSafe", text: $apiKey)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityLabel("Ключ API").accessibilityIdentifier("jev-key")
            TFButton("Сохранить", variant: .secondary, isEnabled: dirty && !busy) {
                Task { await saveConnection() }
            }.accessibilityIdentifier("jev-save")
            TFButton("Проверить подключение", icon: "waveform.path.ecg", variant: .secondary,
                     isEnabled: settings.hasApiKey && !dirty && !busy) {
                Task { await test() }
            }.accessibilityIdentifier("jev-test")
            if busy { ProgressView("Подождите…") }
            if let result {
                Text(result.message).tfText(.action).foregroundStyle(Color.tfSub)
                    .accessibilityIdentifier("jev-test-result")
            }
        } header: { Text("Подключение") }
        footer: { Text("Ключ хранится на сервере. Проверка использует сохранённые настройки.").tfText(.action) }
        .tfText(.input)
        .foregroundStyle(Color.tfText)
        .hintAnchor(HintAnchorID.jevConnection)
    }

    @ViewBuilder private func scenarios(_ settings: JevSettings) -> some View {
        Section {
            if !settings.hasApiKey {
                Text("Сначала сохраните ключ — без него галочки не включаются.")
                    .tfText(.action).foregroundStyle(Color.tfSub)
            }
        } header: { Text("Где использовать") }
        scenario("Выбор шаблона плана", id: "plan", enabled: settings.planProfileEnabled,
                 description: "Когда карточке предлагается командный план, JEV выбирает готовый состав: один исполнитель, исследование, поставка или полный цикл. Без него шаблон выбирается по словам в названии.") { .init(planProfileEnabled: $0) }
        scenario("Роли для подзадач", id: "roles", enabled: settings.subtaskRoleEnabled,
                 description: "JEV читает карточку целиком и решает, какой роли отдать подзадачу и стоит ли выносить её отдельно. Мелкие пункты остаются исполнителю карточки. Если JEV не уверен, роль подбирается как раньше, по смыслу текста.") { .init(subtaskRoleEnabled: $0) }
        scenario("Отбор памяти для роли", id: "recall", enabled: settings.memoryRecallEnabled,
                 description: "Перед ходом роли JEV проверяет до 15 найденных записей: уверенно ненужные убирает, полезные ставит вперёд. Закреплённые не трогает. Ждёт не дольше 3 секунд — иначе память идёт как раньше.") { .init(memoryRecallEnabled: $0) }
        scenario("Проверка записи в память", id: "write", enabled: settings.memoryWriteEnabled,
                 description: "Проверяет, что факт, урок или предпочтение роли — знание на будущее. Уверенно ненужные записи не сохраняются, роль получает объяснение. Ваши собственные записи не проверяются.") { .init(memoryWriteEnabled: $0) }
        scenario("Навыки под задачу", id: "skills", enabled: settings.skillsEnabled,
                 description: "У ролей с числом навыков больше шести JEV отбирает нужные карточке и текущему шагу. Если ничего не выбрал или не ответил, роль получает все навыки.") { .init(skillsEnabled: $0) }
    }

    private func scenario(_ title: String, id: String, enabled: Bool, description: String,
                          patch: @escaping (Bool) -> JevSettingsPatch) -> some View {
        Section {
            HStack {
                Text(title).tfText(.body).foregroundStyle(Color.tfText)
                Spacer()
                TFToggle(isOn: Binding(get: { enabled }, set: { value in Task { await save(patch(value), updateDraft: false) } }))
                    .accessibilityLabel(title)
                    .accessibilityIdentifier("jev-scenario-\(id)")
            }
            .disabled(busy || settings?.hasApiKey != true)
        } footer: { Text(description).tfText(.action).foregroundStyle(Color.tfSub) }
    }

    private func apply(_ value: JevSettings, updateDraft: Bool) {
        settings = value
        if updateDraft {
            baseUrl = value.baseUrl; model = value.model; timeoutMs = String(value.timeoutMs)
            apiKey = ""
        }
    }
    @MainActor private func load() async {
        guard !busy else { return }
        busy = true; error = nil
        defer { busy = false }
        do { apply(try await api.jevSettings(), updateDraft: true) }
        catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    @MainActor private func saveConnection() async {
        guard let timeout = Int(timeoutMs), (500...60000).contains(timeout) else {
            error = "Тайм-аут — целое от 500 до 60000 мс"; return
        }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        await save(.init(baseUrl: baseUrl, model: model, timeoutMs: timeout, apiKey: key.isEmpty ? nil : key), updateDraft: true)
    }
    @MainActor private func save(_ patch: JevSettingsPatch, updateDraft: Bool) async {
        guard !busy else { return }
        busy = true; error = nil; result = nil
        defer { busy = false }
        do { apply(try await api.saveJevSettings(patch), updateDraft: updateDraft) }
        catch { self.error = error.localizedDescription }
    }
    @MainActor private func test() async {
        guard !busy else { return }
        busy = true; error = nil; result = nil
        defer { busy = false }
        do { result = try await api.testJevConnection() }
        catch { self.error = error.localizedDescription }
    }
    @MainActor private func reset() async {
        guard !busy else { return }
        busy = true; error = nil; result = nil
        defer { busy = false }
        do { apply(try await api.resetJevSettings(), updateDraft: true) }
        catch { self.error = error.localizedDescription }
    }
}
