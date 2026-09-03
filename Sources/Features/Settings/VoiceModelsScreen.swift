import SwiftUI

/// `/settings/voice-models` — spec/SCREENS-2.md §16 + `src/screens/VoiceModelsScreen.tsx`
/// (спека не даёт словарь статусов дословно нигде, кроме текста — цвета и
/// раскладку строк беру из веб-кода, ARCHITECTURE.md п.3).
///
/// Шапка — штатная iOS-навигация, общая с остальными экранами настроек.
///
/// ⚠️ Веб-версия при `!localAIModelsSupported()` (браузер, не нативное
/// приложение) заменяет экран целиком на короткую заглушку — здесь это
/// состояние НЕДОСТИЖИМО: это и есть то самое нативное приложение на iPhone,
/// заглушка не рендерится никогда, ветка сознательно не портирована.
///
/// ⚠️ Секция «На телефоне», 03.09.2026: «Распознавание речи» подключена —
/// не `WhisperKit`/`argmaxinc`, как на вебе, а NVIDIA Parakeet TDT v3 через
/// `FluidAudio` (SPM, `project.yml`) — владелец сам назвал модель («маленькая,
/// все хвалят, мультиязычная») и явно попросил не городить пикер из
/// нескольких движков. Реальный статус (не заглушка): строка тянет
/// `DictationEngine.shared.modelState`, тап при «скачать» реально качает и
/// греет модель. Логика записи/распознавания и приёмник UI — там же
/// (`Sources/Core/Speech/DictationEngine.swift`), не в этом файле.
///
/// «Расшифровка действий» — другой по природе движок (локальная LLM,
/// объясняющая, чем занят агент, не спич-ту-текст) — пока НЕ подключена,
/// честный гэп остаётся: строка так и показывает «не скачана».
struct VoiceModelsScreen: View {
    @State private var serverStatus: AIStatusResponse?
    @State private var isLoadingServerStatus = true

    @State private var isLogEnabled = DictationLog.isEnabled()
    @State private var logEntries = DictationLog.readEntries()
    @State private var pendingArchiveCount = DictationArchiveQueue.pendingCount()
    @State private var dictation = DictationEngine.shared

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: TFSpacing.lg) {
                    onDeviceSection
                    onServerSection
                    dictationLogSection
                }
                .padding(.horizontal, TFSpacing.screenHorizontal)
                .padding(.top, TFSpacing.sm)
                .padding(.bottom, TFSpacing.xl * 2)
            }
        }
        .tfNativeHeader("Модели и голоса")
        .background(Color.tfBackground)
        .task {
            dictation.refreshModelState()
            await loadServerStatus()
        }
    }

    private func loadServerStatus() async {
        isLoadingServerStatus = true
        defer { isLoadingServerStatus = false }
        serverStatus = try? await APIClient().aiStatus()
    }

    // MARK: - На телефоне

    private var onDeviceSection: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            SettingsCapsLabel("На телефоне")
            TFCard(padding: 0) {
                VStack(spacing: 0) {
                    Button {
                        Task { await dictation.downloadModelIfNeeded() }
                    } label: {
                        VoiceModelRow(
                            icon: "mic", title: "Распознавание речи",
                            subtitle: speechSubtitle,
                            value: speechValue, dot: speechDot
                        )
                    }
                    .buttonStyle(TFTapRowStyle())
                    .disabled(!isSpeechRowTappable)

                    TFDivider(inset: rowDividerInset)
                    // «Расшифровка действий» — отдельный движок (локальная
                    // LLM, объясняющая, чем занят агент), не распознавание
                    // речи. Владелец 03.09.2026 попросил начать с диктовки —
                    // эта строка честно ждёт своей очереди.
                    VoiceModelRow(
                        icon: "sparkles", title: "Расшифровка действий",
                        subtitle: "Объясняет, чем занят агент в задаче",
                        value: "не скачана", dot: .off
                    )
                }
            }
            .padding(.horizontal, TFSpacing.screenHorizontal)
            Text("Распознавание речи — Parakeet TDT v3 (NVIDIA), полностью на телефоне, без сервера, понимает русский и ещё два десятка языков. Модель качается один раз при первом использовании.")
                .tfText(.caption)
                .foregroundStyle(Color.tfDim)
                .padding(.horizontal, TFSpacing.screenHorizontal + TFSpacing.xs)
        }
    }

    private var speechSubtitle: String {
        if case .failed(let message) = dictation.modelState { return message }
        return "Диктовка задач, заметок и комментариев"
    }
    private var speechValue: String {
        switch dictation.modelState {
        case .unknown: "…"
        case .notDownloaded: "скачать"
        case .downloading(let progress): "\(Int((progress * 100).rounded()))%"
        case .ready: "готова"
        case .failed: "ошибка"
        }
    }
    private var speechDot: VoiceDotState {
        switch dictation.modelState {
        case .ready: .ok
        case .downloading: .warn
        case .failed: .warn
        case .unknown, .notDownloaded: .off
        }
    }
    private var isSpeechRowTappable: Bool {
        switch dictation.modelState {
        case .notDownloaded, .failed: true
        case .unknown, .downloading, .ready: false
        }
    }

    // MARK: - На сервере

    private var onServerSection: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            SettingsCapsLabel("На сервере")
            TFCard(padding: 0) {
                VStack(spacing: 0) {
                    VoiceModelRow(
                        icon: "cpu", title: "Мозг для задач",
                        subtitle: brainSubtitle,
                        value: brainValue, dot: brainDot
                    )
                    TFDivider(inset: rowDividerInset)
                    VoiceModelRow(
                        icon: "cloud", title: serverModelTitle,
                        subtitle: "Разбор диктовки, сводки и AI-действия в Дневнике",
                        value: serverModelValue, dot: serverModelDot
                    )
                }
            }
            .padding(.horizontal, TFSpacing.screenHorizontal)
        }
    }

    private var brainSubtitle: String {
        guard let serverStatus else { return "разбивка задач на шаги" }
        return "\(VoiceModelsScreen.humanServerModelName(serverStatus.model)) · разбивка задач на шаги"
    }
    private var brainValue: String {
        isLoadingServerStatus ? "…" : (serverStatus?.online == true ? "работает" : "нет связи")
    }
    private var brainDot: VoiceDotState {
        isLoadingServerStatus ? .off : (serverStatus?.online == true ? .ok : .off)
    }

    private var serverModelTitle: String {
        serverStatus.map { VoiceModelsScreen.humanServerModelName($0.model) } ?? "Серверная модель"
    }
    private var serverModelValue: String {
        guard !isLoadingServerStatus else { return "…" }
        guard let serverStatus, serverStatus.online else { return "нет связи" }
        if serverStatus.installed == false { return "не найдена" }
        return "работает"
    }
    private var serverModelDot: VoiceDotState {
        guard !isLoadingServerStatus, let serverStatus, serverStatus.online else { return .off }
        return serverStatus.installed == false ? .warn : .ok
    }

    /// Порт `serverModelName` (`src/lib/aiStatus.ts`) — «qwen3.6-27b-iq4-16k:latest» → «Qwen 3.6 · 27B».
    private static func humanServerModelName(_ raw: String) -> String {
        guard !raw.isEmpty else { return "Неизвестная модель" }
        let base = raw.split(separator: ":").first.map(String.init) ?? raw
        let lowerBase = base.lowercased()
        let family: String
        if lowerBase.contains("qwen") { family = "Qwen" }
        else if lowerBase.contains("llama") { family = "Llama" }
        else if lowerBase.contains("deepseek") { family = "DeepSeek" }
        else if lowerBase.contains("hermes") { family = "Hermes" }
        else { family = base.split(whereSeparator: { "-_.".contains($0) }).first.map(String.init) ?? base }

        var parts = [family]
        if let versionRange = base.range(of: #"\d+\.\d+"#, options: .regularExpression) {
            parts.append(String(base[versionRange]))
        }
        let name = parts.joined(separator: " ")

        if let sizeRange = base.range(of: #"\d+[bB]\b"#, options: .regularExpression) {
            let sizeDigits = base[sizeRange].dropLast() // отрезать "b"
            return "\(name) · \(sizeDigits)B"
        }
        return name
    }

    // MARK: - Диагностика диктовки (DictationLogSection)

    private var dictationLogSection: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            SettingsCapsLabel("Диагностика диктовки")

            TFCard(padding: 0) {
                VoiceModelRow(
                    icon: "icloud.and.arrow.up",
                    title: "Архив аудио на сервере",
                    subtitle: pendingArchiveCount == 0 ? "Всё выгружено" : "Ждут отправки: \(pendingArchiveCount). Уйдут, когда .110 будет доступен",
                    value: nil, dot: nil
                )
            }
            .padding(.horizontal, TFSpacing.screenHorizontal)

            TFCard(padding: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Записывать, что распознала модель").tfText(.body).foregroundStyle(Color.tfText)
                        Text("Видно текст от модели и текст после исправлений").tfText(.action).foregroundStyle(Color.tfSub)
                    }
                    Spacer()
                    Button(isLogEnabled ? "Включено" : "Выключено") {
                        isLogEnabled.toggle()
                        DictationLog.setEnabled(isLogEnabled)
                    }
                    .buttonStyle(TFTapScaleStyle())
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isLogEnabled ? Color.tfGreen : Color.tfBlue)
                    .padding(.horizontal, TFSpacing.sm)
                    .padding(.vertical, TFSpacing.xs)
                    .background((isLogEnabled ? Color.tfGreen : Color.tfBlue).opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: TFRadius.md))
                }
                .padding(TFSpacing.md)
            }
            .padding(.horizontal, TFSpacing.screenHorizontal)

            if isLogEnabled && logEntries.isEmpty {
                Text("Пока пусто — продиктуй что-нибудь, и запись появится здесь.")
                    .tfText(.action).foregroundStyle(Color.tfSub)
                    .padding(.horizontal, TFSpacing.screenHorizontal + TFSpacing.xs)
            }

            if !logEntries.isEmpty {
                TFCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(logEntries.enumerated()), id: \.element.at) { index, entry in
                            dictationLogRow(entry)
                            if index != logEntries.count - 1 { TFDivider() }
                        }
                    }
                }
                .padding(.horizontal, TFSpacing.screenHorizontal)

                Button("Очистить журнал") {
                    DictationLog.clear()
                    logEntries = []
                }
                .buttonStyle(TFTapFadeStyle())
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.tfCoral)
                .padding(.horizontal, TFSpacing.screenHorizontal + TFSpacing.xs)
            }
        }
    }

    private func dictationLogRow(_ entry: DictationLogEntry) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.xs) {
            Text("\(Self.entryTimeFormatter.string(from: DateFormats.iso8601(entry.at) ?? Date())) · \(entry.engine)\(entry.raw == entry.normalized ? " · исправлений не потребовалось" : " · исправлено нами")")
                .tfText(.micro).foregroundStyle(Color.tfDim)
            Text("от модели: \(entry.raw.isEmpty ? "—" : entry.raw)")
                .tfText(.action).foregroundStyle(Color.tfSub)
            if entry.raw != entry.normalized {
                Text("после правок: \(entry.normalized)")
                    .tfText(.action).foregroundStyle(Color.tfText)
            }
        }
        .padding(TFSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static let entryTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = TimeZone(identifier: "Europe/Moscow")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private var rowDividerInset: CGFloat { TFSpacing.lg + 32 + TFSpacing.md }
}

// MARK: - Единый словарь статусов (spec §16: работает/прогревается/скачивается/не скачана/нет связи/не найдена)

enum VoiceDotState { case ok, warn, off }

private struct VoiceStatusDot: View {
    let state: VoiceDotState
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }
    private var color: Color {
        switch state {
        case .ok: .tfGreen
        case .warn: .tfYellow
        case .off: Color.tfDim.opacity(0.5)
        }
    }
}

/// Одна строка раздела ИИ — иконка/точка-статус/заголовок/подпись/значение
/// (`ModelRow` в вебе — здесь намеренно с префиксом `Voice`, модуль один на
/// весь таргет, `ModelRow` слишком общее имя для отдельного экрана).
private struct VoiceModelRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let value: String?
    let dot: VoiceDotState?

    var body: some View {
        HStack(spacing: TFSpacing.md) {
            Image(systemName: icon).font(.system(size: TFIconSize.sm)).foregroundStyle(Color.tfDim).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: TFSpacing.xs) {
                    if let dot { VoiceStatusDot(state: dot) }
                    Text(title).tfText(.body).foregroundStyle(Color.tfText).lineLimit(1)
                }
                Text(subtitle).tfText(.action).foregroundStyle(Color.tfSub).lineLimit(1)
            }
            Spacer()
            if let value {
                Text(value).tfText(.action).foregroundStyle(Color.tfDim).lineLimit(1)
            }
        }
        .padding(.horizontal, TFSpacing.lg)
        .padding(.vertical, TFSpacing.md)
    }
}
