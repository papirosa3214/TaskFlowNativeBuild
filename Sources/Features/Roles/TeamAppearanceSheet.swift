import SwiftUI

/// Настройка внешнего вида команды: комплект портретов и переключатель анимации.
///
/// Галочка «Анимировать» одна на всё приложение: включил — портреты ролей
/// играют роликом, снял — вернулись статичные. По умолчанию выключено (восемь
/// одновременно играющих роликов заметно садят батарею).
struct TeamAppearanceSheet: View {
    @AppStorage(TeamAvatarAppearance.storageKey) private var selected = "current"
    @AppStorage(TeamAvatarAnimation.storageKey) private var animated = false
    @AppStorage(TeamAvatarSecretaryVariant.storageKey) private var secretaryVariant = TeamAvatarSecretaryVariant.classic.rawValue
    @Environment(\.dismiss) private var dismiss
    @State private var showRoles = false
    @State private var editingRole: String?
    private let roles = ["researcher", "analyst", "builder", "architect", "code_orchestrator", "secretary", "critic_verifier", "qa", "designer", "infra_engineer"]

    private var showsSecretaryVariants: Bool { selected == TeamAvatarAppearance.noir.rawValue }

    /// Роли, у которых в этом комплекте есть портрет. У «Инженера .110» он
    /// нарисован только для «Иллюстрации», поэтому в «Плакате» и «Гравюре» его
    /// в сетке нет — там роль остаётся инициалами, как у владельца.
    private func rolesWithPortrait(in appearance: TeamAvatarAppearance) -> [String] {
        roles.filter { RoleAvatarAsset.imageName(for: $0, appearance: appearance) != nil }
    }

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
                                ForEach(rolesWithPortrait(in: appearance), id: \.self) { role in
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
                                    .tfText(.meta)
                                    .foregroundStyle(Color.tfSub)
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
                                .tfText(.meta)
                                .foregroundStyle(Color.tfSub)
                        }
                        Spacer()
                        TFToggle(isOn: $animated)
                            .accessibilityIdentifier("team-avatar-animation-switch")
                    }
                    .accessibilityIdentifier("team-avatar-animation-toggle")
                } footer: {
                    Text("Выключено — везде статичные картинки. Включено — портреты ролей комплекта «Гравюра» играют зацикленный ролик.")
                }

                // Портретов у Помощника владельца в «Гравюре» два — прежний и новый.
                // Выбор один на всё приложение, видим только у этого комплекта:
                // в «Иллюстрации» и «Плакате» у роли по-прежнему один портрет.
                //
                // Секция объявлена БЕЗ внешнего `if`: `List` запоминает набор
                // секций при первом построении, и условная не появлялась потом
                // даже при выбранной «Гравюре» (кнопка комплекта показывала
                // «Выбран», блока на экране не было; `.id` на самой секции не
                // помог). Поэтому условие живёт внутри наполнения и заголовка:
                // пустые секция и заголовок не рисуются.
                Section {
                    if showsSecretaryVariants {
                        HStack(spacing: TFSpacing.lg) {
                            ForEach(TeamAvatarSecretaryVariant.allCases) { variant in
                                Button {
                                    secretaryVariant = variant.rawValue
                                } label: {
                                    ZStack(alignment: .topTrailing) {
                                        TFRolePortrait(role: "secretary",
                                                       imageAsset: RoleAvatarAsset.imageName(
                                                            for: "secretary", appearance: .noir,
                                                            secretaryVariant: variant) ?? "",
                                                       loopName: nil, side: 56)
                                        if secretaryVariant == variant.rawValue {
                                            Image(systemName: "checkmark.circle.fill")
                                                .symbolRenderingMode(.palette)
                                                .foregroundStyle(Color.tfRed, Color.tfPaper)
                                                .offset(x: 5, y: -5)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("team-secretary-variant-" + variant.rawValue)
                                .accessibilityValue(secretaryVariant == variant.rawValue ? "Выбран" : "Не выбран")
                            }
                            Spacer(minLength: 0)
                        }
                    }
                } header: {
                    if showsSecretaryVariants {
                        Text("Помощник владельца")
                    }
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
                                    .tfText(.meta)
                                    .foregroundStyle(Color.tfSub)
                            }
                            Spacer()
                        }
                    }
                    .accessibilityIdentifier("team-avatar-crop-open")
                    .tint(.tfRed)
                }
            }
            // Смена комплекта перестраивает список целиком: `List` держит
            // набор секций от первого построения, и секция выбора портрета
            // Помощника владельца оставалась пустой при выбранной «Гравюре» (кнопка
            // комплекта показывала «Выбран», блока на экране не было).
            .id("appearance-list-" + selected)
            .navigationTitle("Внешний вид")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
            .navigationDestination(isPresented: $showRoles) {
                List {
                    ForEach(rolesWithPortrait(in: TeamAvatarAppearance(rawValue: selected) ?? .current), id: \.self) { role in
                        Button {
                            editingRole = role
                        } label: {
                            HStack(spacing: TFSpacing.md) {
                                if let asset = RoleAvatarAsset.imageName(for: role, appearance: TeamAvatarAppearance(rawValue: selected) ?? .current) {
                                    TFRolePortrait(role: role, imageAsset: asset, loopName: nil, side: 44)
                                }
                                Text(AvatarCrop.roleTitle(role))
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(Color.tfSub)
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
