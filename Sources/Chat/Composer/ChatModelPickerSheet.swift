import SwiftUI

/// Выбор модели для сессии.
///
/// Владелец 03.11.2026: insetGrouped, `.tfText` + гарнитура/кегль из настроек
/// приложения (как проекты); звезда справа; столбики стоимости.
/// Чат вокруг гасит шкалу — эту шторку снова включаем.
struct ChatModelPickerSheet: View {
    @Bindable var choice: ChatModelChoice
    @Environment(\.dismiss) private var dismiss
    @State private var favorites = ChatModelFavorites()
    @State private var showsEffort = false
    @State private var presentationDetent: PresentationDetent = .medium

    private var models: [RoleModelOption] {
        ChatModelCatalog.ordered(choice.options, favorites: favorites.ids)
    }

    private var favoritesModels: [RoleModelOption] {
        models.filter { favorites.isFavorite($0.id) }
    }

    private var otherModels: [RoleModelOption] {
        models.filter { !favorites.isFavorite($0.id) }
    }

    private var groups: [RoleModelOption.ProviderGroup] {
        RoleModelOption.grouped(otherModels)
    }

    private func groupTitle(_ provider: String) -> String {
        provider == "Ollama" ? "Ollama — локальные" : provider
    }

    var body: some View {
        NavigationStack {
            List {
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
                        .frame(minHeight: 40)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .modelPickerRow(selected: false)
                    .accessibilityIdentifier("chat.model.effort")
                }
                if !favoritesModels.isEmpty {
                    Section {
                        rows(favoritesModels)
                    } header: {
                        Text("Избранные")
                            .tfText(.title)
                            .foregroundStyle(Color.tfSub)
                    }
                }
                ForEach(groups) { group in
                    Section {
                        rows(group.models)
                    } header: {
                        Text(groupTitle(group.provider))
                            .tfText(.title)
                            .foregroundStyle(Color.tfSub)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .listSectionSpacing(TFSpacing.sm)
            .environment(\.defaultMinListRowHeight, 40)
            .tfScreenBackground()
            .navigationTitle("Выбор модели")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
            .tfSheet(isPresented: $showsEffort) {
                effortSheet
            }
        }
        .environment(\.tfTypeSettingsEnabled, true)
        .presentationDetents([.medium, .large], selection: $presentationDetent)
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func rows(_ options: [RoleModelOption]) -> some View {
        ForEach(options) { option in
            Button {
                Task { await choice.selectModel(option.id) }
            } label: {
                modelRow(option)
            }
            .buttonStyle(.plain)
            .modelPickerRow(selected: choice.selected == option.id)
            .accessibilityIdentifier("chat.model.\(option.id)")
        }
    }

    private func modelRow(_ option: RoleModelOption) -> some View {
        let profile = ChatModelCatalog.profile(for: option.id)
        let selected = choice.selected == option.id
        let favorite = favorites.isFavorite(option.id)
        return HStack(spacing: TFSpacing.sm) {
            Image(systemName: "checkmark")
                .tfTypeFont(size: TFIconSize.xs, weight: .semibold)
                .foregroundStyle(Color.tfText)
                .frame(width: 18, height: 40)
                .opacity(selected ? 1 : 0)
                .accessibilityHidden(!selected)

            Text(option.title)
                .tfText(.body)
                .foregroundStyle(Color.tfText)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if ChatModelCatalog.isFree(option.id) {
                TFPill("Бесплатно", color: .tfText)
                    .fixedSize()
            }

            ModelCostBars(level: profile.costLevel)
                .accessibilityLabel(profile.costAccessibilityLabel)

            Button {
                favorites.toggle(option.id)
            } label: {
                Image(systemName: favorite ? "star.fill" : "star")
                    .tfTypeFont(size: TFIconSize.sm, weight: .regular)
                    .foregroundStyle(favorite ? Color.tfYellow : Color.tfSub)
                    .frame(width: 28, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(favorite ? "Убрать из избранного" : "В избранное")
            .accessibilityIdentifier("chat.model.favorite.\(option.id)")
        }
        .frame(minHeight: 40)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(option.title)
        .accessibilityValue([
            selected ? "Выбрана" : nil,
            favorite ? "Избранная" : nil,
            ChatModelCatalog.isFree(option.id) ? "Бесплатно" : profile.costAccessibilityLabel
        ].compactMap { $0 }.joined(separator: ", "))
    }

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
                .modelPickerRow(selected: choice.thinkingLevel == nil)
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
                    .modelPickerRow(selected: choice.thinkingLevel == level)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .tfScreenBackground()
            .tfNativeHeader("Усилия")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { showsEffort = false }
                }
            }
            .environment(\.tfTypeSettingsEnabled, true)
        }
    }

    private func effortRow(title: String, selected: Bool) -> some View {
        HStack {
            Text(title)
                .tfText(.body)
                .foregroundStyle(Color.tfText)
            Spacer(minLength: 0)
            Image(systemName: "checkmark")
                .tfTypeFont(size: TFIconSize.xs, weight: .semibold)
                .foregroundStyle(Color.tfText)
                .opacity(selected ? 1 : 0)
                .accessibilityHidden(!selected)
        }
        .frame(minHeight: 40)
        .contentShape(Rectangle())
    }
}

private extension View {
    /// Строка окна выбора модели: общий контур секции, серые разделители,
    /// выбор — галочкой. Не плитки режима работы (владелец 03.11.2026).
    /// `selected` только для VoiceOver; окантовку строки не рисуем.
    func modelPickerRow(selected: Bool) -> some View {
        self
            .tfSettingsListRow(selected: false)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

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
