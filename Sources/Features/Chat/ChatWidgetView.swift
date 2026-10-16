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

    var body: some View {
        if let data = WidgetData.parse(json) {
            widget(for: data)
        } else {
            WidgetTextFallback(json: json, note: "Блок не разобран")
        }
    }

    @ViewBuilder
    private func widget(for data: WidgetData) -> some View {
        let type = data.string("type") ?? ""
        switch type {
        case "weather": WeatherWidget(data: data)
        case "metrics": metricsWidget(data)
        case "progress": progressWidget(data)
        case "checklist": checklistWidget(data)
        case "card": cardWidget(data)
        case "chart": chartWidget(data)
        case "status_board": StatusBoardWidget(data: data)
        case "bars_list": BarsListWidget(data: data)
        case "chain": ChainWidget(data: data)
        case "ladder": LadderWidget(data: data)
        case "timeline": TimelineWidget(data: data)
        case "calendar_grid": CalendarGridWidget(data: data)
        case "heatmap": HeatmapWidget(data: data)
        case "compare": CompareWidget(data: data)
        default: WidgetTextFallback(json: json, note: "Виджет этого типа пока не рисуется")
        }
    }

    // MARK: Компоновки К1–К6 поверх шести действующих типов

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
        if hasNewFields {
            WidgetCard(title: data.string("title")) { ChecklistRowsWidget(items: items) }
        } else {
            ChecklistWidget(data: data)
        }
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

    @ViewBuilder
    private func chartWidget(_ data: WidgetData) -> some View {
        if data.string("layout") == "bars" || data.bool("horizontal") == true {
            WidgetCard(title: data.string("title")) {
                ChartBarsWidget(points: barPoints(data))
            }
        } else {
            ChartWidget(data: data)
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

    private func barPoints(_ data: WidgetData) -> [ChartBarPoint] {
        data.array("points").enumerated().compactMap { index, item in
            guard let value = item.number("y") else { return nil }
            return ChartBarPoint(id: index, label: item.string("x") ?? "\(index + 1)", value: value)
        }
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
struct WidgetCard<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.md) {
            if let title {
                Text(title).tfText(.title).foregroundStyle(Color.tfText)
            }
            content
        }
        .padding(TFSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tfCard, in: RoundedRectangle(cornerRadius: TFRadius.xl))
        .overlay(RoundedRectangle(cornerRadius: TFRadius.xl).strokeBorder(Color.tfStroke, lineWidth: TFBorder.width))
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
                        .font(.system(size: 56, weight: .thin))
                        .monospacedDigit()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: TFSpacing.xs) {
                    Image(systemName: WeatherSymbol.name(icon, isDay: isDay))
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 40))
                    if let condition = data.string("condition") {
                        Text(condition).font(.subheadline.weight(.medium))
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
                            Text(day.string("day") ?? "").font(.caption.weight(.semibold))
                            Image(systemName: WeatherSymbol.name(day.string("icon") ?? "cloudy", isDay: true))
                                .symbolRenderingMode(.multicolor)
                                .tfText(.taskTitle)
                                .frame(height: 26)
                            Text(temperature(day.number("high"))).font(.caption.weight(.semibold))
                            Text(temperature(day.number("low"))).tfText(.meta).opacity(0.75)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .foregroundStyle(.white)
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
                            .font(.title2.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Color.tfText)
                        if let delta = item.string("delta") {
                            let trend = item.string("trend") ?? ""
                            Label(delta, systemImage: trend == "up" ? "arrow.up.right"
                                  : trend == "down" ? "arrow.down.right" : "arrow.right")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(trend == "up" ? Color.tfGreen
                                                 : trend == "down" ? Color.tfRed : Color.tfSub)
                        }
                    }
                    .padding(TFSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.tfCard2, in: RoundedRectangle(cornerRadius: TFRadius.lg))
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
                        Text(item.string("label") ?? "").foregroundStyle(Color.tfText)
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

/// Отметки ставятся прямо в чате — локально, для себя: сервер про них не
/// знает (виджет — часть ответа роли, а не задача трекера).
private struct ChecklistWidget: View {
    let data: WidgetData
    @State private var toggled: Set<Int> = []

    var body: some View {
        WidgetCard(title: data.string("title")) {
            ForEach(Array(data.array("items").enumerated()), id: \.offset) { index, item in
                let done = (item.bool("done") ?? false) != toggled.contains(index)
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        if toggled.contains(index) { toggled.remove(index) } else { toggled.insert(index) }
                    }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: TFSpacing.sm) {
                        Image(systemName: done ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(done ? Color.tfGreen : Color.tfDim)
                        Text(item.string("text") ?? "")
                            .strikethrough(done)
                            .foregroundStyle(done ? Color.tfSub : Color.tfText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: toggled)
            }
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
                    Text(title).tfText(.title).foregroundStyle(Color.tfText)
                }
                if let subtitle = data.string("subtitle") {
                    Text(subtitle).tfText(.body).foregroundStyle(Color.tfSub)
                }
            }
            if let bodyText = data.string("body") {
                RoleReplyMarkdown(text: bodyText)
            }
            let rows = data.array("rows")
            if !rows.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        HStack(alignment: .firstTextBaseline) {
                            Text(row.string("label") ?? "").foregroundStyle(Color.tfSub)
                            Spacer(minLength: TFSpacing.md)
                            Text(row.string("value") ?? "—")
                                .foregroundStyle(Color.tfText)
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
                if url.scheme == "task", let taskID = url.host ?? url.pathComponents.last, !taskID.isEmpty {
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

// MARK: - График (старый вид)

private struct ChartWidget: View {
    let data: WidgetData

    private struct Point: Identifiable {
        let id: Int
        let x: String
        let y: Double
    }

    private var points: [Point] {
        data.array("points").enumerated().compactMap { index, item in
            guard let y = item.number("y") else { return nil }
            return Point(id: index, x: item.string("x") ?? "\(index + 1)", y: y)
        }
    }

    var body: some View {
        WidgetCard(title: data.string("title")) {
            let isLine = data.string("kind") == "line"
            Chart(points) { point in
                if isLine {
                    LineMark(x: .value("x", point.x), y: .value("y", point.y))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Color.tfRed)
                    PointMark(x: .value("x", point.x), y: .value("y", point.y))
                        .foregroundStyle(Color.tfRed)
                } else {
                    BarMark(x: .value("x", point.x), y: .value("y", point.y))
                        .foregroundStyle(Color.tfRed.gradient)
                        .cornerRadius(4)
                }
            }
            .chartYAxisLabel(data.string("unit") ?? "")
            .frame(height: 180)
        }
    }
}
