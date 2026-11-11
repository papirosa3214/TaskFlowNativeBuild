import SwiftUI

/// «Настройки → Команда → Реестр правил» (11.11.2026): какие правила сервер
/// вкладывает ролям, какие не доходят, кому адресованы. Владелец включает и
/// выключает правило, выбирает роли и отмечает «рекомендовано всем».
@MainActor
@Observable
final class RoleRulesViewModel {
    var roles: [RoleRuleRole] = []
    var rules: [RoleRule] = []
    var errorMessage: String?
    var isLoading = false
    private let api = APIClient()

    func load() async {
        isLoading = rules.isEmpty
        defer { isLoading = false }
        do {
            let envelope = try await api.roleRules()
            roles = envelope.roles
            rules = envelope.rules
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func rule(_ id: String) -> RoleRule? { rules.first { $0.id == id } }

    func update(_ id: String, _ patch: RoleRulePatch) async {
        do {
            let updated = try await api.updateRoleRule(id: id, patch)
            if let index = rules.firstIndex(where: { $0.id == id }) { rules[index] = updated }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct RoleRulesScreen: View {
    @State private var viewModel = RoleRulesViewModel()
    @State private var roleFilter: String?
    @State private var query = ""
    @State private var detailID: RuleID?

    private struct RuleID: Identifiable { let id: String }

    private var filtered: [RoleRule] {
        let text = query.trimmingCharacters(in: .whitespaces)
        return viewModel.rules.filter { rule in
            if let roleFilter, !rule.roles.includes(roleFilter) { return false }
            guard !text.isEmpty else { return true }
            return rule.id.localizedCaseInsensitiveContains(text) || rule.text.localizedCaseInsensitiveContains(text)
        }
    }

    var body: some View {
        let active = filtered.filter(\.active)
        let inactive = filtered.filter { !$0.active }
        List {
            Section {
                Picker("Роль", selection: $roleFilter) {
                    Text("Все роли").tag(String?.none)
                    ForEach(viewModel.roles) { role in
                        Text(role.name).tag(String?.some(role.id))
                    }
                }
                .pickerStyle(.menu)
            }
            if viewModel.errorMessage != nil {
                Section { TFErrorBanner(viewModel.errorMessage, variant: .block) }
            }
            if viewModel.isLoading {
                Section { TFLoading(.block) }
            }
            if !active.isEmpty {
                Section("Действуют") {
                    ForEach(active) { row($0) }
                }
            }
            if !inactive.isEmpty {
                Section {
                    ForEach(inactive) { row($0) }
                } header: {
                    Text("Не доходят до ролей")
                } footer: {
                    Text("Эти правила роли сейчас не получают — кандидаты на удаление или включение")
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $query, prompt: "Текст или номер правила")
        .tfNativeHeader("Реестр правил")
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .tfSheet(item: $detailID) { item in
            RoleRuleDetailSheet(ruleID: item.id, viewModel: viewModel)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private func row(_ rule: RoleRule) -> some View {
        HStack(alignment: .top, spacing: TFSpacing.sm) {
            VStack(alignment: .leading, spacing: TFSpacing.xs) {
                HStack(spacing: TFSpacing.xs) {
                    Text(rule.id)
                        .tfText(.caption)
                        .foregroundStyle(Color.tfSub)
                    if rule.recommended {
                        Image(systemName: "star.fill")
                            .imageScale(.small)
                            .foregroundStyle(Color.tfYellow)
                            .accessibilityLabel("Рекомендовано всем")
                    }
                }
                Text(rule.text)
                    .tfText(.row)
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
            Button {
                detailID = RuleID(id: rule.id)
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Подробнее о правиле \(rule.id)")
            TFToggle(isOn: Binding(
                get: { rule.active },
                set: { value in Task { await viewModel.update(rule.id, RoleRulePatch(active: value)) } }
            ))
            .accessibilityLabel("Действует")
        }
    }
}

/// Лист «?»: что ожидается от ролей, полный текст, где действует, кому
/// адресовано и «рекомендовано всем».
struct RoleRuleDetailSheet: View {
    let ruleID: String
    @Bindable var viewModel: RoleRulesViewModel

    var body: some View {
        NavigationStack {
            if let rule = viewModel.rule(ruleID) {
                content(rule)
            } else {
                TFEmptyState(icon: "questionmark.circle", text: "Правило не найдено")
            }
        }
    }

    private func content(_ rule: RoleRule) -> some View {
        List {
            if viewModel.errorMessage != nil {
                Section { TFErrorBanner(viewModel.errorMessage, variant: .block) }
            }
            Section("Какое поведение ожидается") {
                Text(explanation(rule))
                    .foregroundStyle(rule.explanation == nil ? Color.tfSub : Color.tfText)
            }
            Section("Текст правила") {
                Text(rule.text).textSelection(.enabled)
            }
            Section("Где действует") {
                if let place = rule.where, !place.isEmpty {
                    Text(place)
                }
                if !rule.channels.isEmpty {
                    LabeledContent("Каналы", value: rule.channels.joined(separator: ", "))
                }
                LabeledContent("Ушло ролям", value: "\(rule.deliveredUses)")
                if let category = rule.category, !category.isEmpty {
                    LabeledContent("Категория", value: category)
                }
            }
            Section {
                LabeledContent("Рекомендовано всем") {
                    TFToggle(isOn: Binding(
                        get: { rule.recommended },
                        set: { value in Task { await viewModel.update(rule.id, RoleRulePatch(recommended: value)) } }
                    ))
                    .accessibilityLabel("Рекомендовано всем")
                }
            }
            Section("Кому") {
                LabeledContent("Все роли") {
                    TFToggle(isOn: Binding(
                        get: { rule.roles.isAll },
                        set: { value in
                            let targets: RoleRuleTargets = value ? .all : .roles(viewModel.roles.map(\.id))
                            Task { await viewModel.update(rule.id, RoleRulePatch(roles: targets)) }
                        }
                    ))
                    .accessibilityLabel("Все роли")
                }
                if !rule.roles.isAll {
                    ForEach(viewModel.roles) { role in
                        let checked = rule.roles.includes(role.id)
                        Button {
                            toggle(role.id, in: rule)
                        } label: {
                            LabeledContent(role.name) {
                                // Значок отметки — как в выборе ролей у интеграций.
                                Image(systemName: checked ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(checked ? Color.tfText : Color.tfDim)
                            }
                        }
                        .tint(Color.tfText)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .tfNativeHeader(rule.id)
    }

    private func explanation(_ rule: RoleRule) -> String {
        if let text = rule.explanation, !text.isEmpty { return text }
        return rule.active ? "Пояснение ещё готовится" : "Правило не доходит до ролей — пояснения нет"
    }

    private func toggle(_ roleID: String, in rule: RoleRule) {
        guard case .roles(var ids) = rule.roles else { return }
        if let index = ids.firstIndex(of: roleID) { ids.remove(at: index) } else { ids.append(roleID) }
        Task { await viewModel.update(rule.id, RoleRulePatch(roles: .roles(ids))) }
    }
}
