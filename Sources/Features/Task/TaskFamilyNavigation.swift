import SwiftUI
import UIKit

/// One native sheet, with an interactive horizontal transition inside it.
struct TaskFormScreen: View {
    @State private var model: TaskFormViewModel
    @State private var selectedCardID: String?
    @State private var models: [String: TaskFormViewModel] = [:]
    @State private var family: [ApiTask] = []
    @State private var familyNumbers: [String: Int] = [:]
    @State private var incoming: TaskFormViewModel?
    @State private var pull: CGFloat = 0
    @State private var pullingCardID: String?
    /// Насколько выехал хлястик под пальцем: 0 — узкий край, 1 — целиком.
    @State private var tabOut: CGFloat = 0
    @State private var expandedSectionsByCard: [String: Set<TaskDetailSection>] = [:]
    @State private var expandedSheet = false
    @State private var settling = false
    @State private var requestSwitch: ((String) -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let expanding: Bool

    init(taskID: String? = nil, presetDueToday: Bool = false, startDictation: Bool = false) {
        _model = State(initialValue: TaskFormViewModel(taskID: taskID, presetDueToday: presetDueToday, startDictation: startDictation))
        _selectedCardID = State(initialValue: taskID)
        expanding = false
    }

    init(expandingFrom viewModel: TaskFormViewModel) {
        _model = State(initialValue: viewModel)
        _selectedCardID = State(initialValue: nil)
        expanding = true
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.tfBackground.ignoresSafeArea()
                TaskCardContent(model: model, expanding: expanding, family: family,
                    onFamilyLoaded: receiveFamily,
                    onFamilySelected: { finishSelection($0, width: geometry.size.width) },
                    onSwitchAvailable: { requestSwitch = $0 },
                    onSelectionFailed: resetPull,
                    initialExpandedSections: expandedSections(for: model),
                    onExpandedSectionsChanged: { storeExpandedSections($0, for: model) })
                    .id(selectedCardID ?? "new")
                    .blur(radius: reduceMotion ? 0 : 3.2 * pullProgress(width: geometry.size.width))
                    .opacity(reduceMotion ? 1 : 1 - 0.14 * latePullProgress(width: geometry.size.width))
                    .overlay {
                        if pull > 0 {
                            Color.tfCard2
                                .opacity((reduceMotion ? 0.06 : 0.16) * pullProgress(width: geometry.size.width))
                                .allowsHitTesting(false)
                        }
                    }
                    .overlay {
                        if pull > 0 || settling {
                            Color.clear.contentShape(Rectangle()).onTapGesture {}.accessibilityHidden(true)
                        }
                    }
                    .zIndex(1)
                if let incoming, backToParent,
                   pull > 0 || (pullingCardID != nil && pullingCardID == incoming.taskID) {
                    // Владелец 02.10.2026: левая — зеркало правой. Родитель
                    // выезжает слева поверх открытого листа, хлястик — на
                    // его правой кромке.
                    TaskCardContent(model: incoming, expanding: false, family: [],
                        onFamilyLoaded: { _ in }, onFamilySelected: { _ in },
                        initialExpandedSections: expandedSections(for: incoming),
                        onExpandedSectionsChanged: { storeExpandedSections($0, for: incoming) },
                        preview: true)
                        .background {
                            UnevenRoundedRectangle(bottomTrailingRadius: 14, topTrailingRadius: 14)
                                .fill(Color.tfBackground)
                                .ignoresSafeArea()
                        }
                        .overlay(alignment: .trailing) {
                            TaskFamilyEdgeTabs.outlineColor
                                .frame(width: TaskFamilyEdgeTabs.outlineWidth)
                                .ignoresSafeArea()
                        }
                        .compositingGroup()
                        .shadow(color: TaskFamilyEdgeTabs.shadowColor, radius: TaskFamilyEdgeTabs.shadowRadius)
                        .offset(x: reduceMotion ? 0 : pull - geometry.size.width)
                        .opacity(reduceMotion ? pullProgress(width: geometry.size.width) : 1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .zIndex(2)
                    // Тень хлястика — копией под листом: на лист она не падает,
                    // стык остаётся бесшовным.
                    parentPullHandle(height: geometry.size.height, shadow: true)
                        .zIndex(1.5)
                    parentPullHandle(height: geometry.size.height, shadow: false)
                        .zIndex(3)
                } else if let incoming, !backToParent {
                    // Лист собирается заранее и ждёт за краем экрана: раньше
                    // он строился в момент касания, и первые пункты тяги
                    // подвисали до «присоединения» (владелец 02.10.2026).
                    let engaged = pull > 0 || (pullingCardID != nil && pullingCardID == incoming.taskID)
                    TaskCardContent(model: incoming, expanding: false, family: [],
                        onFamilyLoaded: { _ in }, onFamilySelected: { _ in },
                        initialExpandedSections: expandedSections(for: incoming),
                        onExpandedSectionsChanged: { storeExpandedSections($0, for: incoming) },
                        preview: true)
                        // Лист во всю высоту — под кнопками шапки и до низа,
                        // как у открытой карточки, без обрубка сверху и
                        // «подбородка» снизу (владелец 02.10.2026). Кнопки
                        // шапки остаются верхним слоем и не двигаются.
                        .background {
                            UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 14)
                                .fill(Color.tfBackground)
                                .ignoresSafeArea()
                        }
                        // Вместо тени — тонкая красная кромка листа; контур
                        // хлястика её продолжает (владелец 02.10.2026).
                        .overlay(alignment: .leading) {
                            TaskFamilyEdgeTabs.outlineColor
                                .frame(width: TaskFamilyEdgeTabs.outlineWidth)
                                .ignoresSafeArea()
                        }
                        .compositingGroup()
                        .shadow(color: TaskFamilyEdgeTabs.shadowColor, radius: TaskFamilyEdgeTabs.shadowRadius)
                        .offset(x: reduceMotion ? 0 : (engaged ? geometry.size.width - pull : geometry.size.width + 40))
                        .opacity(reduceMotion ? min(1, pull / geometry.size.width) : 1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .zIndex(2)
                    // Хлястик — отдельным слоем поверх листа и его тени, в
                    // координатах экрана: ровно слева от кромки листа, на
                    // высоте своего слота — там же, где стоял у края.
                    attachedPullHandle(height: geometry.size.height, width: geometry.size.width, shadow: true)
                        .zIndex(1.5)
                    attachedPullHandle(height: geometry.size.height, width: geometry.size.width, shadow: false)
                        .zIndex(3)
                }
            }
            .overlay(alignment: .trailing) {
                if expandedSheet && family.count > 1 && TaskFamilyEdgeTabs.children(of: family, selectedID: selectedCardID).count > 0 {
                    ZStack(alignment: .trailing) {
                        TaskFamilyEdgeZone()
                        TaskFamilyEdgeTabs(members: family, selectedID: selectedCardID,
                            height: geometry.size.height, width: geometry.size.width,
                            pull: $pull, pullingCardID: $pullingCardID, busy: settling,
                            prepare: prepare, select: select, cancel: resetPull)
                    }
                }
            }
            .overlay(alignment: .leading) {
                // Владелец 02.10.2026: «закладки — это дети, а к родителю —
                // слева». Тянется вправо: текущий лист уходит, родитель под ним.
                if expandedSheet, family.count > 1, let parent = currentParent {
                    ZStack(alignment: .leading) {
                        TaskFamilyEdgeZone()
                        TaskFamilyParentTab(parent: parent,
                            slotHeight: parentSlot(height: geometry.size.height).height,
                            slotOffset: parentSlot(height: geometry.size.height).offset,
                            width: geometry.size.width,
                            pull: $pull, pullingCardID: $pullingCardID, busy: settling,
                            prepare: prepare, select: select, cancel: resetPull)
                    }
                }
            }
            .background(TaskSheetExpansionProbe { expanded in
                if expandedSheet != expanded {
                    // UIKit already animates the detent. Do not start another
                    // animation transaction across the card's open List sections.
                    var transaction = Transaction(animation: nil)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { expandedSheet = expanded }
                }
                if !expanded && !settling && pull > 0 { resetPull() }
            })
        }
        .background(Color.tfBackground.ignoresSafeArea())
        .onChange(of: pullingCardID) { _, new in
            guard new != nil else { return }
            tabOut = 0
            withAnimation(reduceMotion ? nil : .spring(duration: 0.22, bounce: 0.05)) { tabOut = 1 }
        }
        // Отклик (02.10.2026): лёгкий удар, когда карточка приземлилась.
        .sensoryFeedback(.impact(weight: .light), trigger: selectedCardID)
        .environment(\.taskFamilyNumbers, familyNumbers)
        .task(id: model.taskID) {
            guard let id = model.taskID else { return }
            do {
                let api = APIClient()
                var card = try await api.task(id: id)
                var seen = Set<String>()
                while let parent = card.parentId, seen.insert(parent).inserted {
                    card = try await api.task(id: parent)
                }
                let plans = try await api.collaborationPlans(taskId: card.id)
                if let cards = plans.first(where: { $0.branchCards != nil })?.branchCards {
                    let numbers = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0.tabNumber) })
                    if familyNumbers != numbers { familyNumbers = numbers }
                }
            } catch { /* Older servers keep the existing bookmark numbering. */ }
        }
    }

    private func receiveFamily(_ members: [ApiTask]) {
        let incomingIDs = Set(members.map(\.id))
        family = family.filter { !incomingIDs.contains($0.id) } + members
        if let id = model.taskID { models[id] = model }
        for member in members where member.id != model.taskID && models[member.id] == nil {
            let candidate = TaskFormViewModel(taskID: member.id)
            candidate.isLoadingTask = true
            models[member.id] = candidate
            Task { await candidate.loadIfNeeded(); await candidate.loadRoles() }
        }
        preloadIncoming()
    }

    /// Первый из детей справа — заранее как въезжающий лист.
    private func preloadIncoming() {
        guard incoming == nil,
              let next = TaskFamilyEdgeTabs.children(of: family, selectedID: selectedCardID).first
        else { return }
        prepare(next.element.id)
    }

    private func prepare(_ id: String) {
        guard id != selectedCardID, !settling else { return }
        if let cached = models[id] {
            incoming = cached
            if cached.loadedTask == nil && !cached.isLoadingTask {
                cached.isLoadingTask = true
                Task { await cached.loadIfNeeded(); await cached.loadRoles() }
            }
        }
        else {
            let candidate = TaskFormViewModel(taskID: id)
            candidate.isLoadingTask = true
            models[id] = candidate
            incoming = candidate
            Task { await candidate.loadIfNeeded(); await candidate.loadRoles() }
        }
    }

    private func select(_ id: String) {
        guard !settling, id != selectedCardID, let requestSwitch else { resetPull(); return }
        prepare(id)
        guard let candidate = models[id] else { resetPull(); return }
        settling = true
        Task {
            while candidate.isLoadingTask {
                try? await Task.sleep(for: .milliseconds(30))
                if Task.isCancelled { return }
            }
            guard candidate.loadedTask != nil else {
                model.saveErrorMessage = candidate.loadErrorMessage ?? "Не удалось открыть связанную карточку"
                resetPull()
                return
            }
            requestSwitch(id)
        }
    }

    private func finishSelection(_ id: String, width: CGFloat) {
        guard let candidate = models[id] else { resetPull(); return }
        Task {
            while candidate.isLoadingTask {
                try? await Task.sleep(for: .milliseconds(30))
                if Task.isCancelled { return }
            }
            guard candidate.loadedTask != nil else { resetPull(); return }
            incoming = candidate
            withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(duration: 0.38, bounce: 0.04), completionCriteria: .logicallyComplete) {
                pull = width
            } completion: {
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    model = candidate
                    selectedCardID = id
                    incoming = nil
                    pull = 0
                    pullingCardID = nil
                    tabOut = 0
                    settling = false
                }
                preloadIncoming()
            }
        }
    }

    private var currentParent: ApiTask? {
        guard let parentID = model.loadedTask?.parentId else { return nil }
        return family.first { $0.id == parentID }
    }

    /// Переход назад идёт к непосредственному родителю текущей карточки.
    private var backToParent: Bool {
        guard let parentID = currentParent?.id, selectedCardID != parentID,
              let incomingID = incoming?.taskID else { return false }
        return incomingID == parentID
    }

    private func resetPull() {
        withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(duration: 0.3, bounce: 0.08), completionCriteria: .logicallyComplete) {
            pull = 0
            tabOut = 0
            settling = false
        } completion: {
            pullingCardID = nil
        }
    }

    private func pullProgress(width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        return min(1, max(0, pull / width))
    }

    private func latePullProgress(width: CGFloat) -> CGFloat {
        max(0, (pullProgress(width: width) - 0.55) / 0.45)
    }

    private func expandedSections(for model: TaskFormViewModel) -> Set<TaskDetailSection> {
        guard let id = model.taskID else { return [] }
        return expandedSectionsByCard[id] ?? []
    }

    private func storeExpandedSections(_ sections: Set<TaskDetailSection>, for model: TaskFormViewModel) {
        guard let id = model.taskID else { return }
        expandedSectionsByCard[id] = sections
    }

    /// Слот закладки родителя: высота и место — как у слота открытого
    /// ребёнка в правой колонке.
    private func parentSlot(height: CGFloat) -> (height: CGFloat, offset: CGFloat) {
        let kids = TaskFamilyEdgeTabs.children(of: family, selectedID: currentParent?.id)
        let index = kids.firstIndex { $0.element.id == selectedCardID } ?? 0
        return (TaskFamilyEdgeTabs.slotHeight(height: height, count: max(1, kids.count)),
                TaskFamilyEdgeTabs.slotCenterOffset(index: index, count: max(1, kids.count), height: height))
    }

    @ViewBuilder
    private func parentPullHandle(height: CGFloat, shadow: Bool) -> some View {
        if let parentID = currentParent?.id, pullingCardID == parentID {
            let slotHeight = parentSlot(height: height).height
            TaskFamilyParentTab.shape
                .fill(TaskFamilyEdgeTabs.fillColor)
                .overlay { TaskFamilyTabOutline(openEdge: .leading, openInset: TaskFamilyEdgeTabs.seamOverlap).stroke(TaskFamilyEdgeTabs.outlineColor, lineWidth: TaskFamilyEdgeTabs.outlineWidth) }
                .overlay {
                    Image(systemName: "square.stack").font(.caption).foregroundStyle(Color.tfSub)
                        .padding(.leading, TaskFamilyEdgeTabs.seamOverlap)
                }
                .frame(width: TaskFamilyEdgeTabs.expandedWidth + TaskFamilyEdgeTabs.seamOverlap, height: slotHeight)
                .compositingGroup()
                .shadow(color: shadow ? TaskFamilyEdgeTabs.shadowColor : .clear, radius: TaskFamilyEdgeTabs.shadowRadius)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                // Левый край хлястика — правая кромка листа: лист стоит на pull − width.
                .offset(x: (reduceMotion ? 0 : pull) - TaskFamilyEdgeTabs.seamOverlap
                    - (1 - tabOut) * (TaskFamilyEdgeTabs.expandedWidth - TaskFamilyEdgeTabs.restingWidth),
                    y: parentSlot(height: height).offset)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func attachedPullHandle(height: CGFloat, width: CGFloat, shadow: Bool) -> some View {
        if let pullingCardID, pullingCardID != currentParent?.id {
            let remaining = TaskFamilyEdgeTabs.children(of: family, selectedID: selectedCardID)
            let slotHeight = TaskFamilyEdgeTabs.slotHeight(height: height, count: remaining.count)
            VStack(spacing: 8) {
                ForEach(remaining, id: \.element.id) { index, member in
                    if member.id == pullingCardID {
                        // Владелец 02.10.2026: закладка одного цвета с листом —
                        // светлая у края, к середине пути становится ровно
                        // цветом листа; выделяют её только контур и тень.
                        TaskFamilyEdgeTabs.tabShape
                            .fill(TaskFamilyEdgeTabs.fillColor)
                            .background(Color.tfBackground, in: TaskFamilyEdgeTabs.tabShape)
                            .overlay { TaskFamilyTabOutline(openEdge: .trailing, openInset: TaskFamilyEdgeTabs.seamOverlap).stroke(TaskFamilyEdgeTabs.outlineColor, lineWidth: TaskFamilyEdgeTabs.outlineWidth) }
                            .frame(width: TaskFamilyEdgeTabs.expandedWidth + TaskFamilyEdgeTabs.seamOverlap, height: slotHeight)
                            .overlay {
                                Group {
                                    if (familyNumbers[member.id] ?? index) == 0 {
                                        Image(systemName: "square.stack")
                                            .font(.caption)
                                            .foregroundStyle(Color.tfSub)
                                    } else {
                                        TaskFamilyChildMark(number: familyNumbers[member.id] ?? index)
                                    }
                                }
                                .padding(.trailing, TaskFamilyEdgeTabs.seamOverlap)
                            }
                    } else {
                        Color.clear.frame(width: TaskFamilyEdgeTabs.expandedWidth + TaskFamilyEdgeTabs.seamOverlap, height: slotHeight)
                    }
                }
            }
            .frame(width: TaskFamilyEdgeTabs.expandedWidth + TaskFamilyEdgeTabs.seamOverlap)
            .compositingGroup()
                .shadow(color: shadow ? TaskFamilyEdgeTabs.shadowColor : .clear, radius: TaskFamilyEdgeTabs.shadowRadius)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            // Правый край хлястика — кромка листа: лист стоит на width − pull.
            // При касании хлястик выезжает из узкого края на всю ширину.
            .offset(x: (reduceMotion ? width : width - pull) - TaskFamilyEdgeTabs.expandedWidth
                + (1 - tabOut) * (TaskFamilyEdgeTabs.expandedWidth - TaskFamilyEdgeTabs.restingWidth))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// A transparent edge hit area; only a few points of each bookmark remain visible.
struct TaskFamilyEdgeTabs: View {
    @Environment(\.taskFamilyNumbers) private var familyNumbers
    /// В покое — узкий край (владелец 02.10.2026: на полную ширину
    /// закладки задевали текст страницы); под пальцем выезжают целиком.
    static let restingWidth: CGFloat = 10
    static let expandedWidth: CGFloat = 26
    static let cornerRadius: CGFloat = 10
    /// Ровно цвет листа (владелец 02.10.2026): выделяют закладку только
    /// контур и тень — одна и та же в покое и при тяге.
    static let fillColor = Color.tfBackground
    /// Захват — после этого пути пальца: дальше закладка уже не меняется
    /// при движении вдоль края.
    static let captureDistance: CGFloat = 18
    /// Тонкая окантовка акцентным красным вместо теней (владелец 02.10.2026).
    /// Приглушённый акцентный красный — граница видна, но не кричит.
    static let outlineColor = Color.tfRed.opacity(0.35)
    static let outlineWidth: CGFloat = 0.75
    /// Хлястик заходит на лист на эту величину: даже если в каком-то кадре
    /// они разойдутся, разрыва не видно (владелец 02.10.2026: «удлини,
    /// чтобы не мог оторваться»). Текст листа начинается дальше от края.
    static let seamOverlap: CGFloat = 12
    /// Лёгкая тень по периметру — одна и та же у закладок в покое, у
    /// хлястика и у листа при тяге (владелец 02.10.2026): показывает
    /// верхний слой, не перетягивая внимание.
    static let shadowColor = Color.black.opacity(0.3)
    static let shadowRadius: CGFloat = 6
    static let tabShape = UnevenRoundedRectangle(topLeadingRadius: cornerRadius,
        bottomLeadingRadius: cornerRadius)

    let members: [ApiTask]
    let selectedID: String?
    private var remaining: [(offset: Int, element: ApiTask)] {
        Self.children(of: members, selectedID: selectedID)
    }

    /// Дети семьи, кроме открытой карточки. Родитель — первый в семье —
    /// справа не лежит: его закладка слева. Номер — номер ребёнка в семье.
    /// Все дети семьи — постоянные слоты колонки. Слот открытого ребёнка
    /// пустой, а закладка родителя слева стоит на его высоте: доведённая
    /// до края закладка остаётся на той же высоте (владелец 02.10.2026).
    static func allChildren(of members: [ApiTask]) -> [(offset: Int, element: ApiTask)] {
        Array(members.enumerated()).filter { $0.offset > 0 }
    }

    /// Центр слота относительно центра колонки.
    static func slotCenterOffset(index: Int, count: Int, height: CGFloat) -> CGFloat {
        (CGFloat(index) - CGFloat(count - 1) / 2) * (slotHeight(height: height, count: count) + 8)
    }

    static func children(of members: [ApiTask], selectedID: String?) -> [(offset: Int, element: ApiTask)] {
        Array(members.enumerated()).filter { $0.element.parentId == (selectedID ?? members.first?.id) }
    }
    let height: CGFloat
    let width: CGFloat
    @Binding var pull: CGFloat
    @Binding var pullingCardID: String?
    let busy: Bool
    let prepare: (String) -> Void
    let select: (String) -> Void
    let cancel: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered: String?
    @State private var captured: String?
    @State private var suppressTap = false

    static func slotHeight(height: CGFloat, count: Int) -> CGFloat {
        min(116, max(64, height * 0.65 / CGFloat(max(1, count)) - 8))
    }

    private var selectedParentID: String? {
        members.first { $0.id == selectedID }?.parentId
    }

    private var slots: [(offset: Int, element: ApiTask)] { Self.children(of: members, selectedID: selectedID) }
    private var slotHeight: CGFloat { Self.slotHeight(height: height, count: slots.count) }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(slots, id: \.element.id) { index, member in
                if member.id == selectedID {
                    Color.clear.frame(width: 32, height: slotHeight)
                } else {
                Button {
                    // Тап ничего не переключает: закладку только вытягивают свайпом.
                } label: {
                    // Заливка поверх фона листа: полупрозрачная форма давала
                    // тень вполсилы, и спрятанные закладки её почти не отдавали.
                    Self.tabShape
                        .fill(Self.fillColor)
                        .background(Color.tfBackground, in: Self.tabShape)
                        .overlay { TaskFamilyTabOutline(openEdge: .trailing).stroke(Self.outlineColor, lineWidth: Self.outlineWidth) }
                        .frame(width: hovered == member.id ? Self.expandedWidth : Self.restingWidth,
                            height: slotHeight)
                        .compositingGroup()
                        .shadow(color: TaskFamilyEdgeTabs.shadowColor, radius: TaskFamilyEdgeTabs.shadowRadius)
                        .overlay {
                            if hovered == member.id {
                                if (familyNumbers[member.id] ?? index) == 0 { Image(systemName: "square.stack").font(.caption).foregroundStyle(Color.tfSub) }
                                else { TaskFamilyChildMark(number: familyNumbers[member.id] ?? index) }
                            }
                        }
                        .frame(width: 32, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                // Пока выезжает родитель слева, правые тают, чтобы не резать
                // его лист; при тяге ребёнка остальные отъезжают за край.
                .opacity(pullingCardID == member.id ? 0
                    : (pullingCardID != nil && pullingCardID == selectedParentID ? max(0, 1 - pull / 60) : 1))
                .offset(x: pullingCardID == nil || pullingCardID == member.id || pullingCardID == selectedParentID ? 0 : min(40, pull * 0.45))
                .buttonStyle(.plain)
                .accessibilityLabel(member.title)
                .accessibilityIdentifier("task.family.\(member.id)")
                }
            }
        }
        .frame(width: 32)
        .contentShape(Rectangle())
        .disabled(busy)
        .animation(reduceMotion ? nil : .spring(duration: 0.22, bounce: 0.05), value: hovered)
        // Отклик (02.10.2026): щелчок при смене закладки под пальцем и
        // лёгкий удар в момент захвата. Сам жест ниже не тронут.
        .sensoryFeedback(.selection, trigger: hovered) { _, new in new != nil }
        .sensoryFeedback(.impact(weight: .light), trigger: captured) { old, new in old == nil && new != nil }
        .simultaneousGesture(DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !busy, !remaining.isEmpty else { return }
                let distance = max(0, -value.translation.width)
                if abs(value.translation.width) + abs(value.translation.height) > 8 { suppressTap = true }
                if captured == nil {
                    let index = min(slots.count - 1, max(0, Int(value.location.y / (slotHeight + 8))))
                    let id = slots[index].element.id
                    // Пустой слот открытого ребёнка — не закладка.
                    if id != selectedID, hovered != id { hovered = id; prepare(id); pullingCardID = id }
                    if let hovered, distance > Self.captureDistance { captured = hovered }
                }
                if pullingCardID != nil { pull = min(width, distance) }
            }
            .onEnded { value in
                defer { DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { suppressTap = false } }
                let target = captured
                let moved = suppressTap
                hovered = nil
                captured = nil
                // Касание на месте — тап, его открывает кнопка; повели и не
                // дотянули до захвата — хлястик и лист уходят обратно.
                guard let target else {
                    if moved { cancel() }
                    return
                }
                if pull > width * 0.28 || -value.predictedEndTranslation.width > width * 0.55 {
                    select(target)
                } else { cancel() }
            })
    }
}

/// Отметка дочерней на закладке (владелец 02.10.2026: «отметку не в
/// названии, а на вкладках»): значок ветвления и номер ребёнка.
/// Закладка родителя — значок стопки.
struct TaskFamilyChildMark: View {
    let number: Int

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "arrow.triangle.branch")
            Text("\(number)")
        }
        .font(.caption2)
        .foregroundStyle(Color.tfSub)
    }
}

/// Контур закладки без стороны, которой она прилегает к краю или к листу:
/// граница видна, а шва с листом нет.
struct TaskFamilyTabOutline: Shape {
    let openEdge: HorizontalEdge
    /// На сколько хлястик заходит на лист с открытой стороны — контур
    /// обрывается на кромке листа и на лист не ложится.
    var openInset: CGFloat = 0
    var radius: CGFloat = TaskFamilyEdgeTabs.cornerRadius

    func path(in base: CGRect) -> Path {
        var rect = base
        if openEdge == .trailing { rect.size.width -= openInset }
        else { rect.origin.x += openInset; rect.size.width -= openInset }
        let r = min(radius, rect.width, rect.height / 2)
        var path = Path()
        if openEdge == .trailing {
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + r, y: rect.minY))
            path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX, y: rect.minY + r), radius: r)
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))
            path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX + r, y: rect.maxY), radius: r)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
            path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY + r), radius: r)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
            path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX - r, y: rect.maxY), radius: r)
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        return path
    }
}

/// Полоса у края во всю высоту — территория закладок (владелец 02.10.2026:
/// «подраздел открывать посерединке, а края — закладкам»). Тап по краю
/// больше не открывает строку карточки под ним; сами закладки лежат сверху.
struct TaskFamilyEdgeZone: View {
    static let width: CGFloat = 32

    var body: some View {
        Color.clear
            .frame(width: Self.width)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {}
            .accessibilityHidden(true)
    }
}

/// Закладка родителя у левой кромки: зеркало правых закладок, тот же жест.
/// Тянется вправо — открытый лист уходит вправо, родитель выходит из-под него.
struct TaskFamilyParentTab: View {
    let parent: ApiTask
    let slotHeight: CGFloat
    let slotOffset: CGFloat
    let width: CGFloat
    @Binding var pull: CGFloat
    @Binding var pullingCardID: String?
    let busy: Bool
    let prepare: (String) -> Void
    let select: (String) -> Void
    let cancel: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    @State private var captured = false
    @State private var suppressTap = false

    static let shape = UnevenRoundedRectangle(bottomTrailingRadius: TaskFamilyEdgeTabs.cornerRadius,
        topTrailingRadius: TaskFamilyEdgeTabs.cornerRadius)


    var body: some View {
        Button {
            // Тап ничего не переключает: закладку только вытягивают свайпом.
        } label: {
            Self.shape
                .fill(TaskFamilyEdgeTabs.fillColor)
                .background(Color.tfBackground, in: Self.shape)
                .overlay { TaskFamilyTabOutline(openEdge: .leading).stroke(TaskFamilyEdgeTabs.outlineColor, lineWidth: TaskFamilyEdgeTabs.outlineWidth) }
                .frame(width: hovered ? TaskFamilyEdgeTabs.expandedWidth : TaskFamilyEdgeTabs.restingWidth,
                    height: slotHeight)
                .compositingGroup()
                        .shadow(color: TaskFamilyEdgeTabs.shadowColor, radius: TaskFamilyEdgeTabs.shadowRadius)
                .overlay {
                    if hovered {
                        Image(systemName: "square.stack").font(.caption).foregroundStyle(Color.tfSub)
                    }
                }
                .frame(width: 32, alignment: .leading)
                .contentShape(Rectangle())
        }
        .offset(y: slotOffset)
        .buttonStyle(.plain)
        // Закладка тает в первые пункты пути — дальше едет сам лист.
        // Под пальцем вместо неё — хлястик листа родителя.
        // Пока справа выезжает ребёнок, закладка родителя тает: иначе у
        // левого края она ложилась поверх хлястика и резала его своей
        // окантовкой (владелец 02.10.2026).
        .opacity(pullingCardID == parent.id ? 0
            : (pullingCardID != nil && pull > 0 ? max(0, 1 - pull / 60) : 1))
        .frame(width: 32)
        .disabled(busy)
        .animation(reduceMotion ? nil : .spring(duration: 0.22, bounce: 0.05), value: hovered)
        .sensoryFeedback(.selection, trigger: hovered) { _, new in new }
        .sensoryFeedback(.impact(weight: .light), trigger: captured) { old, new in !old && new }
        .accessibilityLabel("Родительская: \(parent.title)")
        .accessibilityIdentifier("task.family.parent.\(parent.id)")
        .simultaneousGesture(DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !busy else { return }
                let distance = max(0, value.translation.width)
                if abs(value.translation.width) + abs(value.translation.height) > 8 { suppressTap = true }
                if !hovered { hovered = true; prepare(parent.id); pullingCardID = parent.id }
                if distance > TaskFamilyEdgeTabs.captureDistance { captured = true }
                if pullingCardID == parent.id { pull = min(width, distance) }
            }
            .onEnded { value in
                defer { DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { suppressTap = false } }
                let wasCaptured = captured
                let moved = suppressTap
                hovered = false
                captured = false
                guard wasCaptured else {
                    if moved { cancel() }
                    return
                }
                if pull > width * 0.28 || value.predictedEndTranslation.width > width * 0.55 {
                    select(parent.id)
                } else { cancel() }
            })
    }
}

/// Reads the actual system-sheet detent, independent of keyboard height.
private struct TaskSheetExpansionProbe: UIViewRepresentable {
    let update: (Bool) -> Void
    func makeUIView(context: Context) -> ProbeView { ProbeView() }
    func updateUIView(_ view: ProbeView, context: Context) { view.update = update; view.check() }
    final class ProbeView: UIView {
        var update: ((Bool) -> Void)?
        private var lastReported: Bool?
        private func report(_ expanded: Bool) {
            guard lastReported != expanded else { return }
            lastReported = expanded
            DispatchQueue.main.async { [weak self] in self?.update?(expanded) }
        }
        override func layoutSubviews() { super.layoutSubviews(); check() }
        override func didMoveToWindow() { super.didMoveToWindow(); check() }
        func check() {
            guard window != nil else { return }
            var responder: UIResponder? = self
            while let next = responder?.next {
                responder = next
                if let controller = next as? UIViewController {
                    var ancestor: UIViewController? = controller
                    while let current = ancestor {
                        if current.presentingViewController != nil,
                           let sheet = current.presentationController as? UISheetPresentationController,
                           sheet.containerView != nil {
                            let expanded = sheet.selectedDetentIdentifier == .large
                            report(expanded)
                            return
                        }
                        ancestor = current.parent
                    }
                    // A full-screen/pushed card has no partial detent.
                    report(true)
                    return
                }
            }
        }
    }
}

/// Invisible intent target prevents the text view from summoning the keyboard.
struct CardTextEditGate: ViewModifier {
    let enabled: Bool
    let identifier: String
    var text: String = ""
    let arm: () -> Void

    func body(content: Content) -> some View {
        content
            .environment(\.documentTextEditable, enabled)
            .accessibilityHidden(!enabled)
            .overlay {
                if !enabled {
                    Button(action: arm) { Color.clear.contentShape(Rectangle()) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(text.isEmpty ? "Показать редактирование" : text)
                        .accessibilityHint("Показать карандаш для редактирования")
                        .accessibilityIdentifier("task.arm.\(identifier)")
                }
            }
    }
}

private struct TaskFamilyNumbersKey: EnvironmentKey {
    static let defaultValue: [String: Int] = [:]
}
private extension EnvironmentValues {
    var taskFamilyNumbers: [String: Int] {
        get { self[TaskFamilyNumbersKey.self] }
        set { self[TaskFamilyNumbersKey.self] = newValue }
    }
}
