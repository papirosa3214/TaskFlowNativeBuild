import SwiftUI

/// Видимая часть следующей колонки: достаточно, чтобы подсказать свайп,
/// но не настолько много, чтобы текущая карточка снова стала узкой.
private let boardNextColumnPeek: CGFloat = 28

// Доска «Сегодня» — spec §3.4/§5.1: колонки «Ждут вас»/«Просрочено»/«Сегодня»,
// БЕЗ группировки по проектам (владелец, прямое решение) — поэтому drag
// между колонками здесь не пишет `project_id` (в вебе карточка просто
// отскакивает назад). Сортировку ВНУТРИ колонки (поле `position`) native-
// версия НЕ делает — не хватает времени в рамках этой сдачи, честно
// оставлено недоделанным (см. отчёт), карточки только открываются тапом.
struct TodayBoardView: View {
    let columns: [TodayBoardColumn]
    let onOpenTask: (String) -> Void
    let onReschedule: () -> Void
    let onAddTask: () -> Void
    var isSelectingTasks = false
    var selectedTaskIDs: Set<String> = []
    var onToggleTaskSelection: (String) -> Void = { _ in }
    var onToggleColumnSelection: (TodayBoardColumn) -> Void = { _ in }
    /// Название видимой колонки уезжает в системную шапку экрана: там оно
    /// стоит по центру под островом и меняется при листании столбиков
    /// (владелец 15.09.2026 — «как все обычно это делают»).
    var onVisibleColumnChange: (String) -> Void = { _ in }
    @State private var visibleColumnID: TodayBoardColumn.Kind?
    /// Палец во время листания колонок.
    @State private var dragTranslation: CGFloat = 0
    /// Ширина одной колонки — из неё считается шаг листания.
    @State private var columnWidth: CGFloat = 0

    /// Сдвиг ряда колонок: видимая колонка встаёт к левому краю, плюс палец.
    private var boardOffset: CGFloat {
        let index = columns.firstIndex { $0.id == visibleColumnID } ?? 0
        return -CGFloat(index) * columnStride + dragTranslation
    }

    /// Шаг между началами соседних колонок — ширина колонки плюс зазор.
    private var columnStride: CGFloat {
        columnWidth + TFSpacing.md
    }

    /// Горизонтальное листание колонок. Порог — треть шага: меньше считается
    /// промахом и колонка возвращается на место.
    private var columnPagingGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                dragTranslation = value.translation.width
            }
            .onEnded { value in
                dragTranslation = 0
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                let index = columns.firstIndex { $0.id == visibleColumnID } ?? 0
                let threshold = columnStride / 3
                if value.translation.width < -threshold, index + 1 < columns.count {
                    visibleColumnID = columns[index + 1].id
                } else if value.translation.width > threshold, index > 0 {
                    visibleColumnID = columns[index - 1].id
                }
            }
    }

    var body: some View {
        // Геометрия колонок теперь берётся у SwiftUI напрямую через
        // `containerRelativeFrame` (iOS 17+). `GeometryReader` убран: он всегда
        // жадно занимал всё доступное пространство, из-за чего на первой
        // загрузке и при rotation SwiftUI переоценивал всю иерархию и доска
        // «прыгала». Каждая колонка теперь занимает ровно ширину контейнера
        // (без peek — `boardNextColumnPeek` ниже, как sentinel).
        // Ряд прижат к левому краю ZStack'ом: `frame(maxWidth:alignment:)` на
        // ряду шире экрана его не прижимает, а ЦЕНТРИРУЕТ — из-за этого под
        // заголовком первой колонки показывалась третья (владелец 15.09.2026:
        // «две крайние правые сделаны нормально, а „Ждут вас“ — нет»).
        GeometryReader { geo in
            HStack(alignment: .top, spacing: TFSpacing.md) {
                ForEach(columns) { column in
                    columnView(column)
                        // `.id(column.id)` раньше стоял здесь явно — когда
                        // `boardColumns` пересобирался на каждый body re-render,
                        // SwiftUI терял identity и `.scrollTargetBehavior` прыгал.
                        // После шага 1 (мемоизация `TodayComputation` через
                        // `.task(id:)` в `TodayScreen`) `column.id` стабилен,
                        // а `TodayBoardColumn: Identifiable` сам даёт нужный
                        // identity для diffing — дополнительный `.id` лишний и
                        // только мешал SwiftUI повторно использовать view-инстанс
                        // при изменении `column.tasks`.
                        // Колонка уже колонки: на ширину `boardNextColumnPeek`
                        // остаётся край следующей — владелец 15.09.2026 просил
                        // «эффект подглядывания следующего столбика». Раньше
                        // колонка занимала всю ширину контейнера, и соседнюю
                        // не было видно вовсе.
                        // Ширина — как в рабочей версии `07f7ec81`: вычитаем
                        // поля ленты с обеих сторон и полосу подглядывания,
                        // чтобы край следующего столбика оставался в кадре.
                        .containerRelativeFrame(.horizontal) { availableWidth, _ in
                            max(280, availableWidth - TFSpacing.lg * 2 - boardNextColumnPeek)
                        }
                        .frame(maxHeight: .infinity, alignment: .top)
                        .background(GeometryReader { proxy in
                            Color.clear.onGeometryChange(for: CGFloat.self) { _ in
                                proxy.size.width
                            } action: { columnWidth = $0 }
                        })
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.leading, TFSpacing.lg)
            .offset(x: boardOffset)
            // Ряд шире экрана, поэтому его надо ЯВНО положить в область
            // экрана и прижать влево: без этого родитель центрирует ряд, и
            // под заголовком первой колонки показывалась третья (замерено
            // логом: index=0, offset=0, а на экране чужая колонка).
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .clipped()
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: visibleColumnID)
        .simultaneousGesture(columnPagingGesture)
        .onAppear {
            keepVisibleColumnValid()
            reportVisibleColumnTitle()
        }
        .onChange(of: columns.map(\.id)) { _, _ in
            keepVisibleColumnValid()
            reportVisibleColumnTitle()
        }
        .onChange(of: visibleColumnID) { _, _ in reportVisibleColumnTitle() }
        // Вход/выход из режима мультивыбора: появление/исчезновение галочек и
        // кнопок «Выбрать все»/«Снять выбор» в шапках колонок плавное.
        .animation(.easeInOut(duration: 0.2), value: isSelectingTasks)
    }

    private func keepVisibleColumnValid() {
        guard let first = columns.first?.id else {
            visibleColumnID = nil
            return
        }
        if let visibleColumnID,
           columns.contains(where: { $0.id == visibleColumnID }) {
            return
        }
        visibleColumnID = first
    }

    private func reportVisibleColumnTitle() {
        let visible = columns.first { $0.id == visibleColumnID } ?? columns.first
        onVisibleColumnChange(visible?.title ?? "")
    }

    private func columnView(_ column: TodayBoardColumn) -> some View {
        // Колонка — самостоятельная сущность: заголовок стоит НАД лентой, а
        // прокрутка принадлежит только ей (так и было сделано в `07f7ec81`,
        // «per-column scroll»). Когда заголовок держали закреплённым ВНУТРИ
        // прокрутки, он болтался вместе с карточками, а оттягивание тащило всю
        // доску разом — владелец 15.09.2026: «у тебя должна быть прям колонка,
        // и у неё своя полоска прокрутки».
        // Названия колонки внутри нет: оно уехало в системную шапку экрана и
        // меняется при листании столбиков. Здесь остаются только действия
        // колонки — «Перенести» у просроченных и выбор в режиме мультивыбора.
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            if isSelectingTasks, !column.tasks.isEmpty {
                let allSelected = column.tasks.allSatisfy { selectedTaskIDs.contains($0.id) }
                Button(allSelected ? "Снять выбор" : "Выбрать все") {
                    onToggleColumnSelection(column)
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.tfRed)
                .frame(maxWidth: .infinity, alignment: .trailing)
            } else if column.id == .overdue {
                Button("Перенести", action: onReschedule)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.tfRed)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: TFSpacing.sm) {
                    if column.tasks.isEmpty && column.id != .today {
                        TFEmptyState(
                            icon: nil,
                            text: "Нет задач"
                        )
                        .frame(maxWidth: .infinity, minHeight: 60)
                    } else {
                        ForEach(column.tasks) { task in
                            boardCard(task)
                        }
                    }

                    if column.id == .today {
                        Button(action: onAddTask) {
                            HStack(spacing: TFSpacing.sm) {
                                Image(systemName: "plus")
                                Text("Добавить задачу")
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.tfRed)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Color.tfRed.opacity(0.05))
                            .overlay {
                                RoundedRectangle(cornerRadius: TFRadius.lg)
                                    .strokeBorder(Color.tfRed.opacity(0.4), lineWidth: 1)
                            }
                        }
                    }
                }
                // Запас снизу — высота панели вкладок: последняя карточка
                // должна доезжать выше неё, а не оставаться под затуханием.
                .padding(.bottom, TFTabBarMetrics.heightCompact + TFSpacing.lg)
            }
            // Ни `ignoresSafeArea`, ни масок: безопасную зону SwiftUI считает
            // сам, игнорировать её положено только фонам (HIG-материал
            // проекта). Затухание — системная кромка прокрутки, `.soft` для
            // обеих кромок: на iOS 27 стиль по умолчанию стал `.hard`.
            .tfBoardNativeScrollEdges()
        }
        .frame(maxHeight: .infinity, alignment: .top)
        // Появление/исчезновение карточек в колонке пружинит — раньше
        // добавление задачи через Realtime или удаление свайпом «схлопывали»
        // колонку мгновенно и доска дёргалась. `column.tasks.map(\.id)`
        // сравнивается по содержимому — перестановка тоже анимируется.
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: column.tasks.map(\.id))
    }

    private func boardCard(_ task: ApiTask) -> some View {
        Button(action: {
            if isSelectingTasks {
                onToggleTaskSelection(task.id)
            } else {
                onOpenTask(task.id)
            }
        }) {
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 4) {
                if let projectName = task.projectName {
                    Text("#\(projectName)")
                        .tfText(.caption)
                        .foregroundStyle(Color(hex: task.projectColor ?? TFHexDefault.unassigned))
                }
                HStack(spacing: TFSpacing.md) {
                    if let initials = task.assigneeInitials, task.assigneeId != nil {
                        TFAvatar(size: .xs, initials: initials, tint: Color(hex: task.assigneeColor ?? TFHexDefault.unassigned))
                    }
                    Text(task.title)
                        .tfText(.body)
                        .foregroundStyle(task.status == .completed ? Color.tfSub : Color.tfText)
                        .strikethrough(task.status == .completed)
                        .lineLimit(1)
                }
                if let description = task.description, !description.isEmpty {
                    Text(description)
                        .tfText(.action)
                        .foregroundStyle(Color.tfSub)
                        .lineLimit(1)
                }
                if let agentText = TodayAgentStateTag.text(task) {
                    Text(agentText)
                        .tfText(.caption)
                        .foregroundStyle(TodayAgentStateTag.color(task))
                }
                    HStack(spacing: TFSpacing.xs) {
                        if !task.subtasks.isEmpty {
                            let done = task.subtasks.count { $0.done }
                            TFPill("\(done)/\(task.subtasks.count)", color: .tfSub, solidBackground: .tfCard2)
                        }
                        if let due = task.dueDate {
                            TFPill(TodayDate.formatDuePlain(due), color: .tfSub, solidBackground: .tfCard2)
                        }
                        if let label = task.labels.first {
                            TFLabelPill(label.name, color: Color(hex: label.color ?? TFHexDefault.unassigned))
                        }
                    }
                }
                if isSelectingTasks {
                    Image(systemName: selectedTaskIDs.contains(task.id) ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selectedTaskIDs.contains(task.id) ? Color.tfRed : Color.tfSub)
                        .padding(8)
                        // Переключение галочки плавное, не мигает.
                        .animation(.easeOut(duration: 0.18), value: selectedTaskIDs.contains(task.id))
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 12)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.tfCard)
            .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
        }
        .buttonStyle(TFTapScaleStyle())
        .accessibilityLabel(
            isSelectingTasks
                ? (selectedTaskIDs.contains(task.id) ? "Снять выбор: \(task.title)" : "Выбрать: \(task.title)")
                : task.title
        )
    }
}

private extension View {
    /// Системное мягкое размытие у верхней кромки прокрутки — тот же приём,
    /// что уже стоит у почасовой сетки (`tfHoursNativeTopScrollEdge`).
    /// Ничего своего не рисуем, на iOS до 26 просто нет эффекта.
    @ViewBuilder
    func tfBoardNativeScrollEdges() -> some View {
        if #available(iOS 26.0, *) {
            self.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
    }
}
