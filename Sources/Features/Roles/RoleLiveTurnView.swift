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


/// Строка шага: значок, действие, подпись (путь, команда, запрос).
struct RoleLiveStepRow: View {
    let step: RoleChatLiveStep
    /// false — подпись показана отдельным блоком ниже («Подробно»).
    var showsDetail = true

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: TFSpacing.sm) {
            icon
                .tfTypeFont(size: 12, weight: .medium)
                .frame(width: 16)
            Text(RoleActionPresentation.forStep(step).title)
                .tfChatText(.meta)
                .foregroundStyle(Color.tfSub)
                // Одна строка: перенос поднял бы строку шага и изменил высоту
                // живого пузыря — лента от этого прыгает (владелец 25.10.2026).
                .lineLimit(1)
            if showsDetail, let detail = RoleActionPresentation.forStep(step).skillName ?? step.detail, !detail.isEmpty {
                Text(detail)
                    .font(.tfChat(.mono, design: .monospaced))
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
    /// Тело шага по его id — когда шаг раскрыли, а тела в списке нет.
    ///
    /// В истории сообщений вывод инструмента и аргументы вызова не присылаются
    /// (29.10.2026, «телефон — чисто окошко»): они весили 3,2 МБ на 20 чатов,
    /// а рисуются только в раскрытой шторке шага. Владелец раскрыл шаг —
    /// телефон спросил ровно этот шаг.
    ///
    /// У идущего хода загрузчика нет: там тела приходят с самим ходом.
    var stepDetailLoader: ((String) async -> RoleChatLiveStep?)?
    /// Превью последнего действия — у каждой полосы, и одиночное действие
    /// тоже полосой. Пока ход идёт, высота пузыря не меняется: ни полоса не
    /// появляется вместо строки, ни превью не пропадает из-под полосы, когда
    /// приходит ответ. Лента привязана к низу, и любое изменение высоты
    /// двигает её — вот откуда «шатается вверх-вниз» (владелец 25.10.2026).
    var showsActionPreview = false
    /// Показать строки подряд, без полосы «Действия»: так работа выглядит
    /// внутри своей шторки, где сворачивать уже нечего (владелец 10.11.2026).
    var ungrouped = false
    /// Строка ленты, в которой стоит этот список: к ней привязаны ключи раскрытия.
    var expansionRow: String = ""
    /// Хранилище раскрытий комнаты. nil — раскрытие живёт в самой вью (шторка
    /// «Работа»): сразу после открытия закрывать нечего, а пересборки строки
    /// там нет.
    var expansion: RoleFeedExpansion? = nil
    /// Своё хранилище — там, где снаружи его нет (шторка «Работа»,
    /// предпросмотры): вью живёт, пока её не пересоберут, раскрытие не теряется.
    @StateObject private var ownExpansion = RoleFeedExpansion()
    @State private var detail: RoleLiveDetail?
    @AppStorage(RoleWorkDetailLevel.storageKey) private var detailLevel = RoleWorkDetailLevel.standard

    var body: some View {
        // Подписка на хранилище — во вложенной вью, а не здесь: `@ObservedObject`
        // нельзя объявить на необязательном свойстве, а без подписки нажатие на
        // полосу «Действия» меняло только таблицу ключей. Строка ленты живёт
        // вне дерева SwiftUI (`ChatFeedVirtualList` собирает её в
        // `cellForRowAt`), поэтому сама она не перерисовывалась — блок не
        // раскрывался, у законченного хода вовсе (критик 11.11.2026).
        RoleLiveItemsContent(items: items, textColor: textColor, fade: fade,
                             isStreaming: isStreaming, stepDetailLoader: stepDetailLoader,
                             showsActionPreview: showsActionPreview, ungrouped: ungrouped,
                             expansionRow: expansionRow, store: expansion ?? ownExpansion,
                             detail: $detail, detailLevel: detailLevel)
    }
}

/// Содержимое списка элементов хода — уже подписанное на хранилище раскрытий.
/// Хранилище приходит сюда готовым объектом, поэтому изменение `expandedKeys`
/// инвалидирует именно эту вью, и полоса «Действия» раскрывается сразу после
/// нажатия, без внешних обновлений ленты.
private struct RoleLiveItemsContent: View {
    let items: [RoleChatLiveItem]
    var textColor: Color = .tfText
    var fade: RoleTextFade?
    var isStreaming = false
    var stepDetailLoader: ((String) async -> RoleChatLiveStep?)?
    var showsActionPreview = false
    var ungrouped = false
    var expansionRow = ""
    @ObservedObject var store: RoleFeedExpansion
    @Binding var detail: RoleLiveDetail?
    var detailLevel: RoleWorkDetailLevel

    var body: some View {
        let visible = detailLevel.visible(items)
        let segments = RoleLiveSegment.split(visible,
                                             grouping: !ungrouped && detailLevel == .standard,
                                             groupsSingleAction: showsActionPreview)
        // Идентичность куска — по содержимому (см. `RoleLiveSegment.identities`):
        // по номеру строки пересоздавались от прихода текста в середину хода.
        let identities = RoleLiveSegment.identities(segments)
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            ForEach(Array(zip(identities, segments)), id: \.0) { identity, segment in
                switch segment {
                case .single(let item):
                    itemView(item)
                case .actions(let group):
                    // «Стандарт» (владелец 20.10.2026): подряд идущие шаги и
                    // размышления — одной строкой, тап раскрывает весь список.
                    RoleActionGroup(items: group, isLive: isStreaming && identity == identities.last,
                                    showsPreview: showsActionPreview,
                                    isExpanded: isGroupExpanded(identity),
                                    onToggle: { toggleGroup(identity) }) { item in
                        itemView(item)
                    }
                }
            }
        }
        .tfSheet(item: $detail) { detail in
            RoleLiveDetailSheet(detail: detail)
        }
        .roleTranslationRequests(finishedTexts)
    }

    /// Раскрыта ли группа действий — по ключу строки ленты и группы, а не по
    /// номеру сегмента в списке.
    private func isGroupExpanded(_ identity: String) -> Bool {
        store.isExpanded(RoleFeedExpansionKey.actions(row: expansionRow, group: identity))
    }

    private func toggleGroup(_ identity: String) {
        store.toggle(RoleFeedExpansionKey.actions(row: expansionRow, group: identity))
    }

    @ViewBuilder
    private func itemView(_ item: RoleChatLiveItem) -> some View {
        let expanded = detailLevel == .detailed
        Group {
            switch item {
            case .text(let text):
                // Показ перевода (владелец 20.10.2026, вернули 08.11.2026:
                // рефакторинг 07.11 выкинул `display`, и кнопка переключала
                // только флаг). Готовые куски — переводом, остальное — как есть.
                let shown = RoleTranslator.shared.display(text)
                RoleReplyMarkdown(text: shown, color: textColor, fade: fade, isStreaming: isStreaming,
                                  prepared: shown == text ? ChatRichContent.liveSegments(shown: text) : nil)
            case .step(let step):
                let hasDetail = !(step.detail ?? "").isEmpty
                Button { openStep(step) } label: {
                    VStack(alignment: .leading, spacing: TFSpacing.xs) {
                        RoleLiveStepRow(step: step, showsDetail: !(expanded && hasDetail))
                        if expanded, hasDetail, let text = step.detail {
                            // «Подробно»: команда или путь целиком, окошком с кодом.
                            Text(text)
                                .font(.tfChat(.mono, design: .monospaced))
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

    /// Раскрыть шаг.
    ///
    /// Тела вызова и ответа в истории не присылаются — телефон достанет их
    /// по этому шагу, когда владелец его раскроет (29.10.2026). Если тела
    /// уже на месте (старый сервер, идущий ход) — открываем сразу, без сети.
    private func openStep(_ step: RoleChatLiveStep) {
        let hasBodies = (step.args?.isEmpty == false) || (step.output?.isEmpty == false)
        guard !hasBodies, step.hasArgs || step.hasOutput, let loader = stepDetailLoader else {
            detail = .step(step)
            return
        }
        Task {
            if let loaded = await loader(step.id) {
                detail = .step(loaded)
            } else {
                detail = .step(step)
            }
        }
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
    /// Ответ закрыт остановкой: подпись «Ответ получен» была бы неправдой
    /// (владелец 30.10.2026 — ход прерван его же уточнением).
    var isStopped = false
    var pacesText = false
    var startsWithSnapshot = false
    /// Строка ленты и раскрытия комнаты: передаются в список действий, чтобы
    /// раскрытая пачка не сворачивалась при пересборке строки.
    var expansionRow: String = ""
    var expansion: RoleFeedExpansion? = nil
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
                    .tfChatText(.meta)
                    .foregroundStyle(Color.tfSub)
            }
            if !(pacesText ? visibleItems : turn.items).isEmpty {
                RoleLiveItemsList(items: pacesText ? visibleItems : turn.items,
                                  fade: pacesText && !reduceMotion ? fade : nil,
                                  isStreaming: !isComplete,
                                  showsActionPreview: true,
                                  expansionRow: expansionRow,
                                  expansion: expansion)
            }
            // Сервер до 30.09.2026 шлёт только признак «думает» без текста.
            if turn.thinking != nil && turn.runningThinking == nil && detailLevel != .minimal {
                RoleThinkingLiveRow(thinking: nil)
            }
            if isComplete {
                Text(footer(now: completedAt ?? .now))
                    .tfChatText(.meta)
                    .foregroundStyle(Color.tfDim)
            } else {
                // Тикающая подпись пишется прямо в UILabel: `TimelineView`
                // пересобирал поддерево каждый тик и дёргал ленту
                // (владелец 10.11.2026).
                ChatTickingText(format: { footer(now: $0) }, isLive: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
            guard pacesText else {
                if !Task.isCancelled && isComplete && !completionReported {
                    completionReported = true
                    onPlaybackComplete()
                }
                return
            }
            let diagnosticID = driver.isAnimating(now: .now) ? AppDiagnostics.shared.begin(.reply) : nil
            defer { if let diagnosticID { AppDiagnostics.shared.end(diagnosticID) } }
            // Часы работают только до опустошения очереди и проявления хвоста.
            // Журнал телефона: подвисание (такт пришёл позже 250 мс) и ход
            // печати раз в 2 с (владелец 07.11.2026: «сначала плавно, потом
            // завтыкало, зависло и пук»).
            var lastBeat = Date()
            var lastReport = Date()
            var maxGap = 0.0
            var hitches = 0
            while !Task.isCancelled && driver.isAnimating(now: .now) {
                do { try await Task.sleep(for: RoleLiveFrame.pacing) } catch { break }
                let beat = Date()
                let gap = beat.timeIntervalSince(lastBeat)
                lastBeat = beat
                maxGap = max(maxGap, gap)
                if gap > 0.05 { hitches += 1 }
                if beat.timeIntervalSince(lastReport) > 2 {
                    lastReport = beat
                    let shown = driver.pacer.visibleCharacters.reduce(0, +)
                    ClientLog.shared.add("bubble:tick turn=\(turn.playbackID) max_gap_ms=\(Int(maxGap * 1000)) hitches50=\(hitches) shown=\(shown) pending=\(driver.pacer.pendingCharacters) rate=\(Int(driver.pacer.rate)) items=\(visibleItems.count) complete=\(isComplete)")
                    maxGap = 0
                    hitches = 0
                }
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
        driver.pacer.ingest(detailLevel.visible(items), isFinal: isComplete)
        if isComplete {
            completionReported = false
            driver.pacer.finish()
        }
        if !seeded {
            seeded = true
            ClientLog.shared.add("bubble:seed turn=\(turn.playbackID) snapshot=\(startsWithSnapshot) complete=\(isComplete) pending=\(driver.pacer.pendingCharacters)")
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
        RoleWorkFooter.text(state: isComplete ? (isStopped ? "Остановлено" : "Ответ получен") : "Работает",
                            startedAt: turn.startDate,
                            steps: turn.items.filter(\.isStep).count,
                            now: now)
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
                        .tfTypeFont(size: 12, weight: .medium)
                        .foregroundStyle(Color.tfSub)
                        .symbolEffect(.pulse, options: .repeating)
                        .frame(width: 16)
                    RoleShimmerText(text: "Думает…")
                    if hasText {
                        Image(systemName: "chevron.right")
                            .tfTypeFont(size: 10, weight: .semibold)
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

/// Частота кадров покадровых механизмов чата: часы живого хода и мыслей,
/// блик «Думает…», проявление по буквам. 30 кадров/с вместо 60 (владелец
/// 06.11.2026: «в чате крутятся пять покадровых механизмов… лечится
/// настройкой»). Темп текста считается по прошедшему времени, не по числу
/// тиков, поэтому скорость появления текста от частоты не зависит.
enum RoleLiveFrame {
    static let seconds: Double = 1.0 / 30
    static let interval: Duration = .milliseconds(33)
    /// Такт выпуска текста. Чаще, чем проявление: за 16 мс на 240 зн/с
    /// приходится 4 знака, и текст идёт по буквам, а не пачками по слову.
    static let pacing: Duration = .milliseconds(16)
}

/// «Думает…» с бликом, пробегающим по буквам — как индикатор в Claude.
struct RoleShimmerText: View {
    let text: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let label = Text(text).tfChatText(.meta)
        if reduceMotion {
            label.foregroundStyle(Color.tfSub)
        } else {
            TimelineView(.animation(minimumInterval: RoleLiveFrame.seconds)) { context in
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

/// Окошко с идущими мыслями: показывает полученный текст сразу.
struct RoleThinkingWindow: View {
    let text: String
    @State private var contentHeight: CGFloat = 0

    private static let maxHeight: CGFloat = 132

    var body: some View {
        HStack(alignment: .top, spacing: TFSpacing.sm) {
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.tfStroke)
                .frame(width: 2)
            ScrollView {
                // `код` и **жирное** — ярче приглушённого текста, чтобы главное
                // сразу бросалось в глаза (владелец 14.10.2026, по образцу).
                RoleReplyMarkdown(text: text, color: .tfSub,
                                  serverBlocks: ChatLiveBlockRegistry.shared.blocks(for: text)?.map(\.block),
                                  textGroup: .thinking)
                    .italic()
                    .foregroundStyle(Color.tfSub)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
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
    }


}

/// Законченное размышление строкой: «Размышления · 12 с», тап — шторка.
struct RoleThinkingDoneRow: View {
    let thinking: RoleChatThinking

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: TFSpacing.sm) {
            Image(systemName: "brain")
                .tfTypeFont(size: 12, weight: .medium)
                .foregroundStyle(Color.tfDim)
                .frame(width: 16)
            Text("Размышления")
                .tfChatText(.meta)
                .foregroundStyle(Color.tfSub)
            if let seconds = thinking.durationSeconds {
                Text(RoleLiveFormat.duration(seconds: seconds))
                    .tfChatText(.meta)
                    .foregroundStyle(Color.tfDim)
            }
            Image(systemName: "chevron.right")
                .tfTypeFont(size: 10, weight: .semibold)
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
                            .tfChatText(.meta)
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
            // Перевод здесь тоже: шторка — то место, где размышления читают.
            // Своего сеанса у шторки нет (20.10.2026: сеанс в шторке ронял
            // приложение), куски уходят в общий сеанс приложения.
            let shown = RoleTranslator.shared.display(thinking.text)
            RoleReplyMarkdown(text: shown, color: .tfText,
                              serverBlocks: shown == thinking.text
                                  ? ChatLiveBlockRegistry.shared.blocks(for: thinking.text)?.map(\.block)
                                  : nil,
                              textGroup: .thinking)
                .italic()
                .textSelection(.enabled)
                .roleTranslationRequests([thinking.text])
        case .step(let step):
            VStack(alignment: .leading, spacing: TFSpacing.md) {
                if let detail = step.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.tfChat(.mono, design: .monospaced))
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
                        .tfChatText(.meta)
                        .foregroundStyle(Color.tfSub)
                }
            }
        }
    }
}

private func ioSection(_ title: String, _ text: String, id: String) -> some View {
    VStack(alignment: .leading, spacing: TFSpacing.xs) {
        Text(title)
            .tfChatText(.meta)
            .foregroundStyle(Color.tfSub)
        Text(text)
            .font(.tfChat(.mono, design: .monospaced))
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
    /// Готовое сообщение проявляется ВПЕРЁД от начала: буквы появляются по
    /// порядку, как при печати (владелец 17.10.2026: «текст появляется очень
    /// плавно, не сразу, как будто построчно печатается»). У хвоста идущего
    /// ответа проявление обратное: текст уже напечатан, гаснет только свежий
    /// хвост.
    var revealsForward = false
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
///
/// Это история ОДНОГО текста. У готового сообщения текстов много (заголовки,
/// пункты, подписи), и у каждого своя — см. `RoleTextRevealHistory`.
final class RoleTextRevealTimeline {
    /// Времена появления ещё не проявившихся глифов (хвост).
    private var appearanceTimes: [Date] = []
    private var animated = true

    /// Число глифов, проявившихся полностью (или не анимировались вовсе).
    private(set) var revealedUpTo = 0

    /// Сколько глифов стоит перед этим текстом в сообщении. В режиме вперёд
    /// текст проявляется после тех, что нарисованы раньше, — сообщение
    /// «печатается» сверху вниз.
    var offset = 0

    /// Откуда считается появление букв этого текста.
    var base: Date = .distantPast

    func record(count: Int, now: Date, rate: Double, animated: Bool, start: Date, forward: Bool) {
        self.animated = animated
        guard count > 0 else { revealedUpTo = 0; appearanceTimes = []; return }
        if !animated {
            // Не анимируем: всё видно сразу, хвоста нет.
            revealedUpTo = count
            appearanceTimes = []
            return
        }
        // При укорочении/переносе сохраняем уже видимое начало и времена
        // оставшегося хвоста. Удаление с начала хвоста и уменьшение префикса
        // заново гасило показанные буквы; при пустом хвосте префикс мог даже
        // оказаться длиннее всего текста.
        revealedUpTo = min(revealedUpTo, count)
        let tailCapacity = count - revealedUpTo
        if appearanceTimes.count > tailCapacity {
            appearanceTimes.removeLast(appearanceTimes.count - tailCapacity)
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
            for step in 0..<pending {
                let index = revealedUpTo + appearanceTimes.count + step
                let time = forward
                    // Готовое сообщение: буква появляется в своё время, вперёд
                    // от начала проявления, — текст печатается по порядку.
                    ? base.addingTimeInterval(Double(offset + index) / max(rate, 1))
                    // Хвост идущего ответа: текст уже напечатан, свежие буквы
                    // «догоняют» темп потока.
                    : now.addingTimeInterval(-Double(pending - step - 1) / max(rate, 1))
                appearanceTimes.append(time)
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

/// Проявление текста в сообщении.
///
/// У каждого независимого текста — своя история глифов. Раньше история была
/// одна на всё дерево готового сообщения, и независимые `Text` (заголовки,
/// пункты, подписи отчёта) делили один хвост: длина и индексы следующего
/// текста брались из предыдущего, из-за чего буквы пропали и ответ выглядел
/// разбитым на узкие колонки (владелец 31.10.2026).
///
/// Режимы:
/// - хвост (`forward: false`) — идущий ответ: текст один и растёт;
/// - вперёд (`forward: true`) — готовое сообщение: буквы появляются по
///   порядку, тексты идут друг за другом сверху вниз.
final class RoleTextRevealHistory {
    /// Хвост идущего текста: одна история на весь растущий текст.
    private var tail = RoleTextRevealTimeline()
    /// Готовое сообщение: своя история на каждый независимый текст.
    /// Ключ — порядковый слот отрисовки в кадре (0, 1, 2…), а не длина:
    /// абзацы одной длины иначе делили один хвост и проявлялись синхронно
    /// (владелец 03.11.2026).
    private var perText: [Int: RoleTextRevealTimeline] = [:]
    /// Текст, который рисуется прямо сейчас (последний записанный).
    private var current = RoleTextRevealTimeline()
    /// Кадр, для которого считается накопленный счётчик глифов.
    private var frameNow: Date?
    /// Сколько глифов нарисовано раньше в этом кадре.
    private var frameOffset = 0
    /// Какой по счёту независимый текст рисуется в этом кадре.
    private var frameSlot = 0
    /// Начало текущего проявления — сменилось, значит сообщение новое.
    private var start: Date = .distantPast

    /// Записать состояние текста из `count` глифов.
    ///
    /// `start` — начало проявления (для режима вперёд); `forward` — проявлять
    /// вперёд (готовое сообщение) или гасить только свежий хвост.
    func record(count: Int, now: Date, rate: Double, animated: Bool,
                start: Date? = nil, forward: Bool = true) {
        let base = start ?? now
        guard forward else {
            // Хвост идущего текста: текст один и растёт кадрами.
            frameNow = nil
            frameOffset = 0
            frameSlot = 0
            current = tail
            tail.record(count: count, now: now, rate: rate, animated: animated, start: base, forward: false)
            return
        }
        if self.start != base {
            // Новое проявление — прежние истории не годятся.
            self.start = base
            perText.removeAll()
            frameNow = nil
            frameOffset = 0
            frameSlot = 0
        }
        if frameNow != now {
            // Новый кадр: слоты и счётчик глифов перед текстом — с нуля.
            // Уже созданные слоты помнят свой offset от первого появления.
            frameNow = now
            frameOffset = 0
            frameSlot = 0
        }
        let slot = frameSlot
        frameSlot += 1
        let timeline: RoleTextRevealTimeline
        if let existing = perText[slot] {
            timeline = existing
        } else {
            let created = RoleTextRevealTimeline()
            created.offset = frameOffset
            // Всегда от начала проявления сообщения: поздний блок с верным
            // offset уже «допечатает» прошедшее и встанет в общую очередь,
            // а не откроет параллельный fade с текущего кадра.
            created.base = base
            perText[slot] = created
            timeline = created
        }
        frameOffset += count
        current = timeline
        timeline.record(count: count, now: now, rate: rate, animated: animated,
                       start: timeline.base, forward: true)
    }

    /// Число глифов, проявившихся полностью, у текста, который рисуется сейчас.
    var revealedUpTo: Int { current.revealedUpTo }

    /// Прозрачность глифа по ЕГО индексу в тексте, который рисуется сейчас.
    func opacity(at index: Int, now: Date) -> Double {
        current.opacity(at: index, now: now)
    }
}

struct RoleRevealRenderer: TextRenderer {
    var fade: RoleTextFade
    var now: Date
    var history: RoleTextRevealHistory

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        var total = 0
        for line in layout { for run in line { total += run.count } }
        history.record(count: total, now: now, rate: fade.rate, animated: fade.isAnimating,
                       start: fade.lastRevealAt, forward: fade.revealsForward)
        var index = 0
        for line in layout {
            var lineCount = 0
            for run in line { lineCount += run.count }
            // Строка целиком проявилась — рисуем одним вызовом.
            if index + lineCount <= history.revealedUpTo {
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
        TimelineView(.animation(minimumInterval: RoleLiveFrame.seconds, paused: !fade.isAnimating)) { context in
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
