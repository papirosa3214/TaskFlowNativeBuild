import SwiftUI

/// Настройки → Искусственный интеллект → Наблюдатель памяти.
///
/// Модель чата — из живого каталога рантайма (`ModelMenu`), как у ролей:
/// `провайдер/id`. Эмбеддинги — тег Ollama (`embedding_model`) и порог дубля.
/// Статистика — журнал исходов `GET /admin/memory-observer/stats`.
struct MemoryObserverSettingsScreen: View {
    @State private var enabled = true
    @State private var modelRef = ""
    @State private var confidence = 60
    @State private var embeddingModel = "bge-m3-embed:latest"
    @State private var duplicateSimilarity = 92
    @State private var models: [RuntimeModel] = []
    @State private var stats: MemoryObserverStats?
    @State private var busy = false
    @State private var error: String?
    @State private var loaded = false
    private let api = APIClient()

    private static let knownEmbeddings = [
        "bge-m3-embed:latest",
        "bge-m3-embed-gpu:latest",
    ]

    private var options: [RuntimeModel] {
        models.filter { $0.available && $0.isRoutable }
    }

    private var modelLabel: String {
        guard !modelRef.isEmpty else { return "— выбрать —" }
        return models.label(forRef: modelRef)
    }

    private var countRows: [(key: String, title: String, value: Int)] {
        guard let counts = stats?.counts else { return [] }
        let order = [
            "total", "wrote", "skip", "similar", "low_confidence",
            "already", "model", "parse_error", "disabled", "not_done", "no_role",
        ]
        var rows: [(key: String, title: String, value: Int)] = []
        for key in order {
            if let value = counts[key], value > 0 || key == "total" {
                rows.append((key, MemoryObserverStats.outcomeTitle(key), value))
            }
        }
        for (key, value) in counts.sorted(by: { $0.key < $1.key }) where !order.contains(key) {
            rows.append((key, MemoryObserverStats.outcomeTitle(key), value))
        }
        return rows
    }

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
                        embeddingCard
                        duplicateCard
                        statsCard
                    }
                }
                .padding(.horizontal, TFSpacing.screenHorizontal)
                .padding(.vertical, TFSpacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await load(force: true) }
        }
        .tfNativeHeader("Наблюдатель памяти")
        .tint(Color.tfText)
        .accessibilityIdentifier("memory-observer-screen")
        .task { await load() }
        .hintAnchor(HintAnchorID.memoryObserver)
    }

    private var toggleCard: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            TFSectionHeader("Запись уроков")
            TFCard(padding: 0, bordered: true) {
                VStack(alignment: .leading, spacing: TFSpacing.xs) {
                    HStack(spacing: TFSpacing.md) {
                        Text("Включён").tfText(.body).foregroundStyle(Color.tfText)
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
            TFCard(padding: 0, bordered: true) {
                HStack(spacing: TFSpacing.md) {
                    Text("Модель чата")
                        .tfText(.body)
                        .foregroundStyle(Color.tfText)
                    Spacer(minLength: TFSpacing.sm)
                    ModelMenu(
                        label: modelLabel,
                        accessibility: "Модель наблюдателя памяти",
                        options: options,
                        disabled: !enabled || busy || options.isEmpty,
                        fillsRow: false
                    ) { picked in
                        modelRef = picked.routeRef
                        Task { await save("memory_observer_model", .string(picked.routeRef)) }
                    }
                    .accessibilityIdentifier("memory-observer-model")
                }
                .padding(.horizontal, TFSpacing.lg)
                .frame(minHeight: TFField.height)
            }
            Text(options.isEmpty
                 ? "В каталоге «Модели и провайдеры» пока нет доступных моделей."
                 : "Список — из каталога «Модели и провайдеры», те же что у ролей.")
                .tfText(.action)
                .foregroundStyle(Color.tfSub)
        }
    }

    private var thresholdCard: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            TFSectionHeader("Порог")
            TFCard(padding: 0, bordered: true) {
                Stepper(value: Binding(get: { confidence }, set: { value in
                    confidence = value
                    Task { await save("memory_observer_min_confidence", .number(Double(value))) }
                }), in: 50...95, step: 5) {
                    Text("Уверенность не ниже \(confidence) %")
                        .tfText(.body)
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

    private var embeddingCard: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            TFSectionHeader("Эмбеддинги")
            TFCard(padding: 0, bordered: true) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: TFSpacing.md) {
                        Text("Модель")
                            .tfText(.body)
                            .foregroundStyle(Color.tfText)
                        Spacer(minLength: TFSpacing.sm)
                        Menu {
                            ForEach(Self.knownEmbeddings, id: \.self) { name in
                                Button(name) {
                                    embeddingModel = name
                                    Task { await save("embedding_model", .string(name)) }
                                }
                            }
                        } label: {
                            Text(embeddingModel.isEmpty ? "— выбрать —" : embeddingModel)
                                .tfText(.action)
                                .foregroundStyle(Color.tfText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .disabled(busy)
                        .accessibilityIdentifier("memory-observer-embedding-model")
                    }
                    .padding(.horizontal, TFSpacing.lg)
                    .frame(minHeight: TFField.height)

                    TFFieldDivider()

                    TextField("тег Ollama, например bge-m3-embed:latest", text: $embeddingModel)
                        .tfText(.input)
                        .foregroundStyle(Color.tfText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, TFSpacing.lg)
                        .frame(minHeight: TFField.height)
                        .accessibilityIdentifier("memory-observer-embedding-field")
                        .onSubmit {
                            let trimmed = embeddingModel.trimmingCharacters(in: .whitespacesAndNewlines)
                            embeddingModel = trimmed
                            Task { await save("embedding_model", .string(trimmed)) }
                        }
                }
            }
            Text("Векторы для поиска похожих записей и отсечения дублей. Меняется без перезапуска сервера.")
                .tfText(.action)
                .foregroundStyle(Color.tfSub)
            if let emb = stats?.embedding {
                Text(emb.ok
                     ? "Сейчас отвечает · \(emb.dim.map(String.init) ?? "—") измерений"
                     : "Не отвечает\(emb.error.map { ": \($0)" } ?? "")")
                    .tfText(.action)
                    .foregroundStyle(emb.ok ? Color.tfSub : Color.tfCoral)
                    .accessibilityIdentifier("memory-observer-embedding-health")
            }
        }
    }

    private var duplicateCard: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            TFSectionHeader("Дубли")
            TFCard(padding: 0, bordered: true) {
                Stepper(value: Binding(get: { duplicateSimilarity }, set: { value in
                    duplicateSimilarity = value
                    Task { await save("memory_duplicate_similarity", .number(Double(value))) }
                }), in: 80...99, step: 1) {
                    Text("Похожесть не ниже \(duplicateSimilarity) %")
                        .tfText(.body)
                        .foregroundStyle(Color.tfText)
                }
                .padding(.horizontal, TFSpacing.lg)
                .padding(.vertical, TFSpacing.md)
                .accessibilityIdentifier("memory-observer-duplicate")
                .disabled(busy)
            }
            Text("При записи, если уже есть достаточно похожий текст, новая строка не создаётся.")
                .tfText(.action)
                .foregroundStyle(Color.tfSub)
        }
    }

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            TFSectionHeader("Статистика")
            TFCard(padding: 0, bordered: true) {
                VStack(alignment: .leading, spacing: TFSpacing.sm) {
                    if let stats {
                        Text("За \(stats.days) дн.")
                            .tfText(.action)
                            .foregroundStyle(Color.tfSub)
                        ForEach(countRows, id: \.key) { row in
                            HStack(alignment: .firstTextBaseline, spacing: TFSpacing.md) {
                                Text(row.title).tfText(.body).foregroundStyle(Color.tfText)
                                Spacer(minLength: TFSpacing.sm)
                                Text("\(row.value)")
                                    .tfText(.body)
                                    .foregroundStyle(Color.tfText)
                                    .monospacedDigit()
                            }
                        }
                        if !stats.recent.isEmpty {
                            TFDivider()
                            Text("Недавние")
                                .tfText(.action)
                                .foregroundStyle(Color.tfSub)
                            ForEach(stats.recent.prefix(12)) { event in
                                VStack(alignment: .leading, spacing: TFSpacing.xs) {
                                    HStack(alignment: .firstTextBaseline, spacing: TFSpacing.sm) {
                                        Text(MemoryObserverStats.outcomeTitle(event.outcome))
                                            .tfText(.body)
                                            .foregroundStyle(Color.tfText)
                                        Spacer(minLength: 0)
                                        if let confidence = event.confidence {
                                            Text("\(Int((confidence * 100).rounded())) %")
                                                .tfText(.action)
                                                .foregroundStyle(Color.tfSub)
                                                .monospacedDigit()
                                        }
                                    }
                                    let subtitle = [event.roleKey, event.title, event.detail]
                                        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                                        .filter { !$0.isEmpty }
                                        .joined(separator: " · ")
                                    if !subtitle.isEmpty {
                                        Text(subtitle)
                                            .tfText(.action)
                                            .foregroundStyle(Color.tfSub)
                                            .lineLimit(2)
                                    }
                                }
                            }
                        }
                    } else if busy {
                        TFLoading(.inline)
                    } else {
                        Text("Потяните вниз, чтобы обновить.")
                            .tfText(.action)
                            .foregroundStyle(Color.tfSub)
                    }
                }
                .padding(.horizontal, TFSpacing.lg)
                .padding(.vertical, TFSpacing.md)
            }
            .accessibilityIdentifier("memory-observer-stats")
        }
    }

    @MainActor
    private func load(force: Bool = false) async {
        guard force || !busy else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            async let settingsTask = api.serverSettings()
            async let modelsTask = api.runtimeModels()
            async let statsTask = api.memoryObserverStats(days: 7)
            let snapshot = try await settingsTask
            models = (try? await modelsTask) ?? []
            stats = try? await statsTask
            enabled = boolValue(snapshot, "memory_observer_enabled", true)
            confidence = intValue(snapshot, "memory_observer_min_confidence", 60)
            embeddingModel = stringValue(snapshot, "embedding_model", "bge-m3-embed:latest")
            duplicateSimilarity = intValue(snapshot, "memory_duplicate_similarity", 92)
            modelRef = Self.resolvedModelRef(
                raw: stringValue(snapshot, "memory_observer_model", ""),
                catalog: models
            )
            loaded = true
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Приводит сохранённое значение к `провайдер/id`. Старый «голый» id
    /// или пара из мёртвого UI поднимаем по каталогу; неизвестное — пусто.
    static func resolvedModelRef(raw: String, catalog: [RuntimeModel]) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let hit = catalog.model(forRef: trimmed) { return hit.routeRef }
        if let byID = catalog.first(where: { $0.id == trimmed && $0.available && $0.isRoutable }) {
            return byID.routeRef
        }
        // Уже похоже на routeRef, но модели нет в каталоге — оставляем как есть,
        // чтобы не стереть выбор до обновления списка.
        if trimmed.contains("/") { return trimmed }
        return ""
    }

    @MainActor
    private func save(_ key: String, _ value: JSONValue) async {
        error = nil
        do {
            try await api.updateServerSetting(key: key, value: value)
            if key == "embedding_model" || key == "memory_duplicate_similarity" {
                stats = try? await api.memoryObserverStats(days: 7)
            }
        } catch {
            self.error = error.localizedDescription
            await load(force: true)
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
