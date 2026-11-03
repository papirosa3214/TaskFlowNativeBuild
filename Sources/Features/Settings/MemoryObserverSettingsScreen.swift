import SwiftUI

/// Настройки → Искусственный интеллект → Наблюдатель памяти.
/// Ключи живут в реестре сервера; телефон только показывает и сохраняет.
struct MemoryObserverSettingsScreen: View {
    @State private var enabled = true
    @State private var provider = "local"
    @State private var model = "MiniMax-M3.1-Flash-Preview"
    @State private var confidence = 60
    @State private var models: [RuntimeModel] = []
    @State private var busy = false
    @State private var error: String?
    @State private var loaded = false
    private let api = APIClient()
    private let providers = [
        ("local", "Локальная (Ollama)"),
        ("minimax", "MiniMax"),
        ("claude", "Claude"),
        ("deepseek", "DeepSeek"),
    ]

    var body: some View {
        ZStack {
            Color.tfBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: TFSpacing.xl) {
                    TFErrorBanner(error)
                    if !loaded && busy {
                        TFLoading(.block)
                    } else {
                        toggleCard
                        modelCard
                        thresholdCard
                    }
                }
                .padding(.horizontal, TFSpacing.screenHorizontal)
                .padding(.vertical, TFSpacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .tfNativeHeader("Наблюдатель памяти")
        .accessibilityIdentifier("memory-observer-screen")
        .task { await load() }
        .hintAnchor(HintAnchorID.memoryObserver)
    }

    private var toggleCard: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            TFSectionHeader("Запись уроков")
            TFCard(padding: 0) {
                VStack(alignment: .leading, spacing: TFSpacing.xs) {
                    HStack(spacing: TFSpacing.md) {
                        Text("Включён").tfText(.action).foregroundStyle(Color.tfText)
                        Spacer(minLength: 0)
                        TFToggle(isOn: Binding(get: { enabled }, set: { value in
                            enabled = value
                            Task { await save("memory_observer_enabled", .bool(value)) }
                        }))
                        .accessibilityIdentifier("memory-observer-enabled")
                    }
                    Text("После полного снимка слота отдельная модель решает, есть ли устойчивый урок, и пишет его в память роли. Роль этого вызова не видит.")
                        .tfText(.action)
                        .foregroundStyle(Color.tfSub)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, TFSpacing.lg)
                .padding(.vertical, TFSpacing.md)
            }
        }
    }

    private var modelCard: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            TFSectionHeader("Модель")
            TFFieldGroup {
                Picker("Провайдер", selection: Binding(get: { provider }, set: { value in
                    provider = value
                    Task { await save("memory_observer_provider", .string(value)) }
                })) {
                    ForEach(providers, id: \.0) { item in
                        Text(item.1).tag(item.0)
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal, TFSpacing.lg)
                .frame(minHeight: TFField.height)
                .accessibilityIdentifier("memory-observer-provider")
                .disabled(!enabled || busy)
                TFFieldDivider()
                if !providerModels.isEmpty {
                    Picker("Модель", selection: Binding(get: { model }, set: { value in
                        model = value
                        Task { await save("memory_observer_model", .string(value)) }
                    })) {
                        ForEach(pickerModels, id: \.self) { id in
                            Text(id).tag(id)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(.horizontal, TFSpacing.lg)
                    .frame(minHeight: TFField.height)
                    .accessibilityIdentifier("memory-observer-model-picker")
                    .disabled(!enabled || busy)
                    TFFieldDivider()
                }
                TextField("", text: $model, prompt: Text("Имя модели").foregroundStyle(Color.tfDim))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .tfText(.input)
                    .foregroundStyle(Color.tfText)
                    .padding(.horizontal, TFSpacing.lg)
                    .frame(minHeight: TFField.height)
                    .accessibilityIdentifier("memory-observer-model")
                    .disabled(!enabled || busy)
                    .onSubmit { Task { await save("memory_observer_model", .string(model)) } }
            }
            Text("Список — из каталога «Модели и провайдеры». Можно вписать имя вручную и нажать Return.")
                .tfText(.action)
                .foregroundStyle(Color.tfSub)
        }
    }

    private var thresholdCard: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            TFSectionHeader("Порог")
            TFCard(padding: 0) {
                Stepper(value: Binding(get: { confidence }, set: { value in
                    confidence = value
                    Task { await save("memory_observer_min_confidence", .number(Double(value))) }
                }), in: 50...95, step: 5) {
                    Text("Уверенность не ниже \(confidence) %")
                        .tfText(.action)
                        .foregroundStyle(Color.tfText)
                }
                .padding(.horizontal, TFSpacing.lg)
                .padding(.vertical, TFSpacing.md)
                .accessibilityIdentifier("memory-observer-confidence")
                .disabled(!enabled || busy)
            }
            Text("Ниже порога наблюдатель молчит и запись не создаёт.")
                .tfText(.action)
                .foregroundStyle(Color.tfSub)
        }
    }

    private var providerModels: [RuntimeModel] {
        let matched = models.filter { $0.provider == provider || (provider == "local" && ($0.provider == "local" || $0.provider == "ollama")) }
        return matched.isEmpty ? models : matched
    }

    private var pickerModels: [String] {
        var ids = providerModels.map(\.id)
        if !ids.contains(model) { ids.insert(model, at: 0) }
        return ids
    }

    @MainActor
    private func load() async {
        guard !busy else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            async let settingsTask = api.serverSettings()
            async let modelsTask = api.runtimeModels()
            let snapshot = try await settingsTask
            models = (try? await modelsTask) ?? []
            enabled = boolValue(snapshot, "memory_observer_enabled", true)
            provider = stringValue(snapshot, "memory_observer_provider", "local")
            model = stringValue(snapshot, "memory_observer_model", "MiniMax-M3.1-Flash-Preview")
            confidence = intValue(snapshot, "memory_observer_min_confidence", 60)
            loaded = true
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }

    @MainActor
    private func save(_ key: String, _ value: JSONValue) async {
        error = nil
        do {
            try await api.updateServerSetting(key: key, value: value)
        } catch {
            self.error = error.localizedDescription
            await load()
        }
    }

    private func boolValue(_ snapshot: ServerSettingsSnapshot, _ key: String, _ fallback: Bool) -> Bool {
        if case .bool(let value) = snapshot.values[key] { return value }
        if case .bool(let value) = snapshot.settings.first(where: { $0.key == key })?.defaultValue { return value }
        return fallback
    }

    private func stringValue(_ snapshot: ServerSettingsSnapshot, _ key: String, _ fallback: String) -> String {
        if case .string(let value) = snapshot.values[key], !value.isEmpty { return value }
        if case .string(let value) = snapshot.settings.first(where: { $0.key == key })?.defaultValue { return value }
        return fallback
    }

    private func intValue(_ snapshot: ServerSettingsSnapshot, _ key: String, _ fallback: Int) -> Int {
        if case .number(let value) = snapshot.values[key] { return Int(value.rounded()) }
        if case .number(let value) = snapshot.settings.first(where: { $0.key == key })?.defaultValue { return Int(value.rounded()) }
        return fallback
    }
}
