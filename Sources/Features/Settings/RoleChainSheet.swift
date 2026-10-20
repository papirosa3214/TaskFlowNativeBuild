import SwiftUI

/// Модели одной роли (владелец 07.10.2026, переделано 20.10.2026: «с телефона не
/// тыкается»). Основная, запасные по порядку и автозамена при лимите — всё на
/// одном экране и обычными нажатиями: без режима «Изменить» и свайпов, в которых
/// меню выбора модели не открывалось. Каждое изменение сохраняется сразу.
struct RoleChainSheet: View {
    @Bindable var viewModel: RoleModelsViewModel
    let profile: AgentProfile
    let models: [RuntimeModel]

    @Environment(\.dismiss) private var dismiss

    /// Актуальный профиль: после сохранения список ролей перечитывается, а `profile` — снимок на момент открытия.
    private var live: AgentProfile { viewModel.roles.first { $0.role == profile.role } ?? profile }
    private var primary: String { live.modelPolicy.primary }
    private var chain: [String] { live.modelPolicy.fallbacks }
    private var options: [RuntimeModel] { models.filter { $0.available && $0.isRoutable } }
    private var busy: Bool { viewModel.busy != nil }

    var body: some View {
        NavigationStack {
            List {
                primarySection
                fallbackSection
                autoSwitchSection
            }
            .tfScreenBackground()
            .navigationTitle(profile.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } }
            }
            .safeAreaInset(edge: .top) { TFErrorBanner(viewModel.errorMessage) }
        }
    }

    private var primarySection: some View {
        Section {
            ModelMenu(
                label: primary.isEmpty ? "— выбрать —" : models.label(forRef: primary),
                accessibility: "Основная модель",
                options: options,
                disabled: busy,
                problem: problem
            ) { model in
                save(primary: model.routeRef, fallbacks: chain.filter { $0 != model.routeRef })
            }
            problemCaption(primary)
        } header: {
            Text("Основная модель")
        }
    }

    private var fallbackSection: some View {
        Section {
            ForEach(Array(chain.enumerated()), id: \.element) { index, ref in
                FallbackRow(
                    index: index,
                    count: chain.count,
                    title: models.label(forRef: ref),
                    problem: providerProblem(ref),
                    disabled: busy
                ) { action in apply(action, at: index) }
            }
            ModelMenu(
                label: "Добавить запасную",
                accessibility: "Добавить запасную модель",
                options: options.filter { $0.routeRef != primary && !chain.contains($0.routeRef) },
                disabled: busy,
                problem: problem
            ) { model in save(primary: primary, fallbacks: chain + [model.routeRef]) }
        } header: {
            Text("Запасные по порядку")
        } footer: {
            Text(chain.isEmpty
                ? "Запасных нет: упрётся в лимит — роль остановится."
                : "Основная упёрлась в лимит — берётся первая запасная, затем вторая…")
        }
    }

    private var autoSwitchSection: some View {
        Section {
            HStack(spacing: TFSpacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Автозамена при лимите").tfText(.body).foregroundStyle(Color.tfText)
                    Text("общая для всех ролей").tfText(.caption).foregroundStyle(Color.tfSub)
                }
                Spacer(minLength: TFSpacing.sm)
                TFToggle(isOn: Binding(
                    get: { viewModel.failover?.autoSwitch ?? false },
                    set: { value in Task { await viewModel.setFailover(autoSwitch: value) } }
                ))
                .disabled(busy || viewModel.failover == nil)
            }
            .frame(minHeight: TFField.height)
        } footer: {
            Text("Выключено — при лимите роль ждёт основную модель, запасные не берутся.")
        }
    }

    @ViewBuilder
    private func problemCaption(_ ref: String) -> some View {
        if let text = providerProblem(ref) {
            Text("⚠︎ \(text)").tfText(.caption).foregroundStyle(Color.tfOrange)
        }
    }

    private func problem(_ provider: String) -> String? { viewModel.failover?.problem(of: provider) }

    /// Провайдер берётся из каталога, а для модели, которой там нет, — из префикса записи.
    private func providerProblem(_ ref: String) -> String? {
        let provider = models.model(forRef: ref)?.provider
            ?? (ref.contains("/") ? String(ref.prefix { $0 != "/" }) : nil)
        return provider.flatMap(problem)
    }

    private func apply(_ action: FallbackRow.Action, at index: Int) {
        var next = chain
        switch action {
        case .up where index > 0: next.swapAt(index, index - 1)
        case .down where index < next.count - 1: next.swapAt(index, index + 1)
        case .remove: next.remove(at: index)
        default: return
        }
        save(primary: primary, fallbacks: next)
    }

    private func save(primary: String, fallbacks: [String]) {
        guard !primary.isEmpty else { return }
        Task { await viewModel.saveChain(role: profile.role, primary: primary, fallbacks: fallbacks) }
    }
}

/// Строка запасной: номер, модель, что мешает провайдеру, и кнопки «выше»,
/// «ниже», «убрать» — каждая со своей зоной нажатия 44×44.
private struct FallbackRow: View {
    enum Action { case up, down, remove }

    let index: Int
    let count: Int
    let title: String
    let problem: String?
    let disabled: Bool
    let onAction: (Action) -> Void

    var body: some View {
        HStack(spacing: TFSpacing.xs) {
            Text("\(index + 1).").tfText(.body).foregroundStyle(Color.tfSub)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).tfText(.body).foregroundStyle(Color.tfText).lineLimit(2)
                if let problem {
                    Text("⚠︎ \(problem)").tfText(.caption).foregroundStyle(Color.tfOrange)
                }
            }
            Spacer(minLength: TFSpacing.xs)
            TFIconButton("chevron.up", label: "Выше") { onAction(.up) }
                .disabled(disabled || index == 0)
                .opacity(index == 0 ? 0.3 : 1)
            TFIconButton("chevron.down", label: "Ниже") { onAction(.down) }
                .disabled(disabled || index == count - 1)
                .opacity(index == count - 1 ? 0.3 : 1)
            TFIconButton("xmark", label: "Убрать") { onAction(.remove) }
                .disabled(disabled)
        }
        .accessibilityElement(children: .contain)
    }
}
