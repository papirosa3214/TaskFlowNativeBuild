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
            HStack(spacing: 4) {
                if let state {
                    Menu {
                        Button("Автоматически") { select("auto", nil) }
                        ForEach(state.candidates) { candidate in
                            Button(candidate.title) { select("manual", candidate.id) }
                        }
                        Button("Не требуется") { select("not_required", nil) }
                        Button("Не выбран") { select("manual", nil) }
                    } label: {
                        TFPill(surface: .clear) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.branch")
                                Text(state.mode == "not_required" ? "Не требуется" : state.owner_title ?? "Выбрать участника")
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                            .tfText(.action)
                            .foregroundStyle(validationError ? Color.red : Color.tfSub)
                            .padding(.horizontal, TFSpacing.sm)
                            .padding(.vertical, 6)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Ответственный за интеграцию")
                    .accessibilityValue(state.mode == "not_required" ? "Не требуется" : state.owner_title ?? "Не выбран")
                    .accessibilityIdentifier("integration-owner-picker")
                    .disabled(saving)
                } else if error == nil {
                    TFLoading(.inline)
                }
                Button { help = true } label: {
                    Image(systemName: "questionmark.circle").foregroundStyle(Color.tfDim)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Об ответственности за интеграцию")
                .accessibilityIdentifier("integration-help")
                Spacer(minLength: 0)
            }
            if validationError {
                Text("Назначьте ответственного за перенос изменений в основную ветку")
                    .tfText(.meta).foregroundStyle(.red)
                    .accessibilityIdentifier("integration-owner-error")
            }
            if let error {
                // 16.10.2026 (LOCK-UI-DRIFT-KNOWN): системная кнопка в потоке
                // экрана всегда синяя, а кнопки приложения серые. Сообщение —
                // общим баннером, действие — кнопкой приложения.
                TFErrorBanner(error, variant: .block)
                    .accessibilityIdentifier("integration-load-error")
                TFButton("Повторить", icon: "arrow.clockwise", variant: .secondary) {
                    Task { await load() }
                }
                .accessibilityIdentifier("integration-retry")
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
        // Отмена — не сбой: обновление карточки перезапускает загрузку, и
        // прерванный запрос показывался красной плашкой «CancellationError»
        // (владелец 20.10.2026). Свежий запрос уже идёт следом.
        catch is CancellationError {}
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
