import SwiftUI

struct AppDiagnosticsScreen: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var snapshot = AppDiagnostics.shared.snapshot()
    @State private var showsReset = false
    /// Системный снимок устройства: читается по требованию, не чаще раза в 5 секунд.
    @State private var deviceSnapshot: DeviceResourceSnapshot?
    /// Ручные снимки заряда: владелец записывает их сам.
    @State private var batterySnapshots: [BatterySnapshot] = []
    /// Что владелец ввёл в поле «Заряд, %».
    @State private var batteryInput = ""
    /// Пометка к снимку: что он делал, когда записывал.
    @State private var batteryNote = ""
    /// Хранилище снимков: локально, на устройстве, никуда не отправляется.
    private let batteryStore = BatterySnapshotStore()

    var body: some View {
        List {
            Section {
                HStack(spacing: TFSpacing.sm) {
                    markIcon(report.mark)
                    Text(report.verdictLine)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("diagnostics-verdict")
                LabeledContent(
                    "Отсчёт",
                    value: "\(DiagnosticsReport.duration(report.intervalMinutes)) · с \(dateLabel(report.startAt))"
                )
                LabeledContent("Приложение", value: snapshot.background ? "В фоне" : "Открыто")
                LabeledContent("Сбор диагностики", value: "Постоянно")
                    .accessibilityElement(children: .combine)
                    .accessibilityValue("Постоянно")
                    .accessibilityIdentifier("diagnostics-collection")
                Text("Счётчики копятся с \(dateLabel(report.countersSince))")
                    .tfText(.meta).foregroundStyle(Color.tfSub)
            } header: {
                Text("Итог")
            } footer: {
                Text("Отсчёт — с того момента, как приложение вернулось на экран (или с запуска): в отчёте видно, сколько стоило то, что вы делали в приложении в этот раз."
                     + " Метки — по скорости роста в минуту: норма, внимание, тревожно. Пороги и откуда они взялись — в DiagnosticsReport.swift."
                     + " Это работа телефона, а не расход батареи в процентах; работа моделей на сервере сюда не входит.")
            }
            Section("Сейчас работает") {
                LabeledContent("Очереди текста", value: snapshot.activeQueues == 0 ? "Спят" : "Работают: \(snapshot.activeQueues)")
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(snapshot.activeQueues == 0 ? "Спят" : "Работают: \(snapshot.activeQueues)")
                    .accessibilityIdentifier("diagnostics-queues")
                ForEach(AppDiagnostics.Work.allCases, id: \.rawValue) { work in
                    LabeledContent(work.title, value: String(snapshot.active[work, default: 0]))
                }
            }
            ForEach(report.groups) { group in
                Section {
                    ForEach(group.rows) { row in counterRow(row) }
                } header: {
                    HStack(spacing: TFSpacing.sm) {
                        Text(group.title)
                        Spacer(minLength: TFSpacing.sm)
                        Text(group.mark.title).foregroundStyle(markColor(group.mark))
                    }
                }
            }
            Section {
                ForEach(report.deviceFacts) { fact in deviceFactRow(fact) }
            } header: {
                HStack(spacing: TFSpacing.sm) {
                    Text("Устройство")
                    Spacer(minLength: TFSpacing.sm)
                    Text("системное измерение").foregroundStyle(Color.tfSub)
                }
            } footer: {
                Text("Заряд, тепло, режим экономии, память — замер iOS в момент, когда открыт экран. "
                     + "iOS не сообщает, сколько батареи съело приложение: расход считается только по ручным снимкам ниже.")
            }
            Section {
                ForEach(report.topConsumers) { row in counterRow(row) }
            } header: {
                HStack(spacing: TFSpacing.sm) {
                    Text("Кто подъедает")
                    Spacer(minLength: TFSpacing.sm)
                    Text("счётчик приложения").foregroundStyle(Color.tfSub)
                }
            } footer: {
                Text("Топ-3 по скорости роста счётчиков приложения за текущий отсчёт. Байты считаются отдельно — у них своя единица.")
            }
            Section {
                if let delta = report.batteryDelta {
                    LabeledContent("Изменение заряда", value: DiagnosticsReport.batteryText(delta))
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("diagnostics-battery-delta")
                } else {
                    Text("Нужны два снимка, чтобы увидеть расход.")
                        .tfText(.meta).foregroundStyle(Color.tfSub)
                }
                LabeledContent("Снимков записано", value: "\(batterySnapshots.count) из \(BatterySnapshotStore.limit)")
                ForEach(batterySnapshots) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(item.level)%")
                        Text(item.note.map { "\(dateLabel(item.date)) · \($0)" } ?? dateLabel(item.date))
                            .tfText(.meta).foregroundStyle(Color.tfSub)
                    }
                }
                TFTextField("Заряд, % — из «Настройки → Батарея»", text: $batteryInput)
                    .keyboardType(.numberPad)
                TFTextField("Пометка (необязательно)", text: $batteryNote)
                Button("Записать снимок") { recordBatterySnapshot() }
                    .foregroundStyle(Color.tfText)
                    .disabled(!canRecordBattery)
                    .accessibilityIdentifier("diagnostics-battery-save")
                if let level = deviceSnapshot?.batteryLevel {
                    Button("Снимок по системному заряду (\(level)%)") { recordSystemBatterySnapshot() }
                        .foregroundStyle(Color.tfText)
                        .accessibilityIdentifier("diagnostics-battery-system")
                }
                if !batterySnapshots.isEmpty {
                    Button("Убрать снимки") {
                        batteryStore.clear()
                        batterySnapshots = []
                    }
                    .foregroundStyle(Color.tfText)
                }
            } header: {
                HStack(spacing: TFSpacing.sm) {
                    Text("Расход батареи")
                    Spacer(minLength: TFSpacing.sm)
                    Text("ручной снимок").foregroundStyle(Color.tfSub)
                }
            } footer: {
                Text("Снимок — это заряд, который вы видите в «Настройки → Батарея». Расход — разница между двумя снимками. "
                     + "Приложение не знает свой расход батареи и не притворяется, что знает: счётчики приложения показывают работу, а не проценты.")
            }
            Section("Последние события") {
                ForEach(snapshot.saved.events.reversed()) { event in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.text)
                        Text("\(dateLabel(event.date)) · \(event.background ? "Фон" : "Открыто")")
                            .tfText(.meta).foregroundStyle(Color.tfSub)
                    }
                }
            }
            Section {
                ShareLink(item: report.text(events: snapshot.saved.events)) {
                    Label("Поделиться диагностикой", systemImage: "square.and.arrow.up")
                        .foregroundStyle(Color.tfText)
                }
                Button("Сбросить счётчики") { showsReset = true }
                    .foregroundStyle(Color.tfText)
                    .accessibilityIdentifier("diagnostics-reset")
            }
        }
        .foregroundStyle(Color.tfText)
        .tint(Color.tfText)
        .tfSettingsListChrome()
        .tfScreenBackground()
        .tfNativeHeader("Диагностика")
        .accessibilityIdentifier("app-diagnostics-screen")
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            // Only the open diagnostics page refreshes; collection itself has no timer.
            // Системные метрики устройства читаем не чаще раза в 5 секунд: чаще —
            // значит сам экран становится причиной расхода.
            var lastDeviceRead = Date.distantPast
            while !Task.isCancelled {
                snapshot = AppDiagnostics.shared.snapshot()
                if Date().timeIntervalSince(lastDeviceRead) >= 5 {
                    lastDeviceRead = Date()
                    deviceSnapshot = DeviceResourceMetrics.currentSnapshot()
                    batterySnapshots = batteryStore.snapshots()
                }
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
        .onDisappear { AppDiagnostics.shared.checkpoint() }
        .confirmationDialog("Сбросить счётчики диагностики?", isPresented: $showsReset, titleVisibility: .visible) {
            Button("Сбросить", role: .destructive) {
                AppDiagnostics.shared.reset()
                snapshot = AppDiagnostics.shared.snapshot()
            }
        }
    }

    private var report: DiagnosticsReport {
        DiagnosticsReport(snapshot: snapshot, device: deviceSnapshot, batterySnapshots: batterySnapshots)
    }

    /// Строка счётчика: сколько всего, сколько прибавилось за отсчёт, с какой
    /// скоростью и что об этом думает метка (владелец 18.10.2026).
    private func counterRow(_ row: DiagnosticsReport.Row) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.xs) {
            HStack(spacing: TFSpacing.sm) {
                markIcon(row.mark)
                Text(row.title)
                Spacer(minLength: TFSpacing.sm)
                Text(DiagnosticsReport.value(row.total, isBytes: row.isBytes))
                    .foregroundStyle(Color.tfSub)
            }
            Text(detail(row))
                .tfText(.meta)
                .foregroundStyle(Color.tfSub)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(row.mark.title). \(detail(row))")
        .accessibilityIdentifier("diagnostics-count-" + row.id)
    }

    private func detail(_ row: DiagnosticsReport.Row) -> String {
        var parts = [
            DiagnosticsReport.deltaText(row.delta, isBytes: row.isBytes) + " за отсчёт",
            DiagnosticsReport.rateText(row.perMinute, isBytes: row.isBytes),
            "норма до " + DiagnosticsReport.rateText(row.normalLimit, isBytes: row.isBytes),
        ]
        if row.backgroundDelta > 0 {
            parts.append("в фоне " + DiagnosticsReport.deltaText(row.backgroundDelta, isBytes: row.isBytes))
        }
        return parts.joined(separator: " · ")
    }

    /// Строка системного факта: значение, метка и пометка источника. Источник
    /// виден рядом со значением — чтобы никто не принял замер iOS за счётчик
    /// приложения.
    private func deviceFactRow(_ fact: DiagnosticsReport.DeviceFact) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.xs) {
            HStack(spacing: TFSpacing.sm) {
                markIcon(fact.mark)
                Text(fact.title)
                Spacer(minLength: TFSpacing.sm)
                Text(fact.value).foregroundStyle(Color.tfSub)
            }
            Text(fact.source)
                .tfText(.meta)
                .foregroundStyle(Color.tfSub)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(fact.value). \(fact.mark.title). \(fact.source)")
        .accessibilityIdentifier("diagnostics-device-" + fact.id)
    }

    /// Записать ручной снимок: число, которое владелец увидел в «Настройки →
    /// Батарея».
    private func recordBatterySnapshot() {
        guard let level = Int(batteryInput.trimmingCharacters(in: .whitespacesAndNewlines)),
              (0...100).contains(level) else { return }
        let note = batteryNote.trimmingCharacters(in: .whitespacesAndNewlines)
        batteryStore.add(level: level, note: note.isEmpty ? nil : note)
        batteryInput = ""
        batteryNote = ""
        batterySnapshots = batteryStore.snapshots()
    }

    /// Записать снимок по текущему системному заряду — быстрый путь, когда
    /// телефон под рукой и «Настройки» открывать не хочется.
    private func recordSystemBatterySnapshot() {
        guard let level = deviceSnapshot?.batteryLevel else { return }
        batteryStore.add(level: level)
        batterySnapshots = batteryStore.snapshots()
    }

    private var canRecordBattery: Bool {
        guard let level = Int(batteryInput.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return (0...100).contains(level)
    }

    private func markIcon(_ mark: DiagnosticsMark) -> some View {
        Image(systemName: mark.symbol)
            .foregroundStyle(markColor(mark))
    }

    private func markColor(_ mark: DiagnosticsMark) -> Color {
        switch mark {
        case .ok: Color.tfGreen
        case .attention: Color.tfOrange
        case .alarm: Color.tfRed
        }
    }

    private func dateLabel(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year().hour().minute().locale(Locale(identifier: "ru_RU")))
    }
}

#if DEBUG
/// Exercises real pacer instrumentation and the real settings entry without a server/model.
struct AppDiagnosticsPreview: View {
    var body: some View {
        NavigationStack {
            ServerSettingsScreen()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink("Поток") { AppDiagnosticsStreamPreview() }
                            .accessibilityIdentifier("diagnostics-preview-stream")
                    }
                }
        }
    }
}

private struct AppDiagnosticsStreamPreview: View {
    @State private var complete = false
    var body: some View {
        ScrollView {
            RoleLiveTurnBubble(
                turn: RoleChatLiveTurn(chatID: "diagnostics", userID: "preview", name: "Проверка",
                    startedAt: nil, items: [.text(String(repeating: "Плавный текст проверяет работу очереди. ", count: 12))], thinking: nil),
                showsName: false, isComplete: true, onPlaybackComplete: { complete = true })
                .padding()
            if complete { Text("Поток завершён").accessibilityIdentifier("diagnostics-preview-complete") }
        }
        .navigationTitle("Проверка потока")
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
