import SwiftUI
import UIKit

// Строка задачи для ProjectTasksScreen — дубль `src/components/TaskRow.tsx`
// (общий компонент, которым пользуется чужой набор экранов), тем же приёмом
// дублирования, что `Features/Today/TodayTaskRow.swift` уже применил для
// «Сегодня» («точность спеки важнее переиспользования» — комментарий того
// файла). Не беру TodayTaskRow как есть: этому экрану нужен подавленный
// бейдж проекта (`showProjectBadge=false` — сам экран уже внутри одного
// проекта). Кнопка закрепления в строке жила здесь до 11.09.2026, когда
// владелец её убрал: закрепление переехало в меню «…» карточки задачи.
//
// ⚠️ Сверено с живым `TaskRow.tsx` 31.08.2026: `ProjectTasksScreen.tsx`
// вызывает `<TaskRow .../>` БЕЗ пропа `overdue` — он там всегда `false` по
// умолчанию, то есть просроченные задачи здесь показывают ОБЫЧНый бейдж
// срока (день+месяц, «· N дней»), а не красную пилюлю «Просрочено» — это не
// упрощение, так in the реальном коде, красная пилюля тут в принципе
// недостижима. Верхний файловый комментарий самого TaskRow.tsx про
// «точку-переключатель статуса» — устаревшая документация: в актуальном
// JSX такой кнопки уже нет (проверено построчно), дот-toggle реально
// существует только в LabelTasksScreen (см. её отдельную реализацию).
struct DirectoryTaskRow: View {
    /// Уникальный id задачи (короткий префикс UUID), чтобы владелец мог
    /// ссылаться на конкретную карточку в чате с исполнителем («посмотри
    /// #b6b57092»). Полный UUID слишком длинный, а в мобильном интерфейсе
    /// скопировать строку нельзя — префикс из 8 hex-символов достаточно
    /// уникален в пределах проекта (коллизия по первым 8 символам UUID
    /// практически невозможна при текущем количестве задач).
    let index: String?
    let task: ApiTask
    let isOwner: Bool
    let onOpen: () -> Void
    let onDelete: () -> Void
    /// Контекстное действие на правом свайпе: поднять флаг / принять ревью.
    let swipeAction: ProjectTaskSwipeAction?
    let onSwipeAction: () -> Void

    /// Необязательная строка «роль · модель» (LOCK-177). Заполняется только
    /// на «Работе агентов»; у остальных списков остаётся пустой и ничего не
    /// меняет. `var` с дефолтом, чтобы не трогать существующие вызовы.
    var agentLine: String? = nil

    /// Тап по аватару родительской задачи — раскрыть/свернуть дочерние. `nil` —
    /// у задачи нет дочерних, аватар не ловит нажатие, строка открывается как раньше.
    var onAvatarTap: (() -> Void)? = nil

    /// Рисовать ли аватарку исполнителя (LOCK 11.10.2026, «Активность»).
    /// `false` — строка без кружка, строка уже и без того компактная, а на
    /// «Активности» их десятки: каждый кружок с портретом роли — это ещё и
    /// видеоплеер (`AVPlayerLayer`+`AVPlayerLooper`, LOCK-TEAM-AVATAR-ANIMATION),
    /// и список выполненных задач подвешивал приложение (проверено спиндампом
    /// симулятора: 199 потоков, 20 видеоконвертеров, главный поток не отвечал).
    /// По умолчанию `true` — прежнее поведение остальных списков.
    var showsAvatar: Bool = true

    /// Слова подтверждения свайпа вправо. `nil` — дефолт «Отправить в архив»,
    /// как у обычного списка. Экран «Архив» переиспользует ту же строку для
    /// безвозвратного удаления и подставляет свои слова (10.10.2026).
    var deleteConfirmTitle: String? = nil
    var deleteConfirmMessage: ((String) -> String)? = nil

    /// Зачёркивать ли название выполненной задачи (LOCK 11.10.2026, экран
    /// «Активность»). `nil` — прежнее поведение: зачёркивание выводится из
    /// `task.status`. На «Активности» задачи по определению выполнены, и
    /// зачёркнутый список читался как «остановленное»: владелец не видел, что
    /// именно надо вернуть в работу. Там передаётся `false`.
    var strikesDoneTitle: Bool? = nil

    /// Подпись времени в строке меток (LOCK 11.10.2026, «Активность»): час
    /// закрытия задачи. `nil` — не показывать, прежнее поведение всех
    /// остальных списков. Нужен именно здесь: у строки выполненной задачи
    /// время закрытия — главное, ради чего список сгруппирован по дням.
    var timestamp: String? = nil

    /// Своё имя в общем реестре раскрытых строк (`TFSwipeRowRegistry`).
    @State private var rowID = UUID()
    @State private var settledOffset: CGFloat = 0
    @State private var dragOffset: CGFloat = 0
    @State private var confirmDelete = false

    private var offsetX: CGFloat { clamp(settledOffset + dragOffset) }

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                swipeIconButton(icon: "archivebox", color: .tfSwipeDelete) {
                    close()
                    // В архив — сразу, без подтверждения (владелец 12.10.2026):
                    // задача не пропадает, её видно в «Архиве» и можно вернуть.
                    // Диалог остаётся только там, где действие необратимо, —
                    // то есть когда строка переиспользуется экраном «Архив»
                    // и передаёт свои `deleteConfirmTitle`/`deleteConfirmMessage`
                    // на окончательное удаление.
                    if deleteConfirmTitle == nil {
                        onDelete()
                    } else {
                        confirmDelete = true
                    }
                }
                .frame(width: leftRevealWidth)
                .opacity(revealOpacity(leftRevealWidth))

                Spacer(minLength: 0)

                if let swipeAction {
                    swipeIconButton(
                        icon: swipeAction.icon,
                        color: .tfGreen,
                        action: { close(); onSwipeAction() },
                        accessibilityLabel: swipeAction.accessibilityLabel,
                        accessibilityIdentifier: swipeAction.accessibilityIdentifier
                    )
                    .frame(width: rightRevealWidth)
                    .opacity(revealOpacity(rightRevealWidth))
                }
            }

            row
                .background(Color.tfBackground)
                .offset(x: offsetX)
                // UIKit-pan не забирает вертикальный жест у ScrollView.
                // Обычный DragGesture здесь делал начало прокрутки вязким:
                // список ждал, решит ли строка трактовать касание как свайп.
                .gesture(
                    HorizontalPan(
                        onBegin: { UIImpactFeedbackGenerator(style: .soft).impactOccurred() },
                        onChange: { dx in dragOffset = dx },
                        onEnd: { dx, velocity in settle(dx: dx, velocity: velocity) }
                    )
                )
        }
        .clipped()
        // Раскрыта всегда одна строка: как только реестр называет другую
        // (или прокрутка гасит всё), эта закрывается сама.
        .onChange(of: TFSwipeRowRegistry.shared.openRowID) { _, openID in
            if openID != rowID, settledOffset != 0 { close() }
        }
        // Диалог остался только для окончательного удаления с экрана «Архив»
        // (там владелец передаёт `deleteConfirmTitle`). Обычный свайп в архив
        // его больше не показывает — поручение владельца 12.10.2026.
        .confirmationDialog(deleteConfirmTitle ?? "Отправить задачу в архив?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(deleteConfirmTitle == nil ? "В архив" : "Удалить окончательно", role: .destructive, action: onDelete)
            Button("Отмена", role: .cancel) {}
        } message: {
            Text(deleteConfirmMessage?(task.title)
                ?? "«\(task.title)» будет отправлена в архив. Её можно восстановить.")
        }
    }

    private var leftRevealWidth: CGFloat { max(offsetX, 0) }
    private var rightRevealWidth: CGFloat { max(-offsetX, 0) }

    private func revealOpacity(_ width: CGFloat) -> Double {
        min(1, Double(width / TFRowActionWidth) * 1.3)
    }

    /// Кнопка свайпа — только иконка, без надписи (владелец 11.09.2026).
    /// Идентификатор и подпись для VoiceOver берутся из действия, когда оно
    /// задано: раньше они были объявлены в перечислении, но на кнопку не
    /// попадали — из-за этого свайп было нечем проверить в UI-тесте.
    private func swipeIconButton(icon: String, color: Color, action: @escaping () -> Void,
                                 accessibilityLabel: String? = nil,
                                 accessibilityIdentifier: String? = nil) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: TFIconSize.md))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(color)
        }
        .buttonStyle(.plain)
        .clipped()
        .allowsHitTesting(abs(offsetX) >= TFRowActionWidth * 0.7)
        .accessibilityHidden(abs(offsetX) < TFRowActionWidth * 0.7)
        .accessibilityLabel(Text(accessibilityLabel ?? icon))
        .accessibilityIdentifier(accessibilityIdentifier ?? icon)
    }

    private var row: some View {
        Button {
            if settledOffset != 0 { close() } else { onOpen() }
        } label: {
            TFTaskRowContent(title: task.title, description: task.description, isDone: strikesDoneTitle ?? (task.status == .completed)) {
                if showsAvatar, let initials = task.rowAvatarInitials {
                    TFAvatar(size: .taskList, initials: initials, tint: Color(hex: task.assigneeColor ?? TFHexDefault.unassigned), userID: task.rowAvatarID, teamIDs: task.rowAvatarTeam, urlPath: task.rowAvatarURL, teamURLs: task.rowAvatarTeamURLs, portrait: task.rowAvatarPortrait)
                        .contentShape(Rectangle())
                        .highPriorityGesture(TapGesture().onEnded { onAvatarTap?() }, including: onAvatarTap == nil ? .none : .all)
                }
            } metadata: {
                if let timestamp, !timestamp.isEmpty {
                    Text(timestamp).layoutPriority(-1)
                }
                // Дата и время заведения заявки — пиксельной меткой в квадратных
                // скобках (LOCK-TASK-CREATED-STAMP, владелец 12.10.2026).
                TFTaskCreatedStamp(createdAt: task.createdAt)
                TFTaskStructureIndicators(priority: TaskPriority(rawValue: task.priority), subtasksDone: task.subtasks.isEmpty ? nil : task.subtasks.count { $0.done }, subtasksTotal: task.subtasks.isEmpty ? nil : task.subtasks.count, childrenCount: task.childrenCount, hasCollaborationPlan: task.hasCollaborationPlan)
                if let due = task.dueDate {
                    TFDueChip(plain: DirectoryDate.formatDuePlain(due), relative: DirectoryDate.formatDaysLeft(due), days: DirectoryDate.daysUntil(due), overdueText: "Просрочено, \(DirectoryDate.formatDuePlain(due))", highlight: task.status == .active)
                }
                if task.needsResearch {
                    TFPill("Исследование", color: .tfSub, solidBackground: .tfCard)
                }
                if let status = DirectoryAgentStateTag.text(task) {
                    Text(status).foregroundStyle(DirectoryAgentStateTag.color(task)).layoutPriority(-1)
                }
                if task.agentState == .review, task.criticApproved == true { TFCriticApprovedMark() }
                if let index {
                    // Кегль и вес — ступенью (было сырое `.system(.caption)` 12
                    // regular, тогда как весь мета-ряд вокруг — `.caption` 11
                    // medium): размер правится в шкале (LOCK-TYPOGRAPHY-UNIFY).
                    Text("#" + index).tfText(.caption).monospaced()
                }
                if let agentLine, !agentLine.isEmpty {
                    Label(agentLine, systemImage: "cpu")
                }
                ForEach(task.labels, id: \.id) { label in
                    TFLabelPill(label.name, color: Color(hex: label.color ?? TFHexDefault.unassigned)).layoutPriority(-1)
                }
            }
        }
        .buttonStyle(TFTapRowStyle())
    }


    private func close() {
        withAnimation(TFRowSwipe.settleAnimation(velocity: 0)) {
            settledOffset = 0
            dragOffset = 0
        }
        TFSwipeRowRegistry.shared.didClose(rowID)
    }

    // Пороги 1:1 с `TaskRow.tsx`: открытие >36px/280px·с⁻¹, закрытие
    // обратным сдвигом >25px/250px·с⁻¹ — асимметрично, легче закрыть, чем открыть.
    private func settle(dx: CGFloat, velocity: CGFloat) {
        let finalOffset = clamp(settledOffset + dx)
        withAnimation(TFRowSwipe.settleAnimation(velocity: velocity)) {
            if settledOffset == 0 {
                if swipeAction != nil, (finalOffset < -TFRowSwipe.openThreshold || velocity < -TFRowSwipe.openVelocity) {
                    settledOffset = -TFRowActionWidth
                } else if finalOffset > TFRowSwipe.openThreshold || velocity > TFRowSwipe.openVelocity {
                    // Открыть «Удалить» слева — те же пороги, что и для
                    // действия справа. confirmDelete срабатывает по тапу.
                    settledOffset = TFRowActionWidth
                } else {
                    settledOffset = 0
                }
            } else if settledOffset < 0 {
                settledOffset = (dx > TFRowSwipe.closeThreshold || velocity > TFRowSwipe.closeVelocity) ? 0 : -2 * TFRowActionWidth
            } else {
                settledOffset = (dx < -TFRowSwipe.closeThreshold || velocity < -TFRowSwipe.closeVelocity) ? 0 : TFRowActionWidth
            }
            dragOffset = 0
        }
        if settledOffset == 0 {
            TFSwipeRowRegistry.shared.didClose(rowID)
        } else {
            TFSwipeRowRegistry.shared.didOpen(rowID)
        }
    }

    /// «Резина» за пределом раскрытия — веб: `W + over × 30 / (30 + over)`.
    /// По одной кнопке с каждой стороны.
    private func clamp(_ raw: CGFloat) -> CGFloat {
        if raw < 0, swipeAction == nil { return 0 }
        let limit = TFRowActionWidth
        if raw > limit {
            let over = raw - limit
            return limit + (over * 30) / (30 + over)
        } else if raw < -limit {
            let over = -raw - limit
            return -limit - (over * 30) / (30 + over)
        }
        return raw
    }
}

/// Статус агента плоским текстом — дубль `TodayAgentStateTag` (`Features/Today/TodayFilters.swift`,
/// чужой файл), те же тексты/цвета AGENT-PROTOCOL.md.
enum DirectoryAgentStateTag {
    static func text(_ task: ApiTask) -> String? {
        guard let state = task.agentState else { return nil }
        return TFAgentStateTag.text(state, stale: task.agentStale == true)
    }

    static func color(_ task: ApiTask) -> Color {
        guard let state = task.agentState else { return .tfTeal }
        return TFAgentStateTag.color(state, stale: task.agentStale == true)
    }
}


/// Контекстное действие на свайпе влево (открывается кнопка справа).
/// Решение: владелец видит разное действие в зависимости от того, готов
/// ли он отдать задачу (флаг) или уже отдал (тогда можно сразу принять).
enum ProjectTaskSwipeAction: Equatable {
    /// Поднять флаг готовности (`ready_for_pickup=1`), чтобы агент мог взять.
    case markReadyForPickup
    /// Завершить задачу (зелёная галочка). Показывается для ВСЕХ
    /// не-завершённых задач с поднятым флагом готовности — владелец 11.09.2026
    /// попросил «если флаг поднят и задача не выполнена, всё равно чтобы
    /// галочка была зелёная принять». Покрывает и ревью (снимает блокировку),
    /// и просто активную задачу в пуле.
    case complete
    /// Вернуть задачу из архива в работу (10.10.2026, экран «Архив»).
    /// Отличается от `.complete` темп��м: свайп влево у архивной строки
    /// означает восстановление, а не закрытие задачи.
    case restore

    /// `currentUserID` — у личного дела (исполнитель — сам владелец) сразу
    /// «Принять», а не «Запустить»: запускать там некого (23.09.2026).
    static func action(for task: ApiTask, isOwner: Bool, currentUserID: String? = nil) -> Self? {
        guard isOwner else { return nil }
        guard task.status == .active else { return nil }
        if let me = currentUserID, task.assigneeId == me { return .complete }
        if !task.readyForPickup { return .markReadyForPickup }
        return .complete
    }

    var icon: String {
        switch self {
        case .complete: "checkmark"
        case .markReadyForPickup: "play.fill"
        case .restore: "arrow.uturn.backward"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .complete: "Принять"
        case .markReadyForPickup: "Запустить"
        case .restore: "Вернуть в работу"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .complete: "project.row.swipe.complete"
        case .markReadyForPickup: "project.row.swipe.ready"
        case .restore: "archive.row.swipe.restore"
        }
    }
}
