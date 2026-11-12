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
    /// Ключ роли (`builder`, `designer`…): по нему открывается её профиль.
    let roleKey: String?
    let member: RoleChatMember
    /// Роль прямо сейчас работает — вокруг кружка цветное кольцо.
    let working: Bool

    static func == (lhs: ChatStory, rhs: ChatStory) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.working == rhs.working
            && lhs.member.avatarURL == rhs.member.avatarURL
    }
}

extension ChatStory {
    /// Куда ведёт тап по кружку (владелец 12.11.2026): роль работает — в её
    /// чаты; не работает — в её профиль («кто он, что он, навыки»).
    var destination: AppRoute {
        if !working, let roleKey, !roleKey.isEmpty { return .agentProfile(id: roleKey) }
        return .chatRole(id: id)
    }
}

/// Размеры ряда. Слой полёта и настоящий ряд считают места по одним числам,
/// иначе в момент подмены кружки дёрнутся.
enum ChatStoriesLayout {
    /// Кружок в ряду.
    /// Кружок в ряду — 68 pt (владелец 12.11.2026: «совсем маленькие, увеличить»;
    /// было 52).
    static let avatar = TFAvatar.Size.taskList
    /// Кружок вместе с кольцом.
    static let box: CGFloat = avatar.rawValue + 8
    /// Кружок в стопке у заголовка.
    static let stackSize: CGFloat = 30
    /// Шаг кружков в стопке (они наезжают друг на друга).
    static let stackStep: CGFloat = 18
    /// Сколько кружков лежит в стопке (владелец 12.11.2026: «не три, а пять»).
    static let stackCount = 5
    /// Ширина места одной роли в ряду.
    static let cell: CGFloat = 80
    static let topPadding: CGFloat = TFSpacing.xs
    static let nameGap: CGFloat = 4
    static let nameHeight: CGFloat = 18
    static let bottomPadding: CGFloat = TFSpacing.xs
    /// Отступ ряда слева: кружок первой роли стоит по краю текста списка.
    static let leading: CGFloat = max(0, TFSpacing.screenHorizontal - (cell - box) / 2)
    static let rowHeight: CGFloat = topPadding + box + nameGap + nameHeight + bottomPadding
    /// Поле поиска с отступом под ним.
    static let fieldHeight: CGFloat = 40
    static let searchHeight: CGFloat = fieldHeight + TFSpacing.xs

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
    /// Наибольшая виденная высота ленты: из неё считается нижний отступ.
    @ObservationIgnored var fullHeight: CGFloat = 0

    /// 0 — кружки в стопке, 1 — в ряду.
    var progress: CGFloat {
        min(1, max(0, 1 - offset / ChatStoriesLayout.rowHeight))
    }
}

/// Отпустил ленту, когда ряд виден наполовину, — она доезжает до ближайшего
/// края: ряд либо раскрыт целиком, либо спрятан. Дальше ряда не вмешивается.
struct ChatStoriesSnap: ScrollTargetBehavior {
    var rowHeight: CGFloat
    /// Высота поля поиска: оно тоже доводится — либо видно целиком, либо
    /// сжато в ноль (как в Telegram, владелец 12.11.2026).
    var searchHeight: CGFloat = ChatStoriesLayout.searchHeight
    /// Короткий список (добран пустым местом): дальше схлопнутого поиска он не
    /// уезжает — строки не прячутся под полоску проектов, после прокрутки
    /// список возвращается к ней (владелец 12.11.2026: «не должен заезжать за
    /// эту панельку»). `nil` — список длинный, прокручивается как обычно.
    var limit: CGFloat? = nil

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        let y = target.rect.minY
        if let limit, y > limit {
            target.rect.origin.y = limit
        } else if rowHeight > 0, y > 0, y < rowHeight {
            target.rect.origin.y = y < rowHeight / 2 ? 0 : rowHeight
        } else if y > rowHeight, y < rowHeight + searchHeight {
            target.rect.origin.y = y < rowHeight + searchHeight / 2 ? rowHeight : rowHeight + searchHeight
        }
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
                // Кружок не растёт и не сжимается вслед за системным размером
                // текста: место под него в ряду постоянное (76), и на телефоне
                // с мелким текстом кружок выходил 54 pt — вокруг пустота, до
                // подписи большой зазор (владелец 12.11.2026, скриншот).
                .environment(\.dynamicTypeSize, .large)
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
                    NavigationLink(value: story.destination) {
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
        // Кружки живут в полосе между шапкой и поиском и уменьшаются, когда
        // она сужается (как в Telegram). Стоя на месте ряда в покое, они
        // уходили под поиск; поднимаясь с лентой в полный размер — наезжали
        // на шапку и её кнопки (владелец 12.11.2026).
        let rowTop = motion.topInset - motion.offset
        let stackScale = ChatStoriesLayout.stackSize / ChatStoriesLayout.box
        let searchTop = rowTop + ChatStoriesLayout.rowHeight
        let bandTop = motion.topInset + ChatStoriesLayout.topPadding
        let fit = (searchTop - ChatStoriesLayout.topPadding - bandTop) / ChatStoriesLayout.box
        let bandScale = min(1, max(stackScale, fit))
        let rowY = bandTop + ChatStoriesLayout.box * bandScale / 2

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
                let scale = bandScale + (stackScale - bandScale) * lift
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
                              y: rowTop + ChatStoriesLayout.topPadding + ChatStoriesLayout.box + ChatStoriesLayout.nameGap + ChatStoriesLayout.nameHeight / 2)
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
/// Подпись та же, что у системного поиска на экранах ролей. Плоская «впадина»
/// системной заливки полей, без стекла — как в Telegram.
struct ChatsSearchField: View {
    @Binding var text: String
    /// Откуда брать прокрутку для сжатия; нет — поле обычное.
    var motion: ChatStoriesMotion? = nil
    /// Сколько ленты над полем (ряд ролей): сжатие начинается после него.
    var rowHeight: CGFloat = 0
    @FocusState private var focused: Bool

    var body: some View {
        // Как в Telegram (владелец 12.11.2026, скриншоты): при прокрутке вверх
        // поле не уезжает под шапку, а сжимается на месте в полоску и
        // пропадает. Место в ленте прежнее — меняется только рисунок.
        let shrink = min(ChatStoriesLayout.fieldHeight, max(0, (motion?.offset ?? 0) - rowHeight))
        let visible = ChatStoriesLayout.fieldHeight - shrink
        field
            .opacity(Double(max(0, 1 - shrink / (ChatStoriesLayout.fieldHeight * 0.5))))
            .frame(height: visible, alignment: .bottom)
            .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
            .clipShape(Capsule())
            .frame(height: ChatStoriesLayout.fieldHeight, alignment: .top)
            .offset(y: shrink)
            .padding(.horizontal, TFSpacing.screenHorizontal)
            .padding(.bottom, TFSpacing.xs)
            .zIndex(1)
    }

    private var field: some View {
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
        .frame(height: ChatStoriesLayout.fieldHeight)
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

/// Папки сессий — проекты TaskFlow, полоской под поиском, как папки в Telegram
/// (владелец 12.11.2026: «нижнюю пилюлину — что-то вроде проектов, куда какие
/// сессии собирать»). «Все» — без фильтра.
///
/// Стекло — как у поля ввода: сама полоска стеклянная, выбранный проект
/// подсвечен стеклянной линзой, и линза переезжает между пунктами (владелец:
/// «эффект стекла должен на нём перемещаться»). Шрифт — группа «Проекты» в
/// «Настройки → Шрифт».
struct ChatsFolderBar: View {
    /// Что можно сделать с проектом из меню по долгому тапу.
    struct Actions {
        var edit: (ApiProject) -> Void
        var addSessions: (ApiProject) -> Void
        /// Новый порядок после «Изменить порядок → Готово».
        var reorder: ([ApiProject]) -> Void
        var export: (ApiProject) -> Void
        var delete: (ApiProject) -> Void
    }

    let projects: [ApiProject]
    @Binding var selected: String
    var actions: Actions? = nil
    @Namespace private var lens
    /// Режим правки (владелец 12.11.2026 вместо «Левее/Правее»): плашки
    /// таскают пальцем внутри той же стеклянной полоски, у каждой крестик.
    /// Кнопки «Готово» нет — правка кончается тапом по пустому месту
    /// (владелец: «готово, когда я просто щелкнул в пустое поле»), тогда
    /// и сохраняется порядок. Экран снимает флаг тапом по списку.
    @Binding var editing: Bool
    @State private var order: [ApiProject] = []
    @State private var dragging: ApiProject?

    var body: some View {
        strip
        .folderBarSurface()
        .onChange(of: projects) { _, list in
            // Удалённый крестиком проект уходит и из правки.
            if editing { order = order.filter { list.contains($0) } }
        }
        .onChange(of: editing) { _, isOn in
            guard !isOn else { return }
            if order.map(\.id) != projects.map(\.id), !order.isEmpty { actions?.reorder(order) }
            dragging = nil
        }
        .padding(.horizontal, TFSpacing.screenHorizontal)
        // Зазор от поиска вдвое больше прежнего (владелец 12.11.2026).
        .padding(.top, TFSpacing.xs)
        .padding(.bottom, TFSpacing.xs)
    }

    private var strip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: editing ? TFSpacing.sm : 2) {
                    if editing {
                        ForEach(order) { project in editChip(project) }
                    } else {
                        item(title: "Все", id: "")
                        ForEach(projects) { project in
                            item(title: project.name, id: project.id)
                                .contextMenu { if let actions { menu(project, actions) } }
                        }
                    }
                }
                .padding(4)
            }
            .scrollIndicators(.hidden)
            // Пустое место полоски заканчивает правку; плашки и крестики —
            // свои кнопки и жесты, им этот тап не мешает.
            .contentShape(Rectangle())
            .onTapGesture { if editing { withAnimation(TFMotion.standard) { editing = false } } }
            .onChange(of: selected) { _, id in
                withAnimation(TFMotion.standard) { proxy.scrollTo(id.isEmpty ? "all" : id, anchor: .center) }
            }
        }
    }

    /// Меню проекта (владелец 12.11.2026): настройки — те же, что в
    /// «Проектах»; плюс собрать сессии в проект, порядок, экспорт, удаление.
    @ViewBuilder
    private func menu(_ project: ApiProject, _ actions: Actions) -> some View {
        Button { actions.edit(project) } label: { Label("Изменить", systemImage: "pencil") }
        Button { actions.addSessions(project) } label: { Label("Добавить сессии", systemImage: "plus.bubble") }
        if projects.count > 1 {
            Button {
                order = projects
                withAnimation(TFMotion.standard) { editing = true }
            } label: { Label("Изменить порядок", systemImage: "arrow.left.arrow.right") }
        }
        Button { actions.export(project) } label: {
            Label("Экспорт сессий в Markdown", systemImage: "square.and.arrow.up")
        }
        Button(role: .destructive) { actions.delete(project) } label: { Label("Удалить", systemImage: "trash") }
    }

    private func item(title: String, id: String) -> some View {
        let isOn = selected == id
        let group = TFTypeGroup.projects
        return Button {
            withAnimation(TFMotion.standard) { selected = id }
        } label: {
            Text(title)
                .font(TFTypeFace.saved(for: .app, group: group.rawValue).font(size: group.size, weight: .semibold))
                // Выбранный пункт красный, как вкладка нижней панели
                // (владелец 12.11.2026: «где линза — чтобы тоже красным рисовала»).
                .foregroundStyle(isOn ? Color.tfRed : Color.tfSub)
                .lineLimit(1)
                .padding(.horizontal, TFSpacing.md)
                .frame(minHeight: 34)
                .background {
                    if isOn { FolderSelection().matchedGeometryEffect(id: "lens", in: lens) }
                }
        }
        .buttonStyle(.plain)
        .id(id.isEmpty ? "all" : id)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier("chats.folder.\(id.isEmpty ? "all" : id)")
    }
}

extension ChatsFolderBar {
    /// Плашка проекта в режиме правки: своё стекло, крестик на углу,
    /// перетаскивается пальцем.
    private func editChip(_ project: ApiProject) -> some View {
        let group = TFTypeGroup.projects
        return Text(project.name)
            .font(TFTypeFace.saved(for: .app, group: group.rawValue).font(size: group.size, weight: .semibold))
            .foregroundStyle(Color.tfText)
            .lineLimit(1)
            .padding(.horizontal, TFSpacing.md)
            .frame(minHeight: 34)
            .background { FolderLens() }
            .overlay(alignment: .topLeading) {
                Button { actions?.delete(project) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.tfText, Color(uiColor: .systemGray3))
                        .tfTypeFont(size: 16)
                }
                .buttonStyle(.plain)
                .offset(x: -4, y: -4)
                .accessibilityLabel("Удалить \(project.name)")
            }
            .opacity(dragging == project ? 0.4 : 1)
            .onDrag {
                dragging = project
                return NSItemProvider(object: project.id as NSString)
            }
            .onDrop(of: [.text], delegate: FolderDrop(target: project, order: $order, dragging: $dragging))
            .accessibilityIdentifier("chats.folder.edit.\(project.id)")
    }
}

/// Перетаскивание плашки: соседи расступаются, пока палец над ними.
private struct FolderDrop: DropDelegate {
    let target: ApiProject
    @Binding var order: [ApiProject]
    @Binding var dragging: ApiProject?

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target,
              let from = order.firstIndex(of: dragging), let to = order.firstIndex(of: target) else { return }
        withAnimation(TFMotion.standard) {
            order.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

/// Линза выбранного проекта: на iOS 26 — стекло, раньше — системная заливка.
private struct FolderLens: View {
    var body: some View {
        if #available(iOS 26.0, *) {
            Capsule().fill(.clear).glassEffect(.regular.interactive(), in: Capsule())
        } else {
            Capsule().fill(Color(uiColor: .secondarySystemFill))
        }
    }
}

/// Подложка выбранного проекта — как у выбранной вкладки нижней панели:
/// тёмная капсула внутри стекла, а не своё светлое стекло (владелец
/// 12.11.2026: «точно такой же компонент, как нижняя панель»).
private struct FolderSelection: View {
    var body: some View {
        Capsule().fill(Color.tfFieldDark)
    }
}

private extension View {
    /// Полоска целиком — то же стекло, что у нижней панели вкладок: отзывается
    /// на касание; раньше iOS 26 — заливка полей.
    @ViewBuilder
    func folderBarSurface() -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.interactive(), in: Capsule())
        } else {
            background(Color(uiColor: .tertiarySystemFill), in: Capsule()).clipShape(Capsule())
        }
    }
}

/// «Добавить сессии» в проект: сессии Помощника с галочками; отмеченные
/// кладутся в проект, снятые — достаются из него.
struct ChatsProjectSessionsSheet: View {
    struct Session: Identifiable {
        let id: String
        let title: String
        let projectID: String?
    }

    let project: ApiProject
    let sessions: [Session]
    let onDone: (_ add: [String], _ remove: [String]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: Set<String> = []

    var body: some View {
        NavigationStack {
            List(sessions) { session in
                Button {
                    if chosen.contains(session.id) { chosen.remove(session.id) } else { chosen.insert(session.id) }
                } label: {
                    HStack {
                        Text(session.title).tfText(.body).foregroundStyle(Color.tfText).lineLimit(2)
                        Spacer()
                        if chosen.contains(session.id) {
                            Image(systemName: "checkmark").foregroundStyle(Color.tfText)
                        }
                    }
                }
                .accessibilityAddTraits(chosen.contains(session.id) ? .isSelected : [])
            }
            .navigationTitle(project.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        let before = Set(sessions.filter { $0.projectID == project.id }.map(\.id))
                        onDone(Array(chosen.subtracting(before)), Array(before.subtracting(chosen)))
                        dismiss()
                    }
                }
            }
            .onAppear { chosen = Set(sessions.filter { $0.projectID == project.id }.map(\.id)) }
        }
    }
}
