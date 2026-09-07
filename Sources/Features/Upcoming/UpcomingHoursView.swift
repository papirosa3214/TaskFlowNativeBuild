import SwiftUI
import UIKit

// Вид «Три дня» — spec/SCREENS-1.md §3.5 `DayHours` (та же сетка, что у
// «Сегодня», просто три колонки вместо одной). Числа — замер владельца,
// дробные значения ЗАКОННЫ, не округляются (спека): `HOUR_H=124/3`,
// `GUTTER_W=161/3`, `SNAP_MIN=15`, `MIN_H=24`.
//
// ⚠️ Хороший кандидат в общий кирпич (нужен и «Сегодня», один день — просьба
// оркестратора учла это заранее) — здесь сделан ЛОКАЛЬНО по правилу
// контракта («не хватает чужого — сделай локально»), в отчёте предлагаю
// оркестратору поднять в `DesignSystem`.
//
// Перетаскивание — И пул («без времени» → на сетку), И уже поставленная
// плашка на новое время/день (просьба владельца 03.09.2026: «задержал и
// передвинул эту плашку по времени»). Оба случая — свой `DragGesture`,
// тот же приём, что уже проверен и работает в «Сегодня»
// (`TodayHoursView.dragGesture`), расширенный на несколько дневных колонок
// сразу: день, над которым сейчас палец, вычисляется по X внутри общего
// именованного пространства координат `upcomingHoursGrid`.
//
// ⚠️ Системный `.draggable`/`.dropDestination` ПРОБОВАЛИ первым для ОБОИХ
// случаев (там, где готово из коробки — меньше кода) — не подошло ни разу:
// сперва для уже поставленной плашки, владелец 03.09.2026: «беру просто
// как тень, но она по сетке вообще не ездит», а после переноса пула на тот
// же приём выяснилось — тень СИСТЕМНОГО drag на этом экране вообще не
// цепляет `.dropDestination` внутри `GeometryReader`+`.position()`-раскладки
// надёжно, не только у уже поставленных плашек. Оставлять два разных
// механизма на одном экране (пул системным, плашки — своим) тоже было
// ошибкой само по себе — расхождение в поведении подряд путало владельца.
// Сейчас оба источника — один и тот же `dragGesture(for:dayIndex:top:height:)`,
// `top == nil` у пула (нет исходной позиции — куда палец, туда и время).
private let baseHourH: CGFloat = 124.0 / 3.0
private let gutterW: CGFloat = 161.0 / 3.0
private let snapMin = 15
private let minBlockH: CGFloat = 24
/// Если сервер ещё не прислал длительность, почасовая сетка использует тот
/// же минимальный слот, что создаётся при переносе задачи: 15 минут.
private let defaultDurationMin = 15
private let rightInset: CGFloat = 6
private let colGap: CGFloat = 3

struct UpcomingHourColumn: Identifiable {
    let date: String
    let tasks: [ApiTask]
    let isToday: Bool
    var id: String { date }
}

struct UpcomingHoursView: View {
    let days: [UpcomingHourColumn]
    let projectColor: (ApiTask) -> Color
    let onTaskTap: (String) -> Void
    /// Перенесли задачу из пула ИЛИ передвинули уже поставленную — назначить
    /// дату (колонки) и время.
    let onSchedule: (String, String, String) -> Void
    /// Горизонтальное перелистывание диапазона: `-1` — назад, `1` — вперёд.
    /// Размер шага определяет владелец данных: один день у «Сегодня», три
    /// дня у трёхдневного режима.
    let onPage: ((Int) -> Void)?
    /// В «Сегодня → Часы» верхняя подпись дня не повторяется: контекст уже
    /// задаёт нативная шапка «Планирования». В «Трёх днях» она остаётся.
    let showsDayHeader: Bool

    /// Два масштаба нужны только трёхдневной шкале. Выбор сохраняется между
    /// открытиями раздела; однодневная шкала всегда вмещает 15 минут целиком.
    @AppStorage("planner_three_day_expanded_timeline") private var isTimelineExpanded = false

    private var hourHeight: CGFloat {
        let fullQuarterHourHeight = (minBlockH + 3) * 4
        if !showsDayHeader { return fullQuarterHourHeight }
        return isTimelineExpanded ? fullQuarterHourHeight : baseHourH
    }

    init(
        days: [UpcomingHourColumn],
        projectColor: @escaping (ApiTask) -> Color,
        onTaskTap: @escaping (String) -> Void,
        onSchedule: @escaping (String, String, String) -> Void,
        onPage: ((Int) -> Void)? = nil,
        showsDayHeader: Bool = true
    ) {
        self.days = days
        self.projectColor = projectColor
        self.onTaskTap = onTaskTap
        self.onSchedule = onSchedule
        self.onPage = onPage
        self.showsDayHeader = showsDayHeader
    }

    private struct DragState {
        let taskID: String
        let title: String
        let color: Color
        let height: CGFloat
        /// Y верхнего края плашки в системе координат сетки (не пальца и не
        /// центра — см. заголовочный комментарий `TodayHoursView.swift`,
        /// та же логика).
        var topY: CGFloat
        var dayIndex: Int
    }

    @State private var dragState: DragState?
    @State private var previewTime: String?
    @State private var gridFrame: CGRect = .zero
    /// Смещение «где на плашке схватили» относительно её верхнего края —
    /// фиксируется один раз при старте жеста, 0 для пула (там перетаскивание
    /// системное, не через эту переменную).
    @State private var grabOffsetY: CGFloat = 0
    @State private var lastTickTime: String?
    /// Держим генераторы живыми и прогретыми (не пересоздаём на каждое
    /// срабатывание) — тот же приём, что и в `TodayHoursView`.
    @State private var grabHaptic = UIImpactFeedbackGenerator(style: .heavy)
    @State private var tickHaptic = UISelectionFeedbackGenerator()

    private var untimed: [ApiTask] {
        days.flatMap(\.tasks).filter { $0.startTime == nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsDayHeader {
                UpcomingDayColumnsHeader(days: days)
            }
            if !untimed.isEmpty {
                untimedPool
            }
            ScrollViewReader { proxy in
                ScrollView {
                    gridBody
                }
                .tfHoursNativeTopScrollEdge()
                .onAppear {
                    // Автопрокрутка к текущему часу с запасом 120px сверху (спека §3.5).
                    let hour = Calendar.current.component(.hour, from: Date())
                    DispatchQueue.main.async {
                        withAnimation { proxy.scrollTo("hour-\(max(0, hour - 1))", anchor: .top) }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coordinateSpace(name: "upcomingHoursGrid")
        .toolbar {
            if showsDayHeader {
                ToolbarItem(placement: .topBarLeading) {
                    Button { isTimelineExpanded.toggle() } label: {
                        Image(systemName: isTimelineExpanded
                            ? "arrow.down.right.and.arrow.up.left"
                            : "arrow.up.left.and.arrow.down.right")
                    }
                    .accessibilityLabel(isTimelineExpanded ? "Сжать временную шкалу" : "Расширить временную шкалу")
                }
            }
        }
        .gesture(
            UpcomingRangePageGesture { translation, velocity in
                guard let onPage, dragState == nil else { return }
                // Короткий медленный сдвиг остаётся случайным касанием. Для
                // флика учитываем скорость, как у системных paging-жестов.
                let projected = translation + velocity * 0.12
                guard abs(translation) >= 45 || abs(projected) >= 90 else { return }
                onPage(projected < 0 ? 1 : -1)
                UISelectionFeedbackGenerator().selectionChanged()
            }
        )
    }

    private var gridBody: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                gridRows
                HStack(spacing: 0) {
                    Color.clear.frame(width: gutterW)
                    ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                        dayColumn(day, index: index)
                    }
                }
                nowLine
            }
            .frame(width: geo.size.width, height: hourHeight * 24, alignment: .topLeading)
            .onAppear {
                grabHaptic.prepare()
                tickHaptic.prepare()
            }
        }
        .frame(height: hourHeight * 24)
        .background(GeometryReader { proxy in
            Color.clear.preference(key: UpcomingHoursGridFrameKey.self, value: proxy.frame(in: .named("upcomingHoursGrid")))
        })
        .onPreferenceChange(UpcomingHoursGridFrameKey.self) { gridFrame = $0 }
        .overlay(alignment: .topLeading) {
            if let dragState {
                let columnWidth = max(1, (gridFrame.width - gutterW) / CGFloat(max(days.count, 1)))
                ghostView(dragState, width: max(4, columnWidth - rightInset))
                    .offset(x: gutterW + CGFloat(dragState.dayIndex) * columnWidth, y: dragState.topY)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Пул задач без времени

    /// Оформление 1-в-1 с пулом «Сегодня» (`TodayHoursView.untimedPool`) —
    /// владелец 03.09.2026: «в трёх днях прицепил к краям, а в Сегодня
    /// аккуратненько висит». Там разница шла ещё и с внешней стороны —
    /// `TodayScreen` даёт всему `TodayHoursView` `.padding(.horizontal:)`
    /// снаружи, здесь `UpcomingHoursView` идёт от края до края (у сетки
    /// часов с тремя колонками свободного места и так впритык, ужимать
    /// не стоит) — поэтому боковой отступ добавлен ЛОКАЛЬНО, только пулу,
    /// а не всему экрану.
    private var untimedPool: some View {
        VStack(spacing: 0) {
            ForEach(Array(untimed.enumerated()), id: \.element.id) { index, task in
                if index > 0 { TFDivider() }
                UpcomingUntimedRow(task: task)
                    .opacity(dragState?.taskID == task.id ? 0.3 : 1)
                    .gesture(dragGesture(for: task, dayIndex: 0, top: nil, height: minBlockH))
                    .onTapGesture { if dragState == nil { onTaskTap(task.id) } }
            }
        }
        .background(Color.tfCard)
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.xl))
        .tfShadow(TFShadow.dropdown)
        .frame(maxHeight: 132)
        .padding(.horizontal, TFSpacing.lg)
        .padding(.bottom, TFSpacing.md)
    }

    // MARK: - Сетка часов

    private var gridRows: some View {
        VStack(spacing: 0) {
            ForEach(0..<25, id: \.self) { h in
                HStack(alignment: .top, spacing: 0) {
                    Text(String(format: "%02d:00", h))
                        .tfText(.micro)
                        .monospacedDigit()
                        .foregroundStyle(Color.tfDim)
                        .frame(width: gutterW, alignment: .trailing)
                        .padding(.trailing, 6)
                        .offset(y: -6)
                    Rectangle().fill(Color.tfStroke).frame(height: TFBorder.width)
                }
                .frame(height: h < 24 ? hourHeight : 0, alignment: .top)
                .id("hour-\(h)")
            }
        }
    }

    private func dayColumn(_ day: UpcomingHourColumn, index: Int) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ForEach(Self.layoutDay(day.tasks, hourHeight: hourHeight)) { block in
                    let isDragged = dragState?.taskID == block.task.id
                    UpcomingTimedBlock(
                        task: block.task,
                        color: projectColor(block.task),
                        durKnown: block.durKnown
                    )
                        .frame(width: Self.blockWidth(colWidth: geo.size.width, totalCols: block.totalCols))
                        .frame(height: block.height)
                        .position(
                            x: Self.blockLeft(colWidth: geo.size.width, col: block.col, totalCols: block.totalCols)
                                + Self.blockWidth(colWidth: geo.size.width, totalCols: block.totalCols) / 2,
                            y: block.top + block.height / 2
                        )
                        .opacity(isDragged ? 0 : 1)
                        .contentShape(Rectangle())
                        .gesture(dragGesture(for: block.task, dayIndex: index, top: block.top, height: block.height))
                        .onTapGesture { if dragState == nil { onTaskTap(block.task.id) } }
                }
            }
        }
        .overlay(alignment: .trailing) { Rectangle().fill(Color.tfStroke).frame(width: TFBorder.width) }
    }

    // MARK: - Перетаскивание — И пул, И уже поставленная плашка (см. заголовочный комментарий файла)

    /// `dayIndex` — исходное значение, только для конструктора `DragState`
    /// (пул им не владеет, передаёт 0 — сразу же на первом `onChanged`
    /// перевычисляется из X пальца). `top` — верхний край плашки ДО
    /// перетаскивания (`block.top`), нужен только чтобы вычислить точку
    /// захвата один раз в начале жеста; `nil` у пула (задача ещё без
    /// времени, точки захвата нет — куда палец, туда и время, как у
    /// «Сегодня»).
    private func dragGesture(for task: ApiTask, dayIndex: Int, top: CGFloat?, height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .named("upcomingHoursGrid"))
            .onChanged { value in
                let fingerX = value.location.x - gridFrame.minX
                let fingerY = value.location.y - gridFrame.minY
                let columnWidth = max(1, (gridFrame.width - gutterW) / CGFloat(max(days.count, 1)))
                let overDay = min(max(Int((fingerX - gutterW) / columnWidth), 0), max(days.count - 1, 0))
                if dragState?.taskID != task.id {
                    let startFingerY = value.startLocation.y - gridFrame.minY
                    grabOffsetY = top.map { startFingerY - $0 } ?? 0
                    lastTickTime = nil
                    grabHaptic.impactOccurred()
                    grabHaptic.prepare()
                    dragState = DragState(
                        taskID: task.id, title: task.title, color: projectColor(task),
                        height: max(minBlockH, height), topY: fingerY - grabOffsetY, dayIndex: overDay
                    )
                } else {
                    dragState?.topY = fingerY - grabOffsetY
                    dragState?.dayIndex = overDay
                }
                let time = Self.timeFromOffset(fingerY - grabOffsetY, hourHeight: hourHeight)
                previewTime = time
                if time != lastTickTime {
                    lastTickTime = time
                    tickHaptic.selectionChanged()
                    tickHaptic.prepare()
                }
            }
            .onEnded { value in
                let fingerX = value.location.x - gridFrame.minX
                let topY = value.location.y - gridFrame.minY - grabOffsetY
                let columnWidth = max(1, (gridFrame.width - gutterW) / CGFloat(max(days.count, 1)))
                let overDay = min(max(Int((fingerX - gutterW) / columnWidth), 0), max(days.count - 1, 0))
                dragState = nil
                previewTime = nil
                guard topY >= -hourHeight, days.indices.contains(overDay) else { return }
                onSchedule(task.id, days[overDay].date, Self.timeFromOffset(topY, hourHeight: hourHeight))
            }
    }

    private func ghostView(_ state: DragState, width: CGFloat) -> some View {
        Text(state.title)
            .tfText(.meta)
            .foregroundStyle(Color.tfHourChipInk)
            .lineLimit(nil)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(width: width, height: state.height, alignment: .topLeading)
            .background(state.color)
            .clipShape(RoundedRectangle(cornerRadius: TFRadius.sm))
            .shadow(color: .black.opacity(0.5), radius: 12, x: 0, y: 6)
            .scaleEffect(1.015)
    }

    private var nowLine: some View {
        let now = Date()
        let comps = Calendar.current.dateComponents([.hour, .minute], from: now)
        let pos = CGFloat(comps.hour ?? 0) * hourHeight + CGFloat(comps.minute ?? 0) / 60 * hourHeight
        return HStack(spacing: 4) {
            Text(String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0))
                .tfText(.micro)
                .monospacedDigit()
                .foregroundStyle(Color.tfRed)
                .frame(width: gutterW, alignment: .trailing)
                .background(Color.tfBackground)
            Circle().fill(Color.tfRed).frame(width: 7, height: 7)
            Rectangle().fill(Color.tfRed).frame(height: 1.5)
        }
        .offset(y: pos - 4)
        .allowsHitTesting(false)
    }

    // MARK: - Раскладка перекрывающихся задач (`layoutDay`, DayHours.tsx)

    private struct PlacedBlock: Identifiable {
        let task: ApiTask
        let top: CGFloat
        let height: CGFloat
        let col: Int
        let totalCols: Int
        let durKnown: Bool
        var id: String { task.id }
    }

    private static func hoursFromTime(_ t: String?) -> Double? {
        guard let (h, m) = DateFormats.localTimeComponents(t) else { return nil }
        return Double(h) + Double(m) / 60
    }

    private static func timeFromOffset(_ px: CGFloat, hourHeight: CGFloat) -> String {
        let raw = (px / hourHeight) * 60
        let snapped = (raw / CGFloat(snapMin)).rounded() * CGFloat(snapMin)
        let clamped = min(max(snapped, 0), CGFloat(24 * 60 - snapMin))
        let h = Int(clamped) / 60
        let m = Int(clamped) % 60
        return String(format: "%02d:%02d", h, m)
    }

    private static func blockWidth(colWidth: CGFloat, totalCols: Int) -> CGFloat {
        let totalGap = CGFloat(totalCols - 1) * colGap
        return max(4, (colWidth - rightInset - totalGap) / CGFloat(totalCols))
    }

    private static func blockLeft(colWidth: CGFloat, col: Int, totalCols: Int) -> CGFloat {
        col == 0 ? 0 : blockWidth(colWidth: colWidth, totalCols: totalCols) * CGFloat(col) + CGFloat(col) * colGap
    }

    private static func layoutDay(_ tasks: [ApiTask], hourHeight: CGFloat) -> [PlacedBlock] {
        struct Item { let task: ApiTask; let start: Double; let end: Double; let durKnown: Bool }
        let items = tasks.compactMap { t -> Item? in
            guard let start = hoursFromTime(t.startTime) else { return nil }
            let durKnown = t.durationMin != nil
            let dur = Double(t.durationMin ?? defaultDurationMin)
            return Item(task: t, start: start, end: start + dur / 60, durKnown: durKnown)
        }.sorted { $0.start != $1.start ? $0.start < $1.start : $0.end < $1.end }

        var placed: [PlacedBlock] = []
        var cluster: [Item] = []
        var clusterEnd = -Double.infinity

        func flush() {
            guard !cluster.isEmpty else { return }
            var colEnds: [Double] = []
            var colOf: [Int] = []
            for item in cluster {
                if let idx = colEnds.firstIndex(where: { $0 <= item.start }) {
                    colEnds[idx] = item.end
                    colOf.append(idx)
                } else {
                    colOf.append(colEnds.count)
                    colEnds.append(item.end)
                }
            }
            let cols = colEnds.count
            for (i, item) in cluster.enumerated() {
                placed.append(PlacedBlock(
                    task: item.task,
                    top: CGFloat(max(0, item.start * Double(hourHeight) + 1)),
                    height: max(minBlockH, CGFloat((item.end - item.start) * Double(hourHeight)) - 3),
                    col: colOf[i],
                    totalCols: cols,
                    durKnown: item.durKnown
                ))
            }
            cluster = []
        }

        for item in items {
            if !cluster.isEmpty, item.start >= clusterEnd {
                flush()
                clusterEnd = -Double.infinity
            }
            cluster.append(item)
            clusterEnd = max(clusterEnd, item.end)
        }
        flush()
        return placed
    }
}

/// Перелистывание временного диапазона поверх вертикального ScrollView.
///
/// Используется тот же направленный UIKit-recognizer, что у свайпов строк:
/// он проваливается при вертикальном движении и не отбирает прокрутку. Если
/// касание началось на карточке, paging ждёт исход собственного long-press:
/// быстрый горизонтальный свайп перелистывает, а удержание с переносом
/// карточки получает жест целиком и не меняет дату после отпускания.
private struct UpcomingRangePageGesture: UIGestureRecognizerRepresentable {
    let onEnded: (CGFloat, CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> HorizontalPanRecognizer {
        let recognizer = HorizontalPanRecognizer()
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: HorizontalPanRecognizer, context: Context) {
        switch recognizer.state {
        case .ended:
            onEnded(recognizer.horizontalTranslation, recognizer.velocity(in: recognizer.view).x)
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            otherGestureRecognizer is UILongPressGestureRecognizer
        }
    }
}

private extension View {
    @ViewBuilder
    func tfHoursNativeTopScrollEdge() -> some View {
        if #available(iOS 26.0, *) {
            self.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
    }
}

/// Заголовок колонок дня — уходит в `ScreenHeader.below` (спека §3.5, `DayColumnsHeader`).
struct UpcomingDayColumnsHeader: View {
    let days: [UpcomingHourColumn]
    var body: some View {
        HStack(spacing: 0) {
            // Без явной высоты гибкий Color забирает всю доступную высоту
            // родительского VStack и уводит подписи дней далеко вниз.
            Color.clear.frame(width: gutterW, height: 1)
            ForEach(days) { day in
                Text(UpcomingDate.formatDayColumnLabel(day.date))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(day.isToday ? Color.tfRed : Color.tfSub)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, TFSpacing.xs)
        .padding(.bottom, TFSpacing.sm)
        .background(Color.tfBackground)
    }
}

/// Плашка задачи без времени в пуле — spec §3.5, `UntimedRow`.
/// Раньше был `Button` — тот же конфликт Button+`DragGesture`, что и у
/// `UpcomingTimedBlock` (см. её комментарий). Тап и перетаскивание
/// навешаны в `untimedPool` двумя независимыми модификаторами.
private struct UpcomingUntimedRow: View {
    let task: ApiTask

    var body: some View {
        HStack(spacing: 8) {
            if task.priority <= 3, let p = TaskPriority(rawValue: task.priority) {
                TFPriorityFlag(p)
            }
            if !task.subtasks.isEmpty {
                Text("\(task.subtasks.count { $0.done })/\(task.subtasks.count)")
                    .font(.system(size: 11)).monospacedDigit().foregroundStyle(Color.tfDim)
            }
            Text(task.title)
                .tfText(.action)
                .foregroundStyle(task.status == .completed ? Color.tfSub : Color.tfText)
                .strikethrough(task.status == .completed)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.leading, 12)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

/// Плашка задачи на сетке — сплошная заливка цветом проекта, тёмный текст
/// (WCAG-аудит §3.5: белый текст не проходит норму ни на одном цвете палитры).
/// Раньше был `Button` — владелец 03.09.2026, после `.draggable`/
/// `.dropDestination` на уже поставленной плашке: «беру как тень, но не
/// ездит» (системный drag не отслеживал перетаскивание внутри
/// `.position()`-блока надёжно). Заменено на свой `DragGesture`, тот же
/// проверенный приём, что уже в «Сегодня» (`TodayHoursView`) — там ровно
/// по той же причине тап сделан `.onTapGesture` снаружи, а не `Button`
/// внутри (Button конкурирует с `DragGesture` за жест на одном и том же
/// касании). Тап и жест перетаскивания теперь оба навешаны в `dayColumn`.
private struct UpcomingTimedBlock: View {
    let task: ApiTask
    let color: Color
    let durKnown: Bool

    var body: some View {
        Text(task.title)
            .tfText(.meta)
            .foregroundStyle(Color.tfHourChipInk)
            .strikethrough(task.status == .completed)
            .lineLimit(nil)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(color)
            .opacity(task.status == .completed ? 0.5 : 1)
            .clipShape(RoundedRectangle(cornerRadius: TFRadius.sm))
            .mask(alignment: .top) {
                if durKnown {
                    Rectangle()
                } else {
                    LinearGradient(colors: [.black, .black, .clear], startPoint: .top, endPoint: .bottom)
                }
            }
    }
}

/// Живая рамка трёхдневной сетки в общем именованном пространстве
/// «upcomingHoursGrid». Перетаскивание из пула «без времени» целится по этой
/// рамке (в т.ч. колонка дня по X); кэш, снятый в `onAppear`, устаревал после
/// автопрокрутки сетки к текущему часу. Фоновый `GeometryReader` обновляет
/// рамку при скролле, а не только при смене размера.
private struct UpcomingHoursGridFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}
