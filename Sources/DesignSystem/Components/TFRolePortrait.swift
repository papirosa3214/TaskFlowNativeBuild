import SwiftUI
import AVFoundation

/// Сколько разных роликов могут одновременно играть на экране.
///
/// Владелец 11.10.2026, после зависания «Активности»: каждый кружок был
/// отдельным `AVQueuePlayer` с `AVPlayerLooper`, и на списке из 69 задач
/// приложение встало колом — 199 потоков и 20 видеоконвертеров. Тогда порог
/// поставили на 5 кружков.
///
/// ## С 21.10.2026 — один плеер на ролик, порог 12 роликов
///
/// Владелец: в панели «Комнаты» 10 ролей, а играли только пять. Теперь плеер
/// заводится ОДИН на ролик (`TFSharedLoopPlayers`) и показывается во всех
/// кружках этой роли сразу — 69 строк одной роли это один плеер, а не 69.
/// Поэтому и порог считает не кружки, а разные ролики: 12 — все внутренние
/// роли с запасом. Тринадцатый разный ролик на экране рисуется статикой.
///
/// Отдельный тумблер «Анимировать» («Внешний вид») при выключенной анимации
/// не трогаем — порог работает только поверх неё.
@MainActor
final class TFPortraitVideoBudget: ObservableObject {
    static let shared = TFPortraitVideoBudget()

    /// Порог одновременных РАЗНЫХ роликов на экране. Больше — статика.
    static let limit = 12

    /// Кружок → его ролик. Порядок `onAppear` идёт сверху вниз, поэтому в
    /// лимите остаются роли, что ближе к началу списка.
    @Published private(set) var active: [UUID: String] = [:]

    private init() {}

    /// `true` — этому кружку можно играть.
    func allows(_ id: UUID) -> Bool { active[id] != nil }

    /// Регистрирует кружок. Ролик, который уже играет, места не занимает.
    /// `false` — разных роликов уже `limit`, рисуем статику.
    @discardableResult
    func acquire(_ id: UUID, loop: String) -> Bool {
        if active[id] != nil { return true }
        let playing = Set(active.values)
        guard playing.contains(loop) || playing.count < Self.limit else { return false }
        active[id] = loop
        return true
    }

    func release(_ id: UUID) {
        active[id] = nil
    }
}

/// Общие плееры роликов: один `AVQueuePlayer` + `AVPlayerLooper` на ролик,
/// сколько бы кружков его ни показывали (21.10.2026). Плеер живёт, пока его
/// держит хоть один кружок.
@MainActor
final class TFSharedLoopPlayers {
    static let shared = TFSharedLoopPlayers()

    private struct Entry {
        let player: AVQueuePlayer
        let looper: AVPlayerLooper
        var holders: Int
    }

    private var entries: [String: Entry] = [:]

    private init() {}

    func retain(_ name: String) -> AVQueuePlayer? {
        if var entry = entries[name] {
            entry.holders += 1
            entries[name] = entry
            return entry.player
        }
        guard let url = Bundle.main.url(forResource: name, withExtension: "mp4") else { return nil }
        let player = AVQueuePlayer()
        player.isMuted = true
        player.actionAtItemEnd = .advance
        let looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        entries[name] = Entry(player: player, looper: looper, holders: 1)
        player.playImmediately(atRate: 1)
        return player
    }

    func release(_ name: String) {
        guard var entry = entries[name] else { return }
        entry.holders -= 1
        if entry.holders > 0 { entries[name] = entry; return }
        // Последний кружок ушёл — плеер останавливаем и отпускаем.
        entry.player.pause()
        entry.looper.disableLooping()
        entry.player.removeAllItems()
        entries[name] = nil
    }
}

/// Портрет роли в кружке: статичная картинка ИЛИ зацикленный ролик.
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
/// ## Кадрирование по роли
///
/// `AvatarCrop` — то, что владелец подобрал сам в редакторе (`AvatarCropEditor`):
/// масштаб, сдвиг, своё фото и форма кружка. Раньше тот же масштаб был зашит
/// в код (1,14×), и картинку от этого срезало по краям; теперь эти числа
/// выставляются руками и по умолчанию равны единице — то есть ничего не
/// трогается, пока владелец сам не попросит.
struct TFRolePortrait: View {
    /// id роли (`researcher`, `qa`, …) — по нему берётся кадрирование.
    let role: String?
    /// Имя imageset-ассета статичного портрета.
    let imageAsset: String
    /// Имя ролика в бандле без расширения; `nil` — показываем статику.
    let loopName: String?
    /// Сторона кружка (уже с учётом Dynamic Type).
    let side: CGFloat
    /// Анимацию просим не запускать (Reduce Motion, режим энергосбережения).
    var allowsAnimation: Bool = true

    @AppStorage(TeamAvatarAnimation.storageKey) private var avatarsAnimated = false
    @StateObject private var budget = TFPortraitVideoBudget.shared
    /// Личный пропуск в бюджет: один кружок — один id, снимается при уходе с экрана.
    @State private var budgetID = UUID()

    private var crop: AvatarCrop.Value {
        guard let role else { return AvatarCrop.Value() }
        return AvatarCrop.value(for: role)
    }

    private var showsLoop: Bool {
        guard avatarsAnimated, allowsAnimation, let loopName,
              !UIAccessibility.isReduceMotionEnabled else { return false }
        // Страховка от чёрного кружка: если файла в бандле нет (забыли положить
        // новую роль), показываем статику, а не пустой видеослой.
        guard Bundle.main.url(forResource: loopName, withExtension: "mp4") != nil else { return false }
        // Порог: кружок за пределами бюджета рисуется статикой (см.
        // `TFPortraitVideoBudget`). Без этой строки длинный список поднимает
        // по плееру на задачу и подвешивает приложение.
        return budget.allows(budgetID)
    }

    private var shape: AvatarCrop.Shape { crop.shape }

    @ViewBuilder private var inner: some View {
        if crop.photo != nil, let url = crop.photo.map(AvatarCrop.photoURL),
           let img = UIImage(contentsOfFile: url.path) {
            Image(uiImage: img).resizable().aspectRatio(contentMode: .fill)
        } else if showsLoop, let loopName {
            TFLoopingAvatarVideo(resourceName: loopName)
        } else {
            Image(imageAsset).resizable().aspectRatio(contentMode: .fill)
        }
    }

    var body: some View {
        inner
            .frame(width: side, height: side)
            .scaleEffect(crop.scale)
            .offset(x: crop.dx, y: crop.dy)
            .clipShape(shape == .circle ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: TFRadius.md)))
            .frame(width: side, height: side)
            .accessibilityHidden(true)
            .onAppear {
                // Занимаем слот только если реально собираемся играть, иначе
                // кружок без ролика зря съедал бы чужое место в бюджете.
                if avatarsAnimated, allowsAnimation, let loopName { budget.acquire(budgetID, loop: loopName) }
            }
            .onDisappear { budget.release(budgetID) }
    }
}

/// Слой с роликом: общий плеер ролика из `TFSharedLoopPlayers`, один на все
/// кружки этой роли (21.10.2026).
private struct TFLoopingAvatarVideo: UIViewRepresentable {
    let resourceName: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.videoGravity = .resizeAspectFill
        view.playerLayer.backgroundColor = UIColor.black.cgColor
        if let player = TFSharedLoopPlayers.shared.retain(resourceName) {
            context.coordinator.name = resourceName
            view.playerLayer.player = player
            player.play()
        }
        return view
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {}

    static func dismantleUIView(_ uiView: PlayerLayerView, coordinator: Coordinator) {
        // Слой отпускает плеер; сам плеер останавливается, когда уходит
        // последний кружок этой роли.
        uiView.playerLayer.player = nil
        if let name = coordinator.name { TFSharedLoopPlayers.shared.release(name) }
        coordinator.name = nil
    }

    final class Coordinator {
        var name: String?
    }

    final class PlayerLayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

#Preview("Портрет роли") {
    HStack(spacing: 16) {
        TFRolePortrait(role: "researcher", imageAsset: "TeamNoirResearcher",
                       loopName: "RoleNoirLoopResearcher", side: 64)
        TFRolePortrait(role: "researcher", imageAsset: "TeamNoirResearcher",
                       loopName: nil, side: 64)
    }
    .padding()
    .background(Color.tfBackground)
}