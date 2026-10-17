import SwiftUI

struct CompletionDay: Identifiable {
    var id: Date { date }
    let date: Date
    let count: Int
    let month: Int
    let monthLabel: String
    let accessibilityLabel: String
    let shortLabel: String
    let isFuture: Bool
    let shade: Color
    let rightShade: Color
    let frontShade: Color

    init(date: Date, count: Int, maxCount: Int, now: Date, calendar: Calendar) {
        self.date = date
        self.count = count
        month = calendar.component(.month, from: date)
        monthLabel = date.formatted(.dateTime.month(.abbreviated))
        accessibilityLabel = date.formatted(date: .abbreviated, time: .omitted) + ": на проверку \(count)"
        shortLabel = date.formatted(.dateTime.day().month(.abbreviated))
        isFuture = date > calendar.startOfDay(for: now)
        let color = HeatmapShade.shade(count, maxCount: maxCount)
        shade = color
        rightShade = color.mix(with: .black, by: 0.20)
        frontShade = color.mix(with: .black, by: 0.08)
    }
}

enum CompletionCalendar {
    static let initialDays = days(dates: [])
    static func days(dates: [Date], now: Date = .now, calendar: Calendar = .current) -> [CompletionDay] {
        let today = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: today)
        let monday = calendar.date(byAdding: .day, value: -((weekday + 5) % 7), to: today)!
        let start = calendar.date(byAdding: .day, value: -175, to: monday)!
        let counts = Dictionary(grouping: dates, by: { calendar.startOfDay(for: $0) }).mapValues(\.count)
        let dates = (0..<182).map { calendar.date(byAdding: .day, value: $0, to: start)! }
        let maxCount = max(1, dates.map { counts[$0, default: 0] }.max() ?? 1)
        return dates.map { date in
            CompletionDay(date: date, count: counts[date, default: 0], maxCount: maxCount, now: now, calendar: calendar)
        }
    }
}

/// Кривая раскатки объёма карты.
///
/// Держится линейной с мягкими краями: кубический in-out отдавал первую
/// десятую пути 0.2% движения, а третью–шестую — 78%, из-за чего карта сначала
/// «ватала», а потом разом становилась объёмной. `rise` тоже линейный: ease-out
/// поднимал столбик мгновенно, и последние колонки догоняли у самого финиша.
enum HeatmapExpansion {
    static func cameraEase(_ t: CGFloat) -> CGFloat {
        let t = min(1, max(0, t))
        let eased = t * t * (3 - 2 * t)
        return t + (eased - t) * 0.18
    }
    // Reveal the plane's depth early instead of spending half the drag orbiting a flat grid.
    static func tiltProgress(_ progress: CGFloat) -> CGFloat {
        let t = min(1, max(0, progress))
        return sin(t * .pi / 2)
    }
    static func rise(_ progress: CGFloat) -> CGFloat {
        min(1, max(0, progress))
    }
}

/// Градация карты: серый пустой день и 32 ступени чистого красного.
///
/// Пороги раньше были жёсткими (1 | 2–3 | 4–6 | 7+), но максимум дня на живых
/// данных — 25. Бакет «7+» накрывал 7…25, то есть девятнадцать разных
/// количеств красились одинаково, и соседние ступени читались как одна.
enum HeatmapShade {
    static let steps = 32

    /// Номер ступени для количества проверок, `nil` означает «пусто».
    ///
    /// Делим диапазон по корню: при линейном делении низкие значения попадали
    /// в одну ступень. Корень разводит их.
    static func step(_ count: Int, maxCount: Int) -> Int? {
        guard count > 0 else { return nil }
        guard maxCount > 1 else { return steps }
        let index = Int(ceil(sqrt(Double(count) / Double(maxCount)) * Double(steps)))
        return min(max(index, 1), steps)
    }

    /// Reference ramp: #080000, #100000, …, #F80000, #FF0000.
    /// Only the red channel changes; empty days retain tfStroke.
    static func color(_ step: Int) -> Color {
        let index = min(max(step, 1), steps)
        let red = index == steps ? 255 : index * 8
        return Color(red: Double(red) / 255, green: 0, blue: 0)
    }

    static func shade(_ count: Int, maxCount: Int) -> Color {
        guard let step = step(count, maxCount: maxCount) else { return Color.tfStroke }
        return color(step)
    }
}

struct CompletionHeatmap: View {
    var depth: CGFloat = 0
    @Environment(TaskStore.self) private var store
    @State private var selected: Date?
    @State private var selectedPoint: CGPoint?
    @State private var selectedObstacles: [CGRect] = []
    @State private var sceneWidth: CGFloat = 0
    @Environment(RealtimeClient.self) private var realtime
    @State private var days = CompletionCalendar.initialDays
    @State private var archiveError = false
    @State private var historyLoaded = false
    private var historyRevision: String {
        "\(realtime.connectionRevision):" + realtime.taskRevisions.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: ",")
    }

    /// Самый продуктивный день поднявшейся карты — заполняет левый нижний угол,
    /// который при объёме остаётся пустым.
    private var recordDay: CompletionDay? {
        days.filter { $0.count > 0 && $0.isFuture == false }
            .max { $0.count < $1.count }
    }

    private var recordBadge: some View {
        // Гейтим по depth, а не только opacity: у элемента с opacity(0) всё равно
        // остаётся в дереве доступности, и VoiceOver читал бы рекорд на плоской
        // карте, где его не видно.
        Group {
            if let day = recordDay, depth > 0.42 {
                let appear = min(1, max(0, (depth - 0.42) / 0.33))
                let eased = appear * appear * (3 - 2 * appear)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Рекорд дня")
                        .font(.caption2).foregroundStyle(Color.tfSub)
                    Text("\(day.count)")
                        .tfText(.heatmapCount)
                        .foregroundStyle(Color.tfRed)
                    Text(day.shortLabel)
                        .font(.caption2).foregroundStyle(Color.tfSub)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Рекорд дня: \(day.count), \(day.shortLabel)")
                .accessibilityIdentifier("overview.heatmap.record")
                .opacity(eased)
                .offset(y: 10 * (1 - eased))
            }
        }
    }

    private var todayBadge: some View {
        Group {
            if let day = days.first(where: { Calendar.current.isDateInToday($0.date) }), historyLoaded, depth > 0.42 {
                let appear = min(1, max(0, (depth - 0.42) / 0.33))
                let eased = appear * appear * (3 - 2 * appear)
                VStack(alignment: .trailing, spacing: 1) {
                    Text("Сегодня")
                        .font(.caption2).foregroundStyle(Color.tfSub)
                    Text("\(day.count)")
                        .tfText(.heatmapCount)
                        .foregroundStyle(day.shade)
                    Text(day.shortLabel)
                        .font(.caption2).foregroundStyle(Color.tfSub)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Сегодня, на проверку: \(day.count), \(day.shortLabel)")
                .accessibilityIdentifier("overview.heatmap.today")
                .opacity(eased)
                .offset(y: 10 * (1 - eased))
                .offset(y: -10)
            }
        }
    }

    private var maxDayCount: Int {
        max(1, days.map(\.count).max() ?? 1)
    }

    var body: some View {
        let values = days
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geometry in
                let pitch = (geometry.size.width + 3) / 26
                ForEach(0..<26, id: \.self) { week in
                    let month = values[week * 7].month
                    let previous = week == 0 ? -1 : values[(week - 1) * 7].month
                    if month != previous {
                        Text(values[week * 7].monthLabel)
                            .font(.caption).foregroundStyle(Color.tfSub)
                            .fixedSize().offset(x: CGFloat(week) * pitch)
                    }
                }
            }.frame(height: 16 * (1 - HeatmapExpansion.cameraEase(depth)))
                .opacity(1 - HeatmapExpansion.cameraEase(depth))
            GeometryReader { geometry in
                let sceneSize = CGSize(width: geometry.size.width, height: geometry.size.width * 7 / 26 + depth * 120)
                ZStack(alignment: .topLeading) {
                    HeatmapScene(values: values, depth: depth, selected: $selected, selectedPoint: $selectedPoint, selectedObstacles: $selectedObstacles)
                        .frame(width: sceneSize.width, height: sceneSize.height)
                    if let date = selected,
                       let day = values.first(where: { $0.date == date }),
                       let point = selectedPoint {
                        HeatmapDayCallout(day: day, anchor: point, sceneSize: sceneSize, obstacles: selectedObstacles)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                }
                .frame(width: sceneSize.width, height: sceneSize.height)
                .animation(.easeOut(duration: 0.16), value: selected)
            }
                .frame(height: sceneWidth * 7 / 26 + depth * 120)
                .overlay(alignment: .bottomLeading) {
                    // Вне сцены: её accessibilityRepresentation заменяет потомков,
                    // и бейдж внутри неё не попадал в дерево доступности.
                    recordBadge
                        .padding(.leading, 2).padding(.bottom, 8)
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .topTrailing) {
                    todayBadge
                        .padding(.trailing, 2).padding(.top, 8)
                        .allowsHitTesting(false)
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { sceneWidth = $0 }
            HStack(spacing: 5) {
                Text("Меньше")
                // Sample the complete ramp in a compact legend; all 32 steps remain in the map.
                ForEach([0, 1, 8, 16, 24, 32], id: \.self) { step in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(step == 0 ? Color.tfStroke : HeatmapShade.color(step))
                        .frame(width: 10, height: 10)
                }
                Spacer(minLength: 0)
            }.font(.caption2).foregroundStyle(Color.tfSub)
            if archiveError {
                Button("История недоступна · Повторить") { Task { await loadArchive() } }.font(.caption)
            }
        }
        .task(id: historyRevision) { await loadArchive() }
    }
    private struct ReviewHistory: Decodable {
        struct Entry: Decodable {
            let task_id: String
            let submitted_at: String
        }
        let entries: [Entry]
    }
    private func loadArchive() async {
        do {
            let response: ReviewHistory = try await APIClient().request(.get, "/stats/review-history")
            let reviewDates = Dictionary(uniqueKeysWithValues: response.entries.compactMap { entry in
                DateFormats.sqliteUTC(entry.submitted_at).map { (entry.task_id, $0) }
            })
            days = CompletionCalendar.days(dates: Array(reviewDates.values))
            historyLoaded = true
            archiveError = false
        } catch is CancellationError { }
        catch { archiveError = true }
    }
}

private struct HeatmapDayCallout: View {
    let day: CompletionDay
    let anchor: CGPoint
    let sceneSize: CGSize
    let obstacles: [CGRect]

    private var labelSize: CGSize {
        let dateWidth = CGFloat(day.shortLabel.count) * 8
        let countWidth = CGFloat(String(day.count).count) * 14 + 8
        return CGSize(width: max(dateWidth, countWidth), height: 48)
    }

    private var underlineWidth: CGFloat { CGFloat(String(day.count).count) * 14 + 8 }

    private var candidateCenters: [CGPoint] {
        let halfWidth = labelSize.width / 2
        let halfHeight = labelSize.height / 2
        let minX = min(halfWidth + 4, sceneSize.width / 2)
        let maxX = max(minX, sceneSize.width - halfWidth - 4)
        let minY = min(halfHeight + 4, sceneSize.height / 2)
        let maxY = max(minY, sceneSize.height - halfHeight - 4)
        let anchorX = min(max(anchor.x, minX), maxX)
        let aboveY = min(max(anchor.y - halfHeight - 10, minY), maxY)
        let belowY = min(max(anchor.y + halfHeight + 10, minY), maxY)
        let xs = [minX, (minX + maxX) / 2, maxX, anchorX]
        let ys = [minY, (minY + maxY) / 2, maxY, aboveY, belowY]
        return xs.flatMap { x in ys.map { CGPoint(x: x, y: $0) } }
    }

    private var center: CGPoint {
        let reserved = [
            CGRect(x: 0, y: max(0, sceneSize.height - 84), width: min(142, sceneSize.width), height: 84),
            CGRect(x: max(0, sceneSize.width - 112), y: 0, width: min(112, sceneSize.width), height: 92),
            CGRect(x: 0, y: max(0, sceneSize.height - 26), width: sceneSize.width, height: 26)
        ]
        func score(_ point: CGPoint) -> CGFloat {
            let rect = CGRect(
                x: point.x - labelSize.width / 2,
                y: point.y - labelSize.height / 2,
                width: labelSize.width,
                height: labelSize.height
            )
            let overlapArea = obstacles.reduce(CGFloat.zero) { total, obstacle in
                let intersection = rect.intersection(obstacle)
                return total + (intersection.isNull ? 0 : intersection.width * intersection.height)
            }
            let reservedOverlap = reserved.reduce(CGFloat.zero) { total, zone in
                let intersection = rect.intersection(zone)
                return total + (intersection.isNull ? 0 : intersection.width * intersection.height)
            }
            let distance = hypot(point.x - anchor.x, point.y - anchor.y)
            return reservedOverlap * 10_000 + overlapArea * 100 + distance
        }
        return candidateCenters.min { score($0) < score($1) } ?? CGPoint(x: sceneSize.width / 2, y: sceneSize.height / 2)
    }

    private var underlineRect: CGRect {
        CGRect(x: center.x - underlineWidth / 2, y: center.y + labelSize.height / 2 - 5,
               width: underlineWidth, height: 1)
    }

    private var underlineAnchor: CGPoint {
        CGPoint(
            x: anchor.x <= center.x ? underlineRect.minX : underlineRect.maxX,
            y: underlineRect.midY
        )
    }

    var body: some View {
        ZStack {
            Path { path in
                path.move(to: anchor)
                path.addLine(to: underlineAnchor)
                path.addLine(to: CGPoint(
                    x: anchor.x <= center.x ? underlineRect.maxX : underlineRect.minX,
                    y: underlineRect.midY
                ))
            }
            .stroke(day.shade, style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))

            Circle()
                .fill(day.shade)
                .frame(width: 7, height: 7)
                .overlay(Circle().stroke(Color.tfBackground, lineWidth: 1.5))
                .position(anchor)

            VStack(alignment: .center, spacing: 0) {
                Text(day.shortLabel)
                    .tfText(.caption)
                    .foregroundStyle(Color.tfSub)
                    .accessibilityIdentifier("overview.heatmap.selection.date")
                Text("\(day.count)")
                    .tfText(.taskTitle)
                    .foregroundStyle(day.shade)
                    .accessibilityIdentifier("overview.heatmap.selection.count")
            }
            .frame(width: labelSize.width, height: labelSize.height, alignment: .center)
            .position(center)
        }
        .frame(width: sceneSize.width, height: sceneSize.height)
        .allowsHitTesting(false)
    }
}

/// Orthographic projection of the same daily cells; height follows actual counts.
private struct HeatmapScene: View, Animatable {
    let values: [CompletionDay]
    var depth: CGFloat
    @Binding var selected: Date?
    @Binding var selectedPoint: CGPoint?
    @Binding var selectedObstacles: [CGRect]
    @State private var sceneSize: CGSize = .zero
    var animatableData: CGFloat {
        get { depth }
        set { depth = newValue }
    }

    private func polygon(_ points: [CGPoint]) -> Path {
        Path { path in
            path.addLines(points)
            path.closeSubpath()
        }
    }
    private func contains(_ point: CGPoint, in cell: (day: CompletionDay, week: Int, row: Int, top: [CGPoint], base: [CGPoint])) -> Bool {
        if polygon(cell.top).contains(point) { return true }
        guard depth > 0.001 else { return false }
        let right = polygon([cell.top[1], cell.top[2], cell.base[2], cell.base[1]])
        let front = polygon([cell.top[2], cell.top[3], cell.base[3], cell.base[2]])
        return right.contains(point) || front.contains(point)
    }
    private func anchor(for date: Date, in size: CGSize) -> CGPoint? {
        guard let cell = cells(in: size).first(where: { $0.day.date == date }) else { return nil }
        let count = CGFloat(cell.top.count)
        return CGPoint(
            x: cell.top.reduce(CGFloat.zero) { $0 + $1.x } / count,
            y: cell.top.reduce(CGFloat.zero) { $0 + $1.y } / count
        )
    }
    private func towerBounds(in size: CGSize) -> [CGRect] {
        cells(in: size).compactMap { cell in
            guard cell.day.count > 0 else { return nil }
            let points = cell.top + cell.base
            guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
                  let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() else { return nil }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).insetBy(dx: -3, dy: -3)
        }
    }
    private func cells(in size: CGSize) -> [(day: CompletionDay, week: Int, row: Int, top: [CGPoint], base: [CGPoint])] {
        let size = CGSize(width: size.width, height: max(1, size.height - 24 * HeatmapExpansion.cameraEase(depth)))
        let t = min(1, max(0, depth))
        let e = HeatmapExpansion.cameraEase(t)
        let pitch = (size.width + 3) / 26
        // Preserve the existing flat cells; match the source's 0.78 → 0.90 ratio.
        let flatSide = pitch - 3
        let side = flatSide * (1 + (0.90 / 0.78 - 1) * e)
        let offset = (flatSide - side) / 2
        let yaw = CGFloat.pi / 4 * e
        let tilt = CGFloat.pi * (56.0 / 180) * HeatmapExpansion.tiltProgress(t)
        let maxCount = max(1, values.map(\.count).max() ?? 1)
        func columnHeight(_ week: Int, _ row: Int) -> CGFloat {
            let count = values[week * 7 + row].count
            let delay = CGFloat(week) / 25 * 0.36 + CGFloat(row) / 6 * 0.06
            let progress = min(1, max(0, (t - delay) / 0.58))
            let rise = HeatmapExpansion.rise(progress)
            let units: CGFloat = count > 0 ? 0.4 + pow(CGFloat(count) / CGFloat(maxCount), 0.85) * 7.2 : 0.2
            return units * pitch * rise
        }
        let yawCos = cos(yaw), yawSin = sin(yaw)
        let tiltCos = cos(tilt), tiltSin = sin(tilt)
        func raw(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> CGPoint {
            let xx = x * yawCos - y * yawSin
            let yy = (x * yawSin + y * yawCos) * tiltCos - z * tiltSin
            return CGPoint(x: xx, y: yy)
        }
        var bounds: [CGPoint] = []
        // Fit both ground and actual tops, including each intermediate wave frame.
        for week in 0..<26 {
            for row in 0..<7 {
                let height = columnHeight(week, row)
                let x = CGFloat(week) * pitch + offset, y = CGFloat(row) * pitch + offset
                for (cx, cy) in [(x,y),(x+side,y),(x+side,y+side),(x,y+side)] {
                    bounds.append(raw(cx, cy, height))
                    bounds.append(raw(cx, cy, 0))
                }
            }
        }
        let minX = bounds.map(\.x).min()!, maxX = bounds.map(\.x).max()!
        let minY = bounds.map(\.y).min()!, maxY = bounds.map(\.y).max()!
        let scale = min(size.width / max(1, maxX - minX), size.height / max(1, maxY - minY))
        func project(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> CGPoint {
            let p = raw(x, y, z)
            return CGPoint(x: (p.x - (minX + maxX) / 2) * scale + size.width / 2,
                           y: (p.y - (minY + maxY) / 2) * scale + size.height / 2)
        }
        return (0..<182).map { slot in
            let week = slot % 26, row = slot / 26
            let day = values[week * 7 + row]
            let x = CGFloat(week) * pitch + offset, y = CGFloat(row) * pitch + offset
            let height = columnHeight(week, row)
            let corners = [(x,y),(x+side,y),(x+side,y+side),(x,y+side)]
            return (day, week, row, corners.map { project($0.0, $0.1, height) }, corners.map { project($0.0, $0.1, 0) })
        }.sorted { $0.base.map(\.y).max()! < $1.base.map(\.y).max()! }
    }
    var body: some View {
        Canvas { context, size in
            let sceneCells = cells(in: size)
            for cell in sceneCells {
                let top = cell.top, base = cell.base
                let shade = cell.day.shade
                if depth > 0.001 {
                    let right = polygon([top[1],top[2],base[2],base[1]])
                    let front = polygon([top[2],top[3],base[3],base[2]])
                    context.fill(right, with: .color(cell.day.rightShade))
                    context.fill(front, with: .color(cell.day.frontShade))
                    context.stroke(right, with: .color(.black.opacity(0.7 * depth)), lineWidth: 0.6)
                    context.stroke(front, with: .color(.black.opacity(0.65 * depth)), lineWidth: 0.5)
                }
                if depth < 0.001 {
                    context.fill(Path(roundedRect: CGRect(x: top[0].x, y: top[0].y, width: top[1].x-top[0].x, height: top[3].y-top[0].y), cornerRadius: 2), with: .color(shade))
                } else {
                    context.fill(polygon(top), with: .color(shade))
                    context.stroke(polygon(top), with: .color(.black.opacity(0.75 * depth)), lineWidth: 0.65)
                }
            }
            let labelOpacity = HeatmapExpansion.cameraEase(depth)
            if labelOpacity > 0.001 {
                for week in 0..<26 {
                    let month = values[week * 7].month
                    let previous = week == 0 ? -1 : values[(week - 1) * 7].month
                    guard month != previous,
                          let cell = sceneCells.first(where: { $0.week == week && $0.row == 6 }) else { continue }
                    let edge = cell.base[3]
                    let dx = cell.base[2].x - edge.x, dy = cell.base[2].y - edge.y
                    let length = max(1, hypot(dx, dy))
                    var labelContext = context
                    labelContext.opacity = labelOpacity
                    labelContext.translateBy(x: edge.x + dx / length * 5 - dy / length * 7, y: edge.y + dy / length * 5 + dx / length * 7)
                    labelContext.rotate(by: .radians(Double(atan2(dy, dx))))
                    labelContext.draw(Text(values[week * 7].monthLabel)
                        .font(.caption).foregroundStyle(Color.tfSub), at: .zero, anchor: .topLeading)
                }
            }
        }
        .contentShape(Rectangle())
        .overlay {
            GeometryReader { geometry in
                Color.clear
                    .contentShape(Rectangle())
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { sceneSize = $0 }
                    .onTapGesture { location in
                        let hit = cells(in: geometry.size).reversed().first(where: { contains(location, in: $0) })
                        guard let cell = hit, !cell.day.isFuture else {
                            selected = nil
                            selectedPoint = nil
                            selectedObstacles = []
                            return
                        }
                        if selected == cell.day.date {
                            selected = nil
                            selectedPoint = nil
                            selectedObstacles = []
                        } else {
                            selected = cell.day.date
                            selectedPoint = anchor(for: cell.day.date, in: geometry.size)
                            selectedObstacles = towerBounds(in: geometry.size)
                        }
                    }
            }
        }
        .accessibilityRepresentation {
            VStack {
                Text(depth > 0.99 ? "Объёмная тепловая карта" : "Плоская тепловая карта")
                    .accessibilityIdentifier("overview.heatmap.mode")
                    .accessibilityValue(depth > 0.99 ? "Объёмная" : depth < 0.01 ? "Плоская" : "Переход")
                Text(depth > 0.99 ? "Месяцы вдоль нижнего края карты" : "Месяцы над картой")
                    .accessibilityIdentifier("overview.heatmap.month-position")
                Grid(horizontalSpacing: 3, verticalSpacing: 3) {
                    ForEach(0..<7, id: \.self) { row in
                        GridRow {
                            ForEach(0..<26, id: \.self) { week in
                                let slot = week * 7 + row
                                let day = values[(slot % 26) * 7 + slot / 26]
                                Button {
                                    selected = day.date
                                    selectedPoint = anchor(for: day.date, in: sceneSize)
                                    selectedObstacles = towerBounds(in: sceneSize)
                                } label: {
                                    Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .contentShape(Rectangle())
                                }
                                .disabled(day.isFuture)
                                .accessibilityLabel(day.accessibilityLabel)
                                .accessibilityIdentifier("overview.heatmap.cell.\(slot)")
                            }
                        }
                    }
                }
            }
        }
    }
}
