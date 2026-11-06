import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import PhotosUI
import UIKit
import QuickLook

struct RoleChatAvatar: View {
    let initials: String
    let tint: Color
    let avatarURL: String?
    let userID: String?
    /// В строке сообщения иконка стоит рядом с именем — там нужен мелкий
    /// размер (`.sm`), а не полноразмерный аватар отдельным столбцом.
    var size: TFAvatar.Size = .md

    /// Иконка автора сообщения с сервера.
    init(message: RoleChatMessage, size: TFAvatar.Size = .md) {
        self.initials = message.fromUserInitials ?? String((message.fromUserName ?? "?").prefix(1))
        self.tint = Color(hex: message.fromUserColor ?? TFHexDefault.unassigned)
        self.avatarURL = message.fromUserAvatarURL
        self.userID = message.fromUserID
        self.size = size
    }

    /// Иконка текущего пользователя — для голосового, которое ещё не ушло на
    /// сервер и потому не имеет строки сообщения.
    init(user: ApiUser?, size: TFAvatar.Size = .md) {
        let name = user?.name ?? "?"
        self.initials = user?.initials ?? String(name.prefix(1))
        self.tint = Color(hex: user?.avatarColor ?? TFHexDefault.unassigned)
        self.avatarURL = user?.avatarUrl
        self.userID = user?.id
        self.size = size
    }

    var body: some View {
        if let path = avatarURL,
           let url = URL(string: APIClient.baseURL.absoluteString + path) {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    TFAvatar(size: size, image: image, initials: initials, tint: tint, userID: userID)
                } else {
                    TFAvatar(size: size, initials: initials, tint: tint, userID: userID)
                }
            }
        } else {
            TFAvatar(size: size, initials: initials, tint: tint, userID: userID)
        }
    }
}

/// Текст сообщения для шторки «Выделить текст».
struct SelectableMessageText: Identifiable {
    let id = UUID()
    let text: String
}
