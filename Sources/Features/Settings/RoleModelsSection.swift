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
        // Прошлые данные из кэша — раздел виден сразу, сеть его обновит.
        if roles.isEmpty, let cached = api.cachedRuntimeProfiles() {
            roles = cached.filter { $0.id != AgentProfile.autoAssignID }
        }
        if failover == nil { failover = api.cachedFailoverStatus() }
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

    /// Как модель записывается в маршрут роли — всегда `провайдер/id`
    /// (20.10.2026). «Голый» id сервер угадывал по имени: `claude-…` есть и у
    /// anthropic, и у opencode, `deepseek-…` — у opencode и opencode-go.
    var routeRef: String { "\(provider)/\(id)" }

    /// Имя провайдера для человека: технический id ничего не говорит о том,
    /// подписка это или оплата за каждый запрос.
    static func providerTitle(_ provider: String) -> String {
        switch provider {
        case "opencode-go": "OpenCode Go · подписка"
        case "opencode": "OpenCode Zen · оплата за запросы"
        case "openai-codex": "ChatGPT · подписка Codex"
        case "openai": "OpenAI · ключ API"
        case "anthropic": "Anthropic · Claude"
        case "minimax": "MiniMax"
        case "kimi-coding": "Kimi"
        case "ollama": "Ollama · локально"
        default: provider
        }
    }

    static func providerShort(_ provider: String) -> String {
        switch provider {
        case "opencode-go": "Go"
        case "opencode": "Zen"
        case "openai-codex": "Codex"
        case "anthropic": "Anthropic"
        case "minimax": "MiniMax"
        default: provider
        }
    }
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
            Text("Основная модель каждой роли станет «\(pendingAll.map { models.label(forRef: $0.routeRef) } ?? "")». Запасные остаются как есть.")
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
                            disabled: viewModel.busy != nil,
                            problem: { viewModel.failover?.problem(of: $0) }
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
        let primaryProblem = models.model(forRef: profile.modelPolicy.primary)
            .flatMap { viewModel.failover?.problem(of: $0.provider) }
        let subtitle = state?.onFallback == true
            ? "сейчас на запасной: \(models.label(forRef: state?.current ?? ""))"
            : primaryProblem.map { "⚠︎ основная: \($0)" }
                ?? (chain.isEmpty ? "запасных нет" : "запасных: \(chain.count)")
        return HStack(spacing: TFSpacing.md) {
            Button { editing = profile } label: {
                HStack(spacing: TFSpacing.sm) {
                    titleBlock(profile.title, subtitle, warn: state?.onFallback == true || primaryProblem != nil)
                    Image(systemName: "chevron.right").tfText(.action).foregroundStyle(Color.tfDim)
                }
                .frame(minHeight: TFField.height)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Модели роли \(profile.title): основная и запасные")
            Spacer(minLength: TFSpacing.sm)
            ModelMenu(
                label: models.label(forRef: profile.modelPolicy.primary),
                accessibility: "Основная модель роли \(profile.title)",
                options: options,
                disabled: viewModel.busy != nil,
                problem: { viewModel.failover?.problem(of: $0) }
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
