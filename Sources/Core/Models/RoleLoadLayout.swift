import Foundation

/// Компоновка «Загрузки ролей»: контуры задач вместо строки на каждый заход.
///
/// Владелец 21.10.2026: «каждая задача занимает, грубо говоря, одну строчку…
/// из-за того, что бывает у кого-то очень много задач, она именно в высоту
/// расширяется. Но при этом они все коротенькие». Поэтому несколько заходов
/// одной задачи сворачиваются в один контур (заливка — фактическая занятость,
/// пустота внутри — простой), а контуры, не пересекающиеся по времени, встают
/// в одну дорожку: высота графика зависит от числа ОДНОВРЕМЕННЫХ задач, а не
/// от числа всех заходов.
struct RoleLoadLayout {

    /// Тон захода — цвет полосы внутри контура.
    enum Tone: Equatable {
        case done, failed, blocked, service, live
    }

    /// Откуда контур: заходы задачи или «идёт сейчас» без записи о попытке.
    enum Origin: Equatable {
        case task
        case liveMark
    }

    /// Один заход внутри контура.
    struct Segment: Identifiable, Equatable {
        let id: String
        let start: CGFloat
        let end: CGFloat
        let tone: Tone
    }

    /// Контур одной задачи: от первого до последнего её захода.
    struct Contour: Identifiable, Equatable {
        let id: String
        let taskID: String
        let title: String
        /// Короткий номер «МАК-ДДММ-ЧЧММ» — по нему задача опознаётся на графике.
        let number: String?
        let start: CGFloat
        let end: CGFloat
        let segments: [Segment]
        let origin: Origin
        /// Сколько места есть под подпись до следующего контура в дорожке:
        /// подпись не должна наезжать на соседнюю.
        var labelWidth: CGFloat = 0
    }

    /// Дорожка — ряд, в который встают непересекающиеся контуры.
    struct Lane: Equatable {
        let contours: [Contour]
    }

    /// Собранная роль: дорожки + слоты без исполнителя.
    struct RoleRow: Identifiable, Equatable {
        let id: String
        let title: String
        let lanes: [Lane]
        let open: [RoleLoad.OpenSlot]
        /// «Идёт сейчас» без записи о попытке — такие контуры рисуем отдельно
        /// по времени, они не дублируют уже нарисованную попытку.
        let liveMarks: [Contour]

        /// Занята ли роль прямо сейчас.
        var isBusy: Bool {
            !liveMarks.isEmpty || lanes.contains { lane in
                lane.contours.contains { $0.segments.contains { $0.tone == .live } }
            }
        }
    }

    /// Высота строки подписи над контуром.
    static let labelHeight: CGFloat = 12
    /// Высота полосы контура.
    static let barHeight: CGFloat = 20
    /// Шаг дорожки: подпись + полоса.
    static let laneStep: CGFloat = labelHeight + barHeight
    /// Минимальная ширина полосы: короткий заход иначе не виден.
    static let minBarWidth: CGFloat = 12
    /// Зазор между подписями соседних контуров в одной дорожке.
    static let labelGap: CGFloat = 6
    /// Минимальная ширина подписи — иначе номер не прочитать.
    static let minLabelWidth: CGFloat = 46

    /// Собирает компоновку по всем ролям.
    static func build(_ data: RoleLoad, width: CGFloat) -> [RoleRow] {
        data.rows.map { buildRow($0, data: data, width: width) }
    }

    private static func buildRow(_ row: RoleLoad.Row, data: RoleLoad, width: CGFloat) -> RoleRow {
        // 1. Заходы одной задачи — в один контур.
        var byTask: [String: [RoleLoad.Attempt]] = [:]
        for attempt in row.attempts { byTask[attempt.task_id, default: []].append(attempt) }

        var contours: [Contour] = []
        for (taskID, attempts) in byTask {
            let segments = attempts
                .map { attempt -> Segment in
                    let start = x(data, attempt.started_at, width)
                    let rawEnd = x(data, attempt.ended_at ?? data.now, width)
                    return Segment(
                        id: attempt.id,
                        start: start,
                        end: max(start + minBarWidth, rawEnd),
                        tone: tone(attempt)
                    )
                }
                .sorted { $0.start < $1.start }
            guard let first = segments.first, let last = segments.last else { continue }
            contours.append(Contour(
                id: taskID,
                taskID: taskID,
                title: attempts.first?.task_title ?? "",
                number: TaskNumber.text(forCreatedAt: attempts.first?.task_created_at),
                start: first.start,
                end: last.end,
                segments: segments,
                origin: .task
            ))
        }
        contours.sort { $0.start < $1.start }

        // 2. «Идёт сейчас» без записи о попытке — свой контур. Если же по
        //    задаче есть незакрытая попытка, она уже нарисована в контуре
        //    выше — второй полосы не делаем (иначе «идёт сейчас» дублируется).
        var marks: [Contour] = []
        for slot in row.active {
            let hasOpenAttempt = row.attempts.contains { $0.task_id == slot.task_id && $0.ended_at == nil }
            guard !hasOpenAttempt else { continue }
            let start = x(data, slot.started_at ?? slot.heartbeat_at ?? data.now, width)
            let now = x(data, data.now, width)
            marks.append(Contour(
                id: "live-\(slot.id)",
                taskID: slot.task_id,
                title: slot.task_title,
                number: TaskNumber.text(forCreatedAt: slot.task_created_at),
                start: start,
                end: max(start + minBarWidth, now),
                segments: [Segment(id: slot.id, start: start, end: max(start + minBarWidth, now), tone: .live)],
                origin: .liveMark
            ))
        }

        // 3. Дорожки: контуры, не пересекающиеся по времени, встают в один ряд.
        var lanes: [[Contour]] = []
        for contour in (contours + marks).sorted(by: { $0.start < $1.start }) {
            if let index = lanes.firstIndex(where: { lane in lane.allSatisfy { $0.end <= contour.start } }) {
                lanes[index].append(contour)
            } else {
                lanes.append([contour])
            }
        }

        // 4. Ширина подписи: до следующего контура в той же дорожке, иначе
        //    подписи наезжают друг на друга.
        let width2 = width
        let sized = lanes.map { lane -> Lane in
            var items = lane
            for index in items.indices {
                let limit = index + 1 < items.count ? items[index + 1].start : width2
                // Подпись занимает место до следующего контура в дорожке и
                // НИКОГДА не выходит за него — иначе номера наезжают друг
                // на друга. Слишком узкое место — подпись сжимается.
                let available = limit - items[index].start - labelGap
                items[index].labelWidth = max(0, available)
            }
            return Lane(contours: items)
        }

        return RoleRow(
            id: row.id,
            title: row.title,
            lanes: sized,
            open: row.open,
            liveMarks: marks
        )
    }

    /// Позиция времени на шкале (в пунктах от нуля).
    private static func x(_ data: RoleLoad, _ value: String, _ width: CGFloat) -> CGFloat {
        width * CGFloat(data.fraction(value))
    }

    private static func tone(_ attempt: RoleLoad.Attempt) -> Tone {
        if attempt.service == true { return .service }
        if attempt.active { return .live }
        switch attempt.outcome {
        case "failed": return .failed
        case "blocked": return .blocked
        default: return .done
        }
    }
}
