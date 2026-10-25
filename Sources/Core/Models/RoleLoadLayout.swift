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
        /// Ход роли в чате без карточки — работа в чате.
        case chat
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

    /// Контур работы в чате: один-два хода роли в одном чате, идущих рядом.
    /// Подпись — название работы из отчёта роли по этому ходу.
    struct ChatContour: Identifiable, Equatable {
        let id: String
        let title: String
        let chatTitle: String?
        let start: CGFloat
        let end: CGFloat
        let segments: [Segment]
        /// Сколько места есть под подпись до следующего контура в дорожке.
        var labelWidth: CGFloat = 0
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
        /// Работа роли в чате без карточки — свои дорожки ниже карточных.
        let chatLanes: [[ChatContour]]

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
        // Положение «сейчас» одно на всю строку — считаем один раз, а не на
        // каждый активный слот (раньше дата разбиралась заново в каждом витке).
        let nowX = x(data, data.now, width)
        for slot in row.active {
            let hasOpenAttempt = row.attempts.contains { $0.task_id == slot.task_id && $0.ended_at == nil }
            guard !hasOpenAttempt else { continue }
            let start = x(data, slot.started_at ?? slot.heartbeat_at ?? data.now, width)
            let now = nowX
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
            liveMarks: marks,
            chatLanes: chatLanes(row.chat, data: data, width: width)
        )
    }

    /// Работа в чате: ходы одной роли в одном чате, идущие рядом (пауза до
    /// 10 минут), сворачиваются в один контур с названием работы.
    private static func chatLanes(_ turns: [RoleLoad.ChatTurn], data: RoleLoad, width: CGFloat) -> [[ChatContour]] {
        guard !turns.isEmpty else { return [] }
        let sorted = turns.sorted { $0.started_at < $1.started_at }
        var groups: [[RoleLoad.ChatTurn]] = []
        for turn in sorted {
            if var last = groups.last, let previous = last.last,
               previous.chat_id == turn.chat_id,
               let gap = chatGap(previous.ended_at, turn.started_at), gap <= 600 {
                last.append(turn)
                groups[groups.count - 1] = last
                continue
            }
            groups.append([turn])
        }
        let contours: [ChatContour] = groups.map { group in
            let segments = group.map { turn -> Segment in
                let start = x(data, turn.started_at, width)
                let end = x(data, turn.ended_at, width)
                return Segment(id: turn.id, start: start, end: max(start + minBarWidth, end), tone: .chat)
            }
            // Название работы — самое длинное из ходов группы: оно и есть суть.
            let title = group.map(\.title).max { $0.count < $1.count } ?? "Чат"
            let start = segments.map(\.start).min() ?? 0
            let end = segments.map(\.end).max() ?? 0
            return ChatContour(
                id: "chat-\(group[0].id)",
                title: title,
                chatTitle: group[0].chat_title,
                start: start,
                end: end,
                segments: segments
            )
        }.sorted { $0.start < $1.start }

        var lanes: [[ChatContour]] = []
        for contour in contours {
            if let index = lanes.firstIndex(where: { lane in lane.allSatisfy { $0.end <= contour.start } }) {
                lanes[index].append(contour)
            } else {
                lanes.append([contour])
            }
        }
        for laneIndex in lanes.indices {
            let lane = lanes[laneIndex]
            for index in lane.indices {
                let limit = index + 1 < lane.count ? lane[index + 1].start : width
                lanes[laneIndex][index].labelWidth = max(0, limit - lane[index].start - labelGap)
            }
        }
        return lanes
    }

    /// Пауза между концом одного хода и началом следующего в минутах.
    private static func chatGap(_ endedAt: String, _ startedAt: String) -> Double? {
        guard let end = RoleLoad.date(endedAt), let start = RoleLoad.date(startedAt) else { return nil }
        return start.timeIntervalSince(end)
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
