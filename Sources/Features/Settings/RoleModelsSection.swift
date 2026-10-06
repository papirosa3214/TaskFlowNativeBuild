import SwiftUI
import Observation

/// «Модели ролей» на экране «Модели и провайдеры» (владелец 07.10.2026):
/// основная модель каждой роли, строка «Всем ролям», цепочка запасных у каждой
/// роли (тап по строке), общие тумблеры автопереключения и статус лимитов.
/// Веб-экран тот же (`RoleModelsBlock.tsx`). Выбор сохраняется сразу.
@MainActor
@Observable
final class RoleModelsViewModel {
    private let api = APIClient()

    var roles: [AgentProfile] = []
    var failover: FailoverStatus?
    /// Роль, которая сохраняется сейчас; "*" — «Всем ролям» и операции с лимитами.
    var busy: String?
    var errorMessage: String?

    func load() async {
        do {
            roles = try await api.runtimeProfiles().filter { $0.id != AgentProfile.autoAssignID }
            failover = try await api.failoverStatus()
            errorMessage = nil
        } catch {
            errorMessage = Self.message(error)
        }
    }

    func set(role: String, to ref: String) async {
        await run(role) { try await self.api.updateRuntimeRoutingPrimary(role: role, primary: ref) }
    }

    func saveChain(role: String, primary: String, fallbacks: [String]) async {
        await run(role) { try await self.api.updateRuntimeRouting(role: role, primary: primary, fallbacks: fallbacks) }
    }

    func setAll(to ref: String) async {
        await run("*") { try await self.api.updateRuntimeRoutingAll(primary: ref) }
    }

    func setFailover(autoSwitch: Bool? = nil, autoReturn: Bool? = nil) async {
        await run("*") { try await self.api.setFailover(autoSwitch: autoSwitch, autoReturn: autoReturn) }
    }

    func release(_ provider: String) async {
        await run("*") { try await self.api.releaseProviderLimit(provider) }
    }

    private func run<T>(_ key: String, _ action: @escaping () async throws -> T) async {
        guard busy == nil else { return }
        busy = key
        defer { busy = nil }
        do {
            _ = try await action()
            await load()
        } catch {
            errorMessage = Self.message(error)
        }
    }

    private static func message(_ error: Error) -> String {
        (error as? APIError)?.errorDescription ?? error.localizedDescription
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
    @State private var editing: AgentProfile?

    private var options: [RuntimeModel] { models.filter { $0.available && $0.isRoutable } }

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.xl) {
            TFErrorBanner(viewModel.errorMessage)
            FailoverSettingsSection(viewModel: viewModel)
            rolesCard
        }
        .confirmationDialog(
            "Поставить эту модель всем ролям?",
            isPresented: Binding(get: { pendingAll != nil }, set: { if !$0 { pendingAll = nil } }),
            titleVisibility: .visible
        ) {
            Button("Поставить всем") {
                if let model = pendingAll { Task { await viewModel.setAll(to: model.routeRef) } }
                pendingAll = nil
            }
            Button("Отмена", role: .cancel) { pendingAll = nil }
        } message: {
            Text("Основная модель каждой роли станет «\(pendingAll?.displayName ?? "")». Запасные остаются как есть.")
        }
        .sheet(item: $editing) { profile in
            RoleChainSheet(viewModel: viewModel, profile: profile, models: models)
        }
    }

    private var rolesCard: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            TFSectionHeader("Модели ролей")
            TFCard(padding: 0) {
                VStack(spacing: 0) {
                    row(title: "Всем ролям", subtitle: "основная модель на всех сразу") {
                        ModelMenu(
                            label: "— выбрать —",
                            accessibility: "Модель для всех ролей",
                            options: options,
                            disabled: viewModel.busy != nil
                        ) { pendingAll = $0 }
                    }
                    ForEach(viewModel.roles) { profile in
                        TFDivider(inset: TFSpacing.lg)
                        roleRow(profile)
                    }
                }
            }
        }
    }

    private func roleRow(_ profile: AgentProfile) -> some View {
        let state = viewModel.failover?.roles.first { $0.role == profile.role }
        let chain = profile.modelPolicy.fallbacks
        let subtitle = state?.onFallback == true
            ? "сейчас на запасной: \(models.name(forRef: state?.current ?? ""))"
            : (chain.isEmpty ? "запасных нет" : "запасных: \(chain.count)")
        return HStack(spacing: TFSpacing.md) {
            Button { editing = profile } label: {
                HStack(spacing: TFSpacing.sm) {
                    titleBlock(profile.title, subtitle, warn: state?.onFallback == true)
                    Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Color.tfDim)
                }
                .frame(minHeight: TFField.height)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Цепочка запасных: \(profile.title)")
            Spacer(minLength: TFSpacing.sm)
            ModelMenu(
                label: models.name(forRef: profile.modelPolicy.primary),
                accessibility: "Модель роли \(profile.title)",
                options: options,
                disabled: viewModel.busy != nil
            ) { model in Task { await viewModel.set(role: profile.role, to: model.routeRef) } }
        }
        .padding(.horizontal, TFSpacing.lg)
    }

    private func titleBlock(_ title: String, _ subtitle: String?, warn: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).tfText(.action).foregroundStyle(Color.tfText)
            if let subtitle {
                Text(subtitle).tfText(.caption).foregroundStyle(warn ? Color.tfOrange : Color.tfSub)
            }
        }
    }

    private func row<Trailing: View>(
        title: String,
        subtitle: String?,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: TFSpacing.md) {
            titleBlock(title, subtitle)
            Spacer(minLength: TFSpacing.sm)
            trailing()
        }
        .padding(.horizontal, TFSpacing.lg)
        .frame(minHeight: TFField.height)
    }
}
