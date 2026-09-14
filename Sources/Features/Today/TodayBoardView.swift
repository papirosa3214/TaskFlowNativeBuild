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
    @State private var visibleColumnID: TodayBoardColumn.Kind?

    var body: some View {
        // Геометрия колонок теперь берётся у SwiftUI напрямую через
        // `containerRelativeFrame` (iOS 17+). `GeometryReader` убран: он всегда
        // жадно занимал всё доступное пространство, из-за чего на первой
        // загрузке и при rotation SwiftUI переоценивал всю иерархию и доска
        // «прыгала». Каждая колонка теперь занимает ровно ширину контейнера
        // (без peek — `boardNextColumnPeek` ниже, как sentinel).
        ScrollView(.horizontal, showsIndicators: false) {
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
                        .containerRelativeFrame(.horizontal, count: 1, span: 1, spacing: 0, alignment: .leading)
                        .containerRelativeFrame(.vertical, alignment: .top)
                }
                // Sentinel для peek: после последней видимой колонки остаётся
                // полоска `boardNextColumnPeek`, по которой `.viewAligned` snap'ит
                // как на «начало следующей колонки». Без sentinel свайп бы
                // останавливался ровно на границе колонки без подсказки «есть
                // ещё», и анимация snap'а выглядела бы рывком.
                Color.clear.frame(width: boardNextColumnPeek)
            }
            .padding(.horizontal, TFSpacing.lg)
            .scrollTargetLayout()
        }
        .scrollPosition(id: $visibleColumnID, anchor: .leading)
        .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
        .onAppear { keepVisibleColumnValid() }
        .onChange(of: columns.map(\.id)) { _, _ in keepVisibleColumnValid() }
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

    private func columnView(_ column: TodayBoardColumn) -> some View {
        // Прокрутка колонки уходит под обе системные кромки: сверху её мягко
        // размывает шапка раздела, снизу карточки проезжают под панелью
        // вкладок с её собственным затуханием. Владелец 10.09.2026: «доски
        // сделать, чтобы системный блюр вверху был и моё затухание внизу, как
        // на всех экранах».
        //
        // Заголовок колонки живёт ВНУТРИ прокрутки — иначе он стоит между
        // шапкой и лентой, лента до системной панели не достаёт, и размывать
        // системе нечего: получается жёсткая обрезка под заголовком, ровно то,
        // на что владелец и указал.
        ScrollView(.vertical, showsIndicators: false) {
            // Заголовок закреплён штатным `pinnedViews` — тот же приём, что у
            // списка «Сегодня» (`TodayListView`): своей подложки и своего
            // размытия у него нет, лента просто идёт под ним.
            LazyVStack(spacing: TFSpacing.sm, pinnedViews: [.sectionHeaders]) {
                Section {
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
                } header: {
                    HStack {
                        Text(column.title)
                            .tfText(.title)
                            .fontWeight(.semibold)
                            .foregroundStyle(column.titleIsRed ? Color.tfRed : Color.tfText)
                        Spacer()
                        if isSelectingTasks, !column.tasks.isEmpty {
                            let allSelected = column.tasks.allSatisfy { selectedTaskIDs.contains($0.id) }
                            Button(allSelected ? "Снять выбор" : "Выбрать все") {
                                onToggleColumnSelection(column)
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.tfRed)
                        } else if column.id == .overdue {
                            Button("Перенести", action: onReschedule)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.tfRed)
                        }
                    }
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Закреплённый заголовок должен закрывать карточки под
                    // собой. Прозрачный header давал наложение текста при
                    // вертикальной прокрутке колонки.
                    .background(Color.tfBackground)
                    .zIndex(1)
                }
            }
            // Запас снизу — высота панели вкладок: последняя карточка должна
            // доезжать выше неё, а не оставаться под затуханием. Отступ висит
            // на всей ленте: на `Section` он раздувал промежуток под КАЖДОЙ
            // карточкой (поймано кадром).
            .padding(.bottom, TFTabBarMetrics.heightCompact + TFSpacing.lg)
        }
        .tfBoardNativeScrollEdges()
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
