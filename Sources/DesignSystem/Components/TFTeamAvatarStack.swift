import SwiftUI
import SDWebImageSwiftUI

/// Бригада плана стопкой: впереди один, остальные выглядывают сзади;
/// каждые 2,5 секунды вперёд выходит следующий.
struct TFTeamAvatarStack: View {
    let ids: [String]
    let urls: [String]
    let side: CGFloat

    private var shown: [String] { Array(ids.prefix(4)) }
    private let period: TimeInterval = 2.5

    var body: some View {
        TimelineView(.periodic(from: .now, by: period)) { context in
            let front = Int(context.date.timeIntervalSinceReferenceDate / period) % shown.count
            let step = side * 0.16
            ZStack {
                ForEach(0..<shown.count, id: \.self) { depth in
                    // depth 0 — передний; дальше уходят назад и вправо
                    let idx = (front + depth) % shown.count
                    avatar(shown[idx], url: (idx < urls.count && !urls[idx].isEmpty) ? urls[idx] : (AvatarDirectory.shared.urls[shown[idx]] ?? ""))
                        .frame(width: side * 0.8, height: side * 0.8)
                        .offset(x: CGFloat(depth) * step - CGFloat(shown.count - 1) * step / 2,
                                y: 0)
                        .zIndex(Double(shown.count - depth))
                }
            }
            .frame(width: side, height: side)
            .animation(.easeInOut(duration: 0.4), value: front)
        }
    }

    @ViewBuilder private func avatar(_ id: String, url: String) -> some View {
        if !url.isEmpty, let full = TFAvatar.fullURL(url) {
            AnimatedImage(url: full, placeholder: { Circle().fill(Color.tfCard2) })
                .resizable().aspectRatio(contentMode: .fill)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.tfBackground, lineWidth: 1.5))
        } else if let asset = RoleAvatarAsset.imageName(forUserID: id) {
            Image(asset).resizable().aspectRatio(contentMode: .fill)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.tfBackground, lineWidth: 1.5))
        } else {
            Circle().fill(Color.tfCard2)
        }
    }
}
