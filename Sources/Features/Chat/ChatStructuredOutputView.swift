import Charts
import SwiftUI

/// Renderer JSON-контракта роли v1. Геометрия и оформление остаются в iOS;
/// модель передаёт только тип блока и его данные.
struct ChatStructuredOutputView: View {
    let json: String
    var isStreaming = false

    private var document: StructuredOutputEnvelope? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(StructuredOutputEnvelope.self, from: data)
    }

    var body: some View {
        if let document, document.isSupported {
            VStack(alignment: .leading, spacing: TFSpacing.md) {
                if document.ok {
                    switch document.output {
                    case .blocks(let blocks):
                        ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                            blockView(block)
                        }
                    case .text(let text):
                        RoleReplyMarkdown(text: text)
                    }
                } else if let error = document.error {
                    errorBlock(error)
                }

                if document.needsHuman {
                    statusBlock(title: "Нужно решение владельца", code: "blocked", text: nil)
                }
                if let hint = document.nextHint, !hint.isEmpty {
                    Text(hint)
                        .tfText(.caption)
                        .foregroundStyle(Color.tfSub)
                        .accessibilityIdentifier("chat.structured-output.next-hint")
                }
                if !document.artifacts.isEmpty {
                    materialsBlock(document.artifacts)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("chat.structured-output")
        } else if isStreaming, let partialText = ChatStructuredJSONStreamParser.partialText(in: json) {
            RoleReplyMarkdown(text: partialText, isStreaming: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("chat.structured-output.streaming-text")
        } else if isStreaming {
            WidgetSkeletonCard()
                .accessibilityIdentifier("chat.structured-output.streaming-pending")
        } else {
            invalidDocument
        }
    }

    @ViewBuilder
    private func blockView(_ block: StructuredOutputBlock) -> some View {
        switch block.type {
        case "text":
            if let text = block.text, !text.isEmpty {
                MarkdownDocumentRenderer(markdown: text)
                    .accessibilityIdentifier("chat.structured-output.text")
            }
        case "heading":
            if let text = block.text, !text.isEmpty {
                StructuredDocumentBlocksView(blocks: [
                    .heading(level: min(max(block.level ?? 2, 1), 3), runs: [RichRun(text: text)])
                ])
                    .accessibilityIdentifier("chat.structured-output.heading")
            }
        case "list":
            listBlock(block)
        case "table":
            tableBlock(block)
        case "status":
            statusBlock(title: block.title ?? "Статус", code: block.code, text: block.text)
        case "progress":
            progressBlock(block)
        case "chart":
            chartBlock(block)
        case "diagram":
            diagramBlock(block)
        case "report":
            reportBlock(block)
        case "handoff":
            handoffBlock(block)
        default:
            unsupportedBlock("Тип блока «\(block.type)» пока не поддерживается")
        }
    }

    private func listBlock(_ block: StructuredOutputBlock) -> some View {
        StructuredDocumentBlocksView(blocks: (block.items ?? []).map { item in
            .listItem(kind: block.ordered == true ? .ordered : .bullet, depth: 0, runs: [RichRun(text: item)])
        })
        .accessibilityIdentifier("chat.structured-output.list")
    }

    @ViewBuilder
    private func tableBlock(_ block: StructuredOutputBlock) -> some View {
        if let columns = block.columns, !columns.isEmpty, let rows = block.rows {
            VStack(alignment: .leading, spacing: TFSpacing.xs) {
                if let title = block.title, !title.isEmpty {
                    Text(title).tfText(.action).foregroundStyle(Color.tfText)
                }
                StructuredDocumentBlocksView(blocks: [
                    .table([
                        NoteTableRow(cells: columns.map { NoteTableCell(runs: [RichRun(text: $0)], isHeader: true) })
                    ] + rows.map { row in
                        NoteTableRow(cells: Array((row + Array(repeating: "", count: columns.count)).prefix(columns.count))
                            .map { NoteTableCell(runs: [RichRun(text: $0)], isHeader: false) })
                    })
                ])
            }
            .accessibilityIdentifier("chat.structured-output.table")
        } else {
            unsupportedBlock("У таблицы должны быть колонки и строки")
        }
    }

    private func statusBlock(title: String, code: String?, text: String?) -> some View {
        HStack(alignment: .top, spacing: TFSpacing.sm) {
            Image(systemName: statusSymbol(code))
                .foregroundStyle(statusColor(code))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: TFSpacing.xs) {
                Text(title).tfText(.action).foregroundStyle(Color.tfText)
                if let text, !text.isEmpty {
                    Text(text).tfText(.body).foregroundStyle(Color.tfSub)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(TFSpacing.md)
        .background(Color.tfCard, in: RoundedRectangle(cornerRadius: TFRadius.lg))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("chat.structured-output.status")
    }

    private func progressBlock(_ block: StructuredOutputBlock) -> some View {
        WidgetCard(title: block.title) {
            VStack(alignment: .leading, spacing: TFSpacing.xs) {
                ProgressView(value: block.current ?? 0, total: max(block.total ?? 1, 1))
                HStack {
                    Text(block.label ?? "\(number(block.current ?? 0)) из \(number(block.total ?? 0))")
                    Spacer(minLength: TFSpacing.sm)
                    if let unit = block.unit { Text(unit) }
                }
                .tfText(.caption)
                .foregroundStyle(Color.tfSub)
            }
        }
        .accessibilityIdentifier("chat.structured-output.progress")
    }

    @ViewBuilder
    private func chartBlock(_ block: StructuredOutputBlock) -> some View {
        if let points = block.points, !points.isEmpty {
            WidgetCard(title: block.title) {
                Chart(points) { point in
                    if block.kind == "line" {
                        LineMark(x: .value("Метка", point.label), y: .value("Значение", point.value))
                            .foregroundStyle(Color.tfTeal)
                        PointMark(x: .value("Метка", point.label), y: .value("Значение", point.value))
                            .foregroundStyle(Color.tfTeal)
                    } else {
                        BarMark(x: .value("Метка", point.label), y: .value("Значение", point.value))
                            .foregroundStyle(Color.tfTeal.gradient)
                            .cornerRadius(4)
                    }
                }
                .chartYAxisLabel(block.unit ?? "")
                .frame(height: 180)
                .accessibilityLabel(chartAccessibilityLabel(block, points: points))
            }
            .accessibilityIdentifier("chat.structured-output.chart")
        } else {
            unsupportedBlock("У графика нет точек данных")
        }
    }

    private func diagramBlock(_ block: StructuredOutputBlock) -> some View {
        WidgetCard(title: block.title) {
            VStack(alignment: .leading, spacing: TFSpacing.sm) {
                ForEach(Array((block.diagramItems ?? []).enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: TFSpacing.sm) {
                        Image(systemName: statusSymbol(item.state))
                            .foregroundStyle(statusColor(item.state))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: TFSpacing.xs) {
                            Text(item.label).tfText(.body).foregroundStyle(Color.tfText)
                            if let detail = item.detail, !detail.isEmpty {
                                Text(detail).tfText(.caption).foregroundStyle(Color.tfSub)
                            }
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("chat.structured-output.diagram")
    }

    private func reportBlock(_ block: StructuredOutputBlock) -> some View {
        let sections = block.sections
        return WidgetCard(title: block.reportKind == "final" ? "Итоговый отчёт" : "Промежуточный отчёт") {
            VStack(alignment: .leading, spacing: TFSpacing.md) {
                reportSection("Результат", sections?.result ?? [])
                reportSection("Что сделано", sections?.work ?? [])
                checksSection(sections?.checks ?? [])
                reportSection("Ограничения", sections?.limitations ?? [])
                materialsSection(sections?.materials ?? [])
            }
        }
        .accessibilityIdentifier("chat.structured-output.report")
    }

    @ViewBuilder
    private func reportSection(_ title: String, _ blocks: [StructuredOutputBlock]) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.xs) {
            Text(title).tfText(.title).foregroundStyle(Color.tfText)
            if blocks.isEmpty {
                Text(emptySectionText(title)).tfText(.caption).foregroundStyle(Color.tfSub)
            } else {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    AnyView(blockView(block))
                }
            }
        }
    }

    private func checksSection(_ checks: [StructuredOutputCheck]) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.xs) {
            Text("Проверки").tfText(.title).foregroundStyle(Color.tfText)
            if checks.isEmpty {
                Text("Проверки не запускались").tfText(.caption).foregroundStyle(Color.tfSub)
            } else {
                ForEach(Array(checks.enumerated()), id: \.offset) { _, check in
                    HStack(alignment: .top, spacing: TFSpacing.sm) {
                        Image(systemName: statusSymbol(check.status))
                            .foregroundStyle(statusColor(check.status))
                        VStack(alignment: .leading, spacing: TFSpacing.xs) {
                            Text(check.label).tfText(.body).foregroundStyle(Color.tfText)
                            if let detail = check.detail, !detail.isEmpty {
                                Text(detail).tfText(.caption).foregroundStyle(Color.tfSub)
                            }
                        }
                    }
                }
            }
        }
    }

    private func materialsSection(_ materials: [StructuredOutputMaterial]) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.xs) {
            Text("Материалы").tfText(.title).foregroundStyle(Color.tfText)
            if materials.isEmpty {
                Text("Материалы не приложены").tfText(.caption).foregroundStyle(Color.tfSub)
            } else {
                ForEach(Array(materials.enumerated()), id: \.offset) { _, material in
                    materialRow(material)
                }
            }
        }
    }

    private func materialsBlock(_ materials: [StructuredOutputMaterial]) -> some View {
        WidgetCard(title: "Материалы") {
            VStack(alignment: .leading, spacing: TFSpacing.xs) {
                ForEach(Array(materials.enumerated()), id: \.offset) { _, material in
                    materialRow(material)
                }
            }
        }
        .accessibilityIdentifier("chat.structured-output.materials")
    }

    @ViewBuilder
    private func materialRow(_ material: StructuredOutputMaterial) -> some View {
        if let url = URL(string: material.ref), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            Link(destination: url) {
                Label(material.title, systemImage: "arrow.up.right.square")
                    .tfText(.body)
                    .foregroundStyle(Color.tfBlue)
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text(material.title).tfText(.body).foregroundStyle(Color.tfText)
                Text(material.ref).tfText(.caption).foregroundStyle(Color.tfSub).textSelection(.enabled)
            }
        }
    }

    private func handoffBlock(_ block: StructuredOutputBlock) -> some View {
        WidgetCard(title: "Передача результата") {
            VStack(alignment: .leading, spacing: TFSpacing.xs) {
                if let key = block.artifactKey {
                    Text("Артефакт: \(key)").tfText(.caption).foregroundStyle(Color.tfSub)
                }
                if let summary = block.summary {
                    Text(summary).tfText(.body).foregroundStyle(Color.tfText)
                }
            }
        }
        .accessibilityIdentifier("chat.structured-output.handoff")
    }

    private func errorBlock(_ error: StructuredOutputError) -> some View {
        WidgetCard(title: "Не удалось подготовить результат") {
            Label(error.message, systemImage: "exclamationmark.triangle")
                .tfText(.body)
                .foregroundStyle(Color.tfRed)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("chat.structured-output.error")
    }

    private var invalidDocument: some View {
        WidgetCard(title: "Структурированный ответ") {
            VStack(alignment: .leading, spacing: TFSpacing.sm) {
                Label("JSON не удалось разобрать", systemImage: "exclamationmark.triangle")
                    .tfText(.body)
                    .foregroundStyle(Color.tfRed)
                Text(json)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color.tfSub)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("chat.structured-output.raw-error")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat.structured-output.invalid")
    }

    private func unsupportedBlock(_ message: String) -> some View {
        Text(message)
            .tfText(.caption)
            .foregroundStyle(Color.tfSub)
            .accessibilityIdentifier("chat.structured-output.unsupported")
    }

    private func statusSymbol(_ status: String?) -> String {
        switch status?.lowercased() {
        case "done", "passed", "complete": "checkmark.circle"
        case "blocked", "failed", "error": "exclamationmark.triangle"
        case "running", "in_progress": "arrow.trianglehead.2.clockwise"
        case "skipped", "not_run": "minus.circle"
        default: "info.circle"
        }
    }

    private func statusColor(_ status: String?) -> Color {
        switch status?.lowercased() {
        case "done", "passed", "complete": Color.tfGreen
        case "blocked", "failed", "error": Color.tfRed
        case "running", "in_progress": Color.tfTeal
        default: Color.tfSub
        }
    }

    private func number(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }

    private func emptySectionText(_ title: String) -> String {
        switch title {
        case "Что сделано": "Работа не указана"
        case "Ограничения": "Ограничения не указаны"
        default: "Нет данных"
        }
    }

    private func chartAccessibilityLabel(_ block: StructuredOutputBlock, points: [StructuredOutputPoint]) -> Text {
        let summary = points.map { "\($0.label): \(number($0.value))" }.joined(separator: ", ")
        return Text([block.title, summary, block.unit].compactMap { $0 }.joined(separator: ". "))
    }
}

private struct StructuredOutputEnvelope: Decodable {
    let schemaVersion: Int?
    let contract: String?
    let ok: Bool
    let output: StructuredOutputContent
    let artifacts: [StructuredOutputMaterial]
    let error: StructuredOutputError?
    let nextHint: String?
    let needsHuman: Bool

    var isSupported: Bool { schemaVersion == 1 || contract == "role.v1" }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case contract, ok, output, artifacts, error
        case nextHint = "next_hint"
        case needsHuman = "needs_human"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion)
        contract = try values.decodeIfPresent(String.self, forKey: .contract)
        ok = try values.decode(Bool.self, forKey: .ok)
        output = try values.decode(StructuredOutputContent.self, forKey: .output)
        error = try values.decodeIfPresent(StructuredOutputError.self, forKey: .error)
        nextHint = try values.decodeIfPresent(String.self, forKey: .nextHint)
        needsHuman = try values.decode(Bool.self, forKey: .needsHuman)

        let rawArtifacts = try values.decodeIfPresent([JSONValue].self, forKey: .artifacts) ?? []
        artifacts = rawArtifacts.compactMap { value in
            switch value {
            case .string(let reference):
                return StructuredOutputMaterial(kind: "artifact", title: reference, ref: reference)
            case .object:
                guard let data = try? JSONEncoder().encode(value) else { return nil }
                return try? JSONDecoder().decode(StructuredOutputMaterial.self, from: data)
            default:
                return nil
            }
        }
    }
}

private enum StructuredOutputContent: Decodable {
    case blocks([StructuredOutputBlock])
    case text(String)

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let blocks = try? value.decode([StructuredOutputBlock].self) {
            self = .blocks(blocks)
        } else if let text = try? value.decode(String.self) {
            self = .text(text)
        } else {
            throw DecodingError.typeMismatch(
                StructuredOutputContent.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "output должен быть текстом или списком блоков")
            )
        }
    }
}

private struct StructuredOutputBlock: Decodable {
    let type: String
    let text: String?
    let level: Int?
    let items: [String]?
    let ordered: Bool?
    let title: String?
    let columns: [String]?
    let rows: [[String]]?
    let code: String?
    let current: Double?
    let total: Double?
    let unit: String?
    let label: String?
    let kind: String?
    let points: [StructuredOutputPoint]?
    let reportKind: String?
    let sections: StructuredOutputSections?
    let diagramItems: [StructuredOutputDiagramItem]?
    let artifactKey: String?
    let summary: String?

    enum CodingKeys: String, CodingKey {
        case type, text, level, items, ordered, title, columns, rows, code, current, total, unit, label, kind, points, sections, summary
        case reportKind = "report_kind"
        case artifactKey = "artifact_key"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        type = try values.decode(String.self, forKey: .type)
        text = try values.decodeIfPresent(String.self, forKey: .text)
        level = try values.decodeIfPresent(Int.self, forKey: .level)
        title = try values.decodeIfPresent(String.self, forKey: .title)
        columns = try values.decodeIfPresent([String].self, forKey: .columns)
        rows = try values.decodeIfPresent([[String]].self, forKey: .rows)
        code = try values.decodeIfPresent(String.self, forKey: .code)
        current = try values.decodeIfPresent(Double.self, forKey: .current)
        total = try values.decodeIfPresent(Double.self, forKey: .total)
        unit = try values.decodeIfPresent(String.self, forKey: .unit)
        label = try values.decodeIfPresent(String.self, forKey: .label)
        kind = try values.decodeIfPresent(String.self, forKey: .kind)
        points = try values.decodeIfPresent([StructuredOutputPoint].self, forKey: .points)
        reportKind = try values.decodeIfPresent(String.self, forKey: .reportKind)
        sections = try values.decodeIfPresent(StructuredOutputSections.self, forKey: .sections)
        artifactKey = try values.decodeIfPresent(String.self, forKey: .artifactKey)
        summary = try values.decodeIfPresent(String.self, forKey: .summary)
        ordered = try values.decodeIfPresent(Bool.self, forKey: .ordered)
        if type == "diagram" {
            diagramItems = try values.decodeIfPresent([StructuredOutputDiagramItem].self, forKey: .items)
            items = nil
        } else {
            items = try values.decodeIfPresent([String].self, forKey: .items)
            diagramItems = nil
        }
    }
}

private struct StructuredOutputPoint: Decodable, Identifiable {
    let label: String
    let value: Double
    var id: Int { label.hashValue }
}

private struct StructuredOutputDiagramItem: Decodable {
    let label: String
    let state: String
    let detail: String?
}

private struct StructuredOutputSections: Decodable {
    let result: [StructuredOutputBlock]
    let work: [StructuredOutputBlock]
    let checks: [StructuredOutputCheck]
    let limitations: [StructuredOutputBlock]
    let materials: [StructuredOutputMaterial]
}

private struct StructuredOutputCheck: Decodable {
    let label: String
    let status: String
    let detail: String?
}

private struct StructuredOutputMaterial: Decodable {
    let kind: String
    let title: String
    let ref: String
}

private struct StructuredOutputError: Decodable {
    let code: String
    let message: String
    let retryable: Bool

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let message = try? value.decode(String.self) {
            code = "other"
            self.message = message
            retryable = false
            return
        }
        let object = try decoder.container(keyedBy: CodingKeys.self)
        code = try object.decode(String.self, forKey: .code)
        message = try object.decode(String.self, forKey: .message)
        retryable = try object.decode(Bool.self, forKey: .retryable)
    }

    private enum CodingKeys: String, CodingKey { case code, message, retryable }
}
