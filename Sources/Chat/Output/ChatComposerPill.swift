import SwiftUI

/// Одна компактная пилюля над полем ввода (владелец 11.11.2026, как в T3
/// Code): «☑ 2/5 · 2 роли работают · 1 отложено ▾». Показывает только
/// непустые части; всё пусто — пилюли нет. Нажатие раскрывает панель вверх:
/// чек-лист плана, работающие исполнители (тап — их чат) и отложенные
/// сообщения владельца («Отправить сейчас» / «Убрать»). Пилюля живёт внутри
/// нижней панели ввода, поэтому лента под ней не двигается.
struct ChatComposerPill: View {
    let plans: [ChatWorkPlan]
    let members: [RoleChatMember]
    let status: ChatComposerStatus
    let onDeletePlan: (ChatWorkPlan) -> Void
    let onOpenChat: (String) -> Void
    let onSendNow: (ChatComposerStatus.Queued) -> Void
    let onRemove: (ChatComposerStatus.Queued) -> Void
    /// Идёт ход роли: в пилюле появляется сегмент «Стоп» (та же остановка,
    /// что кнопка в поле ввода).
    var onStop: (() -> Void)? = nil
    /// Кружок «вниз» стоит в том же ряду справа от пилюли.
    var showsScrollDown = false
    var onScrollDown: () -> Void = {}

    /// Идёт ход роли: пилюля есть всегда, с сегментом «Работает · 0:42».
    var isWorking = false
    var workStartedAt: Date? = nil

    @State private var expanded = false
    @Namespace private var glassNamespace
    @State private var showsQueued = false

    private var running: [ChatComposerStatus.Running] { status.activeRunning }
    private var planTotal: Int { plans.reduce(0) { $0 + $1.items.count } }
    private var planDone: Int { plans.reduce(0) { $0 + $1.doneCount } }
    /// Пилюля никогда не тянется: при появлении кружка «вниз» она держит
    /// свой размер, пара «пилюля + кружок» стоит по центру (владелец 11.11.2026).
    private var stretches: Bool { false }
    private var isEmpty: Bool { !isWorking && plans.isEmpty && running.isEmpty && status.queued.isEmpty }

    var body: some View {
        if isEmpty {
            // Без пилюли кружок — по центру над полем ввода, как в T3 Code
            // (владелец 11.11.2026). Кружок занимает свой ряд: висящий в
            // overlay нулевой высоты он был вне панели и не нажимался
            // (владелец 11.11.2026: «кружочек не работает»).
            if showsScrollDown {
                ChatScrollToBottomButton(action: onScrollDown)
                    .frame(maxWidth: .infinity, minHeight: TFHitTarget.min)
                    .padding(.bottom, TFSpacing.xs)
            } else {
                Color.clear.frame(height: 0)
            }
        } else {
            // Пилюля сама раскрывается в чек-лист и сворачивается обратно в
            // пилюлю — одно стекло перетекает (glassEffectID), без отдельной
            // плашки над пилюлей (владелец 11.11.2026: «пилюля должна сразу
            // раскрывать чек-лист… а не плашка, на которую надо нажать»).
            TFGlassGroup(spacing: TFSpacing.sm) {
                if expanded {
                    panel
                        .tfGlassID("pill", in: glassNamespace)
                } else {
                    // Кружок на фиксированном расстоянии от пилюли, стекло не
                    // сливается (как в T3 Code, владелец 11.11.2026).
                    HStack(spacing: TFSpacing.md) {
                        // Пилюля по центру над полем ввода (владелец 11.11.2026).
                        Spacer(minLength: 0)
                        pill
                        if showsScrollDown {
                            ChatScrollToBottomButton(action: onScrollDown, glassNamespace: glassNamespace)
                        }
                        Spacer(minLength: 0)
                    }
                    // Ряд всегда высотой кружка: пилюля не подпрыгивает от
                    // поля ввода, когда кружок появляется (владелец 11.11.2026).
                    .frame(minHeight: TFHitTarget.min)
                }
            }
            .animation(TFMotion.standard, value: expanded)
            .animation(TFMotion.standard, value: stretches)
            .animation(TFMotion.standard, value: showsScrollDown)
            .animation(TFMotion.standard, value: segmentKey)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, TFSpacing.lg)
            .padding(.bottom, TFSpacing.xs)
        }
    }

    // MARK: Пилюля

    /// Высота пилюли — ниже поля ввода (владелец 11.11.2026: «чуть поуже по высоте»).
    static let segmentHeight: CGFloat = 36

    /// Плавающая стеклянная капсула из сегментов через тонкие разделители:
    /// [люди · «Работают 2 роли»] | [Стоп] | [☑ 2/5] | [1 отложено].
    private var pill: some View {
        // Два вида пилюли (владелец 12.11.2026): полный — словами, компактный —
        // значками и цифрами. Пилюля не шире места между краями экрана:
        // показывается первый вид, который влезает, и чат не растягивается.
        ViewThatFits(in: .horizontal) {
            pillBody(compact: false)
            pillBody(compact: true)
        }
    }

    private func pillBody(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                let segments = segmentViews(compact: compact)
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    if index > 0 {
                        Rectangle().fill(Color.tfStroke).frame(width: 1, height: 16)
                    }
                    segment
                }
            }
        }
        .frame(maxWidth: stretches ? .infinity : nil, alignment: .leading)
        .voiceCapsuleSurface()
        .tfGlassID("pill", in: glassNamespace)
        .fixedSize(horizontal: !stretches, vertical: true)
        .accessibilityIdentifier("chat.composerPill")
    }

    /// Состав сегментов: при его смене пилюля плавно меняет ширину.
    private var segmentKey: [Bool] {
        [isWorking, !running.isEmpty, onStop != nil, !plans.isEmpty, !status.queued.isEmpty]
    }

    private func segmentViews(compact: Bool) -> [AnyView] {
        var views: [AnyView] = []
        if isWorking { views.append(AnyView(workingSegment(compact: compact))) }
        if !running.isEmpty {
            views.append(AnyView(segment(symbol: "person.2",
                                         text: compact ? "\(running.count)" : Self.runningText(running.count),
                                         id: "running", label: Self.runningText(running.count))))
        }
        if let onStop {
            views.append(AnyView(
                Button(action: onStop) {
                    Group {
                        if compact { Image(systemName: "stop.fill") } else { Text("Стоп") }
                    }
                    .padding(.horizontal, TFSpacing.md).frame(minHeight: Self.segmentHeight)
                    .tfText(.meta).foregroundStyle(Color.tfChatText).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Стоп")
                .accessibilityIdentifier("chat.composerPill.stop")
            ))
        }
        if !plans.isEmpty {
            views.append(AnyView(segment(symbol: planDone == planTotal ? "checkmark.square.fill" : "checklist",
                                         text: "\(planDone)/\(planTotal)", id: "plan")))
        }
        if !status.queued.isEmpty {
            views.append(AnyView(queuedSegment(compact: compact)))
        }
        return views
    }

    /// «Работает · 0:42»: значок пульсирует, таймер тикает раз в секунду
    /// только здесь — лента и остальная пилюля не перерисовываются.
    private func workingSegment(compact: Bool) -> some View {
        Button {
            withAnimation(TFMotion.standard) { expanded.toggle() }
        } label: {
            HStack(spacing: TFSpacing.xs) {
                Image(systemName: "brain")
                    .symbolEffect(.pulse, options: .repeating)
                    .accessibilityHidden(true)
                if let start = workStartedAt {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(compact ? Self.clock(from: start, to: context.date)
                                     : "Работает · \(Self.clock(from: start, to: context.date))")
                            .monospacedDigit()
                    }
                } else {
                    Text("Работает")
                }
            }
            .lineLimit(1)
            .tfText(.meta)
            .foregroundStyle(Color.tfChatText)
            .padding(.horizontal, TFSpacing.md)
            .frame(minHeight: Self.segmentHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("chat.composerPill.working")
    }

    static func clock(from start: Date, to now: Date) -> String {
        let total = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Ярлычок отложенных сообщений: значок и счётчик; тап открывает окошко
    /// с полным текстом и кнопками «Отправить сейчас» / «Убрать».
    private func queuedSegment(compact: Bool) -> some View {
        Button { showsQueued = true } label: {
            HStack(spacing: TFSpacing.xs) {
                Image(systemName: "bubble.left").accessibilityHidden(true)
                Text(compact ? "\(status.queued.count)"
                     : (status.queued.count == 1 ? "1 сообщение" : "\(status.queued.count) сообщ.")).lineLimit(1)
            }
            .tfText(.meta)
            .foregroundStyle(Color.tfChatText)
            .padding(.horizontal, TFSpacing.md)
            .frame(minHeight: Self.segmentHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Отложено сообщений: \(status.queued.count)")
        .accessibilityIdentifier("chat.composerPill.queued")
        .popover(isPresented: $showsQueued) {
            queuedSheet
                .presentationCompactAdaptation(.popover)
        }
        .onChange(of: status.queued.isEmpty) { _, empty in if empty { showsQueued = false } }
    }

    private var queuedSheet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TFSpacing.md) {
                ForEach(status.queued) { item in queuedRow(item) }
            }
            .padding(.vertical, TFSpacing.sm)
        }
        .frame(minWidth: 280, idealWidth: 320, maxHeight: 360)
    }

    /// Сегмент-кнопка: нажатие раскрывает и сворачивает панель.
    private func segment(symbol: String?, text: String, id: String, label: String? = nil) -> some View {
        Button {
            withAnimation(TFMotion.standard) { expanded.toggle() }
        } label: {
            HStack(spacing: TFSpacing.xs) {
                if let symbol { Image(systemName: symbol).accessibilityHidden(true) }
                Text(text).lineLimit(1)
            }
            .tfText(.meta)
            .foregroundStyle(Color.tfChatText)
            .padding(.horizontal, TFSpacing.md)
            .frame(minHeight: TFHitTarget.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label ?? text)
        .accessibilityValue(expanded ? "Раскрыто" : "Свёрнуто")
        .accessibilityIdentifier("chat.composerPill.\(id)")
    }

    /// «Работает 1 роль», «Работают 2 роли», «Работают 5 ролей».
    static func runningText(_ count: Int) -> String {
        let n = count % 100
        let last = count % 10
        if n < 11 || n > 14 {
            if last == 1 { return "Работает \(count) роль" }
            if (2...4).contains(last) { return "Работают \(count) роли" }
        }
        return "Работают \(count) ролей"
    }

    // MARK: Раскрытая панель

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !plans.isEmpty {
                // Чек-лист открыт сразу; нажатие на строку плана сворачивает
                // всё обратно в пилюлю.
                ChatWorkPlanRows(plans: plans, members: members,
                                 initiallyExpanded: true,
                                 onDelete: onDeletePlan,
                                 onHeaderTap: collapse)
            }
            if !running.isEmpty {
                if plans.isEmpty {
                    Button(action: collapse) {
                        HStack {
                            section("Работают")
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.down")
                                .tfText(.meta)
                                .foregroundStyle(Color.tfDim)
                                .padding(.trailing, TFSpacing.lg)
                                .padding(.top, TFSpacing.sm)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Свернуть")
                } else {
                    section("Работают")
                }
                ForEach(running) { item in
                    TFListRow(title: runningLine(item), titleStyle: .action,
                              verticalPadding: 0, minHeight: TFHitTarget.min,
                              chevron: .shown) { onOpenChat(item.chatID) }
                        .accessibilityIdentifier("chat.composerPill.running.\(item.chatID)")
                }
            }
        }
        .padding(.vertical, TFSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .voiceRoundedSurface(cornerRadius: TFRadius.xl)
    }

    private func collapse() {
        withAnimation(TFMotion.standard) { expanded = false }
    }

    private func section(_ title: String) -> some View {
        Text(title)
            .tfText(.meta)
            .foregroundStyle(Color.tfSub)
            .padding(.horizontal, TFSpacing.lg)
            .padding(.top, TFSpacing.sm)
    }

    private func runningLine(_ item: ChatComposerStatus.Running) -> String {
        let task = item.title.flatMap { $0.isEmpty ? nil : $0 }
        switch item.state {
        case .waiting: return task.map { "\(item.name) — ждёт: \($0)" } ?? "\(item.name) — ждёт"
        default: return task.map { "\(item.name) — работает над \($0)" } ?? "\(item.name) — работает"
        }
    }

    private func queuedRow(_ item: ChatComposerStatus.Queued) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.xs) {
            Text(item.text)
                .tfText(.action)
                .foregroundStyle(Color.tfText)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: TFSpacing.sm) {
                Button("Отправить сейчас") { onSendNow(item) }
                    .tfText(.meta)
                    .foregroundStyle(Color.tfBlue)
                    .accessibilityIdentifier("chat.composerPill.sendNow.\(item.messageID)")
                Spacer(minLength: 0)
                Button { onRemove(item) } label: {
                    Image(systemName: "xmark")
                        .frame(width: TFHitTarget.min, height: TFHitTarget.min)
                }
                .foregroundStyle(Color.tfSub)
                .accessibilityLabel("Убрать")
                .accessibilityIdentifier("chat.composerPill.remove.\(item.messageID)")
            }
        }
        .padding(.horizontal, TFSpacing.lg)
        .padding(.vertical, TFSpacing.xs)
    }
}

