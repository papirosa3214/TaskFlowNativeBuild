import SwiftUI

// ═══ НОВАЯ ВЕРСИЯ ЧАТА: «Сессии (бета)» — живой ход ═══
// Отдельная копия видов живого хода ТОЛЬКО для сессий (`OwnerSessionScreen`).
// Старая комната роли рисует ход своим файлом
// `Sources/Features/Roles/RoleLiveTurnView.swift` — правки сессий туда не
// вносить, а правки ролей — сюда (владелец 13.11.2026: «тупо физический
// файлик, чтоб уже никто не мог путаться»). Общими остались только модели и
// механика проявления текста (`RoleTextFade`, `RoleLiveBlocks` и т.п.).

struct SessionLiveStepRow: View {
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

struct SessionLiveItemsList: View {
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
    @State private var detail: SessionLiveDetail?
    /// Область живой разметки: у сессии — свой ход, у остальных вызовов — nil.
    /// Без неё два ответа с одинаковым текстом брали чужие блоки.
    var scope: String? = nil
    @AppStorage(RoleWorkDetailLevel.storageKey) private var detailLevel = RoleWorkDetailLevel.standard

    var body: some View {
        // Подписка на хранилище — во вложенной вью, а не здесь: `@ObservedObject`
        // нельзя объявить на необязательном свойстве, а без подписки нажатие на
        // полосу «Действия» меняло только таблицу ключей. Строка ленты живёт
        // вне дерева SwiftUI (`ChatFeedVirtualList` собирает её в
        // `cellForRowAt`), поэтому сама она не перерисовывалась — блок не
        // раскрывался, у законченного хода вовсе (критик 11.11.2026).
        SessionLiveItemsContent(items: items, textColor: textColor, fade: fade,
                             isStreaming: isStreaming, stepDetailLoader: stepDetailLoader,
                             showsActionPreview: showsActionPreview, ungrouped: ungrouped,
                             expansionRow: expansionRow, store: expansion ?? ownExpansion,
                             detail: $detail, detailLevel: detailLevel, scope: scope)
    }
}

/// Содержимое списка элементов хода — уже подписанное на хранилище раскрытий.
/// Хранилище приходит сюда готовым объектом, поэтому изменение `expandedKeys`
/// инвалидирует именно эту вью, и полоса «Действия» раскрывается сразу после
/// нажатия, без внешних обновлений ленты.

private struct SessionLiveItemsContent: View {
    let items: [RoleChatLiveItem]
    var textColor: Color = .tfText
    var fade: RoleTextFade?
    var isStreaming = false
    var stepDetailLoader: ((String) async -> RoleChatLiveStep?)?
    var showsActionPreview = false
    var ungrouped = false
    var expansionRow = ""
    @ObservedObject var store: RoleFeedExpansion
    @Binding var detail: SessionLiveDetail?
    var detailLevel: RoleWorkDetailLevel
    /// Область реестра блоков этого хода (nil — общая, как у ролей и истории).
    var scope: String? = nil

    var body: some View {
        let visible = detailLevel.visible(items)
        // Вызов роли-субагента — отдельной отметкой, а не внутри «Действия»
        // (владелец 13.11.2026: «понимать, какой вызов сделался»).
        let segments = SessionRoleCall.separating(RoleLiveSegment.split(visible,
                                             grouping: !ungrouped && detailLevel == .standard,
                                             groupsSingleAction: showsActionPreview))
        // Идентичность куска — по содержимому (см. `RoleLiveSegment.identities`):
        // по номеру строки пересоздавались от прихода текста в середину хода.
        let identities = RoleLiveSegment.identities(segments)
        VStack(alignment: .leading, spacing: TFSpacing.xs) { // строки хода вдвое плотнее (владелец 13.11.2026)
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
                                    onToggle: { toggleGroup(identity) },
                                    // Три точки в 3D вместо трёх плиток — только пока действие идёт;
                                    // закончилось — без значка, одно слово «Действия» (владелец 13.11.2026).
                                    leadingIcon: isStreaming && identity == identities.last
                                        ? AnyView(SessionDotsGlyph(isAnimating: true)
                                            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 })
                                        : AnyView(EmptyView()),
                                    tightPreview: true) { item in
                        itemView(item)
                    }
                }
            }
        }
        .tfSheet(item: $detail) { detail in
            SessionLiveDetailSheet(detail: detail, scope: scope)
        }
        .roleTranslationRequests(finishedTexts)
        // Каждый вставший блок — лёгкий тык (владелец 11.11.2026:
        // «тык-тык-тык, аккуратненько так оно вставало»).
        .sensoryFeedback(.impact(weight: .light, intensity: 0.55), trigger: isStreaming ? settledBlockCount : 0) { old, new in
            isStreaming && new > old
        }
    }

    /// Сколько блоков хода уже встало: законченные абзацы текста и пункты.
    private var settledBlockCount: Int {
        items.enumerated().reduce(0) { total, entry in
            guard case .text(let text) = entry.element else { return total + 1 }
            let shown = entry.offset == items.count - 1 ? RoleLiveBlocks.settled(text) : text
            return total + RoleLiveBlocks.count(shown)
        }
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
            case .text(let rawText):
                // Идущий ответ встаёт целыми блоками (абзацами): хвост,
                // который ещё пишется, не показывается до конца абзаца
                // (владелец 11.11.2026, вместо пейсера по буквам).
                // Тонкий клиент (владелец 13.11.2026): текст хода — ровно тот, что
                // разметил сервер, и рисуется его разметкой целиком (все блоки:
                // текст, таблицы, виджеты). Поиск «одного блока по началу текста»
                // ломался на ответах из нескольких блоков и давал «Не удалось
                // получить подготовленное содержимое».
                let text = rawText
                // Показ перевода (владелец 20.10.2026, вернули 08.11.2026:
                // рефакторинг 07.11 выкинул `display`, и кнопка переключала
                // только флаг). Перевод применяет общий вид ответа.
                SessionReplyMarkdown(text: text,
                                     segments: SessionLiveReplyContent.prepared(shown: text, scope: scope),
                                     color: textColor, fade: fade, isStreaming: isStreaming)
            case .step(let step) where SessionOwnerQuestion.question(in: step) != nil:
                // Вопрос Помощника владельцу — карточкой с вариантами (сервер 4b774d50).
                // Ответ меняет запись вопроса, ход продолжается с ним.
                RoleQuestionCard(question: SessionOwnerQuestion.question(in: step)!) { answers, note in
                    try await APIClient().answerQuestion(questionID: SessionOwnerQuestion.question(in: step)!.id,
                                                         answers: answers, note: note)
                }
            case .step(let step) where SessionRoleCall(step) != nil:
                Button { openStep(step) } label: {
                    SessionRoleCallRow(call: SessionRoleCall(step)!, status: step.status)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Показать ответ роли")
            case .step(let step):
                let hasDetail = !(step.detail ?? "").isEmpty
                Button { openStep(step) } label: {
                    VStack(alignment: .leading, spacing: TFSpacing.xs) {
                        SessionLiveStepRow(step: step, showsDetail: !(expanded && hasDetail))
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
                    // Бегущее «Думает…» из ленты убрано (владелец 11.11.2026,
                    // индикатор работы — в пилюле над полем ввода); остаётся
                    // только строка с текстом размышления, если он пришёл.
                    if !thinking.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        SessionThinkingLiveRow(thinking: thinking, startsExpanded: expanded, scope: scope)
                    }
                } else {
                    Button { detail = .thinking(thinking) } label: {
                        SessionThinkingDoneRow(thinking: thinking)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Показать размышления")
                    if expanded, !thinking.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        SessionThinkingWindow(text: thinking.text, scope: scope)
                    }
                }
            }
        }
        .modifier(SessionItemAppearance(animate: fade?.isAnimating == true && Self.isAction(item)))
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


private struct SessionItemAppearance: ViewModifier {
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

struct SessionLiveTurnBubble: View {
    let turn: RoleChatLiveTurn
    let showsName: Bool
    /// Область реестра блоков: сессия + начало хода. Регистрация и чтение
    /// берут одну и ту же строку `SessionLiveTurn.scope`, поэтому разметка
    /// одного хода не видна другому (владелец 14.11.2026).
    var scope: String? = nil
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
                SessionLiveItemsList(items: pacesText ? visibleItems : turn.items,
                                  fade: pacesText && !reduceMotion ? fade : nil,
                                  isStreaming: !isComplete,
                                  showsActionPreview: true,
                                  expansionRow: expansionRow,
                                  expansion: expansion,
                                  scope: scope)
            }
            // Сервер до 30.09.2026 шлёт только признак «думает» без текста.
            // С 11.11.2026 индикатор без текста из ленты убран — он в пилюле.
            // Пока ход идёт, подписи «Работает · 0:52» в ленте нет: время и
            // «Стоп» — в пилюле над полем ввода (владелец 11.11.2026: «три
            // надписи работает»). Итог хода остаётся.
            if isComplete {
                Text(footer(now: completedAt ?? .now))
                    .tfChatText(.meta)
                    .foregroundStyle(Color.tfDim)
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
            // Часы оборвались (задачу отменили), а ход уже закончен — текст
            // показывается целиком, а не застревает на «things_t» и «Thi»
            // (владелец 11.11.2026: «не до конца отобразился текст»).
            if isComplete && driver.pacer.hasPendingText {
                ClientLog.shared.add("bubble:flush-after-stop turn=\(turn.playbackID) pending=\(driver.pacer.pendingCharacters) cancelled=\(Task.isCancelled)")
                driver.pacer.flush()
                publish()
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
        driver.pacer.ingest(detailLevel.visible(items), isFinal: isComplete, scope: scope)
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

struct SessionThinkingLiveRow: View {
    /// Область живого хода — чтобы окно размышлений взяло блоки своего хода.
    var scope: String? = nil
    /// nil — сервер прислал только признак «думает».
    let thinking: RoleChatThinking?
    @State private var isExpanded: Bool

    /// `startsExpanded` — уровень «Подробно»: окошко с мыслями открыто сразу.
    init(thinking: RoleChatThinking?, startsExpanded: Bool = false, scope: String? = nil) {
        self.scope = scope
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
                SessionThinkingWindow(text: thinking.text, scope: scope)
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

struct SessionThinkingWindow: View {
    let text: String
    /// Область реестра блоков: размышление ищет разметку только своего хода.
    var scope: String? = nil
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
                                  serverBlocks: ChatLiveBlockRegistry.shared.blocks(for: text, scope: scope)?.map(\.block),
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

struct SessionThinkingDoneRow: View {
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

enum SessionLiveDetail: Identifiable {
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

struct SessionLiveDetailSheet: View {
    let detail: SessionLiveDetail
    /// Область живого хода: шторка берёт разметку своего хода, а не соседнего.
    var scope: String? = nil
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
                                  ? ChatLiveBlockRegistry.shared.blocks(for: thinking.text, scope: scope)?.map(\.block)
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


/// Вызов роли-субагента из сессии (`taskflow_spawn_session` с `role`,
/// владелец 13.11.2026: «субагенты — это и есть роли»).
struct SessionRoleCall: Equatable {
    let roleKey: String
    let title: String
    let task: String

    /// Названия ролей — как на сервере (`roleRouting.ts`).
    static let titles: [String: String] = [
        "researcher": "Исследователь", "analyst": "Аналитик", "critic_verifier": "Критик-проверяющий",
        "architect": "Архитектор", "builder": "Разработчик", "qa": "Лайф-тестировщик", "designer": "Дизайнер",
    ]

    init?(_ step: RoleChatLiveStep) {
        guard step.tool == "taskflow_spawn_session",
              let data = step.args?.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let role = (object["role"] as? String)?.trimmingCharacters(in: .whitespaces), !role.isEmpty else { return nil }
        roleKey = role
        title = Self.titles[role] ?? role
        task = (object["task"] as? String) ?? ""
    }

    /// Вызовы ролей выходят из полосы «Действия» отдельными строками.
    static func separating(_ segments: [RoleLiveSegment]) -> [RoleLiveSegment] {
        var out: [RoleLiveSegment] = []
        for segment in segments {
            guard case .actions(let group) = segment,
                  group.contains(where: { if case .step(let s) = $0 { return SessionRoleCall(s) != nil } else { return false } }) else {
                out.append(segment)
                continue
            }
            var run: [RoleChatLiveItem] = []
            func flush() {
                if run.count > 1 { out.append(.actions(run)) } else if let one = run.first { out.append(.single(one)) }
                run = []
            }
            for item in group {
                if case .step(let s) = item, SessionRoleCall(s) != nil {
                    flush()
                    out.append(.single(item))
                } else {
                    run.append(item)
                }
            }
            flush()
        }
        return out
    }

    /// Работающие роли — в пилюлю над полем ввода, как в чатах ролей.
    static func running(in items: [RoleChatLiveItem]) -> [ChatComposerStatus.Running] {
        items.compactMap { item in
            guard case .step(let step) = item, step.status == .running, let call = SessionRoleCall(step) else { return nil }
            return ChatComposerStatus.Running(chatID: step.id, roleID: call.roleKey, name: call.title,
                                              title: call.task, state: .working)
        }
    }
}

/// Отметка вызова роли в ленте: «→ Исследователь», поручение одной строкой,
/// идёт или готово.
private struct SessionRoleCallRow: View {
    let call: SessionRoleCall
    let status: RoleChatLiveStep.Status

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: TFSpacing.sm) {
            Image(systemName: "arrow.turn.down.right")
                .tfTypeFont(size: 12, weight: .medium)
                .foregroundStyle(Color.tfDim)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: TFSpacing.xs) {
                    Text(call.title).tfText(.meta).foregroundStyle(Color.tfText)
                    Text(statusText).tfText(.caption).foregroundStyle(Color.tfDim)
                }
                if !call.task.isEmpty {
                    Text(call.task).tfText(.caption).foregroundStyle(Color.tfSub).lineLimit(2)
                }
            }
        }
    }

    private var statusText: String {
        switch status {
        case .running: "работает"
        case .error: "не ответила"
        default: "ответила"
        }
    }
}

/// Разметка куска живого ответа сессии — та же подготовленная, что в комнате
/// роли (`RoleLiveTurnView`): ищем по началу текста и обрезаем прозу по
/// проявленной доле. Поиск по точному тексту реплики находил только ответ из
/// одного блока, а ответ из нескольких блоков вставал заглушкой «Не удалось
/// получить подготовленное содержимое» (владелец 14.11.2026).
/// Уточнение 14.11.2026: сначала берём ЦЕЛУЮ запись по тексту (все блоки
/// ответа), иначе — один блок по началу (хвост, который ещё пишется). Одна и
/// та же функция обслуживает живой ход и историю.
/// Текст и блоки берутся у сервера (`display_text`/`text_blocks` в снимке,
/// `text`/`blocks` в `message_end`): телефон не раскладывает текст заново,
/// поэтому одна и та же реплика в живом ходе и после перезахода выглядит
/// одинаково.
enum SessionLiveReplyContent {
    /// Целая реплика: все блоки, как их прислал сервер (текст, таблицы,
    /// виджеты…).
    static func prepared(text: String, blocks: [ChatServerBlock]?) -> [ChatRichSegment]? {
        guard let blocks, !blocks.isEmpty else { return nil }
        return ChatRichContent.segments(fromServer: blocks, key: ChatRichContent.replyCacheKey(blocks))
    }

    /// Живой ход и история: одна и та же разметка из серверных блоков.
    static func prepared(shown: String, scope: String?) -> [ChatRichSegment]? {
        guard let scope else { return nil }
        return ChatRichContent.replySegments(shown: shown, scope: scope)
    }
}

/// Ответ сессии на экране — одна точка отрисовки для живого хода и истории.
struct SessionReplyMarkdown: View {
    let text: String
    /// Разметка сервера для этого текста (nil — сервер её не прислал).
    var segments: [ChatRichSegment]? = nil
    var color: Color = .tfChatText
    var fade: RoleTextFade? = nil
    var isStreaming: Bool = false

    var body: some View {
        // Разметки нет — показываем сам текст (с переводом, если он включён),
        // а не заглушку «Не удалось получить подготовленное содержимое».
        let shown = segments == nil ? RoleTranslator.shared.display(text) : text
        RoleReplyMarkdown(text: shown, color: color, fade: fade, isStreaming: isStreaming,
                          prepared: segments ?? Self.plainText(shown), usesChatTables: true)
    }

    private static func plainText(_ text: String) -> [ChatRichSegment] {
        [.document([NoteBlock(kind: .paragraph, runs: [RichRun(text: text)])], chars: text.count)]
    }
}

/// Вопрос Помощника владельцу в живом ходе: сервер кладёт карточку в
/// промежуточный результат инструмента `taskflow_ask_user_question`
/// (`{"question": …}`), телефон её только показывает.
enum SessionOwnerQuestion {
    static func question(in step: RoleChatLiveStep) -> ChatQuestion? {
        guard step.tool == "taskflow_ask_user_question", step.status == .running,
              let data = step.output?.data(using: .utf8) else { return nil }
        struct Wrapper: Decodable { let question: ChatQuestion }
        return try? JSONDecoder().decode(Wrapper.self, from: data).question
    }
}
