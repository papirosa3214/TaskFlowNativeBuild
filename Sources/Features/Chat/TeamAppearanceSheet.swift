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
    @State private var showRoles = false
    @State private var editingRole: String?
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
                                        TFRolePortrait(role: role, imageAsset: asset, loopName: nil, side: 48)
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

                Section {
                    Button {
                        showRoles = true
                    } label: {
                        HStack(spacing: TFSpacing.md) {
                            Image(systemName: "crop")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Настроить портреты")
                                Text("Двигать и увеличивать картинку в кружке, выбрать своё фото, круг или квадрат.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                    .accessibilityIdentifier("team-avatar-crop-open")
                    .tint(.tfRed)
                }
            }
            .navigationTitle("Внешний вид")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
            .navigationDestination(isPresented: $showRoles) {
                List {
                    ForEach(roles, id: \.self) { role in
                        Button {
                            editingRole = role
                        } label: {
                            HStack(spacing: TFSpacing.md) {
                                if let asset = RoleAvatarAsset.imageName(for: role, appearance: TeamAvatarAppearance(rawValue: selected) ?? .current) {
                                    TFRolePortrait(role: role, imageAsset: asset, loopName: nil, side: 44)
                                }
                                Text(AvatarCrop.roleTitle(role))
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("team-avatar-crop-role-" + role)
                    }
                }
                .navigationTitle("Портреты ролей")
                .navigationBarTitleDisplayMode(.inline)
                .tint(.tfRed)
            }
            .sheet(item: Binding(
                get: { editingRole.map { RoleBox(id: $0) } },
                set: { editingRole = $0?.id }
            )) { box in
                let role = box.id
                AvatarCropEditor(role: role,
                                 roleTitle: AvatarCrop.roleTitle(role),
                                 imageAsset: RoleAvatarAsset.imageName(for: role, appearance: TeamAvatarAppearance(rawValue: selected) ?? .current) ?? "")
            }
        }
    }
}
/// Обёртка для `.sheet(item:)`: `String` не `Identifiable`, а роль — это строка.
private struct RoleBox: Identifiable {
    let id: String
}
