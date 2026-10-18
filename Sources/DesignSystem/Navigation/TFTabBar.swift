import SwiftUI
import UIKit

// Нижняя навигация — spec/DESIGN-TOKENS.md §4 «Нижняя навигация» +
// spec/SCREENS-1.md §2.1 (уточнение координатора 31.08.2026, разведка
// подтвердила: `Layout.tsx` жёстко на `MOBILE_NAV_STYLE = "tabbar"`).
//
// ⚠️ РАСХОЖДЕНИЕ С ФОРМУЛИРОВКОЙ ЗАДАНИЯ: задание просило «панель с горбом»
// и «веер-меню создания». Оба пункта устарели относительно спеки:
// - горб/«пузырь» убран владельцем 27.08.2026 («по бокам кнопочки, никакого
//   горбика не надо») — панель ровная, без выступа;
// - FanMenu (боковой веер) в коде есть, но НЕ активен (`MOBILE_NAV_STYLE`
//   стоит `"tabbar"`, не `"fan"`); реальное меню создания — всплывающая
//   плоская карточка `CreateMenu` (см. `TFCreateMenu` в этом файле), не веер.
// Скриншоты (`today.png`, `overview.png`) подтверждают ровный ряд из 5
// элементов. Сделано по спеке — веер не строился, числами для него спека и
// не снабжает. Если нужен именно веер — это отдельная переработка после
// прямого указания владельца.
//
// Ровно 4 вкладки (2 слева / 2 справа от круглой кнопки создания), без
// подписей под иконками (только доступность), активная — красным.
public struct TFTabItem: Identifiable {
    public let id = UUID()
    let icon: String
    let accessibilityLabel: String
    /// Только у вкладки «Сегодня» — счётчик активных задач на сегодня.
    let badgeCount: Int?
    /// Вкладка «Сегодня» рисует не пустой значок календаря, а рамку с
    /// ЧИСЛОМ текущего дня — как в вебе (`TodayDateIcon` в UI.tsx) и как
    /// это делает системный «Календарь». Владелец 01.09.2026: «сегодня он
    /// отражает фактическую дату, у тебя она не отражается в иконке».
    let showsTodayDate: Bool

    public init(icon: String, accessibilityLabel: String, badgeCount: Int? = nil, showsTodayDate: Bool = false) {
        self.icon = icon
        self.accessibilityLabel = accessibilityLabel
        self.badgeCount = badgeCount
        self.showsTodayDate = showsTodayDate
    }
}

/// Значок календаря с числом сегодняшнего дня. Рисуется нативно в SwiftUI,
/// чтобы шаблонное tint-преобразование иконки не съедало контраст цифры.
///
/// Число берётся у системного календаря и обновляется по `NSCalendarDayChanged`
/// — штатному уведомлению о смене суток. Таймер на полночь (как в вебе) здесь
/// не нужен: система шлёт это уведомление и после возврата из фона, поэтому
/// число не застревает на вчерашнем, если телефон пролежал ночь в кармане.
struct TFTodayDateIcon: View {
    let size: CGFloat
    var isSelected = false
    var outlineColor: Color = .white
    @State private var day = Calendar.current.component(.day, from: Date())

    var body: some View {
        ZStack {
            if isSelected {
                RoundedRectangle(cornerRadius: size * 2 / 24)
                    .fill(Color.tfRed)
                    .frame(width: size * 18 / 24, height: size * 16 / 24)
                    .offset(y: size / 24)

                Rectangle()
                    .fill(Color.tfBackground)
                    .frame(width: size * 18 / 24, height: size * 1.25 / 24)
                    .offset(y: -size * 2 / 24)

                HStack(spacing: size * 6 / 24) {
                    Capsule().fill(Color.tfBackground)
                        .frame(width: size * 1.75 / 24, height: size * 4 / 24)
                    Capsule().fill(Color.tfBackground)
                        .frame(width: size * 1.75 / 24, height: size * 4 / 24)
                }
                .offset(y: -size * 7 / 24)
            } else {
                RoundedRectangle(cornerRadius: size * 2 / 24)
                    .stroke(outlineColor, lineWidth: size / 12)
                    .frame(width: size * 18 / 24, height: size * 16 / 24)
                    .offset(y: size / 24)

                Rectangle()
                    .fill(outlineColor)
                    .frame(width: size * 18 / 24, height: size / 12)
                    .offset(y: -size * 2 / 24)

                HStack(spacing: size * 6 / 24) {
                    Capsule().stroke(outlineColor, lineWidth: size / 16)
                        .frame(width: size * 1.75 / 24, height: size * 4 / 24)
                    Capsule().stroke(outlineColor, lineWidth: size / 16)
                        .frame(width: size * 1.75 / 24, height: size * 4 / 24)
                }
                .offset(y: -size * 7 / 24)
            }

            Text("\(day)")
                .font(.system(size: size * (day > 9 ? 0.34 : 0.38), weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(isSelected ? Color.black : outlineColor)
                .offset(y: size * 0.13)
                .zIndex(1)
        }
        .frame(width: size, height: size)
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            day = Calendar.current.component(.day, from: Date())
        }
    }
}

public struct TFTabBar: View {
    let items: [TFTabItem]
    @Binding var selectedIndex: Int?
    let isCreateMenuOpen: Bool
    let onSelect: (Int) -> Void
    let onCreateTap: () -> Void

    public init(
        items: [TFTabItem],
        selectedIndex: Binding<Int?>,
        isCreateMenuOpen: Bool,
        onSelect: @escaping (Int) -> Void,
        onCreateTap: @escaping () -> Void
    ) {
        precondition(items.count >= 2 && items.count <= 4, "Панель вкладок работает с 2–4 пунктами по бокам центральной кнопки")
        self.items = items
        self._selectedIndex = selectedIndex
        self.isCreateMenuOpen = isCreateMenuOpen
        self.onSelect = onSelect
        self.onCreateTap = onCreateTap
    }

    public var body: some View {
        let leftCount = items.count / 2
        return HStack(spacing: 0) {
            ForEach(0..<leftCount, id: \.self) { tabButton($0) }
            createButton
            ForEach(leftCount..<items.count, id: \.self) { tabButton($0) }
        }
        .frame(height: TFTabBarMetrics.heightCompact)
        .frame(maxWidth: .infinity)
        .background(alignment: .bottom) {
            // Общий слой начинается на середине красной кнопки и тянется
            // под нижнюю safe area до физического края экрана.
            ZStack(alignment: .top) {
                Color.tfBackground

                // Затухание привязано к верхней границе того же слоя.
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: Color.tfBackground.opacity(0.22), location: 0.34),
                        .init(color: Color.tfBackground.opacity(0.76), location: 0.70),
                        .init(color: Color.tfBackground, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 64)
                .offset(y: -64)
                .allowsHitTesting(false)
            }
            .frame(height: TFTabBarMetrics.heightCompact / 2)
            .ignoresSafeArea(edges: .bottom)
            .offset(y: 34)
        }
    }

    private func tabButton(_ index: Int) -> some View {
        let item = items[index]
        let isActive = selectedIndex == index
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onSelect(index)
        } label: {
            ZStack {
                TFGlassTabIcon(
                    size: TFTabBarMetrics.tabPlateSize,
                    tint: Color.tfRed,
                    isActive: isActive
                ) {
                    TFTabDrawIcon(
                        name: item.icon,
                        showsTodayDate: item.showsTodayDate,
                        isActive: isActive,
                        size: TFTabBarMetrics.tabIconSize * 0.625
                    )
                    // Активная иконка красная, неактивная — серая
                    // (владелец 11.10.2026).
                    .foregroundStyle(isActive ? Color.tfRed : Color.tfDim)
                }
                // Фиксируем квадрат: без этого рамки плашку растягивает
                // родитель по ширине и кнопка превращается в вертикальный овал.
                .frame(width: TFTabBarMetrics.tabPlateSize, height: TFTabBarMetrics.tabPlateSize)

            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, TFTabBarMetrics.itemVerticalPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(TFGlassTabStyle())
        .animation(.easeOut(duration: TFAnimation.tabSwitch), value: isActive)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityLabel(item.accessibilityLabel)
        .accessibilityIdentifier(Self.identifier(for: item.icon))
    }

    /// Стабильный идентификатор вкладки по имени её ассета. Не завязан на локаль.
    static func identifier(for icon: String) -> String {
        switch icon {
        case "TabIconToday": return "tab.today"
        case "TabIconHome": return "tab.directory"
        case "TabIconProjects": return "tab.projects"
        case "TabIconPlanning": return "tab.upcoming"
        case "TabIconChat": return "tab.chat"
        default: return "tab.\(icon)"
        }
    }

    private var createButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onCreateTap()
        } label: {
            TFGlassTabIcon(size: TFTabBarMetrics.createButtonSize, tint: .tfRed,
                           isActive: isCreateMenuOpen, circular: true, surfaceTint: .tfRed) {
                Image(systemName: "plus")
                    .font(.system(size: TFTabBarMetrics.iconSize, weight: .semibold))
                    .foregroundStyle(.black)
                    .rotationEffect(.degrees(isCreateMenuOpen ? 45 : 0))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(TFGlassTabStyle())
        .animation(.easeOut(duration: TFAnimation.createMenu), value: isCreateMenuOpen)
        .accessibilityLabel(isCreateMenuOpen ? "Закрыть меню создания" : "Создать")
        .accessibilityIdentifier("tab.add")
    }
}

// MARK: - CreateMenu

/// Пункт всплывающей карточки «что создать».
public struct TFCreateMenuItem: Identifiable {
    public let id = UUID()
    let icon: String
    let title: String
    let subtitle: String?
    let action: () -> Void

    public init(icon: String, title: String, subtitle: String? = nil, action: @escaping () -> Void) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.action = action
    }
}

/// Всплывающая карточка над центральной кнопкой (`CreateMenu.tsx`) — НЕ веер.
/// 232px, радиус 16, раскрывается вверх от кнопки, opacity+scale(.95→1) 200ms.
public struct TFCreateMenu: View {
    let items: [TFCreateMenuItem]

    public init(items: [TFCreateMenuItem]) {
        self.items = items
    }

    /// Стабильный identifier для пункта меню по его title (русскому).
    static func identifier(for title: String) -> String {
        switch title {
        case "Задача": return "create.task"
        case "Заметка": return "create.note"
        case "Проект": return "create.project"
        default: return "create.\(title.lowercased())"
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Rectangle().fill(Color.tfStroke).frame(height: TFBorder.width)
                }
                Button(action: item.action) {
                    HStack(spacing: TFSpacing.md) {
                        RoundedRectangle(cornerRadius: TFCreateMenuMetrics.itemIconSlotRadius)
                            .fill(Color.white.opacity(0.1))
                            .frame(width: TFCreateMenuMetrics.itemIconSlot, height: TFCreateMenuMetrics.itemIconSlot)
                            .overlay {
                                Image(systemName: item.icon)
                                    .font(.system(size: TFCreateMenuMetrics.itemIconSize))
                                    .foregroundStyle(Color.tfText)
                            }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).tfText(.body).fontWeight(.medium).foregroundStyle(Color.tfText)
                            if let subtitle = item.subtitle, !subtitle.isEmpty {
                                Text(subtitle).tfText(.meta).foregroundStyle(Color.tfSub)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, TFCreateMenuMetrics.itemPaddingH)
                    .padding(.vertical, TFCreateMenuMetrics.itemPaddingV)
                    .contentShape(Rectangle())
                }
                .buttonStyle(TFTapMenuStyle())
                .accessibilityLabel(item.title)
                .accessibilityIdentifier(Self.identifier(for: item.title))
            }
        }
        .frame(width: TFCreateMenuMetrics.width)
        .background(Color.tfCard)
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.xl))
        .overlay(RoundedRectangle(cornerRadius: TFRadius.xl).strokeBorder(Color.tfStroke, lineWidth: TFBorder.width))
        .tfShadow(TFShadow.popover)
    }
}

/// `tap-menu`: пункт во всплывающем меню, поверхность на 1 уровень выше — 6% подсветка.
public struct TFTapMenuStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.white.opacity(0.06) : .clear)
    }
}

#Preview("Таббар") {
    VStack {
        Spacer()
        TFTabBar(
            items: [
                TFTabItem(icon: "calendar", accessibilityLabel: "Сегодня", badgeCount: 3),
                TFTabItem(icon: "house", accessibilityLabel: "Обзор"),
                TFTabItem(icon: "calendar.badge.clock", accessibilityLabel: "Планирование"),
                TFTabItem(icon: "message", accessibilityLabel: "Чат"),
            ],
            selectedIndex: .constant(0),
            isCreateMenuOpen: false,
            onSelect: { _ in },
            onCreateTap: {}
        )
    }
    .background(Color.tfBackground)
}

#Preview("Меню создания") {
    ZStack(alignment: .bottom) {
        Color.tfBackground.ignoresSafeArea()
        VStack {
            TFCreateMenu(items: [
                TFCreateMenuItem(icon: "checkmark", title: "Задача") {},
                TFCreateMenuItem(icon: "book", title: "Заметка") {},
                TFCreateMenuItem(icon: "tray", title: "Проект") {},
            ])
            .padding(.bottom, TFCreateMenuMetrics.gapAboveTabBar + TFTabBarMetrics.heightCompact)
        }
    }
}
