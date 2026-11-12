import SwiftUI

/// Настройка внешнего вида команды: комплект портретов и переключатель анимации.
///
/// Галочка «Анимировать» одна на всё приложение: включил — портреты ролей
/// играют роликом, снял — вернулись статичные. По умолчанию выключено (восемь
/// одновременно играющих роликов заметно садят батарею).
/// Общие настройки портретов команды: комплект, анимация, вариант Помощника.
/// Свой портрет роли (фото, кадр, круг или квадрат) — в её профиле
/// (владелец 12.11.2026).
struct TeamAppearanceSheet: View {
    @AppStorage(TeamAvatarAppearance.storageKey) private var selected = "current"
    @AppStorage(TeamAvatarAnimation.storageKey) private var animated = false
    @AppStorage(TeamAvatarSecretaryVariant.storageKey) private var secretaryVariant = TeamAvatarSecretaryVariant.classic.rawValue
    @Environment(\.dismiss) private var dismiss
    /// Роли команды с сервера: ключ → название. Раньше список был зашит
    /// константой из десяти внутренних ролей, и внешних агентов (Claude Code,
    /// Codex, Gemini, Гермес, OpenCode) в «Внешнем виде» не было вовсе
    /// (владелец 09.11.2026: «хотел бы и внешних тоже кастомизировать»).
    @State private var profiles: [RoleProfile] = []

    private var showsSecretaryVariants: Bool { selected == TeamAvatarAppearance.noir.rawValue }

    /// Все роли команды: и внутренние, и внешние агенты. Порядок — как в
    /// «Команде» (сервер отдаёт его по position).
    private var allRoleKeys: [String] {
        profiles.isEmpty
            ? AvatarCrop.knownRoles
            : profiles.map(\.role).filter { !$0.isEmpty }
    }

    /// Роли, у которых в этом комплекте есть вшитый портрет. У «Инженера .110» он
    /// нарисован только для «Иллюстрации», поэтому в «Плакате» и «Гравюре» его
    /// в сетке нет — там роль остаётся инициалами, как у владельца.
    private func rolesWithPortrait(in appearance: TeamAvatarAppearance) -> [String] {
        allRoleKeys.filter { RoleAvatarAsset.imageName(for: $0, appearance: appearance) != nil }
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

            }
            // Смена комплекта перестраивает список целиком: `List` держит
            // набор секций от первого построения, и секция выбора портрета
            // Помощника владельца оставалась пустой при выбранной «Гравюре» (кнопка
            // комплекта показывала «Выбран», блока на экране не было).
            .id("appearance-list-" + selected)
            .navigationTitle("Внешний вид")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
            .task {
                // Список ролей — тот же, что на экране «Команда»: владелец
                // ставит своё фото любой роли, включая внешних агентов.
                profiles = (try? await APIClient().roles(all: true)) ?? []
            }
        }
    }
}
