import SwiftUI
import UIKit

/// Системный TabView: фон, линза, жесты и форма отдельного действия — Apple.
/// Приложение передаёт только свои иконки, подписи, бейджи и содержимое вкладок.
public struct TFPillTabBar<Content: View>: View {
    let items: [TFTabItem]
    @Binding var selectedIndex: Int?
    let onSelect: (Int) -> Void
    let onCreateTap: () -> Void
    private let content: (Int) -> Content
    @State private var calendarDay = Calendar.current.component(.day, from: Date())
    private let isTabBarVisible: Bool
    @Environment(\.displayScale) private var displayScale

    public init(
        items: [TFTabItem], selectedIndex: Binding<Int?>,
        isCreateMenuOpen: Bool, isTabBarVisible: Bool = true,
        onSelect: @escaping (Int) -> Void,
        onCreateTap: @escaping () -> Void,
        @ViewBuilder content: @escaping (Int) -> Content
    ) {
        self.items = items
        self._selectedIndex = selectedIndex
        self.onSelect = onSelect
        self.onCreateTap = onCreateTap
        self.content = content
        self.isTabBarVisible = isTabBarVisible
    }

    /// Выбор раздела. Плюс создания — действие: системный круг под нашим
    /// остаётся на месте и на его тап тоже открываем меню, а не выбираем раздел.
    var selectionBinding: Binding<Int?> {
        Binding(get: { selectedIndex }, set: { value in
            guard let value else { return }
            if value == items.count {
                onCreateTap()
            } else if items.indices.contains(value) {
                onSelect(value)
            }
        })
    }

    private var createRole: TabRole {
        if #available(iOS 27.0, *) { return .prominent }
        return .search
    }

    public var body: some View {
        TabView(selection: selectionBinding) {
            ForEach(items.indices, id: \.self) { index in
                SwiftUI.Tab(value: index) {
                    content(index)
                } label: {
                    Label { Text(items[index].accessibilityLabel) } icon: {
                        tabIcon(items[index], isSelected: selectedIndex == index)
                    }
                }
                .badge(items[index].badgeCount ?? 0)
                .accessibilityIdentifier(TFTabBar.identifier(for: items[index].icon))
            }
            // Системный prominent-круг: место справа, стекло, плюс и нажатие
            // всё его. Свой слой под ним пробовали — системное стекло
            // преломляет его в радужное пятно, поэтому круг остаётся системным.
            SwiftUI.Tab("Создать", systemImage: "plus", value: items.count, role: createRole) {
                EmptyView()
            }
            .accessibilityIdentifier("tab.add")
        }
        .tabViewStyle(.tabBarOnly)
        // Акцент приложения: выбранный ярлык с подписью красится в него сразу,
        // когда линза до него доходит.
        .tint(Color.tfRed)
        .overlay(alignment: .bottomTrailing) { createButtonOverlay }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            calendarDay = Calendar.current.component(.day, from: Date())
        }
    }

    /// Круг «+» живёт вместе с панелью: когда системный таббар скрыт
    /// (`.toolbar(.hidden, for: .tabBar)` на вложенном экране), круг тоже
    /// исчезает — иначе он остаётся висеть один в углу.
    private var createButtonOverlay: some View {
        createButton
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .opacity(isTabBarVisible ? 1 : 0)
            .allowsHitTesting(isTabBarVisible)
            .accessibilityHidden(!isTabBarVisible)
    }

    /// Круг «+» поверх системного prominent-круга.
    ///
    /// Системный круг покрасить нечем: API цвета у `TabRole.prominent` нет,
    /// `.tint`, своя подпись и глобальный акцент его игнорируют (проверено
    /// сборками 18.10.2026; см. `docs/2026-10-18-tabbar-accent.md`). Поэтому
    /// круг наш, и материал ему задаёт тинт стекла `glassEffect(_:in:)`.
    @ViewBuilder
    private var createButton: some View {
        Button(action: onCreateTap) {
            Image(systemName: "plus")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(Color.tfBackground)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tab.create.circle")
        .frame(width: createCircleSize, height: createCircleSize)
        .modifier(CreateCircleMaterial())
        .padding(.trailing, createCircleEdgeInset)
        .padding(.bottom, createCircleEdgeInset)
        .ignoresSafeArea(.container, edges: .bottom)
    }

    /// Геометрия круга — из иерархии симулятора, а не на глаз: системная
    /// кнопка «Создать» на iPhone Air (420×912 pt) имеет frame
    /// `{{337, 829}, 62×62}`, то есть 21 pt от правого и нижнего края экрана.
    /// Наш круг того же диаметра и с тем же отступом — совпадает с системным.
    private var createCircleSize: CGFloat { 62 }
    private var createCircleEdgeInset: CGFloat { 21 }

    private func tabIcon(_ item: TFTabItem, isSelected: Bool) -> Image {
        if item.showsTodayDate {
            return todayCalendarIcon(isSelected: isSelected)
        } else if let symbols = symbols(for: item.icon) {
            // Одна пара SF Symbols: контурный glyph в покое и его залитый вариант при выборе.
            let configuration = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
            let symbol = isSelected ? symbols.filled : symbols.outline
            if let image = UIImage(systemName: symbol, withConfiguration: configuration) {
                return Image(uiImage: image.withRenderingMode(.alwaysTemplate))
                    .renderingMode(.template)
            }
            return Image(systemName: symbol).renderingMode(.template)
        } else {
            return Image(item.icon).renderingMode(.template)
        }
    }

    private func todayCalendarIcon(isSelected: Bool) -> Image {
        // Перерисовать UIImage в день смены календаря.
        let _ = calendarDay
        let renderer = ImageRenderer(content: TFTodayDateIcon(
            size: TFTabBarMetrics.iconSize,
            isSelected: isSelected
        ))
        renderer.scale = displayScale
        guard let image = renderer.uiImage else { return Image("TabIconPlanning") }
        // Календарь и число — разного цвета, поэтому сохраняем результат без template tint.
        return Image(uiImage: image).renderingMode(.original)
    }

    private func symbols(for icon: String) -> (outline: String, filled: String)? {
        switch icon {
        case "TabIconHome": ("house", "house.fill")
        case "TabIconProjects": ("folder", "folder.fill")
        case "TabIconChat": ("bubble.left", "bubble.left.fill")
        default: nil
        }
    }
}

/// Материал круга «+»: тонированное Liquid Glass на iOS 26+, заливка ниже.
private struct CreateCircleMaterial: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(Color.tfRedSolid).interactive(), in: .circle)
        } else {
            content
                .background(Circle().fill(Color.tfRedSolid.opacity(0.86)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.28), lineWidth: 1))
        }
    }
}

extension TFPillTabBar where Content == EmptyView {
    public init(
        items: [TFTabItem], selectedIndex: Binding<Int?>,
        isCreateMenuOpen: Bool, isTabBarVisible: Bool = true,
        onSelect: @escaping (Int) -> Void,
        onCreateTap: @escaping () -> Void
    ) {
        self.init(items: items, selectedIndex: selectedIndex, isCreateMenuOpen: isCreateMenuOpen,
                  isTabBarVisible: isTabBarVisible,
                  onSelect: onSelect, onCreateTap: onCreateTap, content: { _ in EmptyView() })
    }
}
