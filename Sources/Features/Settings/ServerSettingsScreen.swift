import SwiftUI
import Observation

@MainActor @Observable
final class ServerSettingsViewModel {
    var snapshot: ServerSettingsSnapshot?
    var loading = false
    var error: String?
    var log: [ServerSettingLog] = []
    var logLoading = false
    private let api = APIClient()

    func load() async {
        #if DEBUG
        if ProcessInfo.processInfo.environment["TASKFLOW_DIAGNOSTICS_PREVIEW"] == "1" {
            snapshot = ServerSettingsSnapshot(settings: [], values: [:], updatedAt: [:])
            return
        }
        #endif
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do { snapshot = try await api.serverSettings(); error = nil }
        catch {
            if case APIError.server(let status, _) = error, status == 404 {
                self.error = "Параметры пока недоступны на основном сервере. Попробуйте обновить позже."
            } else { self.error = error.localizedDescription }
        }
    }
    func loadLog() async {
        guard !logLoading else { return }
        logLoading = true
        defer { logLoading = false }
        do { log = try await api.serverSettingsLog(); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

struct ServerSettingsScreen: View {
    @State private var model = ServerSettingsViewModel()
    @State private var editing: ServerSetting?
    @State private var showsLog = false

    var body: some View {
        List {
            if let error = model.error {
                Section {
                    Text(error).foregroundStyle(Color.tfSub)
                        .accessibilityIdentifier("server-settings-error")
                    Button("Обновить") { Task { await model.load() } }
                }
            }
            if model.loading && model.snapshot == nil { TFLoading(.inline) }
            if let snapshot = model.snapshot {
                ForEach(snapshot.groups, id: \.self) { group in
                    Section(groupTitle(group)) {
                        ForEach(snapshot.settings.filter { $0.group == group }) { setting in
                            Button { editing = setting } label: {
                                HStack {
                                    Text(setting.label).foregroundStyle(Color.tfText)
                                    Spacer()
                                    Text(setting.displayText(snapshot.values[setting.key] ?? setting.defaultValue))
                                        .foregroundStyle(Color.tfSub)
                                    Image(systemName: "chevron.right").foregroundStyle(Color.tfSub)
                                }
                            }
                            .accessibilityIdentifier("server-setting-" + setting.key)
                            .hintAnchor("server.setting." + setting.key)
                        }
                    }
                }
                Section {
                    Button("История изменений") {
                        showsLog = true
                        Task { await model.loadLog() }
                    }
                    .foregroundStyle(Color.tfText)
                }
            }
            Section {
                NavigationLink {
                    AppDiagnosticsScreen()
                } label: {
                    Label("Диагностика", systemImage: "waveform.path.ecg")
                        .foregroundStyle(Color.tfText)
                }
                .accessibilityIdentifier("server-settings-diagnostics")
            }
        }
        .tfScreenBackground()
        .tfNativeHeader("Параметры сервера")
        .accessibilityIdentifier("server-settings-screen")
        .task { await model.load() }
        .refreshable { await model.load() }
        .sheet(item: $editing) { setting in
            ServerSettingEditor(setting: setting,
                value: model.snapshot?.values[setting.key] ?? setting.defaultValue) {
                    await model.load()
                }
        }
        .sheet(isPresented: $showsLog) {
            NavigationStack {
                List {
                    if model.logLoading { TFLoading(.inline) }
                    if let error = model.error { Text(error) }
                    if !model.logLoading && model.error == nil && model.log.isEmpty {
                        Text("Параметры ещё не меняли").foregroundStyle(Color.tfSub)
                    }
                    ForEach(model.log) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.snapshot?.settings.first { $0.key == entry.key }?.label ?? entry.key)
                            Text("\(readableLogValue(entry.oldValue, key: entry.key)) → \(readableLogValue(entry.newValue, key: entry.key))")
                                .foregroundStyle(Color.tfSub)
                            if let reason = entry.reason, !reason.isEmpty { Text(reason).tfText(.meta) }
                            Text(entry.createdAt).tfText(.meta).foregroundStyle(Color.tfSub)
                        }
                    }
                }
                .navigationTitle("История изменений")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { showsLog = false } } }
            }
        }
    }
    private func readableLogValue(_ raw: String?, key: String) -> String {
        guard let raw else { return "По умолчанию" }
        guard let data = raw.data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data) else { return raw }
        return model.snapshot?.settings.first { $0.key == key }?.displayText(value) ?? value.serverSettingText
    }
    private func groupTitle(_ group: String) -> String {
        switch group {
        case "linear": "Синхронизация Linear"
        case "режим_приёма": "Приём задач"
        case "автоимпорт": "Автоимпорт"
        default: group.capitalized
        }
    }
}

private struct ServerSettingEditor: View {
    let setting: ServerSetting
    let value: JSONValue
    let onSaved: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var number = ""
    @State private var enabled = false
    @State private var option = ""
    @State private var saving = false
    @State private var error: String?
    @State private var confirmsReset = false
    private let api = APIClient()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if setting.kind == "bool" {
                        HStack {
                            Text(setting.label)
                            Spacer()
                            TFToggle(isOn: $enabled)
                        }
                    } else if setting.kind == "enum" {
                        Picker(setting.label, selection: $option) {
                            ForEach(setting.options ?? [], id: \.self) { item in
                                Text(JSONValue.string(item).serverSettingText).tag(item)
                            }
                        }
                    } else {
                        TextField("Значение", text: $number)
                            .keyboardType(.numbersAndPunctuation)
                            .accessibilityIdentifier("server-setting-value")
                        if !setting.unit.isEmpty { Text("Единица: " + setting.unit).foregroundStyle(Color.tfSub) }
                        if let min = setting.min, let max = setting.max {
                            Text("От \(setting.displayNumber(min)) до \(setting.displayNumber(max))").foregroundStyle(Color.tfSub)
                        }
                    }
                } header: { Text(setting.label) }
                footer: {
                    VStack(alignment: .leading, spacing: TFSpacing.xs) {
                        if let explanation = setting.explanation { Text(explanation) }
                        Text("По умолчанию: " + setting.displayText(setting.defaultValue))
                    }
                }
                if let error { Section { Text(error).foregroundStyle(Color.tfCoral) } }
                Section {
                    Button("Сбросить к значению по умолчанию") { confirmsReset = true }
                        .accessibilityIdentifier("server-setting-reset")
                }
            }
            .disabled(saving)
            .navigationTitle("Параметр")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { TFLoading(.inline) }
                    else { Button("Сохранить") { Task { await save() } }.accessibilityIdentifier("server-setting-save") }
                }
            }
            .confirmationDialog("Сбросить параметр?", isPresented: $confirmsReset, titleVisibility: .visible) {
                Button("Сбросить") { Task { await reset() } }
            }
            .onAppear {
                if case .number(let v) = value { number = setting.displayNumber(v) }
                if case .bool(let v) = value { enabled = v }
                if case .string(let v) = value { option = v }
            }
        }
    }
    private func save() async {
        saving = true
        defer { saving = false }
        do {
            let next: JSONValue
            if setting.kind == "bool" { next = .bool(enabled) }
            else if setting.kind == "enum" {
                guard (setting.options ?? []).contains(option) else { throw SettingValidationError(message: "Выберите значение") }
                next = .string(option)
            } else { next = try setting.validatedNumber(number) }
            try await api.updateServerSetting(key: setting.key, value: next)
            await onSaved()
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
    private func reset() async {
        saving = true
        defer { saving = false }
        do {
            try await api.resetServerSetting(key: setting.key)
            await onSaved()
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
