import SwiftUI

/// Настройка внешнего вида команды: комплект портретов и переключатель анимации.
///
/// Галочка «Анимировать» одна на всё приложение: включил — портреты ролей
/// играют роликом, снял — вернулись статичные. По умолчанию выключено (восемь
/// одновременно играющих роликов заметно садят батарею).
struct TeamAppearanceSheet: View {
    @AppStorage(TeamAvatarAppearance.storageKey) private var selected = "current"
    @AppStorage(TeamAvatarAnimation.storageKey) private var animated = false
    @Environment(\.dismiss) private var dismiss
    private let roles = ["researcher", "analyst", "builder", "architect", "code_orchestrator", "secretary", "critic_verifier", "qa", "designer"]

    var body: some View {
        NavigationStack {
            List {
                ForEach(TeamAvatarAppearance.allCases) { appearance in
                    Button {
                        selected = appearance.rawValue
                    } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(appearance.title)
                                Spacer()
                                if selected == appearance.rawValue { Image(systemName: "checkmark") }
                            }
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 10) {
                                ForEach(roles, id: \.self) { role in
                                    if let asset = RoleAvatarAsset.imageName(for: role, appearance: appearance) {
                                        // Превью остаётся статичным НАМЕРЕННО: девять
                                        // одновременно играющих роликов в листе роняют
                                        // интерфейс (UI-тест на этом падал по таймауту
                                        // снимка) и едят батарею. Живой портрет виден
                                        // там, где он и нужен, — в самом приложении.
                                        TFRolePortrait(imageAsset: asset, loopName: nil, side: 48)
                                    }
                                }
                            }
                            if appearance == .noir, animated {
                                Text("Ролики зациклены и идут без звука. У роли «Дизайнер» ролика нет — она остаётся статичной.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .accessibilityIdentifier("team-appearance-" + appearance.rawValue)
                    .accessibilityValue(selected == appearance.rawValue ? "Выбран" : "Не выбран")
                }

                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Анимировать")
                            Text("Анимация есть только у комплекта «Гравюра».")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        TFToggle(isOn: $animated)
                            .accessibilityIdentifier("team-avatar-animation-switch")
                    }
                    .accessibilityIdentifier("team-avatar-animation-toggle")
                } footer: {
                    Text("Выключено — везде статичные картинки. Включено — портреты ролей комплекта «Гравюра» играют зацикленный ролик.")
                }
            }
            .navigationTitle("Внешний вид")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
    }
}