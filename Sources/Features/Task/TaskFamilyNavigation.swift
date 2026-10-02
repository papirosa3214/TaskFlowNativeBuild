import SwiftUI
import UIKit

/// One native sheet, with an interactive horizontal transition inside it.
struct TaskFormScreen: View {
    @State private var model: TaskFormViewModel
    @State private var selectedCardID: String?
    @State private var models: [String: TaskFormViewModel] = [:]
    @State private var family: [ApiTask] = []
    @State private var incoming: TaskFormViewModel?
    @State private var pull: CGFloat = 0
    @State private var pullingCardID: String?
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
                    .blur(radius: reduceMotion || backToParent ? 0 : 3.2 * pullProgress(width: geometry.size.width))
                    .opacity(backToParent
                        ? (reduceMotion ? 1 - pullProgress(width: geometry.size.width) : 1)
                        : (reduceMotion ? 1 : 1 - 0.14 * latePullProgress(width: geometry.size.width)))
                    .overlay {
                        if pull > 0 && !backToParent {
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
                    // Возврат к родителю: лист уходит вправо, у его левой
                    // кромки — та же градиентная тень, что у въезжающего листа.
                    .overlay(alignment: .leading) {
                        if backToParent && pull > 0 {
                            LinearGradient(
                                colors: [.clear, Color.black.opacity(0.18), Color.black.opacity(0.46)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: 58)
                            .offset(x: -58)
                            .allowsHitTesting(false)
                        }
                    }
                    .offset(x: backToParent && !reduceMotion ? pull : 0)
                    .zIndex(1)
                if let incoming, pull > 0, backToParent {
                    // Родитель лежит под уходящим листом и выходит из глубины.
                    TaskCardContent(model: incoming, expanding: false, family: [],
                        onFamilyLoaded: { _ in }, onFamilySelected: { _ in },
                        initialExpandedSections: expandedSections(for: incoming),
                        onExpandedSectionsChanged: { storeExpandedSections($0, for: incoming) },
                        preview: true)
                        .background(Color.tfBackground.ignoresSafeArea())
                        .blur(radius: reduceMotion ? 0 : 3.2 * (1 - pullProgress(width: geometry.size.width)))
                        .overlay {
                            Color.tfCard2
                                .opacity((reduceMotion ? 0.06 : 0.16) * (1 - pullProgress(width: geometry.size.width)))
                        }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .zIndex(0)
                } else if let incoming, pull > 0 {
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
                        .shadow(color: Color.black.opacity(0.52), radius: 10, x: -7)
                        .shadow(color: Color.black.opacity(0.3), radius: 30, x: -18)
                        .background(alignment: .leading) {
                            LinearGradient(
                                colors: [.clear, Color.black.opacity(0.18), Color.black.opacity(0.46)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: 58)
                            .offset(x: -58)
                            .ignoresSafeArea()
                        }
                        .offset(x: reduceMotion ? 0 : geometry.size.width - pull)
                        .opacity(reduceMotion ? min(1, pull / geometry.size.width) : 1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .zIndex(2)
                    // Хлястик — отдельным слоем поверх листа и его тени, в
                    // координатах экрана: ровно слева от кромки листа, на
                    // высоте своего слота — там же, где стоял у края.
                    attachedPullHandle(height: geometry.size.height, width: geometry.size.width)
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
                if expandedSheet, family.count > 1, let parent = family.first,
                   selectedCardID != nil, selectedCardID != parent.id {
                    ZStack(alignment: .leading) {
                        TaskFamilyEdgeZone()
                        TaskFamilyParentTab(parent: parent,
                            height: geometry.size.height, width: geometry.size.width,
                            pull: $pull, pullingCardID: $pullingCardID, busy: settling,
                            prepare: prepare, select: select, cancel: resetPull)
                    }
                }
            }
            .background(TaskSheetExpansionProbe { expanded in
                if expandedSheet != expanded {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) { expandedSheet = expanded }
                }
                if !expanded && !settling && pull > 0 { resetPull() }
            })
        }
        .background(Color.tfBackground.ignoresSafeArea())
        // Отклик (02.10.2026): лёгкий удар, когда карточка приземлилась.
        .sensoryFeedback(.impact(weight: .light), trigger: selectedCardID)
    }

    private func receiveFamily(_ members: [ApiTask]) {
        family = members
        if let id = model.taskID { models[id] = model }
        for member in members where member.id != model.taskID && models[member.id] == nil {
            let candidate = TaskFormViewModel(taskID: member.id)
            candidate.isLoadingTask = true
            models[member.id] = candidate
            Task { await candidate.loadIfNeeded(); await candidate.loadRoles() }
        }
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
                    settling = false
                }
            }
        }
    }

    /// Переход идёт назад, к родителю: родитель — первый в семье.
    private var backToParent: Bool {
        guard let parentID = family.first?.id, selectedCardID != parentID,
              let incomingID = incoming?.taskID else { return false }
        return incomingID == parentID
    }

    private func resetPull() {
        withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(duration: 0.3, bounce: 0.08), completionCriteria: .logicallyComplete) {
            pull = 0
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

    @ViewBuilder
    private func attachedPullHandle(height: CGFloat, width: CGFloat) -> some View {
        if let pullingCardID, pullingCardID != family.first?.id {
            let remaining = TaskFamilyEdgeTabs.children(of: family, selectedID: selectedCardID)
            let slotHeight = TaskFamilyEdgeTabs.slotHeight(height: height, count: remaining.count)
            VStack(spacing: 8) {
                ForEach(remaining, id: \.element.id) { index, member in
                    if member.id == pullingCardID {
                        // Владелец 02.10.2026: закладка одного цвета с листом —
                        // светлая у края, к середине пути становится ровно
                        // цветом листа; выделяют её только контур и тень.
                        TaskFamilyEdgeTabs.tabShape
                            .fill(TaskFamilyEdgeTabs.fillColor
                                .opacity(1 - min(1, pull / max(1, width * 0.5))))
                            .background(Color.tfBackground, in: TaskFamilyEdgeTabs.tabShape)
                            .overlay { TaskFamilyTabOutline(openEdge: .trailing).stroke(TaskFamilyEdgeTabs.outlineColor, lineWidth: TaskFamilyEdgeTabs.outlineWidth) }
                            .frame(width: TaskFamilyEdgeTabs.expandedWidth, height: slotHeight)
                            .overlay {
                                if index == 0 {
                                    Image(systemName: "square.stack")
                                        .font(.caption)
                                        .foregroundStyle(Color.tfSub)
                                } else {
                                    Text("\(index)")
                                        .font(.caption)
                                        .foregroundStyle(Color.tfSub)
                                }
                            }
                    } else {
                        Color.clear.frame(width: TaskFamilyEdgeTabs.expandedWidth, height: slotHeight)
                    }
                }
            }
            .frame(width: TaskFamilyEdgeTabs.expandedWidth)
            .shadow(color: Color.black.opacity(0.52), radius: 10, x: -7)
            .shadow(color: Color.black.opacity(0.3), radius: 30, x: -18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            // Правый край хлястика — кромка листа: лист стоит на width − pull.
            .offset(x: (reduceMotion ? width : width - pull) - TaskFamilyEdgeTabs.expandedWidth)
            .opacity(reduceMotion ? min(1, pull / max(1, width)) : 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// A transparent edge hit area; only a few points of each bookmark remain visible.
struct TaskFamilyEdgeTabs: View {
    static let restingWidth: CGFloat = 10
    static let expandedWidth: CGFloat = 26
    static let cornerRadius: CGFloat = 10
    static let fillColor = Color.tfCard2.opacity(0.48)
    /// Захват — после этого пути пальца: дальше закладка уже не меняется
    /// при движении вдоль края.
    static let captureDistance: CGFloat = 18
    /// С этого пути лист выходит вместе с закладкой — с первых пунктов, а не
    /// рывком в момент захвата (владелец 02.10.2026). Меньше — это тап.
    static let followDistance: CGFloat = 3
    /// Тонкий чёрный контур — чёткая граница закладки (владелец 02.10.2026).
    static let outlineColor = Color.black.opacity(0.85)
    static let outlineWidth: CGFloat = 0.75
    static let tabShape = UnevenRoundedRectangle(topLeadingRadius: cornerRadius,
        bottomLeadingRadius: cornerRadius)

    let members: [ApiTask]
    let selectedID: String?
    private var remaining: [(offset: Int, element: ApiTask)] {
        Self.children(of: members, selectedID: selectedID)
    }

    /// Дети семьи, кроме открытой карточки. Родитель — первый в семье —
    /// справа не лежит: его закладка слева. Номер — номер ребёнка в семье.
    static func children(of members: [ApiTask], selectedID: String?) -> [(offset: Int, element: ApiTask)] {
        Array(members.enumerated()).filter { $0.offset > 0 && $0.element.id != selectedID }
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

    private var slotHeight: CGFloat { Self.slotHeight(height: height, count: remaining.count) }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(remaining, id: \.element.id) { index, member in
                Button {
                    guard !suppressTap else { return }
                    prepare(member.id)
                    select(member.id)
                } label: {
                    // Заливка поверх фона листа: полупрозрачная форма давала
                    // тень вполсилы, и спрятанные закладки её почти не отдавали.
                    Self.tabShape
                        .fill(Self.fillColor)
                        .background(Color.tfBackground, in: Self.tabShape)
                        .overlay { TaskFamilyTabOutline(openEdge: .trailing).stroke(Self.outlineColor, lineWidth: Self.outlineWidth) }
                        .frame(width: hovered == member.id ? Self.expandedWidth : Self.restingWidth,
                            height: slotHeight)
                        .shadow(color: Color.black.opacity(0.52), radius: 10, x: -7)
                        .shadow(color: Color.black.opacity(0.3), radius: 30, x: -18)
                        .overlay {
                            if hovered == member.id {
                                if index == 0 { Image(systemName: "square.stack").font(.caption).foregroundStyle(Color.tfSub) }
                                else { Text("\(index)").font(.caption).foregroundStyle(Color.tfSub) }
                            }
                        }
                        .frame(width: 32, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .opacity(pullingCardID == member.id && pull > 0 ? 0 : 1)
                .offset(x: pullingCardID == nil || pullingCardID == member.id ? 0 : min(40, pull * 0.45))
                .buttonStyle(.plain)
                .accessibilityLabel(member.title)
                .accessibilityIdentifier("task.family.\(member.id)")
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
                    let index = min(remaining.count - 1, max(0, Int(value.location.y / (slotHeight + 8))))
                    let id = remaining[index].element.id
                    if hovered != id { hovered = id; prepare(id) }
                    if distance > Self.followDistance { pullingCardID = id }
                    if distance > Self.captureDistance { captured = id }
                }
                if pullingCardID != nil { pull = min(width, distance) }
            }
            .onEnded { value in
                defer { DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { suppressTap = false } }
                let target = captured
                hovered = nil
                captured = nil
                // Не дотянули до захвата — лист возвращается; касание на
                // месте достаётся кнопке (тап).
                guard let target else {
                    if pull > 0 { cancel() }
                    return
                }
                if pull > width * 0.28 || -value.predictedEndTranslation.width > width * 0.55 {
                    select(target)
                } else { cancel() }
            })
    }
}

/// Контур закладки без стороны, которой она прилегает к краю или к листу:
/// граница видна, а шва с листом нет.
struct TaskFamilyTabOutline: Shape {
    let openEdge: HorizontalEdge
    var radius: CGFloat = TaskFamilyEdgeTabs.cornerRadius

    func path(in rect: CGRect) -> Path {
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
    let height: CGFloat
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

    private static let shape = UnevenRoundedRectangle(bottomTrailingRadius: TaskFamilyEdgeTabs.cornerRadius,
        topTrailingRadius: TaskFamilyEdgeTabs.cornerRadius)

    private var slotHeight: CGFloat { TaskFamilyEdgeTabs.slotHeight(height: height, count: 1) }

    var body: some View {
        Button {
            guard !suppressTap else { return }
            prepare(parent.id)
            select(parent.id)
        } label: {
            Self.shape
                .fill(TaskFamilyEdgeTabs.fillColor)
                .background(Color.tfBackground, in: Self.shape)
                .overlay { TaskFamilyTabOutline(openEdge: .leading).stroke(TaskFamilyEdgeTabs.outlineColor, lineWidth: TaskFamilyEdgeTabs.outlineWidth) }
                .frame(width: hovered ? TaskFamilyEdgeTabs.expandedWidth : TaskFamilyEdgeTabs.restingWidth,
                    height: slotHeight)
                .overlay {
                    if hovered {
                        Image(systemName: "square.stack").font(.caption).foregroundStyle(Color.tfSub)
                    }
                }
                .shadow(color: Color.black.opacity(0.52), radius: 10, x: 7)
                .shadow(color: Color.black.opacity(0.3), radius: 30, x: 18)
                .frame(width: 32, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Закладка тает в первые пункты пути — дальше едет сам лист.
        .opacity(pullingCardID == parent.id ? max(0, 1 - pull / 40) : 1)
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
                if !hovered { hovered = true; prepare(parent.id) }
                if distance > TaskFamilyEdgeTabs.followDistance { pullingCardID = parent.id }
                if distance > TaskFamilyEdgeTabs.captureDistance { captured = true }
                if pullingCardID == parent.id { pull = min(width, distance) }
            }
            .onEnded { value in
                defer { DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { suppressTap = false } }
                let wasCaptured = captured
                hovered = false
                captured = false
                guard wasCaptured else {
                    if pull > 0 { cancel() }
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
