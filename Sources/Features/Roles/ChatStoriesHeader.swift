import SwiftUI
import UIKit

// Аватарки ролей на экране «Чаты» — как истории в Telegram (владелец
// 12.11.2026: «разместить наверху как в Telegram… когда оттягивал, они
// вылазили и вставали в полосу над поиском»; «сделай с нуля»).
//
// В покое пять кружков лежат стопкой у левого края шапки. Над полем поиска в
// ленте есть место под ряд, но лента стоит прокрученной ровно на его высоту —
// ряд спрятан под шапкой. Потяг вниз прокручивает к ряду, и кружки по ходу
// пальца вылетают из стопки на свои места; прокрутка вверх уводит их обратно.
// Отпустил на середине — лента доводит до ближайшего края (`ChatStoriesSnap`).
//
// Полёт рисует слой поверх экрана (`ChatStoriesFlight`): из ленты кружок в
// шапку не попадёт — его срежет затухание верхнего края. Когда ряд раскрыт
// целиком, слой уступает место настоящему ряду в ленте (`ChatStoriesRow`) —
// его можно листать вбок, если ролей больше, чем влезает.
//
// Положение прокрутки живёт в `ChatStoriesMotion`, а не в `@State` экрана:
// так кадр полёта перерисовывает только слой и ряд, а список чатов — нет.
//
// Кружок — тот же `RoleMemberAvatar`, что у строки роли в списке.
// `TFTeamAvatarStack` не подошёл: это неподвижная стопка бригады плана,
// кружки из неё не вылетают. Поле поиска — капсула штатного поиска, а не
// `TFTextField` (поле-карточка 52 pt для форм).

/// Роль в ряду: кто, как выглядит и идёт ли у неё сейчас ход.
struct ChatStory: Identifiable, Equatable {
    let id: String
    let name: String
    let member: RoleChatMember
    /// Роль прямо сейчас работает — вокруг кружка цветное кольцо.
    let working: Bool

    static func == (lhs: ChatStory, rhs: ChatStory) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.working == rhs.working
            && lhs.member.avatarURL == rhs.member.avatarURL
    }
}

/// Размеры ряда. Слой полёта и настоящий ряд считают места по одним числам,
/// иначе в момент подмены кружки дёрнутся.
enum ChatStoriesLayout {
    /// Кружок в ряду.
    static let avatar = TFAvatar.Size.rail
    /// Кружок вместе с кольцом.
    static let box: CGFloat = avatar.rawValue + 8
    /// Кружок в стопке у заголовка.
    static let stackSize: CGFloat = 30
    /// Шаг кружков в стопке (они наезжают друг на друга).
    static let stackStep: CGFloat = 18
    /// Сколько кружков лежит в стопке (владелец 12.11.2026: «не три, а пять»).
    static let stackCount = 5
    /// Ширина места одной роли в ряду.
    static let cell: CGFloat = 76
    static let topPadding: CGFloat = TFSpacing.xs
    static let nameGap: CGFloat = 4
    static let nameHeight: CGFloat = 18
    static let bottomPadding: CGFloat = TFSpacing.xs
    /// Отступ ряда слева: кружок первой роли стоит по краю текста списка.
    static let leading: CGFloat = max(0, TFSpacing.screenHorizontal - (cell - box) / 2)
    static let rowHeight: CGFloat = topPadding + box + nameGap + nameHeight + bottomPadding

    /// Центр кружка `index` в раскрытом ряду, по горизонтали.
    static func rowCenterX(_ index: Int) -> CGFloat {
        leading + cell * CGFloat(index) + cell / 2
    }
}

/// Где сейчас лента: сколько из ряда видно. Пишет `onScrollGeometryChange`
/// экрана, читают только слой полёта и ряд.
@Observable
final class ChatStoriesMotion {
    /// Прокрутка ленты от её верха (0 — ряд раскрыт, `rowHeight` — спрятан).
    var offset: CGFloat = ChatStoriesLayout.rowHeight
    /// Верхний отступ ленты: строка состояния плюс шапка.
    var topInset: CGFloat = 0
    /// Ленту уже поставили в покой «ряд спрятан». Делается один раз.
    @ObservationIgnored var placed = false

    /// 0 — кружки в стопке, 1 — в ряду.
    var progress: CGFloat {
        min(1, max(0, 1 - offset / ChatStoriesLayout.rowHeight))
    }
}

/// Отпустил ленту, когда ряд виден наполовину, — она доезжает до ближайшего
/// края: ряд либо раскрыт целиком, либо спрятан. Дальше ряда не вмешивается.
struct ChatStoriesSnap: ScrollTargetBehavior {
    var rowHeight: CGFloat

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        guard rowHeight > 0 else { return }
        let y = target.rect.minY
        guard y > 0, y < rowHeight else { return }
        target.rect.origin.y = y < rowHeight / 2 ? 0 : rowHeight
    }
}

/// Кружок роли с кольцом «работает».
struct ChatStoryAvatar: View {
    let story: ChatStory
    /// Тёмная обводка, которая отделяет кружки друг от друга в стопке.
    var outline: CGFloat = 0

    var body: some View {
        ZStack {
            if story.working {
                Circle()
                    .strokeBorder(
                        LinearGradient(colors: [Color.tfGreen, Color.tfBlue],
                                       startPoint: .topTrailing, endPoint: .bottomLeading),
                        lineWidth: 2.5)
            }
            RoleMemberAvatar(member: story.member, size: ChatStoriesLayout.avatar)
                .background {
                    Circle()
                        .fill(Color.tfBackground)
                        .padding(-3)
                        .opacity(outline)
                }
        }
        .frame(width: ChatStoriesLayout.box, height: ChatStoriesLayout.box)
    }
}

/// Подпись под кружком.
struct ChatStoryName: View {
    let name: String

    var body: some View {
        Text(name)
            .tfText(.caption)
            .foregroundStyle(Color.tfSub)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: ChatStoriesLayout.cell - 6, height: ChatStoriesLayout.nameHeight)
    }
}

/// Настоящий ряд в ленте над полем поиска. Виден, когда раскрыт целиком;
/// пока кружки летят, вместо него рисует слой полёта.
struct ChatStoriesRow: View {
    let stories: [ChatStory]
    let motion: ChatStoriesMotion
    @State private var position = ScrollPosition(edge: .leading)

    var body: some View {
        let shown = motion.progress >= 0.999
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(stories) { story in
                    NavigationLink(value: AppRoute.chatRole(id: story.id)) {
                        VStack(spacing: ChatStoriesLayout.nameGap) {
                            ChatStoryAvatar(story: story)
                            ChatStoryName(name: story.name)
                        }
                        .frame(width: ChatStoriesLayout.cell)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(story.name)
                    .accessibilityIdentifier("chats.story.\(story.id)")
                }
            }
            .padding(.leading, ChatStoriesLayout.leading)
            .padding(.trailing, TFSpacing.xs)
            .padding(.top, ChatStoriesLayout.topPadding)
            .padding(.bottom, ChatStoriesLayout.bottomPadding)
        }
        .scrollPosition($position)
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .frame(height: ChatStoriesLayout.rowHeight)
        .opacity(shown ? 1 : 0)
        .allowsHitTesting(shown)
        .accessibilityHidden(!shown)
        .onChange(of: shown) { _, isShown in
            // Ряд свернулся — следующий раз кружки вылетят в начало ряда.
            if !isShown { position.scrollTo(edge: .leading) }
        }
    }
}

/// Слой поверх экрана: стопка у заголовка и полёт кружков в ряд.
/// Координаты — экранные, поэтому слой ставится с `.ignoresSafeArea()`.
struct ChatStoriesFlight: View {
    let stories: [ChatStory]
    let motion: ChatStoriesMotion
    /// Заголовок шапки: стопка его не задевает.
    let title: String
    /// Тап по стопке раскрывает ряд.
    let onTapStack: () -> Void

    var body: some View {
        let p = motion.progress
        // Слой не убирается, а прячется: собранный заново, он грузил бы
        // картинки кружков с нуля, и в момент подмены ряда мелькали одни
        // подписи без аватарок.
        GeometryReader { geo in
            content(width: geo.size.width, progress: p)
        }
        .opacity(p < 0.999 ? 1 : 0)
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func content(width: CGFloat, progress p: CGFloat) -> some View {
        let fits = Int(((width - ChatStoriesLayout.leading) / ChatStoriesLayout.cell).rounded(.up))
        let shown = Array(stories.prefix(max(fits, 0)))
        let stackCount = min(ChatStoriesLayout.stackCount, shown.count)
        let stackWidth = ChatStoriesLayout.stackSize + CGFloat(max(stackCount - 1, 0)) * ChatStoriesLayout.stackStep
        // Стопка выровнена по левому краю — по линии аватаров списка: слева в
        // шапке корня кнопок нет, к заголовку прижиматься незачем (владелец
        // 12.11.2026). Длинный заголовок она всё равно не задевает.
        let stackStart = min(TFSpacing.screenHorizontal,
                             width / 2 - Self.titleWidth(title) / 2 - TFSpacing.md - stackWidth)
        let barCenter = (Self.windowTopInset + motion.topInset) / 2
        // Кружки летят к месту ряда в покое, а не едут вверх вместе с лентой:
        // иначе на середине пути они проходили бы по заголовку. Ближе к
        // раскрытию ряд догоняет ленту, чтобы подмена на настоящий ряд не
        // дёргалась.
        let rowTop = motion.topInset - motion.offset * p * p
        let rowY = rowTop + ChatStoriesLayout.topPadding + ChatStoriesLayout.box / 2
        let stackScale = ChatStoriesLayout.stackSize / ChatStoriesLayout.box

        // Сбор в две фазы (владелец 12.11.2026): сначала кружки в полный
        // размер съезжают влево плотной кучкой — крайний правый встаёт у начала
        // заголовка; потом кучка резко уменьшается и уходит вверх в стопку.
        // Раскрытие — тот же путь обратно. p: 1 — ряд, 0 — стопка.
        let slide = Self.smooth((1 - p) / 0.5)          // фаза 1: ряд → кучка
        let lift = Self.smooth((0.5 - p) / 0.5)         // фаза 2: кучка → стопка
        let titleLeft = width / 2 - Self.titleWidth(title) / 2 - TFSpacing.xs
        let clusterFirst = TFSpacing.screenHorizontal + ChatStoriesLayout.box / 2
        let clusterLast = max(clusterFirst, titleLeft - ChatStoriesLayout.box / 2)
        let clusterStep = stackCount > 1
            ? min(ChatStoriesLayout.cell, (clusterLast - clusterFirst) / CGFloat(stackCount - 1))
            : 0

        ZStack(alignment: .topLeading) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, story in
                let slot = min(index, max(stackCount - 1, 0))
                let rowX = ChatStoriesLayout.rowCenterX(index)
                let clusterX = clusterFirst + CGFloat(slot) * clusterStep
                let stackX = stackStart + ChatStoriesLayout.stackSize / 2 + CGFloat(slot) * ChatStoriesLayout.stackStep
                let x = p >= 0.5 ? rowX + (clusterX - rowX) * slide : clusterX + (stackX - clusterX) * lift
                let y = rowY + (barCenter - rowY) * lift
                let scale = 1 + (stackScale - 1) * lift
                // Кто не помещается в стопку (шестой и дальше), гаснет, пока
                // съезжает в кучку.
                let alpha = index < ChatStoriesLayout.stackCount ? 1 : Double(1 - slide)
                ChatStoryAvatar(story: story, outline: max(slide, 1 - p))
                    .scaleEffect(scale)
                    .position(x: x, y: y)
                    .opacity(alpha)
                    .zIndex(Double(-index))
                // Подписи гаснут в начале сбора — дальше кружки уезжают от них.
                ChatStoryName(name: story.name)
                    .position(x: rowX,
                              y: rowY + ChatStoriesLayout.box / 2 + ChatStoriesLayout.nameGap + ChatStoriesLayout.nameHeight / 2)
                    .opacity(Double(max(0, (p - 0.75) / 0.25)))
            }
            if p < 0.02, stackCount > 0 {
                Color.clear
                    .frame(width: stackWidth + 16, height: ChatStoriesLayout.stackSize + 16)
                    .contentShape(Rectangle())
                    .position(x: stackStart + stackWidth / 2, y: barCenter)
                    .onTapGesture(perform: onTapStack)
                    .accessibilityElement()
                    .accessibilityLabel("Показать роли")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("chats.stories.stack")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(p < 0.02)
        .accessibilityHidden(p >= 0.999)
    }

    /// Плавный ход 0…1 с замедлением на концах.
    private static func smooth(_ t: CGFloat) -> CGFloat {
        let c = min(1, max(0, t))
        return c * c * (3 - 2 * c)
    }

    /// Ширина системного заголовка в шапке (17 pt, полужирный).
    private static func titleWidth(_ title: String) -> CGFloat {
        let font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        return ceil((title as NSString).size(withAttributes: [.font: font]).width)
    }

    /// Высота строки состояния: шапка начинается под ней.
    private static var windowTopInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets.top ?? 0
    }
}

/// Поле поиска корня раздела. Своё, а не `.searchable`: системное приклеено к
/// заголовку, и вставить ряд над ним нельзя (выбор владельца 12.11.2026).
/// Подпись та же, что у системного поиска на экранах ролей.
struct ChatsSearchField: View {
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: TFSpacing.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.tfDim)
            TextField(ChatsSystemSearch.prompt, text: $text)
                .focused($focused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityIdentifier("chats.search")
            if !text.isEmpty {
                Button {
                    text = ""
                    focused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.tfDim)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Очистить поиск")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .chatsSearchFieldSurface()
        .padding(.horizontal, TFSpacing.screenHorizontal)
        .padding(.bottom, TFSpacing.xs)
    }
}

private extension View {
    /// На iOS 26 — системное стекло, как у штатного поиска; раньше —
    /// системная заливка полей.
    @ViewBuilder
    func chatsSearchFieldSurface() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            self.background(Color(uiColor: .tertiarySystemFill), in: Capsule())
        }
    }
}

/// Системный поиск в шапке — только на экранах, открытых переходом. В корне
/// раздела поле своё, под рядом историй.
struct ChatsSystemSearch: ViewModifier {
    static let prompt = "Поиск по чатам"
    let enabled: Bool
    @Binding var text: String

    func body(content: Content) -> some View {
        if enabled {
            content.searchable(text: $text,
                               placement: .navigationBarDrawer(displayMode: .always),
                               prompt: Text(Self.prompt))
        } else {
            content
        }
    }
}
