import SwiftUI
import AVFoundation

/// Портрет роли в круге: статичная картинка ИЛИ зацикленный ролик.
///
/// Один вход для всех пяти мест, где рисуется вшитый портрет роли
/// (`TFAvatar`, `TFTeamAvatarStack`, `RoleAvatarView`, `AgentWorkAvatarView`,
/// превью в «Внешнем виде»). Раньше это был повторяющийся в каждом месте
/// `Image(asset)…clipShape(Circle())`, и переключение на анимацию пришлось бы
/// дописывать четыре раза — первое расхождение появилось бы на первом же
/// пропущенном экране.
///
/// ## Зацикливание
///
/// Повтор бесшовный. Ролики склеены «туда-обратно» (пинг-понг: 5 секунд
/// вперёд + те же 5 секунд назад), поэтому стык уже ВНУТРИ файла, последний
/// кадр совпадает с первым. `AVPlayerLooper` здесь техническая страховка на
/// случай, если файл вдруг придёт без пинг-понга — сам он шов не лечит.
///
/// ## Звук
///
/// В файлах его нет намеренно. При обратном ходе звук шёл бы задом наперёд,
/// а для аватарки он не нужен вовсе; слой всё равно глушится на случай, если
/// файл пополнится.
///
/// ## Увеличение по максимуму
///
/// Соблазн увеличить содержимое под круглую маску отменён 10.10.2026 по
/// жалобе владельца: картинка в акте занимает весь квадрат, полей вокруг
/// виньетки практически нет, а масштаб срезал по краям рисунка и сбивал
/// центрирование. Кружок теперь ровно прежнего размера и показывает картинку
/// целиком.
struct TFRolePortrait: View {
    /// Имя imageset-ассета статичного портрета.
    let imageAsset: String
    /// Имя ролика в бандле без расширения; `nil` — показываем статику.
    let loopName: String?
    /// Сторона кружка (уже с учётом Dynamic Type).
    let side: CGFloat
    /// Анимацию просим не запускать (Reduce Motion, режим энергосбережения).
    var allowsAnimation: Bool = true

    private var showsLoop: Bool {
        guard allowsAnimation, let loopName, !UIAccessibility.isReduceMotionEnabled else { return false }
        // Страховка от чёрного кружка: если файла в бандле нет (забыли положить
        // новую роль), показываем статику, а не пустой видеослой.
        return Bundle.main.url(forResource: loopName, withExtension: "mp4") != nil
    }

    var body: some View {
        Group {
            if showsLoop, let loopName {
                TFLoopingAvatarVideo(resourceName: loopName)
                    .frame(width: side, height: side)
                    .clipShape(Circle())
            } else {
                Image(imageAsset).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: side, height: side)
                    .clipShape(Circle())
            }
        }
        .accessibilityHidden(true)
    }
}

/// Слой с роликом. `AVPlayerLayer` + `AVPlayerLooper` поверх `AVQueuePlayer`.
private struct TFLoopingAvatarVideo: UIViewRepresentable {
    let resourceName: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.videoGravity = .resizeAspectFill
        view.playerLayer.backgroundColor = UIColor.black.cgColor
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "mp4") else {
            return view
        }
        let player = AVQueuePlayer()
        player.isMuted = true
        player.actionAtItemEnd = .advance
        context.coordinator.player = player
        context.coordinator.looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        view.playerLayer.player = player
        player.playImmediately(atRate: 1)
        return view
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {}

    static func dismantleUIView(_ uiView: PlayerLayerView, coordinator: Coordinator) {
        // Иначе плеер продолжает играть после ухода вьюхи с экрана.
        coordinator.player?.pause()
        coordinator.player?.replaceCurrentItem(with: nil)
        coordinator.looper = nil
        coordinator.player = nil
    }

    final class Coordinator {
        var looper: AVPlayerLooper?
        var player: AVQueuePlayer?
    }

    final class PlayerLayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

#Preview("Портрет роли") {
    HStack(spacing: 16) {
        TFRolePortrait(imageAsset: "TeamNoirResearcher",
                       loopName: "RoleNoirLoopResearcher", side: 64)
        TFRolePortrait(imageAsset: "TeamNoirResearcher", loopName: nil, side: 64)
    }
    .padding()
    .background(Color.tfBackground)
}