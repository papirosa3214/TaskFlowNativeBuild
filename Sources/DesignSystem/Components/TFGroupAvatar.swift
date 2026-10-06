import SwiftUI

/// Bundled group artwork, selected reproducibly from the persistent group/project ID.
struct TFGroupAvatar: View {
    let identity: String
    var size: TFAvatar.Size = .xl

    private var assetName: String {
        // Swift Hasher is randomly seeded per process; use a fixed hash instead.
        let hash = identity.utf8.reduce(UInt64(14695981039346656037)) {
            ($0 ^ UInt64($1)) &* 1099511628211
        }
        // Общий чат — всегда первая картинка; остальные групповые и проектные
        // чаты — по кругу из шести (владелец 06.10.2026).
        if identity == "chat-common" { return "GroupAvatar01" }
        return String(format: "GroupAvatar%02d", Int(hash % 6) + 1)
    }

    var body: some View {
        TFAvatar(size: size, image: Image(assetName), initials: "",
                 accessibilityLabel: "Аватар группы")
    }
}
