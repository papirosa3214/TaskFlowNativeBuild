import SwiftUI

// Живой ход роли в чате (владелец 27.09.2026, LOCK-229): пока роль отвечает,
// окно чата показывает то же, что окно сессии Claude Code, — текст ответа
// растёт по словам, между кусками текста идут шаги (что читает, что
// выполняет, что ищет). После ответа ход остаётся в ленте таким же, каким
// шёл вживую (владелец 01.10.2026: свёрнутая строка «7 шагов · 42 с»
// выглядела так, будто всё удалили).
//
// 30.09.2026: текст идёт ровной скоростью и проявляется из пустоты,
// размышления — строкой «Думает…» с раскрываемым окошком вместо мелькающих
// фраз; тап по шагу или размышлению открывает шторку с подробностями.

/// Сколько работы роли показывать в ленте (владелец 14.10.2026). Одна
/// настройка на все чаты, меняется в шторке «Чат».
enum RoleWorkDetailLevel: String, CaseIterable, Identifiable {
    case minimal, standard, detailed

    static let storageKey = "chat.workDetailLevel"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .minimal: return "Минимум"
        case .standard: return "Стандарт"
        case .detailed: return "Подробно"
        }
    }

    var explanation: String {
        switch self {
        case .minimal: return "Только ответ и строка «Работает»."
        case .standard: return "Шаги и размышления строками, подробности — по нажатию."
        case .detailed: return "Размышления сразу развёрнуты, команды и правки показаны целиком."
        }
    }

    /// Что из хода попадает в ленту: в «Минимуме» — только текст.
    func visible(_ items: [RoleChatLiveItem]) -> [RoleChatLiveItem] {
        guard self == .minimal else { return items }
        return items.filter { if case .text = $0 { return true }; return false }
    }
}

/// Действие шага по имени инструмента с сервера. Сервер имя не
/// интерпретирует — подпись и значок целиком на клиенте. Существительные, а
/// не глаголы: одна и та же подпись годится и для идущего шага, и для
/// сделанного, и не зависит от рода роли.
enum RoleLiveStepKind {
    static func label(forTool tool: String) -> String {
        // Инструменты трекера (`taskflow_taskflow_agents` и т.п.): что именно
        // сделано, сервер пишет подписью — «кто на связи», «задачи проекта».
        if tool.hasPrefix("taskflow_") { return "Трекер" }
        switch tool {
        case "read": return "Чтение"
        case "edit", "write": return "Правка"
        case "bash": return "Команда"
        case "grep", "glob", "find": return "Поиск"
        case "ls": return "Папка"
        default: return "Действие"
        }
    }

    static func symbol(forTool tool: String) -> String {
        if tool.hasPrefix("taskflow_") { return "checklist" }
        switch tool {
        case "read": return "doc.text"
        case "edit", "write": return "pencil.line"
        case "bash": return "terminal"
        case "grep", "glob", "find": return "magnifyingglass"
        case "ls": return "folder"
        default: return "gearshape"
        }
    }
}

enum RoleLiveFormat {
    /// «1 шаг / 3 шага / 7 шагов».
    static func steps(_ count: Int) -> String {
        let mod100 = count % 100
        let word: String
        if mod100 >= 11 && mod100 <= 14 {
            word = "шагов"
        } else {
            switch count % 10 {
            case 1: word = "шаг"
            case 2, 3, 4: word = "шага"
            default: word = "шагов"
            }
        }
        return "\(count) \(word)"
    }

    /// «42 с», «3 мин 5 с», «12 мин».
    static func duration(seconds: Int) -> String {
        let s = max(0, seconds)
        if s < 60 { return "\(s) с" }
        let minutes = s / 60
        let rest = s % 60
        return rest == 0 ? "\(minutes) мин" : "\(minutes) мин \(rest) с"
    }
}

/// Строка шага: значок, действие, подпись (путь, команда, запрос).
struct RoleLiveStepRow: View {
    let step: RoleChatLiveStep
    /// false — подпись показана отдельным блоком ниже («Подробно»).
    var showsDetail = true

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: TFSpacing.sm) {
            icon
                .font(.system(size: 12, weight: .medium))
                .frame(width: 16)
            Text(RoleActionPresentation.forStep(step).title)
                .tfText(.meta)
                .foregroundStyle(Color.tfSub)
            if showsDetail, let detail = RoleActionPresentation.forStep(step).skillName ?? step.detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color.tfDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("role-action-" + step.id)
    }

    @ViewBuilder
    private var icon: some View {
        switch step.status {
        case .running:
            Image(systemName: RoleActionPresentation.forStep(step).symbol)
                .foregroundStyle(Color.tfSub)
                .symbolEffect(.pulse, options: .repeating)
        case .done:
            Image(systemName: RoleActionPresentation.forStep(step).symbol)
                .foregroundStyle(Color.tfDim)
        case .error:
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Color.tfOrange)
        }
    }

    private var accessibilityText: String {
        let status: String
        switch step.status {
        case .running: status = "идёт"
        case .done: status = "готово"
        case .error: status = "ошибка"
        }
        return [RoleActionPresentation.forStep(step).title, RoleActionPresentation.forStep(step).skillName ?? step.detail, status]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

/// Элементы хода по порядку: шаги строками, текст абзацами, размышления
/// свёрнутой строкой. В истории промежуточный текст («сейчас проверю…»)
/// приглушён — главный ответ в пузыре ниже. Тап по шагу или законченному
/// размышлению — шторка с подробностями (владелец 30.09.2026).
struct RoleLiveItemsList: View {
    let items: [RoleChatLiveItem]
    var textColor: Color = .tfText
    /// Проявление текста из пустоты — только у идущего хода.
    var fade: RoleTextFade?
    var isStreaming = false
    @State private var detail: RoleLiveDetail?
    @AppStorage(RoleWorkDetailLevel.storageKey) private var detailLevel = RoleWorkDetailLevel.standard

    var body: some View {
        let expanded = detailLevel == .detailed
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            // Индекс, а не текст: текст растёт каждые 150 мс, и id по нему
            // пересоздавал бы строку на каждом кадре.
            ForEach(Array(detailLevel.visible(items).enumerated()), id: \.offset) { index, item in
                Group {
                    switch item {
                    case .text(let text):
                        RoleReplyMarkdown(text: RoleTranslator.shared.display(text), color: textColor, fade: fade, isStreaming: isStreaming)
                    case .step(let step):
                        let hasDetail = !(step.detail ?? "").isEmpty
                        Button { detail = .step(step) } label: {
                            VStack(alignment: .leading, spacing: TFSpacing.xs) {
                                RoleLiveStepRow(step: step, showsDetail: !(expanded && hasDetail))
                                if expanded, hasDetail, let text = step.detail {
                                    // «Подробно»: команда или путь целиком, окошком с кодом.
                                    Text(text)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(Color.tfText)
                                        .multilineTextAlignment(.leading)
                                        .padding(TFSpacing.sm)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.tfCard, in: RoundedRectangle(cornerRadius: TFRadius.md))
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Показать подробности")
                    case .thinking(let thinking):
                        if thinking.isRunning {
                            RoleThinkingLiveRow(thinking: thinking, startsExpanded: expanded)
                        } else {
                            Button { detail = .thinking(thinking) } label: {
                                RoleThinkingDoneRow(thinking: thinking)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Показать размышления")
                            if expanded, !thinking.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                RoleThinkingWindow(text: thinking.text)
                            }
                        }
                    }
                }
                .modifier(RoleItemAppearance(animate: fade?.isAnimating == true && Self.isAction(item)))
            }
        }
        .sheet(item: $detail) { detail in
            RoleLiveDetailSheet(detail: detail)
        }
        .modifier(RoleTranslationHost(texts: finishedTexts))
    }

    /// Реплики и законченные размышления, которые уже не растут: у идущего
    /// хода последняя реплика ещё пишется. Размышления переводятся здесь, а
    /// не в их шторке: перевод, запущенный при открытии шторки, открывал
    /// системную шторку переводчика поверх нашей, и приложение падало
    /// (`UISheetPresentationController _tryToConnectToRemoteSheet`, 20.10.2026).
    private var finishedTexts: [String] {
        let thoughts = items.compactMap { item -> String? in
            if case .thinking(let thinking) = item, !thinking.isRunning { return thinking.text }; return nil
        }
        let texts = items.compactMap { item -> String? in
            if case .text(let text) = item { return text }; return nil
        }
        let lastIsText = items.last.map { if case .text = $0 { return true }; return false } ?? false
        return (isStreaming && lastIsText ? Array(texts.dropLast()) : texts) + thoughts
    }

    private static func isAction(_ item: RoleChatLiveItem) -> Bool {
        if case .text = item { return false }; return true
    }

    /// Сколько символов текста идёт после каждого элемента — чтобы хвост
    /// проявлялся по всему ходу, а не у каждого абзаца отдельно.
    static func charactersAfter(_ items: [RoleChatLiveItem]) -> [Int] {
        var result = Array(repeating: 0, count: items.count)
        var sum = 0
        for index in items.indices.reversed() {
            result[index] = sum
            if case .text(let text) = items[index] { sum += text.count }
        }
        return result
    }
}

private struct RoleItemAppearance: ViewModifier {
    let animate: Bool
    @State private var appeared = false
    func body(content: Content) -> some View {
        content
            .opacity(animate && !appeared ? 0 : 1)
            .onAppear {
                if animate { withAnimation(.easeInOut(duration: 0.7)) { appeared = true } }
                else { appeared = true }
            }
    }
}

/// Идущий ход: шаги и растущий текст прямо по фону ленты, без карточки —
/// как ответ роли в 1:1-чате (LOCK-230); внизу — сколько уже идёт.
struct RoleLiveTurnBubble: View {
    let turn: RoleChatLiveTurn
    let showsName: Bool
    var isComplete = false
    var pacesText = true
    var startsWithSnapshot = false
    @State private var seeded = false
    @State private var playbackRevision = 0
    var onPlaybackComplete: () -> Void = {}
    @State private var completionReported = false
    @State private var completedAt: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var driver = RoleLivePacerDriver()
    @State private var visibleItems: [RoleChatLiveItem] = []
    @State private var fade = RoleTextFade()
    @AppStorage(RoleWorkDetailLevel.storageKey) private var detailLevel = RoleWorkDetailLevel.standard

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            if showsName {
                Text(turn.name)
                    .tfText(.meta)
                    .foregroundStyle(Color.tfSub)
            }
            if !(pacesText ? visibleItems : turn.items).isEmpty {
                RoleLiveItemsList(items: pacesText ? visibleItems : turn.items, fade: pacesText && !reduceMotion ? fade : nil, isStreaming: !isComplete)
            }
            // Сервер до 30.09.2026 шлёт только признак «думает» без текста.
            if turn.thinking != nil && turn.runningThinking == nil && detailLevel != .minimal {
                RoleThinkingLiveRow(thinking: nil)
            }
            if isComplete {
                Text(footer(now: completedAt ?? .now))
                    .tfText(.caption)
                    .foregroundStyle(Color.tfDim)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(footer(now: context.date))
                        .tfText(.caption)
                        .foregroundStyle(Color.tfDim)
                }
                .hintAnchor(HintAnchorID.roleActions)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            if isComplete { completedAt = .now }
            if pacesText { ingest(turn.items) }
        }
        .onChange(of: turn.items) { _, items in if pacesText { ingest(items) } }
        .onChange(of: isComplete) { _, complete in
            if complete {
                completedAt = .now
                driver.pacer.finish()
                publish()
            } else { completedAt = nil }
            playbackRevision += 1
        }
        .task(id: playbackRevision) {
            guard pacesText else { return }
            let diagnosticID = driver.isAnimating(now: .now) ? AppDiagnostics.shared.begin(.reply) : nil
            defer { if let diagnosticID { AppDiagnostics.shared.end(diagnosticID) } }
            // Часы работают только до опустошения очереди и проявления хвоста.
            while !Task.isCancelled && driver.isAnimating(now: .now) {
                do { try await Task.sleep(for: .milliseconds(16)) } catch { break }
                if driver.tick() { publish() }
                let animating = driver.isAnimating(now: .now)
                if animating != fade.isAnimating { fade.isAnimating = animating }
            }
            if !Task.isCancelled && isComplete && !completionReported {
                completionReported = true
                onPlaybackComplete()
            }
        }
    }

    private func ingest(_ items: [RoleChatLiveItem]) {
        if !driver.isAnimating(now: .now) { driver.resetClock() }
        // Скрытые шаги в очередь не идут: иначе текст вставал бы на паузу
        // перед действием, которого в «Минимуме» не видно.
        driver.pacer.ingest(detailLevel.visible(items))
        if isComplete {
            completionReported = false
            driver.pacer.finish()
        }
        if !seeded {
            seeded = true
            if startsWithSnapshot { driver.pacer.flush() }
        }
        publish()
        playbackRevision += 1
    }

    private func publish() {
        let items = driver.pacer.visibleItems
        if items != visibleItems {
            visibleItems = items
            AppDiagnostics.shared.increment(.updates)
        }
        fade = RoleTextFade(
            rate: driver.pacer.rate,
            lastRevealAt: driver.pacer.lastRevealAt,
            isAnimating: driver.isAnimating(now: .now)
        )
    }

    private func footer(now: Date) -> String {
        let steps = turn.items.filter(\.isStep).count
        var parts = [isComplete ? "Ответ получен" : "Работает"]
        if let start = turn.startDate {
            parts.append(RoleLiveFormat.duration(seconds: Int(now.timeIntervalSince(start))))
        }
        if steps > 0 { parts.append(RoleLiveFormat.steps(steps)) }
        return parts.joined(separator: " · ")
    }
}

/// Держатель очереди вне наблюдения SwiftUI: такты часов меняют скорость и
/// бюджет, но перерисовку вызывают только новые слова.
@MainActor
final class RoleLivePacerDriver {
    var pacer = RoleLiveTextPacer()
    private var lastTick: ContinuousClock.Instant?

    func resetClock() { lastTick = nil }

    /// Такт; true — видимый текст вырос.
    func tick() -> Bool {
        AppDiagnostics.shared.increment(.ticks)
        let now = ContinuousClock.now
        defer { lastTick = now }
        guard let lastTick, pacer.hasPendingText else { return false }
        let elapsed = now - lastTick
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        let before = pacer.lastPresentationAt
        pacer.advance(elapsed: min(seconds, 0.1))
        let grew = pacer.lastPresentationAt != before
        // Счётчик перерисовок текста до 18.10.2026 нигде не увеличивался и
        // показывал застрявшее число — считаем именно рост видимого текста.
        if grew { AppDiagnostics.shared.increment(.draws) }
        return grew
    }

    func isAnimating(now: Date) -> Bool {
        pacer.hasPendingText || now.timeIntervalSince(pacer.lastPresentationAt) < RoleTextFade.duration + 0.1
    }
}

/// Роль думает (30.09.2026): «Думает…» с бегущим бликом, без мелькающих
/// фраз. Если сервер прислал текст размышления — стрелка раскрывает окошко,
/// где мысли идут прокруткой.
struct RoleThinkingLiveRow: View {
    /// nil — сервер прислал только признак «думает».
    let thinking: RoleChatThinking?
    @State private var isExpanded: Bool

    /// `startsExpanded` — уровень «Подробно»: окошко с мыслями открыто сразу.
    init(thinking: RoleChatThinking?, startsExpanded: Bool = false) {
        self.thinking = thinking
        _isExpanded = State(initialValue: startsExpanded)
    }

    private var hasText: Bool {
        !(thinking?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            Button {
                withAnimation(.snappy(duration: 0.28)) { isExpanded.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: TFSpacing.sm) {
                    Image(systemName: "brain")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.tfSub)
                        .symbolEffect(.pulse, options: .repeating)
                        .frame(width: 16)
                    RoleShimmerText(text: "Думает…")
                    if hasText {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.tfDim)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!hasText)
            .accessibilityLabel("Думает")
            .accessibilityHint(hasText ? (isExpanded ? "Скрыть размышления" : "Показать размышления") : "")

            if isExpanded, let thinking, hasText {
                RoleThinkingWindow(text: thinking.text)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

/// «Думает…» с бликом, пробегающим по буквам — как индикатор в Claude.
struct RoleShimmerText: View {
    let text: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let label = Text(text).tfText(.meta)
        if reduceMotion {
            label.foregroundStyle(Color.tfSub)
        } else {
            TimelineView(.animation) { context in
                let period = 1.8
                let phase = context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: period) / period
                // Блик идёт от -0.3 до 1.3, чтобы входить и выходить за край.
                let center = -0.3 + phase * 1.6
                label
                    .foregroundStyle(Color.tfSub)
                    .overlay {
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: center - 0.25),
                                .init(color: Color.tfText, location: center),
                                .init(color: .clear, location: center + 0.25),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .mask(label)
                    }
            }
        }
    }
}

/// Окошко с идущими мыслями: невысокое, прокручивается само вниз, новый
/// текст проявляется так же плавно, как ответ. Уже накопленное при
/// раскрытии показывается сразу.
struct RoleThinkingWindow: View {
    let text: String
    @State private var driver = RoleLivePacerDriver()
    @State private var visible = ""
    @State private var fade = RoleTextFade()
    @State private var contentHeight: CGFloat = 0
    @State private var playbackRevision = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let maxHeight: CGFloat = 132

    var body: some View {
        HStack(alignment: .top, spacing: TFSpacing.sm) {
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.tfStroke)
                .frame(width: 2)
            ScrollView {
                // `код` и **жирное** — ярче приглушённого текста, чтобы главное
                // сразу бросалось в глаза (владелец 14.10.2026, по образцу).
                Text(Self.highlighted(visible))
                    .tfText(.caption)
                    .italic()
                    .foregroundStyle(Color.tfSub)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .roleReveal(reduceMotion ? nil : fade)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .scrollIndicators(.hidden)
            .defaultScrollAnchor(.bottom)
            .defaultScrollAnchor(.bottom, for: .sizeChanges)
            .frame(height: min(max(contentHeight, 1), Self.maxHeight))
            .mask {
                // Верх окошка растворяется, когда мыслей больше, чем влезает.
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: contentHeight > Self.maxHeight ? 24 : 0)
                    Color.black
                }
            }
        }
        .padding(.leading, 7)
        .onAppear {
            driver.pacer.ingest([.text(text)])
            driver.pacer.flush()
            publish()
        }
        .onChange(of: text) { _, text in
            if !driver.isAnimating(now: .now) { driver.resetClock() }
            driver.pacer.ingest([.text(text)])
            publish()
            playbackRevision += 1
        }
        .task(id: playbackRevision) {
            let diagnosticID = driver.isAnimating(now: .now) ? AppDiagnostics.shared.begin(.thinking) : nil
            defer { if let diagnosticID { AppDiagnostics.shared.end(diagnosticID) } }
            while !Task.isCancelled && driver.isAnimating(now: .now) {
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
                if driver.tick() { publish() }
                let animating = driver.isAnimating(now: .now)
                if animating != fade.isAnimating { fade.isAnimating = animating }
            }
        }
    }

    static func highlighted(_ text: String) -> AttributedString {
        var result = AttributedString()
        for (index, line) in text.components(separatedBy: "\n").enumerated() {
            if index > 0 { result += AttributedString("\n") }
            for run in MarkdownParser.parseInline(line) {
                var piece = AttributedString(run.text)
                if run.code {
                    piece.font = .system(.caption, design: .monospaced)
                    piece.foregroundColor = .tfText
                } else if run.bold {
                    piece.inlinePresentationIntent = .stronglyEmphasized
                    piece.foregroundColor = .tfText
                } else if run.italic {
                    piece.inlinePresentationIntent = .emphasized
                }
                result += piece
            }
        }
        return result
    }

    private func publish() {
        if case .text(let shown)? = driver.pacer.visibleItems.first {
            if shown != visible {
                visible = shown
                AppDiagnostics.shared.increment(.updates)
            }
        }
        fade = RoleTextFade(
            rate: driver.pacer.rate,
            lastRevealAt: driver.pacer.lastRevealAt,
            isAnimating: driver.isAnimating(now: .now)
        )
    }
}

/// Законченное размышление строкой: «Размышления · 12 с», тап — шторка.
struct RoleThinkingDoneRow: View {
    let thinking: RoleChatThinking

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: TFSpacing.sm) {
            Image(systemName: "brain")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.tfDim)
                .frame(width: 16)
            Text("Размышления")
                .tfText(.meta)
                .foregroundStyle(Color.tfSub)
            if let seconds = thinking.durationSeconds {
                Text(RoleLiveFormat.duration(seconds: seconds))
                    .tfText(.caption)
                    .foregroundStyle(Color.tfDim)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.tfDim)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard let seconds = thinking.durationSeconds else { return "Размышления" }
        return "Размышления, \(RoleLiveFormat.duration(seconds: seconds))"
    }
}

/// Что открыто в шторке: размышление или шаг.
enum RoleLiveDetail: Identifiable {
    case thinking(RoleChatThinking)
    case step(RoleChatLiveStep)

    var id: String {
        switch self {
        case .thinking(let thinking): return "thinking-\(thinking.id)"
        case .step(let step): return "step-\(step.id)"
        }
    }
}

/// Системная шторка на пол-экрана, тянется до полного: всё о выбранном
/// размышлении или шаге.
struct RoleLiveDetailSheet: View {
    let detail: RoleLiveDetail
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TFSpacing.md) {
                    if let meta, !meta.isEmpty {
                        Text(meta)
                            .tfText(.caption)
                            .foregroundStyle(Color.tfDim)
                    }
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, TFSpacing.screenHorizontal)
                .padding(.vertical, TFSpacing.md)
            }
            .tfNativeHeader(title, displayMode: .inline)
            .toolbar {
                // Перевод размышлений (владелец 20.10.2026): кнопка там, где
                // их читают, — в этой шторке. Переключатель общий с лентой.
                if case .thinking(let thinking) = detail {
                    ToolbarItem(placement: .topBarLeading) {
                        RoleTranslateToggle(texts: [thinking.text])
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var title: String {
        switch detail {
        case .thinking: return "Размышления"
        case .step(let step): return RoleActionPresentation.forStep(step).title
        }
    }

    private var meta: String? {
        switch detail {
        case .thinking(let thinking):
            return thinking.durationSeconds.map { RoleLiveFormat.duration(seconds: $0) }
        case .step(let step):
            let status: String
            switch step.status {
            case .running: status = "Идёт"
            case .done: status = "Готово"
            case .error: status = "Ошибка"
            }
            return ([status, step.durationSeconds.map { RoleLiveFormat.duration(seconds: $0) }, step.tool] as [String?])
                .compactMap { $0 }
                .joined(separator: " · ")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch detail {
        case .thinking(let thinking):
            RoleReplyMarkdown(text: RoleTranslator.shared.display(thinking.text), color: .tfText)
                .italic()
                .textSelection(.enabled)
        case .step(let step):
            VStack(alignment: .leading, spacing: TFSpacing.md) {
                if let detail = step.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(Color.tfText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                // Владелец 20.10.2026: «нет точного вызова команды, нет точного
                // ответа» — показываем оба, чтобы разбирать сбой самому.
                if let args = step.args, !args.isEmpty { ioSection("Вызов", args, id: "role.step.args") }
                if let output = step.output, !output.isEmpty { ioSection("Ответ", output, id: "role.step.output") }
                if (step.detail ?? "").isEmpty, (step.args ?? "").isEmpty, (step.output ?? "").isEmpty {
                    Text("Подробностей у шага нет.")
                        .tfText(.meta)
                        .foregroundStyle(Color.tfSub)
                }
            }
        }
    }
}

private func ioSection(_ title: String, _ text: String, id: String) -> some View {
    VStack(alignment: .leading, spacing: TFSpacing.xs) {
        Text(title)
            .tfText(.meta)
            .foregroundStyle(Color.tfSub)
        Text(text)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(Color.tfText)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(TFSpacing.sm)
            .background(Color.tfCard, in: RoundedRectangle(cornerRadius: TFRadius.md))
            .accessibilityIdentifier(id)
    }
}

// MARK: - Проявление текста

/// Как проявляется хвост идущего текста (владелец 30.09.2026): новые буквы
/// выходят из прозрачности и лёгкого размытия. Возраст буквы считается от
/// времени первого появления; новые слова не меняют возраст старых букв.
struct RoleTextFade: Equatable {
    var rate: Double = RoleLiveTextPacer.minRate
    var lastRevealAt: Date = .distantPast
    var isAnimating = false
    static let duration: TimeInterval = 0.7
}

/// Retain each glyph's first appearance across word batches, pauses and reflow.
/// This reference lives in the modifier's State and does not publish draw ticks.
///
/// Владелец 17.10.2026 («окна скачет, что-то моргает»): проходить по всем
/// глифам на каждом кадре было нельзя — на длинном ответе это десятки тысяч
/// итераций × 60–120 Гц, и лента мигала. Поэтому проявившиеся глифы
/// отбрасываются разом: `revealedUpTo` — сколько глифов уже проявились
/// полностью, а `appearanceTimes` хранит только непроявившийся хвост.
/// Инвариант: `revealedUpTo + appearanceTimes.count == count`.
final class RoleTextRevealHistory {
    /// Времена появления ещё не проявившихся глифов (хвост).
    private var appearanceTimes: [Date] = []
    private var animated = true

    /// Число глифов, проявившихся полностью (или не анимировались вовсе).
    private(set) var revealedUpTo = 0

    func record(count: Int, now: Date, rate: Double, animated: Bool) {
        self.animated = animated
        guard count > 0 else { revealedUpTo = 0; appearanceTimes = []; return }
        if !animated {
            // Не анимируем: всё видно сразу, хвоста нет.
            revealedUpTo = count
            appearanceTimes = []
            return
        }
        // Инвариант `revealedUpTo + appearanceTimes.count <= count` держим жёстко:
        // всё, что выходит за пределы текста, — проявившийся глиф, хвост обрезаем
        // с начала и прибавляем к `revealedUpTo`. Смысл тот же, что у старого кода
        // при укорочении текста: показанное начало остаётся показанным.
        let overflow = revealedUpTo + appearanceTimes.count - count
        if overflow > 0 {
            let drop = min(overflow, appearanceTimes.count)
            appearanceTimes.removeFirst(drop)
            revealedUpTo -= drop
        }
        // Хвост, доживший до конца проявления, оседает разом — с этого момента
        // по уже показанным глифам больше не ходим.
        let settled = appearanceTimes.prefix { now.timeIntervalSince($0) >= RoleTextFade.duration }.count
        if settled > 0 {
            appearanceTimes.removeFirst(settled)
            revealedUpTo += settled
        }
        // Новая порция текста: ДОБАВЛЯЕМ `pending` глифов в конец хвоста.
        // Верхняя граница — хвост плюс новая порция, а не сама порция:
        // пока хвост ещё не осел, текст в чате растёт кадрами, и диапазон
        // `appearanceTimes.count..<pending` оказывался вывернут (lowerBound >
        // upperBound) → EXC_BREAKPOINT, то есть вылет приложения.
        let pending = count - revealedUpTo - appearanceTimes.count
        if pending > 0 {
            for offset in 0..<pending {
                appearanceTimes.append(
                    now.addingTimeInterval(-Double(pending - offset - 1) / max(rate, 1))
                )
            }
        }
    }

    /// Прозрачность глифа по ЕГО индексу во всём тексте (0-based).
    /// Глифы до `revealedUpTo` проявились целиком — их не трогаем; анимируется
    /// только хвост, то есть та порция текста, что пришла последней.
    func opacity(at index: Int, now: Date) -> Double {
        guard animated, index >= revealedUpTo else { return 1 }
        let tailIndex = index - revealedUpTo
        guard appearanceTimes.indices.contains(tailIndex) else { return 1 }
        let t = min(1, max(0, now.timeIntervalSince(appearanceTimes[tailIndex]) / RoleTextFade.duration))
        return t * t * (3 - 2 * t)
    }
}

struct RoleRevealRenderer: TextRenderer {
    var fade: RoleTextFade
    var now: Date
    var history: RoleTextRevealHistory

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        var total = 0
        for line in layout { for run in line { total += run.count } }
        history.record(count: total, now: now, rate: fade.rate, animated: fade.isAnimating)
        var index = 0
        for line in layout {
            var lineCount = 0
            for run in line { lineCount += run.count }
            // Строка целиком проявилась — рисуем одним вызовом.
            if index >= history.revealedUpTo {
                ctx.draw(line)
                index += lineCount
                continue
            }
            for run in line {
                for glyph in run {
                    let opacity = history.opacity(at: index, now: now)
                    index += 1
                    guard opacity > 0.01 else { continue }
                    var copy = ctx
                    copy.opacity = opacity
                    copy.draw(glyph)
                }
            }
        }
    }
}

private struct RoleTextRevealModifier: ViewModifier {
    let fade: RoleTextFade
    @State private var history = RoleTextRevealHistory()

    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: nil, paused: !fade.isAnimating)) { context in
            content.textRenderer(RoleRevealRenderer(
                fade: fade,
                now: fade.isAnimating ? context.date : .distantFuture,
                history: history
            ))
        }
    }
}

extension View {
    /// Проявление хвоста текста; nil — текст рисуется как обычно.
    @ViewBuilder
    func roleReveal(_ fade: RoleTextFade?) -> some View {
        if let fade { self.modifier(RoleTextRevealModifier(fade: fade)) }
        else { self }
    }
}
