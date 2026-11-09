import SwiftUI

// Карточка/секция и мелкие структурные примитивы — из общих правил спеки
// (радиус `xl`=16 для карточек, толщина границы 1px `stroke`, отступ экрана 16px).

/// Обёртка карточки общего назначения (статистика в «Обзоре», пункты списка
/// настроек и т.п.) — фон `card`, радиус 16px, без рамки по умолчанию (рамка
/// нужна только там, где карточка на том же фоне, что и подложка — задаётся снаружи).
///
/// Milestone 3, семейство F20: это ЕДИНСТВЕННАЯ карточка приложения. Раньше
/// та же подложка собиралась руками в 33 файлах — `.background(Color.tfCard)`
/// плюс свой `clipShape`. У такой сборки было два недостатка: подложка бралась
/// не из канона (а значит, могла разойтись с ним), и каждая копия решала
/// радиус по-своему. Теперь радиус и поверхность — параметры канона.
///
/// Поверхность: `.card` (обычная карточка) или `.card2` (вложенная вложенная
/// подложка — на тон темнее основной). Владелец 01.11.2026: две поверхности
/// НЕ сливать — они отличаются на 7 пунктов яркости, и это осознанно.
/// Радиус: по умолчанию `xl` (карточка), но у части мест был свой (`lg` — строка
/// карточки, `md` — компактная). Параметр существует, чтобы перевод НЕ менял
/// вид: те же числа, что стояли вручную.
public struct TFCard<Content: View>: View {
    /// Поверхность карточки.
    public enum Surface {
        /// Основная карточка — `tfCard`.
        case card
        /// Вложенная подложка — `tfCard2` (на тон темнее).
        case card2
        /// Тёмная подложка без рамки — карточки в чате (владелец 06.11.2026:
        /// «в чате вообще не должно быть ни у кого никакой окантовки»).
        case dark

        var color: Color {
            switch self {
            case .card: return .tfCard
            case .card2: return .tfCard2
            case .dark: return .tfFieldDark
            }
        }
    }

    let content: Content
    let padding: CGFloat
    let surface: Surface
    /// Радиус скругления. `nil` — подложка без скругления (прямоугольная
    /// плашка, как всплывающий список подсказок в чате).
    let radius: CGFloat?
    /// Окантовка как у полей рутины: тонкая тёмно-красная `tfFieldBorder`
    /// (владелец 03.11.2026 — скрин рутины, не светлый `tfStroke`).
    let bordered: Bool

    public init(
        padding: CGFloat = TFSpacing.lg,
        surface: Surface = .card,
        radius: CGFloat? = TFRadius.xl,
        bordered: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.surface = surface
        self.radius = radius
        self.bordered = bordered
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            // С окантовкой — почти чёрная подложка рутины, иначе светлый
            // `tfCard` и «толстая светлая линия» (жалоба владельца 03.11.2026).
            .background(bordered ? Color.tfFieldDark : surface.color)
            .modifier(ClipRadius(radius: radius))
            .modifier(TFCardBorder(radius: radius, enabled: bordered))
    }
}

/// В настройках красная кромка снята (владелец 10.11.2026): подложка и
/// отступы карточки остаются, рисуется только обводка.
struct TFSuppressRedOutlineKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var tfSuppressRedOutline: Bool {
        get { self[TFSuppressRedOutlineKey.self] }
        set { self[TFSuppressRedOutlineKey.self] = newValue }
    }
}

extension View {
    func tfSuppressRedOutline() -> some View {
        environment(\.tfSuppressRedOutline, true)
    }
}

/// Рамка рутины: 1px тёмно-красная, не полупрозрачная белая.
private struct TFCardBorder: ViewModifier {
    let radius: CGFloat?
    let enabled: Bool
    @Environment(\.tfSuppressRedOutline) private var suppressRedOutline

    func body(content: Content) -> some View {
        if enabled, let radius, !suppressRedOutline {
            content.overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.tfFieldBorder, lineWidth: TFBorder.width)
            )
        } else {
            content
        }
    }
}

/// Плитка выбора. В настройках красная кромка выбранной не рисуется.
private struct TFSelectTileModifier: ViewModifier {
    let selected: Bool
    let radius: CGFloat
    @Environment(\.tfSuppressRedOutline) private var suppressRedOutline

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.tfFieldDark)
            )
            .overlay {
                if selected && !suppressRedOutline {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(Color.tfFieldBorder, lineWidth: TFBorder.width)
                }
            }
    }
}

/// Подложка строки настроек. Красная кромка выбранной снимается тем же флагом.
private struct TFSettingsListRowBackground: View {
    let selected: Bool
    let fill: Color
    @Environment(\.tfSuppressRedOutline) private var suppressRedOutline

    var body: some View {
        ZStack {
            fill
            if selected && !suppressRedOutline {
                RoundedRectangle(cornerRadius: TFRadius.md, style: .continuous)
                    .strokeBorder(Color.tfFieldBorder, lineWidth: TFBorder.width)
                    .padding(1)
            }
        }
    }
}

/// Скругление по радиусу; `nil` — без скругления (прямоугольная подложка).
private struct ClipRadius: ViewModifier {
    let radius: CGFloat?

    func body(content: Content) -> some View {
        if let radius {
            content.clipShape(RoundedRectangle(cornerRadius: radius))
        } else {
            content
        }
    }
}

/// Заголовок секции — ОДИН компонент на два жанра (F19).
///
/// `.standard` — приглушённая подпись над группой карточек («Пользовательские
/// настройки», «Общие» на settings.png): 13 pt `tfSub`, отступы экрана.
/// `.caps` — тот же заголовок прописными полужирным («МОДЕЛИ И ГОЛОСА»): 13 pt
/// `tfSub`, вес `.semibold`, без своих отступов — их задаёт место.
///
/// Второго компонента-заголовка в приложении нет: отдельная обёртка
/// «капс-заголовка» удалена 01.11.2026 (F19), капс-режим живёт здесь.
public struct TFSectionHeader: View {
    /// Жанр заголовка раздела.
    public enum Style {
        /// Приглушённая подпись над группой карточек.
        case standard
        /// Прописными полужирным — как в «Моделях и голосах».
        case caps
    }

    let title: String
    let style: Style
    /// Необязательный правый слот заголовка (кнопка «+ Добавить» в шаблонах).
    let trailing: (() -> AnyView)?

    public init(
        _ title: String,
        style: Style = .standard,
        trailing: (() -> AnyView)? = nil
    ) {
        self.title = title
        self.style = style
        self.trailing = trailing
    }

    public var body: some View {
        switch style {
        case .standard:
            Text(title)
                .tfText(.action)
                .foregroundStyle(Color.tfSub)
                .padding(.horizontal, TFSpacing.screenHorizontal)
        case .caps:
            HStack {
                Text(title.uppercased())
                    .tfText(.action)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.tfSub)
                Spacer()
                trailing?()
            }
        }
    }
}

// Статусы-точки (`VoiceDotState`/`VoiceStatusDot`) УДАЛЕНЫ 20.09.2026 по
// требованию владельца: статус пишется СЛОВОМ («работает», «не работает»),
// цветных точек в приложении быть не должно.
/// Строка настроек/справочника с иконкой слева, заголовком, подписью и
/// шевроном справа — универсальный «пункт меню», из которого собираются
/// списки настроек/справочников.
///
/// `iconStyle` — просьба владельца 03.09.2026: похвалил именно `VoiceModelRow`
/// («Модели и голоса» — лаконично, не цветасто, только точки-индикаторы) и
/// попросил причесать под него Настройки/Обзор. `.tinted` (цветной квадрат-
/// плашка под иконкой) — старое поведение, оставлено по умолчанию ради
/// обратной совместимости с местами, которые этой правки не касаются
/// (`SearchScreen`); `.plain` — новый вариант, голая серая иконка без
/// подложки, тот же приём, что у `VoiceModelRow`/`TFFieldRow`.
///
/// `titleDot` — та же просьба: `ServerStatusSection` красил статус эмоджи
/// («🟢»/«🔴») прямо внутри длинной строки значения — вместе с длинным
/// заголовком это распирало ряд и текст переносился посреди слова. Точка
/// перед заголовком — компактный сигнал без эмодзи, тот же приём, что у
/// `VoiceModelRow`.
public struct TFListRow: View {
    public enum IconStyle {
        case tinted
        case plain
        case asset(String)
        /// Логотип по ссылке (сервисы Composio). Пока не загрузился или
        /// ссылки нет — `icon` как у `.plain`.
        case remote(URL?)
        /// Логотип сервиса, нарисованный заранее и положенный в бандл
        /// (`Resources/ComposioIcons`): серый силуэт на плитке одного цвета.
        /// Ключ сервиса — `github`, `linear` и т. п.
        case bundledLogo(String)
    }

    /// Режим шеврона справа.
    public enum Chevron {
        /// Как раньше: шеврон, когда у строки есть действие и нет своего
        /// правого слота.
        case auto
        /// Шеврона нет (своё значение справа, раскрывашка со своим знаком).
        case hidden
        /// Шеврон есть всегда — в том числе когда справа стоит своё значение.
        case shown
    }

    /// Свой ведущий слот (аватар, точка статуса) — вместо иконки.
    let leading: AnyView?
    let icon: String?
    let iconTint: Color
    let iconStyle: IconStyle
    let title: String
    let subtitle: String?
    let subtitleStyle: TFTextStyle
    /// Своя центральная колонка — когда заголовка/подписи не хватает
    /// (рупная подпись в профиле, несколько строк в строке агента).
    let content: AnyView?
    let trailing: AnyView?
    let action: (() -> Void)?
    let titleStyle: TFTextStyle
    let titleColor: Color
    let verticalPadding: CGFloat
    let horizontalPadding: CGFloat
    let spacing: CGFloat
    let alignment: VerticalAlignment
    let minHeight: CGFloat?
    let chevron: Chevron

    public init(
        icon: String? = nil,
        iconTint: Color = .tfRed,
        iconStyle: IconStyle = .tinted,
        leading: AnyView? = nil,
        title: String = "",
        subtitle: String? = nil,
        subtitleStyle: TFTextStyle = .action,
        content: AnyView? = nil,
        trailing: AnyView? = nil,
        titleStyle: TFTextStyle = .body,
        titleColor: Color = .tfText,
        verticalPadding: CGFloat = TFSpacing.md,
        horizontalPadding: CGFloat = TFSpacing.lg,
        spacing: CGFloat = TFSpacing.md,
        alignment: VerticalAlignment = .center,
        minHeight: CGFloat? = nil,
        chevron: Chevron = .auto,
        action: (() -> Void)? = nil
    ) {
        self.leading = leading
        self.icon = icon
        self.iconTint = iconTint
        self.iconStyle = iconStyle
        self.title = title
        self.subtitle = subtitle
        self.subtitleStyle = subtitleStyle
        self.content = content
        self.trailing = trailing
        self.titleStyle = titleStyle
        self.titleColor = titleColor
        self.verticalPadding = verticalPadding
        self.horizontalPadding = horizontalPadding
        self.spacing = spacing
        self.alignment = alignment
        self.minHeight = minHeight
        self.chevron = chevron
        self.action = action
    }

    public var body: some View {
        let row = HStack(alignment: alignment, spacing: spacing) {
            if let leading {
                leading
            } else if let icon {
                iconView
            }
            if let content {
                content
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .tfText(titleStyle)
                        .foregroundStyle(titleColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let subtitle {
                        Text(subtitle)
                            .tfText(subtitleStyle)
                            .foregroundStyle(Color.tfSub)
                            .lineLimit(1)
                    }
                }
            }
            Spacer()
            if let trailing {
                trailing
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .tfTypeFont(size: 13)
                    .foregroundStyle(Color.tfDim)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .contentShape(Rectangle())
        .frame(minHeight: minHeight)

        if let action {
            Button(action: action) { row }.buttonStyle(TFTapRowStyle())
        } else {
            row
        }
    }

    /// Шеврон рисуется, когда его просит режим, — и никогда не «вместо»
    /// правого слота: значение справа и шеврон уживаются.
    private var showsChevron: Bool {
        switch chevron {
        case .auto:
            action != nil && trailing == nil
        case .hidden:
            false
        case .shown:
            true
        }
    }

    @ViewBuilder
    private var iconView: some View {
        switch iconStyle {
        case .tinted:
            RoundedRectangle(cornerRadius: TFRadius.md)
                .fill(iconTint.opacity(0.18))
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: icon ?? "")
                        .tfTypeFont(size: TFIconSize.sm)
                        .foregroundStyle(iconTint)
                }
        case .asset(let name):
            Image(name)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: TFIconSize.sm, height: TFIconSize.sm)
                .foregroundStyle(Color.tfDim)
                .frame(width: 40, height: 40)
        case .plain:
            Image(systemName: icon ?? "")
                .tfTypeFont(size: TFIconSize.sm)
                .foregroundStyle(Color.tfDim)
                .frame(width: 40, height: 40)
        case .remote(let url):
            AsyncImage(url: url) { image in
                image.resizable().scaledToFit()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: TFRadius.sm))
            } placeholder: {
                Image(systemName: icon ?? "")
                    .tfTypeFont(size: TFIconSize.sm)
                    .foregroundStyle(Color.tfDim)
            }
            .frame(width: 40, height: 40)
        case .bundledLogo(let slug):
            ComposioServiceIcon(slug: slug, fallback: icon ?? "")
        }
    }
}

/// Разделитель между строками внутри карточки-списка (`TFListRow` и подобных) —
public extension View {
    /// Плитка выбора (сессия, тон текста, дни…): выбранная — `tfFieldDark` +
    /// тонкая `tfFieldBorder`; невыбранная — тот же фон без окантовки.
    /// Цвет иконки/текста задаёт вызывающий: выбранная → `tfText`, иначе
    /// `tfDim` (владелец 03.11.2026).
    func tfSelectTile(selected: Bool, radius: CGFloat = TFRadius.md) -> some View {
        modifier(TFSelectTileModifier(selected: selected, radius: radius))
    }

    /// Строка `List`/`Form` в настройках: одна сплошная группа как карточка
    /// рутины (без щелей → без «пилюль»), `tfFieldDark` + тонкая тёмно-красная
    /// окантовка у выбранной (владелец 03.11.2026). В настройках флаг
    /// `tfSuppressRedOutline` эту окантовку не рисует.
    func tfSettingsListRow(selected: Bool = false, background: Color = .tfFieldDark) -> some View {
        self
            .listRowInsets(EdgeInsets(
                top: 0, leading: TFSpacing.md,
                bottom: 0, trailing: TFSpacing.md
            ))
            .listRowSeparator(.visible, edges: .bottom)
            .listRowSeparatorTint(Color.tfStroke)
            .alignmentGuide(.listRowSeparatorLeading) { _ in TFSpacing.md }
            .alignmentGuide(.listRowSeparatorTrailing) { dimensions in
                dimensions.width - TFSpacing.md
            }
            .listRowBackground(TFSettingsListRowBackground(selected: selected, fill: background))
    }

    /// Список настроек поверх чёрного фона экрана, без серой системной подложки.
    func tfSettingsListChrome() -> some View {
        self
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .listSectionSpacing(TFSpacing.sm)
    }
}

/// 1px `stroke`, вставляется вручную между строками (спека держит инсет
/// разный по месту, поэтому не делаем это неявным поведением контейнера).
///
/// `dimmed` — вариант `stroke/50` (спека §4 «Строка задачи»: разделитель между
/// строками списка задач вдвое прозрачнее обычного, Tailwind `/50` умножает
/// альфу цвета на 50%, а не задаёт непрозрачность заново).
public struct TFDivider: View {
    let inset: CGFloat
    let dimmed: Bool
    public init(inset: CGFloat = 0, dimmed: Bool = false) {
        self.inset = inset
        self.dimmed = dimmed
    }
    public var body: some View {
        Rectangle()
            .fill(Color.tfStroke.opacity(dimmed ? 0.5 : 1))
            .frame(height: TFBorder.width)
            .padding(.leading, inset)
    }
}

#Preview("Карточки и списки") {
    ScrollView {
        VStack(alignment: .leading, spacing: TFSpacing.xl) {
            TFSectionHeader("Пользовательские настройки")
            TFCard(padding: 0) {
                VStack(spacing: 0) {
                    TFListRow(icon: "moon", title: "Тема", trailing: AnyView(Text("Тёмная").tfText(.body).foregroundStyle(Color.tfSub)))
                    TFDivider(inset: TFSpacing.lg + 40 + TFSpacing.md)
                    TFListRow(icon: "photo", title: "Иконка", trailing: AnyView(Text("Pure Minimal Glass").tfText(.body).foregroundStyle(Color.tfSub)), action: {})
                }
            }
        }
        .padding(.vertical, TFSpacing.lg)
    }
    .background(Color.tfBackground)
}
