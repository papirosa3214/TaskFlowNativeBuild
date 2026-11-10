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

    /// Внешний агент без своего фото: серверная картинка — чужая авто-иконка
    /// (краб Claude). Пока владелец не выбрал фото, остаются инициалы.
    private var hidesServerIcon: Bool {
        guard let role, localPhoto == nil else { return false }
        return RoleAvatarAsset.isExternalChatRole(roleKey: role, userID: "role_" + role)
    }

    /// Картинка роли с сервера — тот же справочник, что у остальных экранов.
    private var serverURL: URL? {
        guard let role, let path = AvatarDirectory.shared.urls["role_" + role] else { return nil }
        return TFAvatar.fullURL(path)
    }

    /// Своё фото, выбранное в редакторе портрета и лежащее в файлах телефона
    /// (`AvatarCrop`). Раньше его видел только сам редактор: отсюда рисовался
    /// вшитый портрет, и владелец видел «в настройках сохранилось, а нигде не
    /// отображается» (09.11.2026). Локальное фото главнее и серверного, и
    /// вшитого — его выбирали последним.
    private var localPhoto: URL? {
        guard let role, let name = AvatarCrop.value(for: role).photo else { return nil }
        let url = AvatarCrop.photoURL(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Своё фото, поставленное владельцем из приложения. Отличаем его от
    /// авто-иконки внешнего агента по имени файла: авто-иконки сервер
    /// называет `agent-<рантайм>-<хэш>.svg`, а загруженное фото — уникальным
    /// id. Своё фото главнее вшитого портрета — иначе настройка была бы
    /// пустышкой (владелец 09.11.2026).
    private var ownerPhotoURL: URL? {
        guard let role, let path = AvatarDirectory.shared.urls["role_" + role],
              !path.hasSuffix(".svg") else { return nil }
        return TFAvatar.fullURL(path)
    }

    var body: some View {
        Group {
            if localPhoto != nil, let role {
                // Кадрирование, форму и масштаб применяет сам портрет — поэтому
                // рисуем через него, а не голой картинкой.
                TFRolePortrait(
                    role: role,
                    imageAsset: RoleAvatarAsset.imageName(for: role, appearance: TeamAvatarAppearance(rawValue: avatarAppearance) ?? .current) ?? "",
                    loopName: nil,
                    side: size
                )
            } else if let ownerPhotoURL, !hidesServerIcon {
                // Своё фото владельца — главнее всего остального.
                AnimatedImage(url: ownerPhotoURL, placeholder: { Circle().fill(tint) })
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if let asset = RoleAvatarAsset.imageName(for: role, appearance: TeamAvatarAppearance(rawValue: avatarAppearance) ?? .current) {
                let appearance = TeamAvatarAppearance(rawValue: avatarAppearance) ?? .current
                let loop = avatarsAnimated ? RoleAvatarAsset.loopName(for: role, appearance: appearance) : nil
                TFRolePortrait(role: role, imageAsset: asset, loopName: loop, side: size)
            } else if let serverURL, !hidesServerIcon {
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
