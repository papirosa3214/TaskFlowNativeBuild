import SwiftUI
import UIKit

/// Строка ленты для нативной коллекции: что рисовать и в какой версии.
struct ChatFeedVirtualRow: Hashable {
    let id: String
    /// Версия содержимого строки: та же строка с новой версией перестраивается,
    /// с прежней — остаётся как была.
    let version: Int
}

/// Команды ленты снаружи: экран просит ленту подвинуться, а не ведёт смещение
/// сам (это делает таблица — она одна знает измеренные высоты).
@MainActor
final class ChatFeedScrollHandle {
    enum Anchor { case top, bottom }

    fileprivate weak var list: ChatFeedTableView?
    fileprivate var indexByID: [String: Int] = [:]

    /// Встать к низу и снова идти за ним.
    func scrollToBottom(animated: Bool = true) {
        guard let list else { return }
        list.followsBottom = true
        list.scrollToBottom(animated: animated)
    }

    /// Встать к конкретной строке (переход по оглавлению, «в ответ на»).
    func scroll(to id: String, anchor: Anchor = .top, animated: Bool = true) {
        guard let list, let index = indexByID[id] else { return }
        list.followsBottom = false
        list.scroll(toRow: index, anchor: anchor, animated: animated)
    }
}

/// Лента чата на `UITableView`: живут только видимые строки, высота каждой
/// меряется нативно по содержимому, ячейки переиспользуются.
///
/// Владелец 10.11.2026: «поведение ленты прям нравится, ноль тупняка, в отличие
/// от моего чата». Лента была `ScrollView` с обычным `VStack`: все строки окна
/// монтировались сразу, вместе со всеми сегментами ответов (22–27 тыс. pt на
/// окно), и раскладка шла на каждый тик живого хода. T3 Code держит ленту
/// виртуальным списком (`LegendList`) — живут только видимые строки, высота
/// измеренная, а не угаданная. Здесь то же самое средствами UIKit.
final class ChatFeedTableView: UITableView {
    /// Лента идёт за низом, пока владелец сам не отлистал вверх.
    var followsBottom = true

    private var isAdjustingOffset = false

    func scrollToBottom(animated: Bool) {
        layoutIfNeeded()
        let target = ChatFeedScrollPolicy.bottomOffset(contentHeight: contentSize.height,
                                                       viewport: bounds.height,
                                                       insetTop: contentInset.top,
                                                       insetBottom: contentInset.bottom)
        guard abs(contentOffset.y - target) > 0.5 else { return }
        setContentOffset(CGPoint(x: 0, y: target), animated: animated)
    }

    func scroll(toRow index: Int, anchor: ChatFeedScrollHandle.Anchor, animated: Bool) {
        guard numberOfSections > 0, index >= 0, index < numberOfRows(inSection: 0) else { return }
        layoutIfNeeded()
        setContentOffset(CGPoint(x: 0, y: offset(forRow: index, anchor: anchor)), animated: animated)
        // Виртуальная лента знает только измеренные высоты: после первого
        // перехода цель может оказаться не на месте — доводим шагами.
        guard !animated else { return }
        for _ in 0..<3 {
            layoutIfNeeded()
            let target = offset(forRow: index, anchor: anchor)
            guard abs(contentOffset.y - target) > 0.5 else { return }
            setContentOffset(CGPoint(x: 0, y: target), animated: false)
        }
    }

    private func offset(forRow index: Int, anchor: ChatFeedScrollHandle.Anchor) -> CGFloat {
        let rect = rectForRow(at: IndexPath(row: index, section: 0))
        switch anchor {
        case .top: return rect.minY - contentInset.top
        case .bottom: return rect.maxY - bounds.height + contentInset.bottom
        }
    }

    /// Ширина, под которой собраны видимые строки. Пересборка идёт из
    /// `updateUIView`, а не из `layoutSubviews`: `reloadData` внутри раскладки
    /// запускал раскладку заново, и прокрутка становилась «липкой»
    /// (владелец 10.11.2026).
    var rowWidth: CGFloat = 0

    override func layoutSubviews() {
        super.layoutSubviews()
        // Рост содержимого лента больше НЕ догоняет сама. Раньше здесь каждый
        // кадр печати доводил смещение к низу: пока ответ растёт, всё, что выше
        // (в том числе последнее сообщение владельца), ползло вверх рывками по
        // мере измерения высоты строки (владелец 10.11.2026: «скачет последнее
        // моё сообщение при живом ходе»). Теперь низ держится только вставкой
        // новых строк, а растущий ответ растёт вниз, ничего не сдвигая.
    }
}

/// Идентификатор переиспользования ячейки ленты. Вынесен из обобщённых типов:
/// статическое хранимое свойство внутри generic-типа Swift не разрешает.
private let chatFeedRowReuseID = "chat.feed.row"

/// Ячейка ленты: содержимое — SwiftUI-строка, высоту меряет система.
final class ChatFeedHostingCell: UITableViewCell {
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none
        backgroundConfiguration = .clear()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// Виртуальная лента чата: строки создаются только для видимого участка.
struct ChatFeedVirtualList<Row: View>: UIViewRepresentable {
    var rows: [ChatFeedVirtualRow]
    /// Другая переписка — сброс: лента открывается у низа.
    var contentKey: String
    var handle: ChatFeedScrollHandle
    var contentInsets: UIEdgeInsets
    var horizontalPadding: CGFloat
    var rowSpacing: CGFloat
    /// Оценка высоты строки до её измерения. У ленты длинные строки (тысячи
    /// пунктов), и грубая оценка в 260 pt заставляла UIKit постоянно
    /// поправлять смещение — прокрутка «липла» (владелец 10.11.2026).
    var estimatedHeight: (String) -> CGFloat
    var onNearBottomChange: (Bool) -> Void
    var onScrollingChange: (Bool) -> Void
    var onNearTop: () -> Void
    let row: (String) -> Row

    init(rows: [ChatFeedVirtualRow],
         contentKey: String,
         handle: ChatFeedScrollHandle,
         // Верх и низ добирает безопасная область (шапка и панель ввода);
         // боковые поля — у самой строки (`horizontalPadding`), иначе левое и
         // правое поле выходили разными (владелец 10.11.2026).
         contentInsets: UIEdgeInsets = UIEdgeInsets(top: TFSpacing.sm, left: 0,
                                                    bottom: TFSpacing.sm, right: 0),
         horizontalPadding: CGFloat = TFSpacing.lg,
         rowSpacing: CGFloat = TFSpacing.md,
         estimatedHeight: @escaping (String) -> CGFloat = { _ in 600 },
         onNearBottomChange: @escaping (Bool) -> Void = { _ in },
         onScrollingChange: @escaping (Bool) -> Void = { _ in },
         onNearTop: @escaping () -> Void = {},
         @ViewBuilder row: @escaping (String) -> Row) {
        self.rows = rows
        self.contentKey = contentKey
        self.handle = handle
        self.contentInsets = contentInsets
        self.horizontalPadding = horizontalPadding
        self.rowSpacing = rowSpacing
        self.estimatedHeight = estimatedHeight
        self.onNearBottomChange = onNearBottomChange
        self.onScrollingChange = onScrollingChange
        self.onNearTop = onNearTop
        self.row = row
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> ChatFeedTableView {
        let table = ChatFeedTableView(frame: .zero, style: .plain)
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.separatorStyle = .none
        table.backgroundColor = .clear
        // Безопасную область считает сама таблица: только так содержимое уходит
        // под шапку и панель ввода, и работает штатное затухание Apple у
        // кромок (владелец 10.11.2026: «сплошняком идёт низ и верх экрана без
        // режима затухания эпл»).
        table.contentInsetAdjustmentBehavior = .automatic
        table.alwaysBounceHorizontal = false
        table.showsHorizontalScrollIndicator = false
        // Лента вертикальная: диагональный жест не должен уводить её вбок.
        table.isDirectionalLockEnabled = true
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 600
        table.keyboardDismissMode = .interactive
        table.showsVerticalScrollIndicator = false
        table.register(ChatFeedHostingCell.self, forCellReuseIdentifier: chatFeedRowReuseID)
        if #available(iOS 26.0, *) {
            // Обе кромки — штатное затухание Apple, своё у экрана чата не
            // рисуется: сверху шапка, снизу панель ввода. Раньше нижнее было
            // выключено ради «полностью прозрачного низа», теперь владелец
            // 10.11.2026 просит нативное стекло с двух сторон.
            table.topEdgeEffect.style = .soft
            table.bottomEdgeEffect.style = .soft
        }
        context.coordinator.attach(table)
        handle.list = table
        return table
    }

    func updateUIView(_ table: ChatFeedTableView, context: Context) {
        context.coordinator.parent = self
        handle.list = table
        if table.contentInset != contentInsets { table.contentInset = contentInsets }
        if abs(table.rowWidth - table.bounds.width) > 0.5 {
            // Поворот, панель, другая ширина окна: строки собираются заново
            // под новую ширину — но только здесь, не во время раскладки.
            table.rowWidth = table.bounds.width
            context.coordinator.forceReload(in: table)
        }
        context.coordinator.apply(rows: rows, contentKey: contentKey, to: table)
    }

    static func dismantleUIView(_ uiView: ChatFeedTableView, coordinator: Coordinator) {
        coordinator.parent.handle.list = nil
    }

    @MainActor
    final class Coordinator: NSObject, UITableViewDataSource, UITableViewDelegate {
        var parent: ChatFeedVirtualList
        private var applied: [ChatFeedVirtualRow] = []
        private var appliedKey = ""
        private var isNearBottom = true
        private var isNearTop = false

        init(parent: ChatFeedVirtualList) {
            self.parent = parent
        }

        func attach(_ table: ChatFeedTableView) {
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            // Тап по пустому месту ленты снимает фокус поля ввода, но не
            // съедает нажатия по строкам.
            tap.cancelsTouchesInView = false
            table.addGestureRecognizer(tap)
        }

        @objc private func handleTap() {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                            to: nil, from: nil, for: nil)
        }

        func apply(rows: [ChatFeedVirtualRow], contentKey: String, to table: ChatFeedTableView) {
            let keyChanged = contentKey != appliedKey
            guard keyChanged || rows != applied else { return }
            let heightBefore = table.contentSize.height
            let offsetBefore = table.contentOffset.y
            let firstBefore = applied.first?.id
            let follows = keyChanged ? true : table.followsBottom

            applied = rows
            appliedKey = contentKey
            parent.handle.indexByID = Dictionary(rows.enumerated().map { ($0.element.id, $0.offset) },
                                                 uniquingKeysWith: { first, _ in first })
            if keyChanged { table.followsBottom = true }
            table.reloadData()
            table.layoutIfNeeded()

            if follows {
                table.scrollToBottom(animated: false)
            } else if let firstBefore, rows.first?.id != firstBefore {
                // Над видимой частью появились старые сообщения — держим на
                // экране то же место, что владелец видел.
                let delta = table.contentSize.height - heightBefore
                table.setContentOffset(CGPoint(x: 0, y: offsetBefore + delta), animated: false)
            }
        }

        func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
            guard indexPath.row < applied.count else { return 600 }
            return max(80, parent.estimatedHeight(applied[indexPath.row].id))
        }

        func forceReload(in table: ChatFeedTableView) {
            applied = []
            appliedKey = ""
            table.reloadData()
        }

        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            applied.count
        }

        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let cell = tableView.dequeueReusableCell(withIdentifier: chatFeedRowReuseID, for: indexPath)
            guard indexPath.row < applied.count else { return cell }
            let id = applied[indexPath.row].id
            let row = parent.row
            let spacing = parent.rowSpacing
            let side = parent.horizontalPadding
            let width = max(0, tableView.bounds.width - side * 2)
            cell.contentConfiguration = UIHostingConfiguration {
                row(id)
                    .frame(width: width, alignment: .leading)
                    .padding(.horizontal, side)
                    .padding(.bottom, spacing)
            }
            .margins(.all, 0)
            return cell
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            // Горизонтального движения у ленты нет совсем: широкое содержимое
            // строки (таблица, код) и отскок жеста всё равно возвращаются в
            // ноль — иначе лента «ёрзает влево-вправо» (владелец 10.11.2026).
            if abs(scrollView.contentOffset.x) > 0.5 {
                var offset = scrollView.contentOffset
                offset.x = 0
                scrollView.setContentOffset(offset, animated: false)
            }
            let position = ChatFeedScrollPolicy.position(contentHeight: scrollView.contentSize.height,
                                                         offset: scrollView.contentOffset.y,
                                                         viewport: scrollView.bounds.height,
                                                         insetTop: scrollView.contentInset.top,
                                                         insetBottom: scrollView.contentInset.bottom)
            if position.isNearBottom != isNearBottom {
                isNearBottom = position.isNearBottom
                parent.onNearBottomChange(position.isNearBottom)
            }
            if position.isNearTop != isNearTop {
                isNearTop = position.isNearTop
                if position.isNearTop { parent.onNearTop() }
            }
            guard let table = scrollView as? ChatFeedTableView else { return }
            let byUser = table.isTracking || table.isDragging || table.isDecelerating
            let follows = ChatFeedScrollPolicy.followsBottom(current: table.followsBottom,
                                                             isNearBottom: position.isNearBottom,
                                                             byUser: byUser)
            if follows != table.followsBottom { table.followsBottom = follows }
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            parent.onScrollingChange(true)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate { parent.onScrollingChange(false) }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            parent.onScrollingChange(false)
        }
    }
}
