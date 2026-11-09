import SwiftUI
import Charts

struct AIUsageScreen: View {
    @State private var window = "week"
    @State private var usage: AIUsage?
    @State private var error: String?
    @State private var loading = false
    /// Выбранный на графике день (`2026-10-23`); `nil` — весь период.
    @State private var pickedLabel: String?
    @State private var modelsExpanded = false
    /// Вид графика: столбики по дням или прогноз темпа (владелец 09.11.2026 —
    /// «одна иконочка с краешком графика, нажимаешь — вид меняется»).
    @State private var chartMode: ChartMode = .bars
    /// Разрез графика: по моделям или по провайдерам — это фильтр, а не вид.
    @State private var breakdown: Breakdown = .model

    enum ChartMode { case bars, forecast }
    enum Breakdown { case model, provider }

    private var selectedDay: String? {
        guard let pickedLabel, let usage else { return nil }
        return usage.daily.first { dayLabel($0.day) == pickedLabel }?.day
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TFSpacing.lg) {
                Picker("Период", selection: $window) {
                    Text("Сегодня").tag("today")
                    Text("7 дней").tag("week")
                    Text("30 дней").tag("month")
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("ai-usage.period")
                TFErrorBanner(error, variant: .inline)
                if loading { TFLoading(.block) }
                if let usage {
                    chartSection(usage)
                    numbersSection(usage)
                    if usage.totals.calls == 0 {
                        TFEmptyState(icon: "chart.bar", text: "За этот период нет сохранённого расхода ролей.")
                    } else {
                        modelsSection(usage)
                    JevUsageSection(window: jevWindow)
                    }
                    Text("Учтены сохранённые ответы моделей ролям TaskFlow. Это не расход всего аккаунта провайдера. Стоимость — тарифная оценка SDK, а не списание с подписки; баланс и стоимость подписки здесь не учитываются.")
                        .tfText(.caption).foregroundStyle(Color.tfSub)
                    if usage.totals.unpricedCalls > 0 {
                        Text("Без данных о цене: \(usage.totals.unpricedCalls) вызовов.")
                            .tfText(.caption).foregroundStyle(Color.tfSub)
                    }
                    if let since = usage.trackingSince, let date = DateFormats.sqliteUTC(since) {
                        Text("Сохранённая история с \(date.formatted(date: .abbreviated, time: .omitted))")
                            .tfText(.caption).foregroundStyle(Color.tfSub)
                    }
                }
            }
            .padding(.horizontal, TFSpacing.screenHorizontal)
            .padding(.vertical, TFSpacing.md)
        }
        .tfScreenBackground()
        .tfNativeHeader("Статистика", displayMode: .inline)
        .accessibilityIdentifier("ai-usage.screen")
        .hintAnchor(HintAnchorID.aiUsage)
        .task(id: window) { await load() }
        .refreshable { await load() }
    }

    // MARK: - График

    /// График — наверху: вопрос «сколько и когда», цифры — ниже. Столбик дня
    /// делится по моделям оттенками красного, тап по столбику выбирает день.
    private func chartSection(_ usage: AIUsage) -> some View {
        // Тело — два выражения (график и подпись прогноза), поэтому общий
        // `VStack`: без него `some View` не выводится и сборка падает. Отступ
        // малый (`.xs`): подпись прогноза идёт вплотную к графику, а не через
        // `lg`, как между крупными секциями экрана.
        VStack(spacing: TFSpacing.xs) {
            chartWithHeader(usage)
            if chartMode == .forecast {
                Text(forecastText(usage))
                    .tfText(.caption)
                    .foregroundStyle(Color.tfSub)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private func chartWithHeader(_ usage: AIUsage) -> some View {
        VStack(spacing: TFSpacing.sm) {
            HStack(spacing: TFSpacing.sm) {
                Spacer(minLength: 0)
                Text("Токены по дням")
                    .tfText(.row)
                    .foregroundStyle(Color.tfText)
                Spacer(minLength: 0)
                Menu {
                    Picker("Разрез", selection: $breakdown) {
                        Text("По моделям").tag(Breakdown.model)
                        Text("По провайдерам").tag(Breakdown.provider)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 17)) // design-system-guard: ignore — иконка меню, не текст
                        .foregroundStyle(Color.tfSub)
                }
                .accessibilityIdentifier("ai-usage.breakdown")
                .accessibilityLabel("Разрез графика")
            }
            if usage.hasModelBreakdown {
                ZStack(alignment: .topTrailing) {
                    stackedChart(usage)
                    Button {
                        chartMode = chartMode == .bars ? .forecast : .bars
                    } label: {
                        Image(systemName: chartMode == .bars ? "chart.bar.fill" : "chart.xyaxis.line")
                            .font(.system(size: 15)) // design-system-guard: ignore — иконка переключателя
                            .foregroundStyle(Color.tfSub)
                            .frame(width: 32, height: 28)
                            .background(Color.tfTile, in: RoundedRectangle(cornerRadius: TFRadius.sm))
                    }
                    .accessibilityIdentifier("ai-usage.chart-mode")
                    .accessibilityLabel(chartMode == .bars ? "Показать прогноз" : "Показать столбики")
                }
                legend(usage)
            } else {
                Chart(usage.daily) { day in
                    BarMark(x: .value("День", dayLabel(day.day)),
                            y: .value("Токены", tokensInAxisUnit(day.totalTokens, for: usage)))
                    .foregroundStyle(Color.tfRed)
                }
                .chartYAxisLabel(axisUnitName(for: usage), position: .leading)
                .chartXAxisLabel("Дни")
                .frame(height: 170)
            }
        }
        .accessibilityIdentifier("ai-usage.chart")
    }

    private func stackedChart(_ usage: AIUsage) -> some View {
        Chart(chartRows(usage)) { row in
            BarMark(x: .value("День", dayLabel(row.day)),
                    y: .value("Токены", tokensInAxisUnit(row.totalTokens, for: usage)))
            .foregroundStyle(by: .value("Строка", row.key))
            .opacity(selectedDay == nil || selectedDay == row.day ? 1 : 0.35)
        }
        .chartForegroundStyleScale(domain: chartKeys(usage),
                                   range: chartKeys(usage).map { color(for: $0, in: usage) })
        .chartLegend(.hidden)
        .chartXAxis {
            // За 30 дней даты не помещаются в строку: Swift Charts их прятал,
            // и ось оставалась пустой. Пишем каждую дату вертикально мелким
            // кеглем — они уходят в ту же полосу, что и сетка (владелец 24.10.2026).
            AxisMarks(values: usage.daily.map { dayLabel($0.day) }) { value in
                AxisGridLine()
                AxisValueLabel(orientation: verticalAxis ? .verticalReversed : .horizontal) {
                    if let label = value.as(String.self) {
                        Text(label).tfText(.caption)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let tick = value.as(Double.self) {
                        Text(axisTick(tick)).tfText(.caption)
                    }
                }
            }
        }
        .chartYAxisLabel(axisUnitName(for: usage), position: .leading)
        .chartXAxisLabel("Дни")
        .chartXSelection(value: $pickedLabel)
        .frame(height: 170)
    }

    /// Строки графика: день и ключ разреза (модель или провайдер).
    private struct ChartRow: Identifiable {
        var id: String { day + ":" + key }
        let day: String
        let key: String
        let totalTokens: Int
    }

    private func chartRows(_ usage: AIUsage) -> [ChartRow] {
        let keys = chartKeys(usage)
        func rank(_ key: String) -> Int { keys.firstIndex(of: key) ?? keys.count }
        if breakdown == .provider {
            return usage.dailyByProvider
                .map { ChartRow(day: $0.day, key: $0.provider, totalTokens: $0.totalTokens) }
                .sorted { $0.day == $1.day ? rank($0.key) < rank($1.key) : $0.day < $1.day }
        }
        return usage.chartSegments
            .map { ChartRow(day: $0.day, key: $0.model, totalTokens: $0.totalTokens) }
    }

    /// Окно для расхода JEV: у него нет «сегодня», есть сутки.
    private var jevWindow: String {
        switch window {
        case "today": return "24h"
        case "month": return "month"
        default: return "week"
        }
    }

    /// Месяц не влезает в подписи по горизонтали — там даты идут вертикально.
    private var verticalAxis: Bool { window == "month" }

    /// Деление оси — просто число: «1» вместо «1,0».
    private func axisTick(_ value: Double) -> String {
        let text = String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
        return text.hasSuffix(",0") ? String(text.dropLast(2)) : text
    }

    /// Единица оси считается один раз на период: «млн» или «млрд». По делениям
    /// идут простые числа, а не «500,0 млн» у каждой отметки.
    private func axisUnit(for usage: AIUsage) -> Double {
        let peak = usage.daily.map(\.totalTokens).max() ?? 0
        if peak >= 1_000_000_000 { return 1_000_000_000 }
        if peak >= 1_000_000 { return 1_000_000 }
        return 1_000
    }

    private func axisUnitName(for usage: AIUsage) -> String {
        switch axisUnit(for: usage) {
        case 1_000_000_000: return "Токены, млрд"
        case 1_000_000: return "Токены, млн"
        default: return "Токены, тыс"
        }
    }

    private func tokensInAxisUnit(_ value: Int, for usage: AIUsage) -> Double {
        Double(value) / axisUnit(for: usage)
    }

    private func legend(_ usage: AIUsage) -> some View {
        VStack(spacing: 4) {
            ForEach(legendModels(usage), id: \.self) { model in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color(for: model, in: usage))
                        .frame(width: 8, height: 8)
                    if let provider = provider(of: model, in: usage) {
                        AIUsageProviderBadge(provider: provider, size: 14)
                    }
                    Text(model)
                        .tfText(.caption)
                        .foregroundStyle(Color.tfSub)
                        .lineLimit(1)
                    Spacer(minLength: TFSpacing.sm)
                    Text(AIUsageFormat.tokens(tokens(of: model, in: usage)))
                        .tfText(.caption)
                        .foregroundStyle(Color.tfSub)
                        .monospacedDigit()
                }
            }
        }
        .accessibilityIdentifier("ai-usage.legend")
    }

    /// Какой провайдер у модели — для значка рядом с названием.
    private func provider(of model: String, in usage: AIUsage) -> String? {
        usage.dailyByModel.first { $0.model == model }?.provider
            ?? usage.models.first { $0.model == model }?.provider
    }

    /// Строка прогноза под графиком. Лимита провайдера у нас нет, поэтому
    /// дату «хватит до …» не пишем — только темп и ожидание на 30 дней.
    private func forecastText(_ usage: AIUsage) -> String {
        guard chartMode == .forecast else { return "" }
        guard usage.forecast.enoughData else { return "Мало данных для прогноза: нужен расход хотя бы в двух днях." }
        return "При таком темпе: ≈ \(AIUsageFormat.tokens(usage.forecast.tokensPerDay)) в сутки, "
            + "≈ \(AIUsageFormat.tokens(usage.forecast.tokensNext30Days)) за 30 дней."
    }

    /// В легенде — только модели, которые реально съели токены, и не больше
    /// шести: остальные всё равно видны под «Подробнее по моделям».
    private func legendModels(_ usage: AIUsage) -> [String] {
        Array(usage.modelOrder.filter { tokens(of: $0, in: usage) > 0 }.prefix(6))
    }

    // MARK: - Цифры (первая категория, отделены линиями)

    private func numbersSection(_ usage: AIUsage) -> some View {
        let totals = usage.totals(for: selectedDay)
        return VStack(alignment: .leading, spacing: TFSpacing.sm) {
            TFDivider()
            Text(selectedDay == nil ? periodTitle : "День \(dayLabel(selectedDay ?? ""))")
                .tfText(.row)
                .foregroundStyle(Color.tfText)
                .frame(maxWidth: .infinity, alignment: .center)
            if selectedDay != nil {
                Button("Весь период") { pickedLabel = nil }
                    .tfText(.caption)
                    .foregroundStyle(Color.tfSub)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityIdentifier("ai-usage.reset-day")
            }
            metric("Оценка стоимости", totals.costLabel)
                .accessibilityIdentifier("ai-usage.cost")
            metric("Всего токенов", AIUsageFormat.tokens(totals.totalTokens))
            metric("Вход без кэша", AIUsageFormat.tokens(totals.inputTokens))
            metric("Чтение кэша", AIUsageFormat.tokens(totals.cacheReadTokens))
            metric("Выход", AIUsageFormat.tokens(totals.outputTokens))
            metric("Доля кэша во входе", totals.cacheHitRate.map { String(format: "%.1f%%", $0 * 100).replacingOccurrences(of: ".", with: ",") } ?? "Нет данных")
            metric("Вызовов модели", String(totals.calls))
            TFDivider()
        }
        .accessibilityIdentifier("ai-usage.summary")
    }

    /// Подпись и значение одного ранга: одинаковый размер и цвет, значение —
    /// моноширинными цифрами в один столбец (владелец 24.10.2026).
    private func metric(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: TFSpacing.md) {
            Text(label)
                .tfText(.row)
                .foregroundStyle(Color.tfText)
            Spacer(minLength: TFSpacing.sm)
            Text(value)
                .tfText(.row)
                .foregroundStyle(Color.tfText)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    // MARK: - Разбивка по моделям

    private func modelsSection(_ usage: AIUsage) -> some View {
        let models = usage.models(for: selectedDay)
        return VStack(alignment: .leading, spacing: TFSpacing.sm) {
            DisclosureGroup(isExpanded: $modelsExpanded) {
                VStack(alignment: .leading, spacing: TFSpacing.sm) {
                    ForEach(models) { model in
                        VStack(alignment: .leading, spacing: TFSpacing.xs) {
                            HStack(spacing: TFSpacing.xs) {
                                AIUsageProviderBadge(provider: model.provider, size: 16)
                                Text(model.model).tfText(.row).foregroundStyle(Color.tfText)
                            }
                            Text("\(model.provider) · \(AIUsageFormat.tokens(model.totalTokens)) токенов · \(model.calls) вызовов")
                                .tfText(.caption).foregroundStyle(Color.tfSub)
                            if let cost = model.estimatedCostUsd {
                                Text((model.unpricedCalls > 0 ? "Частично: " : "") + RoleTurnUsageRow.cost(cost))
                                    .tfText(.caption).foregroundStyle(Color.tfSub)
                            }
                        }
                        TFDivider()
                    }
                }
                .padding(.top, TFSpacing.sm)
            } label: {
                Text("Подробнее по моделям")
                    .tfText(.row)
                    .foregroundStyle(Color.tfText)
            }
            .accessibilityIdentifier("ai-usage.models-toggle")
        }
    }

    // MARK: - Служебное

    private var periodTitle: String {
        switch window {
        case "today": return "Сегодня"
        case "month": return "30 дней"
        default: return "7 дней"
        }
    }

    /// День на оси — «17.10»: сначала число, потом месяц, как пишут даты.
    private func dayLabel(_ day: String) -> String {
        let parts = day.split(separator: "-")
        guard parts.count == 3 else { return day }
        return "\(parts[2]).\(parts[1])"
    }

    private func tokens(of model: String, in usage: AIUsage) -> Int {
        usage.dailyByModel.filter { $0.model == model }.reduce(0) { $0 + $1.totalTokens }
    }

    /// Ключи строк графика в текущем разрезе: модели или провайдеры.
    private func chartKeys(_ usage: AIUsage) -> [String] {
        breakdown == .provider ? usage.providers.map(\.provider) : usage.modelOrder
    }

    /// Цвет строки графика: свой на каждую модель (или провайдера), из палитры
    /// дизайн-системы. Градация красного тут не годится — владелец 09.11.2026:
    /// «тут абсолютно разные модели, их надо считывать гораздо четче».
    private func color(for key: String, in usage: AIUsage) -> Color {
        AIUsagePalette.color(for: key, order: usage.modelOrder)
    }

    @MainActor private func load() async {
        let selected = window
        loading = true; error = nil; usage = nil; pickedLabel = nil
        do {
            let value: AIUsage = try await APIClient().request(.get, "/runtime/usage", query: [URLQueryItem(name: "window", value: selected)])
            guard !Task.isCancelled, selected == window else { return }
            usage = value
        } catch {
            guard !Task.isCancelled, selected == window else { return }
            self.error = error.localizedDescription
        }
        loading = false
    }
}
