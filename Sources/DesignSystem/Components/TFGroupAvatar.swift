import SwiftUI

/// Bundled group artwork, selected reproducibly from the persistent group/project ID.
struct TFGroupAvatar: View {
    let identity: String
    var size: TFAvatar.Size = .xl
    @ScaledMetric(relativeTo: .subheadline) private var scalePercent: CGFloat = 100
    private var side: CGFloat { (size.rawValue * scalePercent / 100).rounded() }

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
        // Рисуем кругом сами: общий TFAvatar кладёт картинку в скруглённый
        // квадрат на сером фоне, и прозрачные углы круглой картинки
        // превращались в тёмные углы (владелец 06.10.2026).
        Image(assetName)
            .resizable()
            .scaledToFill()
            .frame(width: side, height: side)
            .clipShape(Circle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Аватар группы")
    }
}
