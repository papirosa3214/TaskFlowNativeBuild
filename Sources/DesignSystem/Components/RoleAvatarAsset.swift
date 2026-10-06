/// Bundled portraits shared by the team, chats and task surfaces.
/// Only known agent accounts get an illustration; humans keep their own photo/initials.
enum RoleAvatarAsset {
    static func imageName(for role: String?) -> String? {
        switch role {
        case "architect": "RoleAvatarArchitect"
        case "builder": "RoleAvatarBuilder"
        case "qa": "RoleAvatarQA"
        case "researcher": "RoleAvatarResearcher"
        case "analyst": "RoleAvatarAnalyst"
        case "critic_verifier": "RoleAvatarCriticVerifier"
        case "designer": "RoleAvatarDesigner"
        case "secretary": "RoleAvatarSecretary"
        case "orchestrator": "RoleAvatarOrchestrator"
        default: nil
        }
    }

    static func imageName(forUserID userID: String?) -> String? {
        guard let userID else { return nil }
        if userID == "u-secretary" { return imageName(for: "secretary") }
        // Учётка «Оркестратор Claude» — не role_*, у неё свой постоянный id.
        if userID == "6848a89b-04fe-4015-bb1c-61b03782c378" { return imageName(for: "orchestrator") }
        guard userID.hasPrefix("role_") else { return nil }
        return imageName(for: String(userID.dropFirst("role_".count)))
    }
}
