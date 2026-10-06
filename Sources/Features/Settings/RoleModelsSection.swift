import SwiftUI
import Observation

/// «Модели ролей» на экране «Модели и провайдеры» (владелец 07.10.2026):
/// основная модель каждой роли и строка «Всем ролям» — выбрал, раскатилось
/// на все роли. Веб-экран тот же (`RoleModelsBlock.tsx`). Выбор сохраняется
/// сразу; запасные модели роли сервер не трогает (PUT без fallbacks), на них
/// держится автопереключение при лимите.
@MainActor
@Observable
final class RoleModelsViewModel {
    private let api = APIClient()

    var roles: [AgentProfile] = []
    /// Роль, которая сохраняется сейчас; "*" — «Всем ролям».
    var busy: String?
    var errorMessage: String?

    func load() async {
        do {
            roles = try await api.runtimeProfiles().filter { $0.id != AgentProfile.autoAssignID }
            errorMessage = nil
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func set(role: String, to ref: String) async {
        guard busy == nil else { return }
        busy = role
        defer { busy = nil }
        do {
            try await api.updateRuntimeRoutingPrimary(role: role, primary: ref)
            await load()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func setAll(to ref: String) async {
        guard busy == nil else { return }
        busy = "*"
        defer { busy = nil }
        do {
            try await api.updateRuntimeRoutingAll(primary: ref)
            await load()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

extension RuntimeModel {
    /// Провайдеры, которые сервер умеет маршрутизировать по ссылке
    /// `провайдер/модель` (`KNOWN_MODEL_PROVIDERS` в `attemptModel.ts`).
    private static let routable: Set<String> = [
        "opencode-go", "opencode", "minimax", "anthropic",
        "openai-codex", "openai", "kimi-coding", "ollama",
    ]

    var isRoutable: Bool { Self.routable.contains(provider) }

    /// Провайдер «по имени модели» — так угадывает сервер (`providerOfModel`).
    private static func guessProvider(_ id: String) -> String {
        let m = id.lowercased()
        if m.hasPrefix("claude") { return "anthropic" }
        if m.hasPrefix("gpt") || m.hasPrefix("o1") || m.hasPrefix("o3") { return "openai" }
        return "minimax"
    }

    /// Как модель записывается в маршрут роли: «голый» id, если провайдер
    /// угадывается по имени, иначе `провайдер/id`.
    var routeRef: String { Self.guessProvider(id) == provider ? id : "\(provider)/\(id)" }
}

struct RoleModelsSection: View {
    @Bindable var viewModel: RoleModelsViewModel
    let models: [RuntimeModel]

    @State private var pendingAll: RuntimeModel?

    private var options: [RuntimeModel] { models.filter { $0.available && $0.isRoutable } }

    private var providerOrder: [String] {
        var seen: [String] = []
        for model in options where !seen.contains(model.provider) { seen.append(model.provider) }
        return seen
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            TFSectionHeader("Модели ролей")
            TFErrorBanner(viewModel.errorMessage)
            TFCard(padding: 0) {
                VStack(spacing: 0) {
                    allRolesRow
                    ForEach(viewModel.roles) { profile in
                        TFDivider(inset: TFSpacing.lg)
                        roleRow(profile)
                    }
                }
            }
        }
        .confirmationDialog(
            "Поставить эту модель всем ролям?",
            isPresented: Binding(get: { pendingAll != nil }, set: { if !$0 { pendingAll = nil } }),
            titleVisibility: .visible
        ) {
            Button("Поставить всем") {
                if let model = pendingAll {
                    Task { await viewModel.setAll(to: model.routeRef) }
                }
                pendingAll = nil
            }
            Button("Отмена", role: .cancel) { pendingAll = nil }
        } message: {
            Text("Основная модель каждой роли станет «\(pendingAll?.displayName ?? "")». Запасные остаются как есть.")
        }
    }

    private var allRolesRow: some View {
        row(title: "Всем ролям", subtitle: "на всех сразу") {
            picker(label: "— выбрать —", accessibility: "Модель для всех ролей") { pendingAll = $0 }
        }
    }

    private func roleRow(_ profile: AgentProfile) -> some View {
        let current = profile.modelPolicy.primary
        let currentName = models.first { $0.routeRef == current }?.displayName ?? current
        return row(title: profile.title, subtitle: nil) {
            picker(label: currentName, accessibility: "Модель роли \(profile.title)") { model in
                Task { await viewModel.set(role: profile.role, to: model.routeRef) }
            }
        }
    }

    private func row<Trailing: View>(
        title: String,
        subtitle: String?,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: TFSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .tfText(.action)
                    .foregroundStyle(Color.tfText)
                if let subtitle {
                    Text(subtitle)
                        .tfText(.caption)
                        .foregroundStyle(Color.tfSub)
                }
            }
            Spacer(minLength: TFSpacing.sm)
            trailing()
        }
        .padding(.horizontal, TFSpacing.lg)
        .frame(minHeight: TFField.height)
    }

    private func picker(
        label: String,
        accessibility: String,
        onPick: @escaping (RuntimeModel) -> Void
    ) -> some View {
        Menu {
            ForEach(providerOrder, id: \.self) { provider in
                Section(provider) {
                    ForEach(options.filter { $0.provider == provider }, id: \.uid) { model in
                        Button(model.displayName) { onPick(model) }
                    }
                }
            }
        } label: {
            HStack(spacing: TFSpacing.xs) {
                Text(label)
                    .tfText(.action)
                    .foregroundStyle(Color.tfSub)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote)
                    .foregroundStyle(Color.tfDim)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .disabled(viewModel.busy != nil)
        .accessibilityLabel(accessibility)
    }
}
