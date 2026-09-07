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
/// Визуальный пол высоты плашки в состоянии покоя И во время перетаскивания
/// (не путать с `minBlockH` — та участвует в формуле масштаба развёрнутой
/// шкалы, `minBlockH + 3) * 4`, трогать её нельзя, поменяется зум). Владелец
/// 07.09.2026, третий заход подряд: «карточка должна быть такой же плотной,
/// а не полоска» — короткие задачи (пул без времени, 15-минутные) рисовались
/// с высотой `minBlockH` (24pt) и в покое, и на драге — визуально читались
/// как тонкая полоска, а не как карточка с телом.
private let minCardBodyHeight: CGFloat = 44
/// Видимый диапазон суток — владелец 07.09.2026: «в 6 утра всё равно никто
/// не встаёт, в час ночи никто не встаёт», убрать портянку из пустых ночных
/// часов. Тот же диапазон, что у «Сегодня» (см. `TodayHoursMetrics`), но
/// этот файл — общий для «Сегодня → Часы» И «Три дня», своих констант нет.
private let startHour = 6
private let endHour = 22
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
        /// Реальная ширина колонки, снятая синхронным `GeometryReader` в
        /// `dayColumn` в момент захвата — НЕ пересчитывается из `gridFrame`
        /// (та обновляется асинхронно через `PreferenceKey` и в момент
        /// самого захвата бывает ещё не готова, отсюда «плавающая
        /// четвертинка» вместо нормальной ширины, владелец 07.09.2026).
        let width: CGFloat
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
                    // Автопрокрутка к текущему часу с запасом 120px сверху
                    // (спека §3.5), зажатая видимым диапазоном (владелец
                    // 07.09.2026: сетка теперь только startHour...endHour).
                    let hour = Calendar.current.component(.hour, from: Date())
                    let anchor = min(max(hour - 1, startHour), endHour)
                    DispatchQueue.main.async {
                        withAnimation { proxy.scrollTo("hour-\(anchor)", anchor: .top) }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                previewLine
            }
            .frame(width: geo.size.width, height: hourHeight * CGFloat(endHour - startHour), alignment: .topLeading)
            .onAppear {
                grabHaptic.prepare()
                tickHaptic.prepare()
            }
        }
        .frame(height: hourHeight * CGFloat(endHour - startHour))
        .background(GeometryReader { proxy in
            // `.global` вместо именованного пространства — жест теперь
            // `UIGestureRecognizerRepresentable` (см. `HoursDragGesture`
            // ниже), он отдаёт координаты через `converter.localToGlobal`,
            // именованное SwiftUI-пространство ему не нужно.
            Color.clear.preference(key: UpcomingHoursGridFrameKey.self, value: proxy.frame(in: .global))
        })
        .onPreferenceChange(UpcomingHoursGridFrameKey.self) { gridFrame = $0 }
        .overlay(alignment: .topLeading) {
            if let dragState {
                // Ширина ghost — из `dragState.width` (снята синхронно в
                // момент захвата, см. `DragState`), НЕ пересчитывается из
                // `gridFrame` (та обновляется асинхронно и в момент захвата
                // бывает ещё не готова). X-смещение по колонке дня — по
                // `gridFrame` по-прежнему, пол 80pt страхует только от
                // деления на почти-ноль, на позицию это не так критично,
                // как ширина самой плашки.
                let columnWidth = max(80, (gridFrame.width - gutterW) / CGFloat(max(days.count, 1)))
                ghostView(dragState, width: dragState.width)
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
        GeometryReader { geo in
            VStack(spacing: 0) {
                ForEach(Array(untimed.enumerated()), id: \.element.id) { index, task in
                    if index > 0 { TFDivider() }
                    UpcomingUntimedRow(task: task)
                        .opacity(dragState?.taskID == task.id ? 0.3 : 1)
                        .gesture(dragGesture(for: task, dayIndex: 0, top: nil, height: minBlockH, width: geo.size.width))
                        .onTapGesture { if dragState == nil { onTaskTap(task.id) } }
                }
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
            ForEach(startHour...endHour, id: \.self) { h in
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
                .frame(height: h < endHour ? hourHeight : 0, alignment: .top)
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
                        // Владелец 07.09.2026: «вся плашка исчезает, надо
                        // чтобы тень оставалась на старом месте» — приглушаем
                        // вместо полного скрытия.
                        .opacity(isDragged ? 0.35 : 1)
                        .contentShape(Rectangle())
                        // `HoursDragGesture` — свой `UIGestureRecognizerRepresentable`,
                        // см. заголовочный комментарий структуры ниже по файлу.
                        .gesture(dragGesture(for: block.task, dayIndex: index, top: block.top, height: block.height, width: Self.blockWidth(colWidth: geo.size.width, totalCols: block.totalCols)))
                        .onTapGesture { if dragState == nil { onTaskTap(block.task.id) } }
                        // `.position()` обязан идти ПОСЛЕДНИМ: он отдаёт
                        // родителю размер всего контейнера вместо размера
                        // плашки, и любой `.gesture`/`.onTapGesture`,
                        // навешанный ПОСЛЕ него, ловит касание по всей сетке,
                        // а не по видимой плашке.
                        .position(
                            x: Self.blockLeft(colWidth: geo.size.width, col: block.col, totalCols: block.totalCols)
                                + Self.blockWidth(colWidth: geo.size.width, totalCols: block.totalCols) / 2,
                            y: block.top + block.height / 2
                        )
                }
            }
        }
        .overlay(alignment: .trailing) { Rectangle().fill(Color.tfStroke).frame(width: TFBorder.width) }
    }

    // MARK: - Перетаскивание — И пул, И уже поставленная плашка (см. заголовочный комментарий файла)

    /// `dayIndex` — исходное значение, только для конструктора `DragState`
    /// (пул им не владеет, передаёт 0 — сразу же на первом обновлении
    /// пересчитывается из X пальца). `top` — верхний край плашки ДО
    /// перетаскивания (`block.top`), нужен только чтобы вычислить точку
    /// захвата один раз в начале жеста; `nil` у пула (задача ещё без
    /// времени, точки захвата нет — куда палец, туда и время).
    ///
    /// Владелец 07.09.2026, живой тест на iPhone Air: SwiftUI-жест
    /// (`LongPressGesture.sequenced(before: DragGesture)`, что через
    /// `.gesture`, что через `.simultaneousGesture`) не давал `ScrollView`
    /// прокручиваться, если палец стартовал прямо на карточке — тот же
    /// диагноз, что уже задокументирован в `HorizontalPan.swift` для свайпа
    /// строки. Решение оттуда же: `UIGestureRecognizerRepresentable` поверх
    /// `UILongPressGestureRecognizer` — он САМ проваливается, если палец
    /// уходит дальше `allowableMovement` (по умолчанию 10pt) до истечения
    /// `minimumPressDuration`, отдавая касание `ScrollView`; после успешного
    /// распознавания `.changed` как обычно несёт текущую позицию пальца без
    /// ограничения на смещение — то самое «зажал, потом веди».
    private static let dragHoldSeconds: Double = 0.25

    /// `width` — реальная ширина колонки/пула в точке вызова, снятая
    /// СИНХРОННЫМ `GeometryReader` (`dayColumn` уже его имеет; пул — своим,
    /// см. `untimedPool`), а не пересчитанная из асинхронного `gridFrame`.
    private func dragGesture(for task: ApiTask, dayIndex: Int, top: CGFloat?, height: CGFloat, width: CGFloat) -> some UIGestureRecognizerRepresentable {
        func columnAndDay(_ point: CGPoint) -> (fingerY: CGFloat, overDay: Int) {
            let fingerX = point.x - gridFrame.minX
            let fingerY = point.y - gridFrame.minY
            let columnWidth = max(80, (gridFrame.width - gutterW) / CGFloat(max(days.count, 1)))
            let overDay = min(max(Int((fingerX - gutterW) / columnWidth), 0), max(days.count - 1, 0))
            return (fingerY, overDay)
        }
        return HoursDragGesture(
            minimumPressDuration: Self.dragHoldSeconds,
            onBegin: { point in
                let (fingerY, overDay) = columnAndDay(point)
                grabOffsetY = top.map { fingerY - $0 } ?? 0
                lastTickTime = nil
                grabHaptic.impactOccurred()
                grabHaptic.prepare()
                dragState = DragState(
                    taskID: task.id, title: task.title, color: projectColor(task),
                    height: max(minBlockH, height), width: width, topY: fingerY - grabOffsetY, dayIndex: overDay
                )
                let time = Self.timeFromOffset(fingerY - grabOffsetY, hourHeight: hourHeight)
                previewTime = time
                lastTickTime = time
            },
            onChange: { point in
                guard dragState?.taskID == task.id else { return }
                let (fingerY, overDay) = columnAndDay(point)
                dragState?.topY = fingerY - grabOffsetY
                dragState?.dayIndex = overDay
                let time = Self.timeFromOffset(fingerY - grabOffsetY, hourHeight: hourHeight)
                previewTime = time
                if time != lastTickTime {
                    lastTickTime = time
                    tickHaptic.selectionChanged()
                    tickHaptic.prepare()
                }
            },
            onEnd: { point in
                guard dragState?.taskID == task.id else { return }
                let (fingerY, overDay) = columnAndDay(point)
                let topY = fingerY - grabOffsetY
                dragState = nil
                previewTime = nil
                guard topY >= -hourHeight, days.indices.contains(overDay) else { return }
                onSchedule(task.id, days[overDay].date, Self.timeFromOffset(topY, hourHeight: hourHeight))
            },
            onCancel: {
                guard dragState?.taskID == task.id else { return }
                dragState = nil
                previewTime = nil
            }
        )
    }

    /// Ghost рисуется не тоньше `minCardBodyHeight`, тот же порог, что у
    /// плашки в покое (`layoutDay`) — реальная (снапнутая) высота на
    /// итоговое размещение не влияет.
    private func ghostView(_ state: DragState, width: CGFloat) -> some View {
        Text(state.title)
            .tfText(.meta)
            .foregroundStyle(Color.tfHourChipInk)
            .lineLimit(nil)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(width: width, height: max(minCardBodyHeight, state.height), alignment: .topLeading)
            .background(state.color)
            .clipShape(RoundedRectangle(cornerRadius: TFRadius.sm))
            .shadow(color: .black.opacity(0.5), radius: 12, x: 0, y: 6)
            .scaleEffect(1.015)
    }

    @ViewBuilder
    private var nowLine: some View {
        let now = Date()
        let comps = Calendar.current.dateComponents([.hour, .minute], from: now)
        let hour = comps.hour ?? 0
        // Видимый диапазон теперь startHour...endHour, а не сутки целиком
        // (владелец 07.09.2026) — вне этого окна линия просто не рисуется.
        if hour >= startHour, hour < endHour {
            let pos = CGFloat(hour - startHour) * hourHeight + CGFloat(comps.minute ?? 0) / 60 * hourHeight
            HStack(spacing: 4) {
                Text(String(format: "%02d:%02d", hour, comps.minute ?? 0))
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
    }

    /// Точка + время во время перетаскивания, БЕЗ линии через всю сетку —
    /// владелец 07.09.2026: «зачем ты мне приебашил этот лазер на весь
    /// экран, я просил только точечку с цифрами». Раньше `previewTime`
    /// считался, но нигде не рисовался вообще.
    @ViewBuilder
    private var previewLine: some View {
        if let preview = previewTime, let minutes = Self.minutesFrom(preview) {
            let pos = CGFloat(minutes - startHour * 60) / 60 * hourHeight
            HStack(spacing: 4) {
                Text(preview)
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.tfRed)
                    .frame(width: gutterW, alignment: .trailing)
                    .background(Color.tfBackground)
                Circle().fill(Color.tfRed).frame(width: 7, height: 7)
            }
            .fixedSize()
            .offset(y: pos - 4)
            .allowsHitTesting(false)
        }
    }

    private static func minutesFrom(_ hhmm: String) -> Int? {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return parts[0] * 60 + parts[1]
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

    /// Смещение от верха сетки (0 = `startHour`) → «ЧЧ:ММ», зажатое видимым
    /// диапазоном `startHour...endHour` (владелец 07.09.2026).
    private static func timeFromOffset(_ px: CGFloat, hourHeight: CGFloat) -> String {
        let raw = (px / hourHeight) * 60
        let snapped = (raw / CGFloat(snapMin)).rounded() * CGFloat(snapMin)
        let startMin = CGFloat(startHour * 60)
        let endMin = CGFloat(endHour * 60)
        let clamped = min(max(snapped + startMin, startMin), endMin - CGFloat(snapMin))
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
                // Задачи ДО `startHour` (глубокая ночь) прижимаются к верху
                // сетки вместо отрицательных координат (владелец 07.09.2026).
                let hoursFromTop = item.start - Double(startHour)
                placed.append(PlacedBlock(
                    task: item.task,
                    top: CGFloat(max(0, hoursFromTop * Double(hourHeight) + 1)),
                    height: max(minCardBodyHeight, CGFloat((item.end - item.start) * Double(hourHeight)) - 3),
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

/// Перетаскивание карточки/плашки на почасовой сетке — тот же приём, что
/// `HorizontalPan` (см. заголовочный комментарий этого файла и
/// `HorizontalPan.swift`): SwiftUI `DragGesture`/`.simultaneousGesture`
/// объявляют себя хозяином касания раньше, чем `ScrollView` успевает решить,
/// прокрутка это или нет, и список не листается пальцем по карточке ни в
/// одном варианте (владелец 07.09.2026, живой тест на iPhone Air). Здесь
/// вместо своего распознавателя — штатный `UILongPressGestureRecognizer`:
/// он сам проваливается на движении больше `allowableMovement` до истечения
/// `minimumPressDuration`, отдавая касание `ScrollView`, а после успешного
/// распознавания продолжает нести текущую позицию пальца в `.changed` без
/// ограничения на смещение.
private struct HoursDragGesture: UIGestureRecognizerRepresentable {
    let minimumPressDuration: Double
    let onBegin: (CGPoint) -> Void
    let onChange: (CGPoint) -> Void
    let onEnd: (CGPoint) -> Void
    let onCancel: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = minimumPressDuration
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        let point = context.converter.location(in: .global)
        switch recognizer.state {
        case .began:
            // Владелец 07.09.2026: «скролл да, но лозит весь экран, я хочу
            // двигать карточку, а двигаю весь экран» — до успешного
            // распознавания прокрутке НЕ мешаем (быстрый свайп должен
            // скроллить), но как только жест реально начался (палец
            // удержан, карточка захвачена), прокрутку глушим на время
            // перетаскивания. `isScrollEnabled = false` — штатный способ
            // остановить `UIScrollView` целиком (не только его собственный
            // `panGestureRecognizer`), надёжнее точечного переключения
            // одного распознавателя.
            Self.enclosingScrollView(of: recognizer.view)?.isScrollEnabled = false
            onBegin(point)
        case .changed:
            onChange(point)
        case .ended:
            Self.enclosingScrollView(of: recognizer.view)?.isScrollEnabled = true
            onEnd(point)
        case .cancelled, .failed:
            Self.enclosingScrollView(of: recognizer.view)?.isScrollEnabled = true
            onCancel()
        default:
            break
        }
    }

    /// Владелец 07.09.2026, диагностика через unified log: `recognizer.view`
    /// у `UIGestureRecognizerRepresentable` — это ХОСТИНГ-VIEW всего экрана
    /// целиком (`frame = 402x874`, весь экран), а не маленькая вьюха
    /// карточки. Реальный `UIScrollView` от SwiftUI `ScrollView` — ПОТОМОК
    /// этого хостинга, а не предок: поиск вверх по `.superview` (как было)
    /// гарантированно возвращал `nil`, отсюда скролл не глушился ни разу.
    /// Ищем вниз по `.subviews` (BFS от самого хостинга).
    private static func enclosingScrollView(of view: UIView?) -> UIScrollView? {
        guard let root = view else { return nil }
        var queue: [UIView] = [root]
        while !queue.isEmpty {
            let current = queue.removeFirst()
            if let scrollView = current as? UIScrollView { return scrollView }
            queue.append(contentsOf: current.subviews)
        }
        return nil
    }

    /// До момента `.began` прокрутке не мешаем — тот же приём, что у
    /// `HorizontalPan.Coordinator`; сама блокировка активной прокрутки — в
    /// `handleUIGestureRecognizerAction` выше, через `isScrollEnabled`.
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
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
