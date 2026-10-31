import SwiftUI
import SDWebImageSwiftUI

struct RoleAvatarView: View {
    @AppStorage(TeamAvatarAppearance.storageKey) private var avatarAppearance = "current"
    @AppStorage(TeamAvatarAnimation.storageKey) private var avatarsAnimated = false
    let initials: String
    let tint: Color
    let size: CGFloat
    /// Роль из `RoleProfile.role` — если для неё есть присланный владельцем
    /// аватар в `Resources/Assets.xcassets`, рисуем его. Неизвестные роли
    /// (owner, orchestrator) идут на прежний цветной круг с инициалами —
    /// ассета под них нет, рисовать заглушку из чужих рук неуместно.
    var role: String? = nil

    /// Картинка роли с сервера — тот же справочник, что у остальных экранов.
    private var serverURL: URL? {
        guard let role, let path = AvatarDirectory.shared.urls["role_" + role] else { return nil }
        return TFAvatar.fullURL(path)
    }

    var body: some View {
        Group {
            if let asset = RoleAvatarAsset.imageName(for: role, appearance: TeamAvatarAppearance(rawValue: avatarAppearance) ?? .current) {
                let appearance = TeamAvatarAppearance(rawValue: avatarAppearance) ?? .current
                let loop = avatarsAnimated ? RoleAvatarAsset.loopName(for: role, appearance: appearance) : nil
                TFRolePortrait(role: role, imageAsset: asset, loopName: loop, side: size)
            } else if let serverURL {
                AnimatedImage(url: serverURL, placeholder: { Circle().fill(tint) })
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Circle()
                    .fill(tint)
                    .overlay {
                        Text(initials)
                            .font(.system(size: size * 0.4, weight: .semibold))  // design-system-guard: ignore — инициалы растут вместе с кружком
                            .foregroundStyle(Color.tfPaper)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}
