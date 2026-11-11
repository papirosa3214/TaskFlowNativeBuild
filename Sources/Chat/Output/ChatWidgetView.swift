import Charts
import SwiftUI

/// Нативный виджет в ответе роли — блок ```widget с JSON (владелец
/// 01.10.2026: «на вопрос какая погода агент скидывает виджет в чат»).
/// Формат задаёт промпт чата (`chat.wrapper` на сервере); данные погоды
/// роль берёт готовыми из `taskflow_weather`.
///
/// Разбор нестрогий: число может прийти строкой и наоборот, незнакомое поле
/// пропускается. Непонятный тип — не пустое место и не «виджет не разобран»,
/// а текст из тех же полей (`WidgetTextFallback`): старый клиент новых типов не
/// знает, и заглушка выглядела для владельца поломкой.
///
/// Реестр `type → компонент` — в `widget(for:)`: парсер про типы не знает,
/// добавление типа это одна запись здесь плюс компонент в `Widgets/`.
struct ChatWidgetView: View {
    let json: String
    /// Номер блока виджета в сообщении строкой — тем же порядком, каким блоки
    /// считает сервер. Нужен, когда у блока нет своего `id`/`key`. Вне чата
    /// (галерея виджетов, превью) — nil.
    var widgetKey: String? = nil
    /// Контекст сообщения для отправки отметки checklist. nil — виджет не из
    /// переписки (галерея, превью): отметка остаётся локальной, как раньше.
    var checklist: ChecklistSyncContext? = nil

    @State private var sync: ChecklistMessageSync?

    var body: some View {
        Group {
            if let data = WidgetData.parse(json) {
                widget(for: data)
            } else {
                WidgetTextFallback(json: json, note: "Блок не разобран")
            }
        }
    }

    /// Связь виджета с отметками сообщения: виджет спрашивает «отмечен ли
    /// пункт» и «переключи», а ключи, отправка и разбор отказа живут здесь.
    struct ChecklistBinding {
        let isDone: (Int, WidgetData) -> Bool
        let toggle: (Int, WidgetData) -> Void
        let failure: () -> String?
    }

    @ViewBuilder
    private func widget(for data: WidgetData) -> some View {
        switch AgentComponentRegistry.kind(for: data.string("type") ?? "") {
        case .weather: WeatherWidget(data: data)
        case .metrics: metricsWidget(data)
        case .progress: progressWidget(data)
        case .checklist: checklistWidget(data)
        case .card: cardWidget(data)
        case .chart: chartWidget(data)
        case .statusBoard: StatusBoardWidget(data: data)
        case .barsList: BarsListWidget(data: data)
        case .chain: ChainWidget(data: data)
        case .ladder: LadderWidget(data: data)
        case .timeline: TimelineWidget(data: data)
        case .calendarGrid: CalendarGridWidget(data: data)
        case .heatmap: HeatmapWidget(data: data)
        case .compare: CompareWidget(data: data)
        case .table: tableWidget(data)
        default: WidgetTextFallback(json: json, note: "Виджет этого типа пока не рисуется")
        }
    }

    // MARK: Компоновки К1–К6 поверх шести действующих типов

    /// Таблица виджета (карточка 6556fa2d): сервер учит роль отдавать таблицу
    /// виджетом, а клиент такой тип не рисовал — блок уходил в текстовую
    /// заглушку. Рисуем тем же `ChatTableView`, что и markdown-таблицу в тексте
    /// ответа, поэтому обе формы выглядят одинаково.
    @ViewBuilder
    private func tableWidget(_ data: WidgetData) -> some View {
        switch WidgetTableParser.parse(data.raw) {
        case .success(let table):
            // Таблица-виджет — такой же блок на тёмной подложке, как остальные
            // виджеты (владелец 11.11.2026: подложка как у пузыря сообщения).
            WidgetCard(title: table.title) {
                VStack(alignment: .leading, spacing: TFSpacing.xs) {
                    ChatTableView(table: ChatTable(
                        header: table.columns,
                        alignments: Array(repeating: .leading, count: table.columns.count),
                        rows: table.rows
                    ))
                    if let note = table.truncatedNote {
                        Text(note).tfText(.meta).foregroundStyle(Color.tfSub)
                    }
                }
            }
        case .failure(let problem):
            WidgetTextFallback(json: json, note: problem.note)
        }
    }

    /// Ветка включается наличием НОВЫХ полей, а не флагом: старый блок без них
    /// уходит в прежний вид и рисуется ровно как раньше.
    @ViewBuilder
    private func metricsWidget(_ data: WidgetData) -> some View {
        let items = data.array("items")
        if data.string("layout") == "strip" {
            WidgetCard(title: data.string("title")) { MetricsStripWidget(items: items) }
        } else if items.contains(where: { $0.string("tone") != nil || $0.string("icon") != nil }) {
            WidgetCard(title: data.string("title")) { MetricsTilesWidget(items: items) }
        } else {
            MetricsWidget(data: data)
        }
    }

    @ViewBuilder
    private func checklistWidget(_ data: WidgetData) -> some View {
        let items = data.array("items")
        let hasNewFields = data.bool("rows") == true
            || items.contains(where: { $0.string("tone") != nil || $0.string("meta") != nil || $0.number("progress") != nil })
        let binding = checklistBinding(for: data)
        if hasNewFields {
            WidgetCard(title: data.string("title")) { ChecklistRowsWidget(items: items, binding: binding) }
        } else {
            ChecklistWidget(data: data, binding: binding)
        }
    }

    /// nil — виджет не из переписки: отметка остаётся локальной. Иначе виджет
    /// спрашивает состояние у сервера и отправляет нажатие туда же (карточка
    /// 21842242: иначе роль отметку не видит, а после перезапуска она теряется).
    private func checklistBinding(for data: WidgetData) -> ChecklistBinding? {
        guard let checklist else { return nil }
        let key = ChecklistKey.widget(data, position: widgetKey)
        let sync = sync
        let state: (Int, WidgetData) -> Bool = { index, item in
            let itemKey = ChecklistKey.item(item, index: index)
            if let sync {
                return sync.done(widgetKey: key, itemKey: itemKey,
                                 inBlock: item.bool("done") ?? false)
            }
            // Синхронизации ещё нет — рисуем то, что уже знаем с сервера.
            return checklist.seed.first { $0.widgetKey == key && $0.itemKey == itemKey }?.done
                ?? item.bool("done") ?? false
        }
        return ChecklistBinding(
            isDone: state,
            toggle: { index, item in
                let itemKey = ChecklistKey.item(item, index: index)
                let current = state(index, item)
                Task { @MainActor in
                    await ensureSync()?.toggle(widgetKey: key, itemKey: itemKey, to: !current)
                }
            },
            failure: { sync?.failure }
        )
    }

    /// Создаётся лениво, по первому нажатию: до него виджет рисует сохранённое
    /// состояние сообщения, а объект синхронизации не нужен.
    private func ensureSync() -> ChecklistMessageSync? {
        guard let checklist else { return nil }
        if let sync { return sync }
        let created = ChecklistMessageSync(seed: checklist.seed, send: checklist.send)
        sync = created
        return created
    }

    @ViewBuilder
    private func progressWidget(_ data: WidgetData) -> some View {
        if let milestone = data.object("milestone") {
            WidgetCard(title: data.string("title")) {
                ProgressMilestoneWidget(items: data.array("items"), milestone: milestone)
            }
        } else {
            ProgressWidget(data: data)
        }
    }

    /// Блок графика ```widget рисуется тем же `RoleChartBlock`, что и блок
    /// конверта: раньше здесь был свой рисунок красным, а в конверте — teal,
    /// и один и тот же ответ роли выглядел по-разному (карточка 19f57bc9).
    @ViewBuilder
    private func chartWidget(_ data: WidgetData) -> some View {
        if data.string("layout") == "bars" || data.bool("horizontal") == true {
            WidgetCard(title: data.string("title")) {
                ChartBarsWidget(points: barPoints(data))
            }
        } else {
            RoleChartBlock(title: data.string("title"),
                           kind: data.string("kind"),
                           unit: data.string("unit"),
                           points: data.roleChartPoints())
        }
    }

    @ViewBuilder
    private func cardWidget(_ data: WidgetData) -> some View {
        CardWidget(data: data, ribbon: ribbonTone(data))
    }

    /// Лента статуса (К5) — только если тон из смысловой таблицы: произвольную
    /// строку цветом не красим.
    private func ribbonTone(_ data: WidgetData) -> WidgetTone? {
        guard let raw = data.string("tone"), WidgetTone(rawValue: raw.lowercased()) != nil else { return nil }
        return WidgetTone(raw)
    }

    /// Полосы того же блока читаются тем же разбором точек, что и график.
    private func barPoints(_ data: WidgetData) -> [ChartBarPoint] {
        data.roleChartPoints().map { ChartBarPoint(id: $0.id, label: $0.label, value: $0.value) }
    }
}

// MARK: - Данные

/// Обёртка над JSON-объектом с мягкими геттерами.
struct WidgetData {
    let raw: [String: Any]

    static func parse(_ json: String) -> WidgetData? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return WidgetData(raw: object)
    }

    func string(_ key: String) -> String? {
        switch raw[key] {
        case let s as String:
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        case let n as NSNumber:
            return Self.format(n.doubleValue)
        default:
            return nil
        }
    }

    func number(_ key: String) -> Double? {
        switch raw[key] {
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s.replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: CharacterSet(charactersIn: "0123456789.-").inverted))
        default: return nil
        }
    }

    func bool(_ key: String) -> Bool? {
        switch raw[key] {
        case let n as NSNumber: return n.boolValue
        case let s as String: return ["true", "да", "1", "yes"].contains(s.lowercased())
        default: return nil
        }
    }

    func array(_ key: String) -> [WidgetData] {
        (raw[key] as? [[String: Any]] ?? []).map(WidgetData.init)
    }

    func object(_ key: String) -> WidgetData? {
        (raw[key] as? [String: Any]).map(WidgetData.init)
    }

    static func format(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

// MARK: - Общая подложка

/// Подложка виджета. Не `private`: ею пользуются все восемь новых типов и
/// компоновки из `Widgets/`.
///
/// Тёмная подложка без рамки (владелец 06.11.2026: «в чате вообще не
/// должно быть ни у кого никакой окантовки»).
struct WidgetCard<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        TFCard(padding: TFSpacing.lg, surface: .dark) {
            VStack(alignment: .leading, spacing: TFSpacing.md) {
                if let title {
                    Text(title).tfText(.title).foregroundStyle(Color.tfChatText)
                }
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Погода

private struct WeatherWidget: View {
    let data: WidgetData

    private var isDay: Bool { data.bool("is_day") ?? true }
    private var icon: String { data.string("icon") ?? "cloudy" }

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(data.string("location") ?? "Погода")
                        .tfText(.title)
                    Text(temperature(data.number("temperature")))
                        .tfChatText(.body, weight: .thin, scale: 56 / TFChatTypeGroup.body.baseSize)
                        .monospacedDigit()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: TFSpacing.xs) {
                    Image(systemName: WeatherSymbol.name(icon, isDay: isDay))
                        .symbolRenderingMode(.multicolor)
                        .tfTypeFont(size: 40)
                    if let condition = data.string("condition") {
                        Text(condition).tfChatText(.body, weight: .medium)
                    }
                    if let high = data.number("high"), let low = data.number("low") {
                        Text("Макс. \(temperature(high)) · мин. \(temperature(low))")
                            .tfText(.meta)
                    }
                }
            }
            details
            let forecast = data.array("forecast")
            if !forecast.isEmpty {
                Divider().overlay(.white.opacity(0.35))
                HStack {
                    ForEach(Array(forecast.prefix(5).enumerated()), id: \.offset) { _, day in
                        VStack(spacing: TFSpacing.xs) {
                            Text(day.string("day") ?? "").tfChatText(.meta, weight: .semibold)
                            Image(systemName: WeatherSymbol.name(day.string("icon") ?? "cloudy", isDay: true))
                                .symbolRenderingMode(.multicolor)
                                .tfText(.taskTitle)
                                .frame(height: 26)
                            Text(temperature(day.number("high"))).tfChatText(.meta, weight: .semibold)
                            Text(temperature(day.number("low"))).tfText(.meta).opacity(0.75)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .foregroundStyle(Color.tfPaper)
        .padding(TFSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: WeatherSymbol.gradient(icon, isDay: isDay),
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: TFRadius.sheet)
        )
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var details: some View {
        let items: [(String, String)] = [
            data.number("feels_like").map { ("thermometer.medium", "Ощущается \(temperature($0))") },
            data.number("humidity").map { ("humidity", "\(WidgetData.format($0))%") },
            data.string("wind").map { ("wind", $0) },
        ].compactMap { $0 }
        if !items.isEmpty {
            HStack(spacing: TFSpacing.lg) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Label(item.1, systemImage: item.0).tfText(.meta)
                }
            }
            .opacity(0.9)
        }
    }

    private func temperature(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded()))°"
    }
}

enum WeatherSymbol {
    static func name(_ icon: String, isDay: Bool) -> String {
        switch icon.lowercased() {
        case "clear", "sunny": return isDay ? "sun.max.fill" : "moon.stars.fill"
        case "partly_cloudy", "partly": return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case "fog": return "cloud.fog.fill"
        case "drizzle": return "cloud.drizzle.fill"
        case "rain": return "cloud.rain.fill"
        case "snow": return "cloud.snow.fill"
        case "storm", "thunder": return "cloud.bolt.rain.fill"
        case "wind": return "wind"
        default: return "cloud.fill"
        }
    }

    static func gradient(_ icon: String, isDay: Bool) -> [Color] {
        if !isDay { return [Color(hex: "#1B2735"), Color(hex: "#3A4B6B")] }
        switch icon.lowercased() {
        case "clear", "sunny": return [Color(hex: "#3D8BD9"), Color(hex: "#7EC2F0")]
        case "partly_cloudy", "partly": return [Color(hex: "#4E86B8"), Color(hex: "#93B8D6")]
        case "rain", "drizzle", "storm": return [Color(hex: "#3F5163"), Color(hex: "#6F8194")]
        case "snow": return [Color(hex: "#7F9AB6"), Color(hex: "#B9C9DA")]
        case "fog": return [Color(hex: "#737D87"), Color(hex: "#A3ACB4")]
        default: return [Color(hex: "#5E6E7E"), Color(hex: "#8E9BA8")]
        }
    }
}

// MARK: - Метрики (старый вид)

private struct MetricsWidget: View {
    let data: WidgetData

    var body: some View {
        WidgetCard(title: data.string("title")) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: TFSpacing.md),
                                GridItem(.flexible(), spacing: TFSpacing.md)],
                      alignment: .leading, spacing: TFSpacing.md) {
                ForEach(Array(data.array("items").enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: TFSpacing.xs) {
                        Text(item.string("label") ?? "")
                            .tfText(.meta)
                            .foregroundStyle(Color.tfSub)
                        Text(item.string("value") ?? "—")
                            .tfChatText(.heading, weight: .semibold, scale: 22 / TFChatTypeGroup.heading.baseSize)
                            .monospacedDigit()
                            .foregroundStyle(Color.tfChatText)
                        if let delta = item.string("delta") {
                            let trend = item.string("trend") ?? ""
                            Label(delta, systemImage: trend == "up" ? "arrow.up.right"
                                  : trend == "down" ? "arrow.down.right" : "arrow.right")
                                .tfChatText(.meta, weight: .medium)
                                .foregroundStyle(trend == "up" ? Color.tfGreen
                                                 : trend == "down" ? Color.tfRed : Color.tfSub)
                        }
                    }
                    .padding(TFSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Плитка на тон светлее карточки, без рамки (владелец 06.11.2026).
                    .background(Color.tfTile, in: RoundedRectangle(cornerRadius: TFRadius.lg))
                }
            }
        }
    }
}

// MARK: - Прогресс (старый вид)

private struct ProgressWidget: View {
    let data: WidgetData

    var body: some View {
        WidgetCard(title: data.string("title")) {
            ForEach(Array(data.array("items").enumerated()), id: \.offset) { _, item in
                let raw = item.number("value") ?? 0
                let fraction = min(1, max(0, raw > 1 ? raw / 100 : raw))
                VStack(alignment: .leading, spacing: TFSpacing.xs) {
                    HStack {
                        Text(item.string("label") ?? "").foregroundStyle(Color.tfChatText)
                        Spacer()
                        Text("\(Int((fraction * 100).rounded()))%")
                            .monospacedDigit()
                            .foregroundStyle(Color.tfSub)
                    }
                    .tfText(.body)
                    ProgressView(value: fraction)
                        .tint(fraction >= 1 ? Color.tfGreen : Color.tfBlue)
                    if let note = item.string("note") {
                        Text(note).tfText(.meta).foregroundStyle(Color.tfSub)
                    }
                }
            }
        }
    }
}

// MARK: - Чек-лист (старый вид)

/// Отметки ставятся прямо в чате и уходят на сервер: роль читает их
/// операцией `taskflow_checklist_state`, а состояние переживает перезапуск
/// приложения. Вне переписки (галерея виджетов, превью) отметка локальная.
private struct ChecklistWidget: View {
    let data: WidgetData
    /// nil — виджет вне переписки (галерея, превью): отметка локальная.
    var binding: ChatWidgetView.ChecklistBinding?
    @State private var toggled: Set<Int> = []

    var body: some View {
        WidgetCard(title: data.string("title")) {
            // Пункты разделены линией цвета рамки (`ChecklistDivider`).
            VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(data.array("items").enumerated()), id: \.offset) { index, item in
                let done = isDone(index: index, item: item)
                if index > 0 { ChecklistDivider() }
                Button {
                    toggle(index: index, item: item)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: TFSpacing.sm) {
                        TFCheckbox(isChecked: done)
                        Text(item.string("text") ?? "")
                            .strikethrough(done)
                            .foregroundStyle(done ? Color.tfSub : Color.tfChatText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(minHeight: TFHitTarget.min)
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: done)
                .accessibilityLabel(item.string("text") ?? "Пункт")
                .accessibilityValue(done ? "Отмечен" : "Не отмечен")
            }
            }
            ChecklistSyncNotice(failure: binding?.failure())
        }
    }

    /// С перепиской — по состоянию сообщения (оно пришло с сервера, поэтому
    /// отметка переживает перезапуск). Без переписки — по-старому, локально.
    private func isDone(index: Int, item: WidgetData) -> Bool {
        if let binding { return binding.isDone(index, item) }
        return (item.bool("done") ?? false) != toggled.contains(index)
    }

    private func toggle(index: Int, item: WidgetData) {
        guard let binding else {
            withAnimation(.snappy(duration: 0.2)) {
                if toggled.contains(index) { toggled.remove(index) } else { toggled.insert(index) }
            }
            return
        }
        binding.toggle(index, item)
    }
}

/// Честный текст под checklist: сервер отметку не принял. Молчаливый откат
/// выглядел бы как «отметка сработала».
struct ChecklistSyncNotice: View {
    let failure: String?

    var body: some View {
        if let failure {
            Label(failure, systemImage: "exclamationmark.triangle")
                .tfText(.meta)
                .foregroundStyle(Color.tfRed)
        }
    }
}

// MARK: - Карточка

private struct CardWidget: View {
    let data: WidgetData
    /// К5: лента статуса, когда блок принёс смысловой тон.
    var ribbon: WidgetTone?
    @Environment(\.openURL) private var openURL

    var body: some View {
        WidgetCard(title: nil) {
            if let ribbon {
                WidgetToneRibbon(tone: ribbon)
            }
            VStack(alignment: .leading, spacing: 2) {
                if let title = data.string("title") {
                    Text(title).tfText(.title).foregroundStyle(Color.tfChatText)
                }
                if let subtitle = data.string("subtitle") {
                    Text(subtitle).tfText(.body).foregroundStyle(Color.tfSub)
                }
            }
            if let bodyText = data.string("body") {
                RoleReplyMarkdown(text: bodyText, serverBlocks: ChatServerBlock.list(fromFoundation: data.raw["body_blocks"]))
            }
            let rows = data.array("rows")
            if !rows.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        HStack(alignment: .firstTextBaseline) {
                            Text(row.string("label") ?? "").foregroundStyle(Color.tfSub)
                            Spacer(minLength: TFSpacing.md)
                            Text(row.string("value") ?? "—")
                                .foregroundStyle(Color.tfChatText)
                                .multilineTextAlignment(.trailing)
                        }
                        .tfText(.body)
                        .padding(.vertical, TFSpacing.sm)
                        if index < rows.count - 1 { Divider() }
                    }
                }
            }
            if let link = data.object("link"), let raw = link.string("url"), let url = URL(string: raw) {
                let label = Label(link.string("title") ?? "Открыть", systemImage: "arrow.up.right.square")
                    .frame(maxWidth: .infinity)
                // task://<id> — карточка внутри приложения (владелец 13.10.2026):
                // система такую ссылку не знает, openURL молча ничего не делал.
                if case .note(let noteID) = ChatMaterialDestination.resolve(raw) {
                    NavigationLink(value: AppRoute.noteEditor(noteID: noteID)) { label }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("widget-card-open-note")
                } else if url.scheme == "task", let taskID = url.host ?? url.pathComponents.last, !taskID.isEmpty {
                    TaskCardLink(taskID: taskID) { label }
                        .buttonStyle(.bordered)
                        .tint(Color.tfRed)
                        .accessibilityIdentifier("widget-card-open-task")
                } else {
                    Button { openURL(url) } label: { label }
                        .buttonStyle(.bordered)
                        .tint(Color.tfRed)
                }
            }
        }
    }
}
