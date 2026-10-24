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
                    JevUsageSection()
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
        .background(Color.tfBackground)
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
        VStack(spacing: TFSpacing.sm) {
            Text("Токены по дням")
                .tfText(.row)
                .foregroundStyle(Color.tfText)
                .frame(maxWidth: .infinity, alignment: .center)
            if usage.hasModelBreakdown {
                stackedChart(usage)
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
        Chart(usage.chartSegments) { row in
            BarMark(x: .value("День", dayLabel(row.day)),
                    y: .value("Токены", tokensInAxisUnit(row.totalTokens, for: usage)))
            .foregroundStyle(by: .value("Модель", row.model))
            .opacity(selectedDay == nil || selectedDay == row.day ? 1 : 0.35)
        }
        .chartForegroundStyleScale(domain: usage.modelOrder,
                                   range: usage.modelOrder.map(shade))
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
                        .fill(shade(model))
                        .frame(width: 8, height: 8)
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
                            Text(model.model).tfText(.row).foregroundStyle(Color.tfText)
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

    /// Оттенки красного по рангу модели: больше расход — насыщеннее.
    private func shade(_ model: String) -> Color {
        let opacities: [Double] = [1, 0.72, 0.52, 0.36, 0.24, 0.15]
        let rank = usage?.shadeIndex(for: model) ?? opacities.count
        return Color.tfRed.opacity(rank < opacities.count ? opacities[rank] : 0.1)
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
