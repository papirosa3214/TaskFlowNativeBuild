import SwiftUI

/// Выбор модели для сессии.
///
/// Владелец 03.11.2026: без лишнего текста, шрифт как в меню сессии, минимум
/// отступов, без полосок-разделителей; звезда избранного; ориентир стоимости —
/// столбики, как у приоритета, вместо поясняющей подписи под названием.
struct ChatModelPickerSheet: View {
    @Bindable var choice: ChatModelChoice
    @Environment(\.dismiss) private var dismiss
    @State private var favorites = ChatModelFavorites()
    @State private var showsEffort = false

    private var models: [RoleModelOption] {
        ChatModelCatalog.ordered(choice.options, favorites: favorites.ids)
    }

    private var favoritesModels: [RoleModelOption] {
        models.filter { favorites.isFavorite($0.id) }
    }

    private var otherModels: [RoleModelOption] {
        models.filter { !favorites.isFavorite($0.id) }
    }

    /// Разделы по провайдерам (владелец 31.10.2026).
    private var groups: [RoleModelOption.ProviderGroup] {
        RoleModelOption.grouped(otherModels)
    }

    private func groupTitle(_ provider: String) -> String {
        provider == "Ollama" ? "Ollama — локальные" : provider
    }

    var body: some View {
        NavigationStack {
            List {
                if !favoritesModels.isEmpty {
                    Section("Избранные") { rows(favoritesModels) }
                }
                ForEach(groups) { group in
                    Section {
                        rows(group.models)
                    } header: {
                        Text(groupTitle(group.provider))
                    }
                }
                Section {
                    Button { showsEffort = true } label: {
                        HStack {
                            Text("Усилия")
                                .tfText(.body)
                                .foregroundStyle(Color.tfText)
                            Spacer(minLength: TFSpacing.sm)
                            Text(effortTitle)
                                .tfText(.body)
                                .foregroundStyle(Color.tfSub)
                        }
                        .frame(minHeight: 36)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                    .listRowInsets(Self.rowInsets)
                    .accessibilityIdentifier("chat.model.effort")
                }
            }
            .tfScreenBackground()
            .listStyle(.plain)
            .listSectionSpacing(TFSpacing.sm)
            .navigationTitle("Выбор модели")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
            .sheet(isPresented: $showsEffort) {
                effortSheet
            }
        }
    }

    private static let rowInsets = EdgeInsets(
        top: TFSpacing.xs, leading: TFSpacing.md,
        bottom: TFSpacing.xs, trailing: TFSpacing.md
    )

    @ViewBuilder
    private func rows(_ options: [RoleModelOption]) -> some View {
        ForEach(options) { option in
            Button {
                Task { await choice.selectModel(option.id) }
            } label: {
                modelRow(option)
            }
            .buttonStyle(.plain)
            .listRowSeparator(.hidden)
            .listRowInsets(Self.rowInsets)
            .accessibilityIdentifier("chat.model.\(option.id)")
        }
    }

    private func modelRow(_ option: RoleModelOption) -> some View {
        let profile = ChatModelCatalog.profile(for: option.id)
        let selected = choice.selected == option.id
        let favorite = favorites.isFavorite(option.id)
        return HStack(spacing: TFSpacing.sm) {
            Button {
                favorites.toggle(option.id)
            } label: {
                Image(systemName: favorite ? "star.fill" : "star")
                    .tfTypeFont(size: 15, weight: .medium)
                    .foregroundStyle(favorite ? Color.tfYellow : Color.tfSub)
                    .frame(width: 28, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(favorite ? "Убрать из избранного" : "В избранное")
            .accessibilityIdentifier("chat.model.favorite.\(option.id)")

            Text(option.title)
                .tfText(.body)
                .foregroundStyle(Color.tfText)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            ModelCostBars(level: profile.costLevel)
                .accessibilityLabel(profile.costAccessibilityLabel)

            Image(systemName: "checkmark")
                .tfTypeFont(size: 14, weight: .semibold)
                .foregroundStyle(Color.tfText)
                .frame(width: 16, height: 36)
                .opacity(selected ? 1 : 0)
                .accessibilityHidden(!selected)
        }
        .frame(minHeight: 36)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(option.title)
        .accessibilityValue([
            selected ? "Выбрана" : nil,
            favorite ? "Избранная" : nil,
            profile.costAccessibilityLabel
        ].compactMap { $0 }.joined(separator: ", "))
    }

    // MARK: - Усилия

    private var effortTitle: String {
        guard let level = choice.thinkingLevel else { return "По настройке роли" }
        return choice.effectiveOption?.thinkingLevelLabels?[level] ?? ChatSessionPreferences.thinkingTitle(level)
    }

    private var effortSheet: some View {
        NavigationStack {
            List {
                Button {
                    Task { await choice.selectThinking(nil) }
                    showsEffort = false
                } label: {
                    effortRow(title: "По настройке роли", selected: choice.thinkingLevel == nil)
                }
                .buttonStyle(.plain)
                .listRowSeparator(.hidden)
                .listRowInsets(Self.rowInsets)
                ForEach(choice.availableThinkingLevels, id: \.self) { level in
                    Button {
                        Task { await choice.selectThinking(level) }
                        showsEffort = false
                    } label: {
                        effortRow(
                            title: choice.effectiveOption?.thinkingLevelLabels?[level]
                                ?? ChatSessionPreferences.thinkingTitle(level),
                            selected: choice.thinkingLevel == level)
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                    .listRowInsets(Self.rowInsets)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Усилия")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { showsEffort = false }
                }
            }
        }
    }

    private func effortRow(title: String, selected: Bool) -> some View {
        HStack {
            Text(title)
                .tfText(.body)
                .foregroundStyle(Color.tfText)
            Spacer(minLength: 0)
            Image(systemName: "checkmark")
                .tfTypeFont(size: 14, weight: .semibold)
                .foregroundStyle(Color.tfText)
                .opacity(selected ? 1 : 0)
                .accessibilityHidden(!selected)
        }
        .frame(minHeight: 36)
        .contentShape(Rectangle())
    }
}

/// Столбики стоимости модели: слева низкий, справа высокий (как ориентир
/// приоритета). Заполненные — текущий уровень, пустые — серые.
private struct ModelCostBars: View {
    let level: Int
    private let maxLevel = 4

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(1...maxLevel, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(index <= level ? Color.tfText : Color.tfSub.opacity(0.35))
                    .frame(width: 3, height: CGFloat(6 + index * 3))
            }
        }
        .frame(height: 18)
        .accessibilityHidden(true)
    }
}
