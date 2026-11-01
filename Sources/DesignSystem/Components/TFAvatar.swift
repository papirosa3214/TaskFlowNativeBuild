import SwiftUI
import SDWebImageSwiftUI

// Аватар (`Avatar`, UI.tsx) — spec/DESIGN-TOKENS.md §4.
// Два принципиально разных вида в зависимости от наличия фото:
// - фото — радиус 8px (`rounded-lg`), НЕ круг, `object-fit: contain`
//   (вписывается целиком, не обрезает) — осознанное решение 18.08.2026,
//   круглая обрезка давала «кругляш» на фото с прозрачным фоном;
// - инициалы-заглушка — круг, фон = цвет пользователя или `#A6A6A6`,
//   шрифт `size × 0.43`, вес 600, белый текст.
public struct TFAvatar: View {
    @AppStorage(TeamAvatarAppearance.storageKey) private var avatarAppearance = "current"
    /// Галочка «Анимировать» в «Внешнем виде»: когда включена, портреты ролей
    /// комплекта «Ретро-нуар» играют роликом, иначе остаются статичными.
    @AppStorage(TeamAvatarAnimation.storageKey) private var avatarsAnimated = false
    @Environment(\.tfAvatarLiveTurn) private var liveTurn
    public enum Size: CGFloat {
        case xs = 18   // строка карточки доски
        case sm = 20   // строка задачи в списке
        case md = 30
        case lg = 32   // размер по умолчанию
        /// Строка списка чатов (`RoleChatsScreen`) — 21.09.2026, LOCK-195:
        /// там аватар ведущий элемент строки, а не спутник текста.
        case xl = 44
        /// Панель «Комнаты» в чатах (владелец 21.10.2026): во всю ширину
        /// вкладки 60 pt минус по `TFSpacing.xs` с краёв.
        case rail = 52
        /// Списки задач: роль читается отдельной колонкой рядом с тремя
        /// строками содержания, а не теряется в одной строке заголовка.
        case taskList = 68
        /// Профиль в настройках (владелец 06.10.2026).
        case profile = 72
        /// Портрет роли на стартовом экране чата (владелец 29.10.2026:
        /// «аватарка такая побольше»).
        case chatHero = 96
        /// Узел графа плана: раньше аватар был 32pt в коробке 56pt и тонул в ней.
        case node = 56
        /// Роль в круговом графе плана ветки (владелец 08.10.2026: «чуть увеличить»).
        case ringNode = 64
        /// Увеличенный просмотр по долгому нажатию.
        case zoom = 300
        /// Один участник бригады в увеличенном просмотре (до 5 штук разом).
        case team = 150
    }

    let size: Size
    /// nil — показываем инициалы-заглушку.
    let image: Image?
    /// Stable account ID for bundled agent artwork (e.g. `role_qa`, `u-secretary`).
    let userID: String?
    /// Бригада плана: если больше одного — наверх по очереди выходит каждый.
    let teamIDs: [String]
    /// Фото человека с сервера; для известных ролей используется выбранный комплект команды.
    let urlPath: String?
    let teamURLs: [String]
    /// Круглый портрет агента (fill) вместо фото человека (fit в скруглённом квадрате).
    let portrait: Bool
    /// Долгое нажатие увеличивает аватар (владелец 06.10.2026). Выключено у самого увеличенного вида.
    let zoomable: Bool
    @State private var showZoom = false
    /// Кто в стопке бригады спереди; сдвигается после просмотра всех.
    @State private var teamFront = 0
    let initials: String
    let tint: Color
    /// Подпись для VoiceOver. `nil` — собирается из инициалов.
    ///
    /// 14.09.2026, a11y-аудит: раньше метки не было ВООБЩЕ, и VoiceOver читал
    /// инициалы как россыпь отдельных букв («М», «К») без указания, что это
    /// исполнитель. В строках задач имя больше нигде не выводится — аватар
    /// единственный носитель этой информации, поэтому молчать он не имеет права.
    /// Вызывающий может передать своё (например, настоящее имя, если оно есть).
    let accessibilityLabel: String?

    /// 14.09.2026, Dynamic Type: кружок растёт вместе с текстом строки.
    ///
    /// HIG прямо просит этого — «Increase the size of meaningful interface
    /// icons as font size increases»: аватар здесь не украшение, он несёт
    /// информацию об исполнителе (имя в строке задачи больше нигде не выведено).
    /// Кривая взята от `subheadline` — той же ступени, что у основного текста
    /// строки, поэтому аватар и подпись растут синхронно.
    ///
    /// На дефолтном размере коэффициент равен 1.0, то есть круг остаётся ровно
    /// 18/20/30/32 — визуально не меняется НИЧЕГО. Дальше растёт по системной
    /// кривой и упирается в общий потолок приложения (`xxxLarge` в
    /// `TaskFlowApp`), где даёт 1.40×.
    ///
    /// База именно 100, а не 1: `UIFontMetrics.scaledValue(for:)` округляет
    /// результат, и на базе «1» рост схлопнулся бы обратно в 1.0. Проценты
    /// от округления не страдают.
    @ScaledMetric(relativeTo: .subheadline) private var scalePercent: CGFloat = 100

    private var growth: CGFloat { scalePercent / 100 }
    /// Сторона квадрата/диаметр круга — база ступени, умноженная на рост.
    private var side: CGFloat { (size.rawValue * growth).rounded() }
    /// Радиус фото-варианта держим пропорцией к стороне (в спеке 8pt на 32pt),
    /// иначе на выросшем аватаре скругление выглядит слишком мелким.
    private var cornerRadius: CGFloat { (TFRadius.md * growth).rounded() }
    private var resolvedAccessibilityLabel: String {
        if let accessibilityLabel { return accessibilityLabel }
        return initials.isEmpty ? "Аватар" : "Аватар: \(initials)"
    }

    public init(
        size: Size = .lg,
        image: Image? = nil,
        initials: String,
        tint: Color = Color(hex: TFHexDefault.unassigned),
        accessibilityLabel: String? = nil,
        userID: String? = nil,
        teamIDs: [String] = [],
        urlPath: String? = nil,
        teamURLs: [String] = [],
        portrait: Bool = false,
        zoomable: Bool = true
    ) {
        self.size = size
        self.image = image
        self.userID = userID
        self.teamIDs = teamIDs
        self.urlPath = urlPath
        self.teamURLs = teamURLs
        self.portrait = portrait
        self.zoomable = zoomable
        self.initials = initials
        self.tint = tint
        self.accessibilityLabel = accessibilityLabel
    }

    /// Своя картинка, а если не передали — из справочника по id учётки.
    private var resolvedURLPath: String? {
        if let urlPath { return urlPath }
        guard let userID else { return nil }
        return AvatarDirectory.shared.urls[userID]
    }

    static func fullURL(_ path: String) -> URL? {
        URL(string: APIClient.baseURL.absoluteString + path)
    }

    /// Портрет роли: статика или ролик — смотря по галочке в «Внешнем виде».
    /// Увеличение по максимуму и круглая обрезка живут в `TFRolePortrait`,
    /// здесь только выбор, что именно рисовать.
    private var roleAppearance: TeamAvatarAppearance {
        TeamAvatarAppearance(rawValue: avatarAppearance) ?? .current
    }

    private var roleAsset: String? {
        RoleAvatarAsset.imageName(forUserID: userID, appearance: roleAppearance)
    }

    /// Роль по `userID` — по ней `TFRolePortrait` берёт кадрирование из редактора.
    private var roleKey: String? { RoleAvatarAsset.role(forUserID: userID) }

    private var roleLoop: String? {
        guard avatarsAnimated || liveTurn else { return nil }
        return RoleAvatarAsset.loopName(forUserID: userID, appearance: roleAppearance)
    }

    /// Пока картинка грузится (или недоступна): вшитый портрет роли, иначе инициалы.
    @ViewBuilder private var placeholderCircle: some View {
        if let asset = roleAsset {
            TFRolePortrait(role: roleKey, imageAsset: asset, loopName: roleLoop, side: side)
        } else {
            Circle().fill(tint).frame(width: side, height: side)
                .overlay { Text(initials).tfTypeFont(size: side * 0.43, weight: .semibold).foregroundStyle(Color.tfPaper) }
        }
    }

    public var body: some View {
        Group {
            if teamIDs.count > 1 {
                TFTeamAvatarStack(ids: teamIDs, urls: teamURLs, side: side, front: teamFront)
            } else if let asset = roleAsset {
                TFRolePortrait(role: roleKey, imageAsset: asset, loopName: roleLoop, side: side)
            } else if let urlPath = resolvedURLPath, let url = TFAvatar.fullURL(urlPath) {
                if portrait || self.urlPath == nil {
                    AnimatedImage(url: url, placeholder: { placeholderCircle })
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: side, height: side)
                        .clipShape(Circle())
                } else {
                    AnimatedImage(url: url, placeholder: { placeholderCircle })
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: side, height: side)
                        .background(Color.tfCard2)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                }
            } else if let image {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit) // object-fit: contain
                    .frame(width: side, height: side)
                    .background(Color.tfCard2)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            } else {
                Circle()
                    .fill(tint)
                    .frame(width: side, height: side)
                    .overlay {
                        // Пропорция 0.43 от спек — считается от РАСТУЩЕЙ стороны,
                        // поэтому инициалы увеличиваются вместе с кружком.
                        Text(initials)
                            .font(.system(size: side * 0.43, weight: .semibold))  // design-system-guard: ignore — инициалы растут вместе с кружком
                            .foregroundStyle(Color.tfPaper)
                    }
            }
        }
        // Один элемент, а не круг + буквы по отдельности: `children: .ignore`
        // глушит внутренние тексты, дальше читается только наша метка.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(resolvedAccessibilityLabel)
        // Удержание — системное контекстное меню с превью портрета (владелец
        // 21.10.2026, DESIGN.md «Удержание: контекстное меню»): отклик, подъём
        // и размытие даёт система. Раньше был свой `LongPressGesture` со своей
        // вибрацией и сразу полноэкранное окно — теперь оно за пунктом меню.
        .modifier(AvatarZoomMenu(isEnabled: zoomable, onOpen: { showZoom = true }) { zoomContent })
        .fullScreenCover(isPresented: $showZoom) {
            ZStack {
                Color.black.opacity(0.88).ignoresSafeArea()
                zoomContent
            }
            .contentShape(Rectangle())
            .onTapGesture { showZoom = false }
            .presentationBackground(.clear)
        }
        .onChange(of: showZoom) { _, open in
            if !open, teamIDs.count > 1 { teamFront += 1 }
        }
    }

    /// Крупный портрет: превью меню удержания и полноэкранный просмотр.
    @ViewBuilder private var zoomContent: some View {
        if teamIDs.count > 1 {
            // Бригада: все портреты разом, до пяти.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                ForEach(Array(teamIDs.prefix(5).enumerated()), id: \.offset) { i, id in
                    TFAvatar(size: .team, initials: initials, tint: tint,
                             userID: id,
                             urlPath: i < teamURLs.count && !teamURLs[i].isEmpty ? teamURLs[i] : nil,
                             portrait: true, zoomable: false)
                }
            }
            .padding(24)
        } else {
            TFAvatar(size: .zoom, image: image, initials: initials, tint: tint,
                     accessibilityLabel: accessibilityLabel, userID: userID,
                     urlPath: urlPath, portrait: portrait, zoomable: false)
        }
    }
}

/// Меню удержания аватарки: превью — крупный портрет, пункт — открыть его во
/// весь экран. Без пунктов система меню не показывает, поэтому пункт есть.
private struct AvatarZoomMenu<Preview: View>: ViewModifier {
    let isEnabled: Bool
    let onOpen: () -> Void
    @ViewBuilder let preview: () -> Preview

    func body(content: Content) -> some View {
        if isEnabled {
            content.contextMenu {
                Button("Открыть крупно", systemImage: "arrow.up.left.and.arrow.down.right", action: onOpen)
            } preview: {
                preview()
            }
        } else {
            content
        }
    }
}

#Preview("Аватары") {
    HStack(alignment: .center, spacing: TFSpacing.md) {
        TFAvatar(size: .xs, initials: "МК", tint: .tfBlue)
        TFAvatar(size: .sm, initials: "МК", tint: .tfPurple)
        TFAvatar(size: .md, initials: "МК", tint: .tfTeal)
        TFAvatar(size: .lg, initials: "МК")
    }
    .padding()
    .background(Color.tfBackground)
}
