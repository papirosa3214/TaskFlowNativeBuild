import SwiftUI
import AVFoundation

/// Сколько видео-портретов могут одновременно играть на экране.
///
/// Владелец 11.10.2026, после зависания «Активности»: каждый кружок — это
/// отдельный `AVQueuePlayer` с `AVPlayerLooper`, и на списке из 69 выполненных
/// задач приложение встало колом — спиндамп симулятора показал 199 потоков и
/// 20 видеоконвертеров, главный поток не отвечал. Кружок в списке — это 18-20pt,
/// зритель различает «живую» и «статичную» картинку, но не различает их ВОСЕМЬ
/// таких одновременно; платить за это надоевшим подтормаживанием нельзя.
///
/// ## Почему 5
///
/// - 5 — примерно то, сколько строк крупного списка помещается в первый экран;
///   дальше список либо листают (тогда освободившиеся слоты занимает новое), либо
///   не смотрят в упор, и анимация там не нужна.
/// - 69 сработали как «много», 5 — как «много ИЗ 69 на одном экране»: на списке
///   до 5 задач видео играет, на списке из 69 первые пять играют, остальные
///   автоматически становятся статичными. Порог единый для приложения, а не
///   угадывание на каждый экран.
/// - Запас есть: каждый плеер тянет несколько потоков декодирования, поэтому
///   даже в 5 одновременных счётчик потоков остаётся втрое меньше, чем был.
///
/// Отдельный тумблер «Анимировать» («Внешний вид») при выключенной анимации
/// не трогаем — порог работает только поверх неё.
@MainActor
final class TFPortraitVideoBudget: ObservableObject {
    static let shared = TFPortraitVideoBudget()

    /// Порог одновременных видео-портретов на экране. Больше — статика.
    static let limit = 5

    /// Кто сейчас имеет право играть. Порядок важен: `onAppear` идёт сверху
    /// вниз, поэтому в лимите остаются те кружки, что ближе к началу списка.
    @Published private(set) var activeIDs: Set<UUID> = []

    private init() {}

    /// `true` — этому кружку можно играть.
    func allows(_ id: UUID) -> Bool { activeIDs.contains(id) }

    /// Регистрирует кружок. `false` — места в бюджете нет, рисуем статику.
    func acquire(_ id: UUID) -> Bool {
        if activeIDs.contains(id) { return true }
        guard activeIDs.count < Self.limit else { return false }
        activeIDs.insert(id)
        return true
    }

    func release(_ id: UUID) {
        activeIDs.remove(id)
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
                if avatarsAnimated, allowsAnimation { budget.acquire(budgetID) }
            }
            .onDisappear { budget.release(budgetID) }
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
        TFRolePortrait(role: "researcher", imageAsset: "TeamNoirResearcher",
                       loopName: "RoleNoirLoopResearcher", side: 64)
        TFRolePortrait(role: "researcher", imageAsset: "TeamNoirResearcher",
                       loopName: nil, side: 64)
    }
    .padding()
    .background(Color.tfBackground)
}