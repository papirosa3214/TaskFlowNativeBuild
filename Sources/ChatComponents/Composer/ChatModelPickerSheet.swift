import SwiftUI

/// Выбор модели для сессии (владелец 29.10.2026, образец из другого
/// приложения): список моделей с описанием, галочкой у выбранной, звёздочкой
/// избранного и отдельной строкой «Усилия».
///
/// Избранные модели показываются первыми — их можно пометить, чтобы потом
/// не искать в длинном списке.
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

    /// Разделы по провайдерам (владелец 31.10.2026: «должны быть подразделы
    /// по провайдерам — я даже не понимаю, к какому провайдеру какая модель»).
    /// Список был один плоский, и 160 моделей шли подряд без единого
    /// разделителя; провайдер в строке не показывался.
    private var groups: [RoleModelOption.ProviderGroup] {
        RoleModelOption.grouped(otherModels)
    }

    /// Название раздела. Локальные модели (Ollama на .110) помечаем явно:
    /// владелец просил видеть, какие модели считаются на его железе, а не
    /// в облаке.
    private func groupTitle(_ provider: String) -> String {
        provider == "Ollama" ? "Ollama — локальные" : provider
    }

    var body: some View {
        NavigationStack {
            List {
                if !favoritesModels.isEmpty {
                    Section("Избранные") { rows(favoritesModels) }
                }
                // Остальные — по провайдерам, каждый своей секцией.
                ForEach(groups) { group in
                    Section {
                        rows(group.models)
                    } header: {
                        Text(groupTitle(group.provider))
                    }
                }
                Section {
                    Button { showsEffort = true } label: {
                        LabeledContent("Усилия", value: effortTitle)
                    }
                    .tint(.primary)
                    .accessibilityIdentifier("chat.model.effort")
                }
            }
            .listStyle(.plain)
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

    @ViewBuilder
    private func rows(_ options: [RoleModelOption]) -> some View {
        ForEach(options) { option in
            Button {
                Task { await choice.selectModel(option.id) }
            } label: {
                modelRow(option)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("chat.model.\(option.id)")
        }
    }

    private func modelRow(_ option: RoleModelOption) -> some View {
        HStack(alignment: .top, spacing: TFSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(option.title)
                    .tfText(.body)
                    .foregroundStyle(Color.tfText)
                    .multilineTextAlignment(.leading)
                Text(ChatModelCatalog.profile(for: option.id).summary)
                    .tfText(.caption)
                    .foregroundStyle(Color.tfSub)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button {
                favorites.toggle(option.id)
            } label: {
                Image(systemName: favorites.isFavorite(option.id) ? "star.fill" : "star")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(favorites.isFavorite(option.id) ? Color.tfYellow : Color.tfDim)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(favorites.isFavorite(option.id) ? "Убрать из избранного" : "В избранное")
            .accessibilityIdentifier("chat.model.favorite.\(option.id)")
            if choice.selected == option.id {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.tfRed)
                    .frame(width: 20, height: 32)
                    .accessibilityLabel("Выбрана")
            }
        }
        .padding(.vertical, TFSpacing.xs)
        .contentShape(Rectangle())
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
                    LabeledContent("По настройке роли", value: choice.thinkingLevel == nil ? "Выбрано" : "")
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                ForEach(choice.availableThinkingLevels, id: \.self) { level in
                    Button {
                        Task { await choice.selectThinking(level) }
                        showsEffort = false
                    } label: {
                        LabeledContent(
                            choice.effectiveOption?.thinkingLevelLabels?[level] ?? ChatSessionPreferences.thinkingTitle(level),
                            value: choice.thinkingLevel == level ? "Выбрано" : "")
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Усилия")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { showsEffort = false }
                }
            }
        }
    }
}
