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
    private let isTabBarVisible: Bool
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                        .background {
                            TabBarItemImagePairInstaller(
                                images: items.map { tabImages(for: $0) }
                            )
                            .frame(width: 0, height: 0)
                        }
                } label: {
                    Label { Text(items[index].accessibilityLabel) } icon: {
                        tabIcon(items[index])
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

    @ViewBuilder
    private func tabIcon(_ item: TFTabItem) -> some View {
        if let symbols = symbols(for: item.icon) {
            if let image = tabSymbol(named: symbols.outline) {
                Image(uiImage: image)
            }
        } else {
            Image(item.icon).renderingMode(.template)
        }
    }

    private func symbols(for icon: String) -> (outline: String, filled: String)? {
        switch icon {
        case "TabIconHome": ("house", "house.fill")
        case "TabIconProjects": ("folder", "folder.fill")
        case "TabIconPlanning", "TabIconToday": ("calendar", "calendar")
        case "TabIconChat": ("ellipsis.bubble", "ellipsis.bubble.fill")
        default: nil
        }
    }

    /// Keep the exact requested SF Symbol shape. A bitmap template still receives
    /// the native tab tint, but SwiftUI cannot substitute its automatic fill variant.
    private func tabSymbol(named name: String) -> UIImage? {
        let configuration = UIImage.SymbolConfiguration(pointSize: TFTabBarMetrics.iconSize, weight: .regular)
        guard let symbol = UIImage(systemName: name, withConfiguration: configuration) else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = displayScale
        let image = UIGraphicsImageRenderer(size: symbol.size, format: format).image { _ in
            symbol.withTintColor(.white, renderingMode: .alwaysOriginal)
                .draw(in: CGRect(origin: .zero, size: symbol.size))
        }
        return image.withRenderingMode(.alwaysTemplate)
    }

    private func tabImages(for item: TFTabItem) -> (normal: UIImage, selected: UIImage)? {
        guard let symbols = symbols(for: item.icon),
              let normal = tabSymbol(named: symbols.outline),
              let selected = tabSymbol(named: symbols.filled) else { return nil }
        return (normal.withRenderingMode(.alwaysTemplate), selected.withRenderingMode(.alwaysTemplate))
    }
}

/// Supplies both symbol states to UIKit's native tab item. UIKit owns the
/// selected-state transition; this probe only assigns its normal/selected images.
private struct TabBarItemImagePairInstaller: UIViewControllerRepresentable {
    let images: [(normal: UIImage, selected: UIImage)?]

    func makeUIViewController(context: Context) -> InstallerController {
        InstallerController()
    }

    func updateUIViewController(_ controller: InstallerController, context: Context) {
        controller.images = images
        controller.install()
        // SwiftUI may update tab labels later in the same render transaction.
        DispatchQueue.main.async { [weak controller] in controller?.install() }
    }

    final class InstallerController: UIViewController {
        var images: [(normal: UIImage, selected: UIImage)?] = []

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            install()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            install()
        }

        func install() {
            guard let tabController,
                  let items = tabController.tabBar.items else { return }
            // Install every pair: unopened tabs have no content controller yet.
            for (item, images) in zip(items, images) {
                guard let images else { continue }
                item.image = images.normal
                item.selectedImage = images.selected
            }
            tabController.tabBar.unselectedItemTintColor = .white
            tabController.tabBar.tintColor = UIColor(Color.tfRed)
        }

        private var tabController: UITabBarController? {
            var ancestor = parent
            while let current = ancestor {
                if let tabController = current as? UITabBarController { return tabController }
                ancestor = current.parent
            }
            return nil
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
