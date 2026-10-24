import Charts
import SwiftUI

/// Renderer JSON-контракта роли v1. Геометрия и оформление остаются в iOS;
/// модель передаёт только тип блока и его данные.
struct ChatStructuredOutputView: View {
    let json: String
    var isStreaming = false
    /// Контекст сообщения для отметок checklist-виджета внутри конверта
    /// (карточка 21842242); nil — конверт не из переписки.
    var checklist: ChecklistSyncContext? = nil
    /// Кнопка «Запустить» у блока `command` — только владельцу и не в режиме выбора.
    var allowsCommands = false

    /// Разобранный конверт кэшируется по строке JSON: `document` читается на
    /// каждом проходе `body`, а `JSONDecoder` на каждый вызов — это работа,
    /// которую лента сообщений повторяла на каждый кадр.
    private static let documentCache = ParsedValueCache<StructuredOutputEnvelope>(limit: 32)

    private var document: StructuredOutputEnvelope? {
        if let cached = Self.documentCache.value(for: json) { return cached }
        guard let data = json.data(using: .utf8) else { return nil }
        let decoded = try? JSONDecoder().decode(StructuredOutputEnvelope.self, from: data)
        if let decoded {
            Self.documentCache.set(decoded, for: json)
        }
        return decoded
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
                        RoleReplyMarkdown(text: text, checklist: checklist)
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
            RoleReplyMarkdown(text: partialText, isStreaming: true, checklist: checklist)
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
                RoleReplyMarkdown(text: text, checklist: checklist)
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
        case "command":
            commandBlock(block)
        case "link":
            linkBlock(block)
        default:
            unsupportedBlock("Тип блока «\(block.type)» пока не поддерживается")
        }
    }

    /// Команда для .110 (контракт v1, блок `command`). До 20.10.2026 этот тип
    /// здесь не рисовался — кнопка «Запустить» пропала с переходом ролей на JSON.
    @ViewBuilder
    private func commandBlock(_ block: StructuredOutputBlock) -> some View {
        if let command = block.command?.trimmingCharacters(in: .whitespacesAndNewlines), !command.isEmpty {
            VStack(alignment: .leading, spacing: TFSpacing.xs) {
                if let title = block.title, !title.isEmpty {
                    Text(title).tfText(.meta).foregroundStyle(Color.tfSub)
                }
                if allowsCommands {
                    BashCommandBlock(command: command).id(command)
                } else {
                    RoleReplyMarkdown(text: "```bash\n" + command + "\n```")
                }
            }
            .accessibilityIdentifier("chat.structured-output.command")
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

    /// График рисуется общим `RoleChartBlock` — тем же, что и блок
    /// ```widget в `ChatWidgetView`. Свой рисунок здесь означал второй цвет и
    /// свой формат точек: график по каталогу ролей в результате шага и в итоге
    /// задачи не рисовался вовсе (карточка 19f57bc9).
    @ViewBuilder
    private func chartBlock(_ block: StructuredOutputBlock) -> some View {
        let points = (block.points ?? []).enumerated().map { index, point in
            RoleChartPoint(id: index, label: point.label, value: point.value)
        }
        if !points.isEmpty {
            RoleChartBlock(title: block.title,
                           kind: block.kind,
                           unit: block.unit,
                           points: points,
                           accessibilityId: "chat.structured-output.chart")
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
        switch ChatMaterialDestination.resolve(material.ref, kind: material.kind) {
        case .note(let id):
            NavigationLink(value: AppRoute.noteEditor(noteID: id)) {
                Label(material.title, systemImage: "doc.text")
                    .tfText(.body)
                    .foregroundStyle(Color.tfBlue)
            }
            .accessibilityIdentifier("chat.material.note.\(id)")
        case .task(let id):
            TaskCardLink(taskID: id) {
                Label(material.title, systemImage: "checklist").tfText(.body)
            }
        case .web(let url):
            Link(destination: url) {
                Label(material.title, systemImage: "arrow.up.right.square")
                    .tfText(.body)
                    .foregroundStyle(Color.tfBlue)
            }
        case nil:
            VStack(alignment: .leading, spacing: 2) {
                Text(material.title).tfText(.body).foregroundStyle(Color.tfText)
                Text(material.ref).tfText(.caption).foregroundStyle(Color.tfSub).textSelection(.enabled)
            }
        }
    }

    /// Ссылка из ответа роли (владелец 23.10.2026: «ссылку правильную давай
    /// на материал... чтобы по падении мог сразу прочитать, а то щас не
    /// кликабельна»).
    ///
    /// Разбор адреса — тот же, что у материалов (`ChatMaterialDestination`):
    /// `note://<id>` — заметка «Базы знаний» открывается ВНУТРИ приложения
    /// (пуш в редактор заметки), `task://<id>` — карточка задачи, `http(s)` —
    /// внешняя ссылка в системном браузере. До этой правки блок `link` в iOS
    /// не рисовался вовсе: попадал в «Тип блока не поддерживается».
    @ViewBuilder
    private func linkBlock(_ block: StructuredOutputBlock) -> some View {
        let title = block.title ?? block.url ?? "Ссылка"
        switch ChatMaterialDestination.resolve(block.url ?? "") {
        case .note(let id):
            NavigationLink(value: AppRoute.noteEditor(noteID: id)) {
                Label(title, systemImage: "doc.text")
                    .tfText(.body)
                    .foregroundStyle(Color.tfBlue)
            }
            .accessibilityIdentifier("chat.link.note.\(id)")
        case .task(let id):
            TaskCardLink(taskID: id) {
                Label(title, systemImage: "checklist").tfText(.body)
            }
            .accessibilityIdentifier("chat.link.task.\(id)")
        case .web(let url):
            Link(destination: url) {
                Label(title, systemImage: "arrow.up.right.square")
                    .tfText(.body)
                    .foregroundStyle(Color.tfBlue)
            }
            .accessibilityIdentifier("chat.link.web")
        case nil:
            unsupportedBlock("У ссылки должен быть http(s)-адрес или note://<id заметки>")
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
        // В описании карточки роль пишет конверт сама и `needs_human` часто
        // опускает; без поля — решение владельца не нужно (владелец 19.10.2026).
        needsHuman = try values.decodeIfPresent(Bool.self, forKey: .needsHuman) ?? false

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
    let command: String?
    let url: String?

    enum CodingKeys: String, CodingKey {
        case type, text, level, items, ordered, title, columns, rows, code, current, total, unit, label, kind, points, sections, summary, command, url
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
        command = try values.decodeIfPresent(String.self, forKey: .command)
        url = try values.decodeIfPresent(String.self, forKey: .url)
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

/// Точка блока графика в конверте. Читает и `label`/`value` каталога ролей,
/// и `x`/`y` старого блока виджета: один и тот же ответ роли не должен
/// зависеть от того, каким экраном его покажут (карточка 19f57bc9).
private struct StructuredOutputPoint: Decodable {
    let label: String
    let value: Double

    enum CodingKeys: String, CodingKey { case label, value, x, y }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let rawLabel = try values.decodeIfPresent(String.self, forKey: .label)
            ?? values.decodeIfPresent(String.self, forKey: .x)
        let rawValue = try values.decodeIfPresent(Double.self, forKey: .value)
            ?? values.decodeIfPresent(Double.self, forKey: .y)
        guard let rawLabel, let rawValue else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath,
                                      debugDescription: "Точка графика без метки и значения"))
        }
        label = rawLabel
        value = rawValue
    }
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
