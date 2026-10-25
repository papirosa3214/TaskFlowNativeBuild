import Foundation

/// Метка счётчика: сразу видно, что в норме, что требует внимания, а что —
/// тревожный сигнал (владелец 18.10.2026: «счётчики скомпоновать, чтобы
/// понимать: вот сейчас что-то растёт — это плохо, а это в норме»).
enum DiagnosticsMark: String, Sendable {
    case ok, attention, alarm

    var title: String {
        switch self {
        case .ok: "норма"
        case .attention: "внимание"
        case .alarm: "тревожно"
        }
    }

    /// Для сравнения меток: чем больше, тем хуже.
    var rank: Int {
        switch self {
        case .ok: 0
        case .attention: 1
        case .alarm: 2
        }
    }

    /// Значок для экрана. Цвет — из палитры на месте (`tfGreen` / `tfOrange` / `tfRed`).
    var symbol: String {
        switch self {
        case .ok: "checkmark.circle.fill"
        case .attention: "exclamationmark.circle.fill"
        case .alarm: "exclamationmark.triangle.fill"
        }
    }
}

/// Чистая логика отчёта по счётчикам: скорость роста за отсчёт, метка, группы
/// и текст для «Поделиться». Вынесено из хранилища (`AppDiagnostics`) ради
/// юнит-тестов: само хранилище остаётся тонким счётчиком и про пороги не знает.
///
/// Пороги — в минуту, и они не выдуманы, а выведены из кода и замеров:
/// • цикл проявления ответа идёт шагом 16 мс, то есть максимум 3 750 тактов
///   в минуту (`RoleLiveTurnView`), — норма заметно ниже, цикл должен спать;
/// • задокументированные циклы опроса карточки: 3 с → 20 запросов/мин,
///   10 с → 6, 15 с → 4 (аудит батареи 09.10.2026);
/// • замер владельца 18.10.2026 в чате с ролью: 4,6 запроса/мин, ~300 КБ/мин,
///   296 тактов/мин, 25 пробуждений/мин, 106 сообщений соединения/мин.
/// Пределы округлены вверх, чтобы метка не срабатывала от одного всплеска.
struct DiagnosticsReport {
    struct Row: Identifiable, Sendable {
        let id: String
        let title: String
        let total: Int
        let background: Int
        let delta: Int
        let backgroundDelta: Int
        let perMinute: Double
        /// Предел нормы в минуту; 0 — норма только при полном покое.
        let normalLimit: Double
        let isBytes: Bool
        let mark: DiagnosticsMark
    }

    struct Group: Identifiable, Sendable {
        let id: String
        let title: String
        let rows: [Row]

        var mark: DiagnosticsMark {
            rows.map(\.mark).max { $0.rank < $1.rank } ?? .ok
        }
    }

    /// Разовое значение об устройстве: это не счётчик, поэтому у него нет
    /// скорости и предела — только значение, источник и метка.
    struct DeviceFact: Identifiable, Sendable {
        let id: String
        let title: String
        let value: String
        /// Откуда значение: «системное измерение» (iOS), а не счётчик
        /// приложения.
        let source: String
        let mark: DiagnosticsMark
    }

    /// Дельта между двумя последними ручными снимками заряда. Единственный
    /// честный способ сказать «минус 8 %»: iOS не сообщает, сколько батареи
    /// съело приложение.
    struct BatteryDelta: Sendable {
        /// Более ранний снимок.
        let previous: BatterySnapshot
        /// Более свежий снимок.
        let latest: BatterySnapshot
        /// Изменение в процентах: минус — батарея просела.
        let percentChange: Int
        /// Сколько времени между снимками.
        let interval: TimeInterval
    }

    /// Когда начался текущий отсчёт (приложение вернулось на экран).
    let startAt: Date
    /// Минут с начала отсчёта.
    let intervalMinutes: Double
    /// Когда вообще начался сбор счётчиков.
    let countersSince: Date
    /// Что происходит прямо сейчас: очереди, соединение, островок.
    let stateLine: String
    let groups: [Group]
    /// Системные метрики устройства. Источник — системное измерение iOS.
    let deviceFacts: [DeviceFact]
    /// Кто подъедает больше всех по счётчикам приложения.
    let topConsumers: [Row]
    /// Дельта между двумя последними ручными снимками заряда.
    let batteryDelta: BatteryDelta?

    var rows: [Row] { groups.flatMap(\.rows) }
    var alarmCount: Int { rows.filter { $0.mark == .alarm }.count }
    var attentionCount: Int { rows.filter { $0.mark == .attention }.count }
    var mark: DiagnosticsMark { groups.map(\.mark).max { $0.rank < $1.rank } ?? .ok }

    init(
        snapshot: AppDiagnostics.Snapshot,
        device: DeviceResourceSnapshot? = nil,
        batterySnapshots: [BatterySnapshot] = [],
        now: Date = Date()
    ) {
        let baseline = snapshot.baseline
        startAt = baseline.at
        countersSince = snapshot.saved.since
        stateLine = Self.stateLine(snapshot)
        intervalMinutes = max(now.timeIntervalSince(baseline.at) / 60, 0)
        // Скорость считаем не меньше чем за минуту: короткое окно иначе
        // раздувает один-два запроса в «тревожный» всплеск.
        let minutes = max(intervalMinutes, 1)

        func row(_ spec: Spec) -> Row {
            let total = snapshot.count(spec.counter)
            let background = snapshot.count(spec.counter, backgroundOnly: true)
            let delta = max(total - baseline.totals[spec.counter.rawValue, default: 0], 0)
            let backgroundDelta = max(
                background - baseline.backgroundTotals[spec.counter.rawValue, default: 0], 0
            )
            let perMinute = Double(delta) / minutes
            return Row(
                id: spec.counter.rawValue,
                title: spec.title,
                total: total,
                background: background,
                delta: delta,
                backgroundDelta: backgroundDelta,
                perMinute: perMinute,
                normalLimit: spec.normal,
                isBytes: spec.isBytes,
                mark: Self.mark(perMinute: perMinute, normal: spec.normal, alarm: spec.alarm)
            )
        }

        var built: [Group] = Self.layout.map { group in
            Group(id: group.id, title: group.title, rows: group.specs.map(row))
        }

        // Фон — отдельная группа: любой прирост в фоне уже сигнал, а не норма.
        let backgroundCounters: [AppDiagnostics.Counter] = [
            .ticks, .draws, .updates, .wakes, .sleeps, .messages, .requests, .watchdogChecks, .bytes
        ]
        let backgroundDelta = backgroundCounters.reduce(0) { sum, counter in
            sum + max(
                snapshot.count(counter, backgroundOnly: true)
                    - baseline.backgroundTotals[counter.rawValue, default: 0],
                0
            )
        }
        let islandActive = snapshot.active[.location, default: 0] > 0
        let backgroundTotal = backgroundCounters.reduce(0) {
            $0 + snapshot.count($1, backgroundOnly: true)
        }
        let backgroundWork = Row(
            id: "background-work",
            title: "Работа в фоне",
            total: backgroundTotal,
            background: backgroundTotal,
            delta: backgroundDelta,
            backgroundDelta: backgroundDelta,
            perMinute: Double(backgroundDelta) / minutes,
            normalLimit: 0,
            isBytes: false,
            mark: Self.backgroundMark(backgroundDelta: backgroundDelta, islandActive: islandActive)
        )
        built.append(Group(id: "background", title: "Фон", rows: [
            row(Spec(counter: .locationEvents, title: "События геопозиции", normal: 0, alarm: 5)),
            backgroundWork,
        ]))

        groups = built
        topConsumers = Self.topConsumers(from: built.flatMap(\.rows))
        deviceFacts = Self.deviceFacts(from: device)
        // Снимки хранятся свежими сверху, но порядок определяем по дате:
        // часы телефона могли перевести.
        let sorted = batterySnapshots.sorted { $0.date > $1.date }
        if sorted.count >= 2 {
            batteryDelta = BatteryDelta(
                previous: sorted[1],
                latest: sorted[0],
                percentChange: sorted[0].level - sorted[1].level,
                interval: sorted[0].date.timeIntervalSince(sorted[1].date)
            )
        } else {
            batteryDelta = nil
        }
    }

    // MARK: - Правила

    /// Топ потребителей по скорости роста счётчиков приложения.
    /// Байты с тактами не сравниваются (разные единицы), поэтому «Получено от
    /// сервера» в топ не входит; агрегированная «Работа в фоне» — тоже: это
    /// сумма, а не отдельный потребитель.
    static func topConsumers(from rows: [Row], limit: Int = 3) -> [Row] {
        rows
            .filter { $0.id != "background-work" && !$0.isBytes }
            .sorted { lhs, rhs in
                lhs.perMinute == rhs.perMinute ? lhs.title < rhs.title : lhs.perMinute > rhs.perMinute
            }
            .prefix(limit)
            .map { $0 }
    }

    /// Факты об устройстве — только то, что система отдаёт сама.
    static func deviceFacts(from device: DeviceResourceSnapshot?) -> [DeviceFact] {
        guard let device else { return [] }
        return [
            DeviceFact(
                id: "battery", title: "Заряд",
                value: device.batteryLevel.map { "\($0)%" } ?? "система не сообщает",
                source: "системное измерение", mark: batteryMark(device.batteryLevel)
            ),
            DeviceFact(
                id: "thermal", title: "Тепло", value: thermalText(device.thermalState),
                source: "системное измерение", mark: thermalMark(device.thermalState)
            ),
            DeviceFact(
                id: "low-power", title: "Режим экономии",
                value: device.lowPowerModeEnabled ? "включён" : "выключен",
                source: "системное измерение", mark: .ok
            ),
            DeviceFact(
                id: "available-memory", title: "Свободная память",
                value: bytes(Int(device.availableMemoryBytes)),
                source: "системное измерение", mark: memoryMark(device.availableMemoryBytes)
            ),
            DeviceFact(
                id: "footprint", title: "Память приложения",
                value: bytes(Int(device.appFootprintBytes)),
                source: "системное измерение", mark: .ok
            ),
        ]
    }

    /// Заряд: iOS просит беречь батарею на 20 % и предупреждает о критическом
    /// на 10 % — это пороги внимания и тревоги.
    static func batteryMark(_ level: Int?) -> DiagnosticsMark {
        guard let level else { return .ok }
        if level < 10 { return .alarm }
        if level < 20 { return .attention }
        return .ok
    }

    /// Тепло: serious — система сама ограничивает нагрузку, critical — уже
    /// жарко.
    static func thermalMark(_ state: ProcessInfo.ThermalState) -> DiagnosticsMark {
        switch state {
        case .critical: return .alarm
        case .serious: return .attention
        default: return .ok
        }
    }

    static func thermalText(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "норма"
        case .fair: "тепло"
        case .serious: "горячо"
        case .critical: "критично"
        @unknown default: "норма"
        }
    }

    /// Память: ниже 100 МБ системе скоро станет тесно, ниже 50 МБ iOS начинает
    /// снимать фоновые приложения.
    static func memoryMark(_ available: UInt64) -> DiagnosticsMark {
        let megabyte: UInt64 = 1_048_576
        if available < 50 * megabyte { return .alarm }
        if available < 100 * megabyte { return .attention }
        return .ok
    }

    /// Метка по скорости: выше предела нормы — внимание, выше предела тревоги —
    /// тревожно.
    static func mark(perMinute: Double, normal: Double, alarm: Double) -> DiagnosticsMark {
        if perMinute > alarm { return .alarm }
        if perMinute > normal { return .attention }
        return .ok
    }

    /// Работа в фоне: приложение вправе жить в фоне только пока держится
    /// островок. Всё остальное — сигнал: без островка это тревожно.
    static func backgroundMark(backgroundDelta: Int, islandActive: Bool) -> DiagnosticsMark {
        guard backgroundDelta > 0 else { return .ok }
        return islandActive ? .attention : .alarm
    }

    /// Строка «что происходит прямо сейчас» — состояния обработчиков, а не
    /// счётчики: их видно и без отчёта.
    static func stateLine(_ snapshot: AppDiagnostics.Snapshot) -> String {
        var parts: [String] = [snapshot.background ? "приложение в фоне" : "приложение открыто"]
        let queues = snapshot.activeQueues
        parts.append(queues == 0 ? "очереди текста спят" : "очереди текста работают: \(queues)")
        parts.append(snapshot.active[.socket, default: 0] > 0 ? "соединение работает" : "соединение стоит")
        if snapshot.active[.watchdog, default: 0] > 0 { parts.append("идёт проверка связи") }
        if snapshot.active[.location, default: 0] > 0 { parts.append("держится фон островка") }
        if snapshot.active[.http, default: 0] > 0 { parts.append("идёт запрос к серверу") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Описание счётчиков

    private struct Spec {
        let counter: AppDiagnostics.Counter
        let title: String
        let normal: Double
        let alarm: Double
        var isBytes = false
    }

    private static let layout: [(id: String, title: String, specs: [Spec])] = [
        ("text", "Текст ответа", [
            Spec(counter: .ticks, title: "Такты очереди", normal: 600, alarm: 2_000),
            Spec(counter: .draws, title: "Перерисовки текста", normal: 300, alarm: 1_000),
            Spec(counter: .updates, title: "Обновления содержимого", normal: 120, alarm: 400),
            Spec(counter: .wakes, title: "Пробуждения очереди", normal: 30, alarm: 120),
            Spec(counter: .sleeps, title: "Засыпания очереди", normal: 30, alarm: 120),
        ]),
        ("network", "Сеть", [
            Spec(counter: .requests, title: "Запросы к серверу", normal: 12, alarm: 40),
            Spec(
                counter: .bytes, title: "Получено от сервера",
                normal: 1_000_000, alarm: 5_000_000, isBytes: true
            ),
            Spec(counter: .messages, title: "Сообщения соединения", normal: 240, alarm: 900),
            Spec(counter: .watchdogChecks, title: "Проверки связи", normal: 10, alarm: 30),
            Spec(counter: .reconnects, title: "Переподключения", normal: 0.5, alarm: 2),
        ]),
    ]

    // MARK: - Текст отчёта

    /// Текст отчёта. Пишется так, чтобы человек без счётчиков понял: что
    /// происходит, что плохо и на что смотреть в первую очередь.
    func text(events: [AppDiagnostics.Entry] = []) -> String {
        var lines: [String] = []
        lines.append("Диагностика приложения")
        lines.append("Отсчёт: \(Self.duration(intervalMinutes)) с \(Self.stamp(startAt))")
        lines.append("Счётчики копятся с: \(Self.stamp(countersSince))")
        lines.append("Сейчас: \(stateLine)")
        lines.append("ИТОГ: \(verdictLine)")
        lines.append("")
        lines.append("Как читать: «за отсчёт» — прирост скорости сейчас, «всего» — с начала сбора. "
                     + "Метки: норма — в пределах порога, внимание — выше нормы, тревожно — вне обычного режима. "
                     + "Пороги — в DiagnosticsReport.swift.")
        lines.append("Источники: устройство — системное измерение iOS; «кто подъедает» — счётчики приложения; "
                     + "расход батареи — ручные снимки владельца (iOS не сообщает расход батареи приложением).")
        for group in groups {
            lines.append("")
            lines.append("[\(group.title)] — \(group.mark.title)")
            for row in group.rows { lines.append(Self.rowText(row)) }
        }
        if !deviceFacts.isEmpty {
            lines.append("")
            lines.append("[Устройство] — системное измерение iOS")
            for fact in deviceFacts { lines.append(Self.factText(fact)) }
        }
        if !topConsumers.isEmpty {
            lines.append("")
            lines.append("[Кто подъедает] — счётчики приложения, топ-3 по скорости")
            for row in topConsumers { lines.append(Self.rowText(row)) }
        }
        if let batteryDelta {
            lines.append("")
            lines.append("[Расход батареи] — ручные снимки владельца")
            lines.append(Self.batteryText(batteryDelta))
        }
        if !events.isEmpty {
            lines.append("")
            lines.append("Последние события:")
            for event in events {
                lines.append("\(Self.stamp(event.date)) · \(event.background ? "Фон" : "Открыто") · \(event.text)")
            }
        }
        return lines.joined(separator: "\n")
    }

    var verdictLine: String {
        guard mark != .ok else { return "всё в норме — все \(rows.count) счётчиков в пределах порога" }
        var parts: [String] = []
        if alarmCount > 0 { parts.append("тревожно — \(alarmCount)") }
        if attentionCount > 0 { parts.append("внимание — \(attentionCount)") }
        let rest = rows.count - alarmCount - attentionCount
        parts.append("в норме — \(rest)")
        return parts.joined(separator: ", ") + ". Подробности ниже."
    }

    static func factText(_ fact: DeviceFact) -> String {
        "\(fact.title): \(fact.value) — \(fact.mark.title)"
    }

    /// Снимки батареи: «62% → 54% за 4 ч 12 мин, −8%».
    static func batteryText(_ delta: BatteryDelta) -> String {
        let change = delta.percentChange
        let sign = change > 0 ? "+" : (change < 0 ? "−" : "")
        return "\(delta.previous.level)% → \(delta.latest.level)% за \(Self.duration(delta.interval / 60))"
            + ", \(sign)\(abs(change))%"
    }

    static func rowText(_ row: Row) -> String {
        var line = "\(row.title): всего \(Self.value(row.total, isBytes: row.isBytes))"
        line += ", за отсчёт \(Self.deltaText(row.delta, isBytes: row.isBytes))"
        line += " (\(Self.rateText(row.perMinute, isBytes: row.isBytes))"
        line += ", предел нормы \(Self.rateText(row.normalLimit, isBytes: row.isBytes)))"
        line += " — \(row.mark.title)"
        if row.backgroundDelta > 0 {
            line += ", в фоне \(Self.deltaText(row.backgroundDelta, isBytes: row.isBytes))"
        }
        return line
    }

    static func deltaText(_ value: Int, isBytes: Bool) -> String {
        (value > 0 ? "+" : "") + Self.value(value, isBytes: isBytes)
    }

    static func value(_ value: Int, isBytes: Bool) -> String {
        isBytes ? bytes(value) : value.formatted()
    }

    static func rateText(_ perMinute: Double, isBytes: Bool) -> String {
        if isBytes { return bytes(Int(perMinute.rounded())) + "/мин" }
        if perMinute > 0, perMinute < 1 { return "меньше 1/мин" }
        return "\(Int(perMinute.rounded()))/мин"
    }

    static func bytes(_ value: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: Int64(value))
    }

    static func duration(_ minutes: Double) -> String {
        if minutes < 1 { return "меньше минуты" }
        if minutes < 60 { return "\(Int(minutes.rounded())) мин" }
        let hours = Int(minutes / 60)
        let rest = Int(minutes.rounded()) % 60
        return rest == 0 ? "\(hours) ч" : "\(hours) ч \(rest) мин"
    }

    static func stamp(_ date: Date) -> String {
        date.formatted(
            .dateTime.day().month(.abbreviated).hour().minute()
                .locale(Locale(identifier: "ru_RU"))
        )
    }
}
