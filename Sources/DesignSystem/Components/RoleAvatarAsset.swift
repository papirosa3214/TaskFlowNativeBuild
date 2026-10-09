import Foundation

/// One persisted appearance shared by every agent avatar; people keep their photos.
enum TeamAvatarAppearance: String, CaseIterable, Identifiable {
    case current, previous, noir
    static let storageKey = "teamAvatarAppearance"
    var id: String { rawValue }
    var title: String {
        switch self { case .current: "Текущий"; case .previous: "Предыдущий"; case .noir: "Ретро-нуар" }
    }
}

enum RoleAvatarAsset {
    static func imageName(for role: String?, appearance: TeamAvatarAppearance? = nil) -> String? {
        let suffix: String
        switch role {
        case "architect": suffix = "Architect"
        case "builder": suffix = "Builder"
        case "qa": suffix = "QA"
        case "researcher": suffix = "Researcher"
        case "analyst": suffix = "Analyst"
        case "critic_verifier": suffix = "CriticVerifier"
        case "designer": suffix = "Designer"
        case "secretary": suffix = "Secretary"
        case "code_orchestrator", "orchestrator": suffix = "Orchestrator"
        default: return nil
        }
        let selected = appearance ?? TeamAvatarAppearance(rawValue: UserDefaults.standard.string(forKey: TeamAvatarAppearance.storageKey) ?? "current") ?? .current
        switch selected {
        case .current: return "RoleAvatar" + suffix
        case .previous: return "TeamPrevious" + suffix
        case .noir: return "TeamNoir" + suffix
        }
    }

    static func imageName(forUserID userID: String?, appearance: TeamAvatarAppearance? = nil) -> String? {
        guard let userID else { return nil }
        if userID == "u-secretary" { return imageName(for: "secretary", appearance: appearance) }
        guard userID.hasPrefix("role_") else { return nil }
        return imageName(for: String(userID.dropFirst("role_".count)), appearance: appearance)
    }
}
