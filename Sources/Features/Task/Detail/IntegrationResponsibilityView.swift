import SwiftUI

struct IntegrationResponsibilityView: View {
    let taskID: String
    let reloadToken: Int
    @Binding var validationError: Bool
    @State private var state: IntegrationResponsibility?
    @State private var help = false
    @State private var error: String?
    @State private var saving = false
    private let api = APIClient()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Ответственный за интеграцию").font(.subheadline)
                    .foregroundStyle(validationError ? Color.red : Color.primary)
                Button { help = true } label: {
                    Image(systemName: "questionmark.circle").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Об ответственности за интеграцию")
                .accessibilityIdentifier("integration-help")
                Spacer(minLength: 0)
            }
            if let state {
                Menu {
                    Button("Автоматически") { select("auto", nil) }
                    ForEach(state.candidates) { candidate in
                        Button(candidate.title) { select("manual", candidate.id) }
                    }
                    Button("Не требуется") { select("not_required", nil) }
                    Button("Не выбран") { select("manual", nil) }
                } label: {
                    HStack {
                        Text(state.mode == "not_required" ? "Не требуется" : state.owner_title ?? "Выбрать участника")
                        Image(systemName: "chevron.up.chevron.down").font(.caption)
                    }
                }
                .accessibilityIdentifier("integration-owner-picker")
                .disabled(saving)
            } else if error == nil {
                ProgressView()
            }
            if validationError {
                Text("Назначьте ответственного за перенос изменений в основную ветку")
                    .font(.caption).foregroundStyle(.red)
                    .accessibilityIdentifier("integration-owner-error")
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
                Button("Повторить") { Task { await load() } }
            }
        }
        .task(id: "\(taskID)-\(reloadToken)") { await load() }
        .sheet(isPresented: $help) {
            NavigationStack {
                List {
                    Text("Переносит проверенные изменения из рабочих веток в основную ветку репозитория и проверяет общий результат. Выкладка — отдельный шаг, если она входит в задачу.")
                    Text("Автоматический выбор: оркестратор → архитектор → единственный исполнитель. Если исполнителей несколько, выберите конкретного участника. Назначение можно изменить.")
                    Text("Для работы без изменений в репозитории выберите «Не требуется». Черновик можно сохранить без ответственного; запуск команды требует назначения.")
                }
                .navigationTitle("Интеграция")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { help = false } } }
            }
        }
    }
    private func load() async {
        do { state = try await api.integrationResponsibility(taskID: taskID); error = nil }
        catch { self.error = error.localizedDescription }
    }
    private func select(_ mode: String, _ id: String?) {
        saving = true
        Task {
            defer { saving = false }
            do {
                state = try await api.setIntegrationResponsibility(taskID: taskID, mode: mode, ownerID: id)
                validationError = false
                error = nil
            } catch { self.error = error.localizedDescription }
        }
    }
}
