import SwiftUI
import Observation
import os

// Настройки → Сервер: строка «Перезапустить сервер» (только владелец, MAK-76).
// Перезапуск обрывает идущие запуски; после старта сервер возобновляет их
// сам, поэтому перед действием спрашиваем подтверждение и называем число
// идущих запусков.

@MainActor
@Observable
final class ServerRestartViewModel {
    private let api: APIClient
    private let log = Logger(subsystem: "TaskFlow", category: "server-restart")

    /// `nil` — не дозвонились до сервера. Это не «0 запусков»: подпись
    /// «нет идущих» там, где мы просто не знаем, соврала бы владельцу.
    private(set) var activeRuns: Int?
    private(set) var isRestarting = false
    var errorMessage: String?

    init(api: APIClient = APIClient()) {
        self.api = api
    }

    func load() async {
        do {
            activeRuns = try await api.fetchOwnerRuntimeStatus().activeRuns
        } catch {
            log.error("состояние запусков не прочитано: \(error.localizedDescription, privacy: .public)")
            activeRuns = nil
        }
    }

    func restart() async {
        guard !isRestarting else { return }
        isRestarting = true
        errorMessage = nil
        do {
            _ = try await api.restartServer()
        } catch {
            log.error("перезапуск не принят: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Команда не принята сервером"
            isRestarting = false
            return
        }
        // Сервер поднимается сам; ждём немного и перечитываем состояние.
        try? await Task.sleep(for: .seconds(15))
        isRestarting = false
        await load()
    }
}

struct ServerRestartRow: View {
    @State private var viewModel = ServerRestartViewModel()
    @State private var showConfirm = false

    var body: some View {
        TFCard(padding: 0, bordered: true) {
            VStack(spacing: 0) {
                TFListRow(
                    icon: "arrow.triangle.2.circlepath", iconStyle: .plain,
                    title: "Перезапустить сервер",
                    subtitle: subtitle,
                    trailing: viewModel.isRestarting ? AnyView(ProgressView()) : nil,
                    titleStyle: .body,
                    verticalPadding: TFSpacing.xs,
                    action: {
                        guard !viewModel.isRestarting else { return }
                        showConfirm = true
                    }
                )
                .accessibilityIdentifier("settings.restart-server")
                if viewModel.errorMessage != nil {
                    TFErrorBanner(viewModel.errorMessage)
                        .padding(.horizontal, TFSpacing.lg)
                        .padding(.bottom, TFSpacing.sm)
                }
            }
        }
        .task { await viewModel.load() }
        .confirmationDialog("Перезапустить сервер?", isPresented: $showConfirm, titleVisibility: .visible) {
            Button("Перезапустить", role: .destructive) {
                Task { await viewModel.restart() }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text(confirmMessage)
        }
    }

    private var subtitle: String? {
        if viewModel.isRestarting { return "перезапускается…" }
        guard let runs = viewModel.activeRuns else { return "Нет связи с сервером" }
        return "идущих запусков: \(runs)"
    }

    private var confirmMessage: String {
        if let runs = viewModel.activeRuns, runs > 0 {
            return "Идущие запуски (\(runs)) оборвутся и продолжатся после старта сервера."
        }
        return "Сервер поднимется сам, зависшие шаги он возобновит."
    }
}
