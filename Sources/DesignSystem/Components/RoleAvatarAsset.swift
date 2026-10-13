import Foundation

/// One persisted appearance shared by every agent avatar; people keep their photos.
enum TeamAvatarAppearance: String, CaseIterable, Identifiable {
    case current, previous, noir
    static let storageKey = "teamAvatarAppearance"
    var id: String { rawValue }
    /// Названия переименованы по стилю 10.10.2026: прежние «Текущий»,
    /// «Предыдущий», «Ретро-нуар» ничего не говорили о том, что видно.
    /// `rawValue` остались прежними — сохранённый у владельца выбор не слетает.
    var title: String {
        switch self { case .current: "Иллюстрация"; case .previous: "Плакат"; case .noir: "Гравюра" }
    }
}

/// Переключатель анимации аватарок. Общий для всех экранов: включил в
/// «Внешнем виде» — поехали все портреты ролей приложения, снял — вернулись
/// статичные. Выключен по умолчанию, потому что восемь одновременно играющих
/// роликов заметно садят батарею.
enum TeamAvatarAnimation {
    static let storageKey = "teamAvatarAnimated"
}

/// У роли «Секретарь» в комплекте «Гравюра» два портрета: прежний и новый
/// мужской. Выбор владельца, один на всё приложение; по умолчанию прежний,
/// чтобы установленная сборка не меняла картинку сама.
enum TeamAvatarSecretaryVariant: String, CaseIterable, Identifiable {
    case classic, male
    static let storageKey = "teamAvatarSecretaryVariant"
    var id: String { rawValue }
}

enum RoleAvatarAsset {
    /// Хвост имени ассета роли. `nil` — роль без вшитого портрета.
    private static func suffix(for role: String?) -> String? {
        switch role {
        case "architect": return "Architect"
        case "builder": return "Builder"
        case "qa": return "QA"
        case "researcher": return "Researcher"
        case "analyst": return "Analyst"
        case "critic_verifier": return "CriticVerifier"
        case "designer": return "Designer"
        case "secretary": return "Secretary"
        case "code_orchestrator", "orchestrator": return "Orchestrator"
        default: return nil
        }
    }

    private static func resolve(_ appearance: TeamAvatarAppearance?) -> TeamAvatarAppearance {
        appearance
            ?? TeamAvatarAppearance(rawValue: UserDefaults.standard.string(forKey: TeamAvatarAppearance.storageKey) ?? "current")
            ?? .current
    }

    /// Сохранённый выбор портрета Секретаря; `nil` — читаем из `UserDefaults`.
    private static func resolve(_ variant: TeamAvatarSecretaryVariant?) -> TeamAvatarSecretaryVariant {
        variant
            ?? TeamAvatarSecretaryVariant(rawValue: UserDefaults.standard.string(forKey: TeamAvatarSecretaryVariant.storageKey) ?? "classic")
            ?? .classic
    }

    /// У Секретаря комплекта «Гравюра» два ассета, у остальных ролей — один.
    /// Мужской вариант меняет и статичную картинку, и ролик: иначе при
    /// включённой анимации кружок играл бы не тот портрет, что показан в
    /// «Внешнем виде».
    private static func noirSuffix(_ role: String?, _ suffix: String,
                                   variant: TeamAvatarSecretaryVariant) -> String {
        guard role == "secretary", variant == .male else { return suffix }
        return suffix + "Male"
    }

    static func imageName(for role: String?, appearance: TeamAvatarAppearance? = nil,
                          secretaryVariant: TeamAvatarSecretaryVariant? = nil) -> String? {
        guard let suffix = suffix(for: role) else { return nil }
        switch resolve(appearance) {
        case .current: return "RoleAvatar" + suffix
        case .previous: return "TeamPrevious" + suffix
        case .noir:
            return "TeamNoir" + noirSuffix(role, suffix, variant: resolve(secretaryVariant))
        }
    }

    /// Роли, для которых ролик реально лежит в бандле. Перечислены ЯВНО, а не по
    /// правилу «имя ассета + Loop»: у девятой роли «Дизайнер» портрет есть, а
    /// ролика нет, и общее правило подставляло несуществующее имя — вьюха
    /// рисовала пустой видеослой, то есть чёрный кружок вместо статики.
    private static let loopRoles: Set<String> = [
        "researcher", "analyst", "builder", "architect",
        "code_orchestrator", "orchestrator", "secretary", "critic_verifier", "qa",
        // 10.10.2026: ролик «Дизайнера» появился (RoleLoopDesigner), роль
        // добавлена в список. До этого вьюха рисовала пустой видеослой.
        "designer",
    ]

    /// Имя ролика в бандле (без `.mp4`) для роли, `nil` — анимации нет.
    ///
    /// У комплекта «Иллюстрация» свои ролики `RoleLoop*` — сняты 10.10.2026 с
    /// перерисованных портретов этого же комплекта, поэтому переключатель
    /// оживляет именно его. У «Гравюры» — прежние `RoleNoirLoop*`, их не
    /// трогаем. У «Плаката» роликов нет: там переключатель ничего не меняет.
    static func loopName(for role: String?, appearance: TeamAvatarAppearance? = nil,
                         secretaryVariant: TeamAvatarSecretaryVariant? = nil) -> String? {
        guard let role, loopRoles.contains(role), let suffix = suffix(for: role) else { return nil }
        switch resolve(appearance) {
        case .current: return "RoleLoop" + suffix
        case .noir:
            let name = noirSuffix(role, suffix, variant: resolve(secretaryVariant))
            return "RoleNoirLoop" + name
        case .previous: return nil
        }
    }

    static func imageName(forUserID userID: String?, appearance: TeamAvatarAppearance? = nil,
                          secretaryVariant: TeamAvatarSecretaryVariant? = nil) -> String? {
        guard let role = role(forUserID: userID) else { return nil }
        return imageName(for: role, appearance: appearance, secretaryVariant: secretaryVariant)
    }

    static func loopName(forUserID userID: String?, appearance: TeamAvatarAppearance? = nil,
                         secretaryVariant: TeamAvatarSecretaryVariant? = nil) -> String? {
        guard let role = role(forUserID: userID) else { return nil }
        return loopName(for: role, appearance: appearance, secretaryVariant: secretaryVariant)
    }

    /// Роль по id учётки; `nil` — не наша роль (владелец, обычный человек).
    static func role(forUserID userID: String?) -> String? {
        guard let userID else { return nil }
        if userID == "u-secretary" { return "secretary" }
        guard userID.hasPrefix("role_") else { return nil }
        return String(userID.dropFirst("role_".count))
    }
}