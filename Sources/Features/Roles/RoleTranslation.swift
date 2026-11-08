import SwiftUI
import NaturalLanguage
import Translation

// Перевод ленты роли (владелец 20.10.2026): роли думают и пишут как им
// удобнее, обычно по-английски, а в ленте по кнопке показывается русский
// перевод. Переводит системный переводчик Apple на самом телефоне — без
// сервера и без токенов. Переводятся только реплики роли; шаги (команды,
// пути, имена инструментов) остаются как есть, иначе перевод их портит.
//
// Почему быстро (владелец 08.11.2026: «текста одно предложение и вообще
// полдня оно переводится»): текст режется на куски по ~300 знаков
// (`RoleTranslationChunks`), куски копятся в очереди и уходят в ОДИН живой
// сеанс переводчика на всё приложение, готовые куски показываются сразу по
// порядку. Раньше весь ответ уходил одним запросом, а сеанс
// перезапускался (`invalidate()`) на каждое изменение ленты.

/// Общий для всех экранов переводчик: включён ли перевод, что уже переведено
/// и какая очередь кусков ждёт перевода.
@MainActor
@Observable
final class RoleTranslator {
    static let shared = RoleTranslator()
    /// Настройка «Переводить работу ролей сразу» в шторке «Чат».
    static let autoKey = "chat.autoTranslate"

    static let english = Locale.Language(identifier: "en")
    static let russian = Locale.Language(identifier: "ru")

    /// Сколько кусков отправляем за один запрос: несколько коротких кусков
    /// уходят пачкой, ожидание у них общее.
    private static let batchSize = 8
    /// Когда текст не удалось перевести. Не навсегда: окно скачивания языка
    /// могло закрыться на полуслове — через `retryAfter` пробуем снова.
    private static let retryAfter: TimeInterval = 30

    var isOn = UserDefaults.standard.bool(forKey: RoleTranslator.autoKey) {
        didSet { if !isOn { clearQueue() } }
    }

    /// Готовые переводы кусков; ключ — сам кусок.
    private(set) var translations: [String: String] = [:]
    /// Сколько кусков ждёт перевода — по нему поднимается сеанс.
    private(set) var pendingCount = 0
    /// Диагностика для владельца (20.10.2026): на каком шаге перевод — строка
    /// рядом со значком, пока перевод включён.
    var status = ""

    /// Очередь кусков в том порядке, в каком их просят экраны.
    @ObservationIgnored private var queue: [String] = []
    @ObservationIgnored private var queued: Set<String> = []
    /// Сигнал «работа появилась»: без него сеанс спал бы на опросе.
    @ObservationIgnored private var wake: AsyncStream<Void>.Continuation?
    @ObservationIgnored private var englishCache: [String: Bool] = [:]
    @ObservationIgnored private var failedAt: [String: Date] = [:]
    /// Идёт ли сейчас запрос в сеанс. `TranslationSession` нельзя спрашивать
    /// дважды одновременно (владелец 08.11.2026: приложение вылетало по
    /// нажатию «Перевести» — старый цикл ещё ждал ответа, новый уже просил).
    @ObservationIgnored private var working = false
    /// Нарезка текстов, которую уже считали: `display` зовётся на каждой
    /// перерисовке.
    @ObservationIgnored private var splitCache: [String: [String]] = [:]

    init() {}

    /// Что система говорит о паре английский → русский.
    func checkLanguages() async -> Bool {
        switch await LanguageAvailability().status(from: Self.english, to: Self.russian) {
        case .installed:
            status = "языки скачаны"
            return true
        case .supported:
            status = "языки: не скачаны — Настройки → Переводчик"
            return false
        case .unsupported:
            status = "языки: пара не поддерживается"
            return false
        @unknown default:
            status = "языки: неизвестный ответ"
            return false
        }
    }

    /// Что показать вместо текста: готовые куски — переводом, остальное — как
    /// есть. Текст никогда не пропадает и не обрезается.
    func display(_ text: String) -> String {
        guard isOn, !text.isEmpty, !translations.isEmpty else { return text }
        return RoleTranslationChunks.shown(text, translations: translations, chunks: chunks(of: text))
    }

    /// Нарезка кэшируется: `display` зовётся в теле вью на каждой
    /// перерисовке, а лента растёт покадрово. Кэш короткий — держим только
    /// последние тексты.
    private func chunks(of text: String) -> [String] {
        if let known = splitCache[text] { return known }
        let chunks = RoleTranslationChunks.of(text)
        if splitCache.count > 128 { splitCache.removeAll(keepingCapacity: true) }
        splitCache[text] = chunks
        return chunks
    }

    func isEnglish(_ text: String) -> Bool {
        if let known = englishCache[text] { return known }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let result = recognizer.dominantLanguage == .english
        englishCache[text] = result
        return result
    }

    /// Просьба перевести тексты, которые сейчас на экране. Повторные просьбы
    /// бесплатны: готовое и уже стоящее в очереди отбрасывается.
    func request(_ texts: [String]) {
        guard isOn else { return }
        var added = false
        for text in texts {
            for chunk in RoleTranslationChunks.of(text) {
                guard translations[chunk] == nil, !queued.contains(chunk), isEnglish(chunk) else { continue }
                if let failed = failedAt[chunk], Date().timeIntervalSince(failed) < Self.retryAfter { continue }
                queue.append(chunk)
                queued.insert(chunk)
                added = true
            }
        }
        pendingCount = queue.count
        if added { wake?.yield() }
    }

    /// Живой сеанс: переводит очередь, пока приложение не закроют. Задачу
    /// сеанса запускает `RoleTranslationHost` в корне.
    func work(with session: TranslationSession) async {
        // Второй цикл поверх первого — это два одновременных запроса в один
        // сеанс, на котором системный переводчик и падал. Чужой цикл уже
        // разбирает очередь: он и подхватит новые куски.
        guard !working else { return }
        working = true
        defer { working = false }
        while !Task.isCancelled {
            if queue.isEmpty {
                await waitForWork()
                continue
            }
            let batch = Array(queue.prefix(Self.batchSize))
            queue.removeFirst(batch.count)
            for chunk in batch { queued.remove(chunk) }
            pendingCount = queue.count
            let alive = await translate(batch, with: session)
            if !alive { return }
        }
    }

    /// `false` — задача отменена: сеанс больше не продолжится.
    private func translate(_ batch: [String], with session: TranslationSession) async -> Bool {
        status = "перевожу \(batch.count)"
        let requests = batch.enumerated().map { index, chunk in
            TranslationSession.Request(sourceText: chunk, clientIdentifier: String(index))
        }
        do {
            for response in try await session.translations(from: requests) {
                guard let id = response.clientIdentifier, let index = Int(id), batch.indices.contains(index) else { continue }
                translations[batch[index]] = response.targetText
            }
            status = "переведено \(translations.count)"
            return true
        } catch {
            // Отмена — не ошибка: куски вернутся в очередь, их подхватит
            // следующий сеанс.
            if Task.isCancelled || error is CancellationError {
                requeue(batch)
                return false
            }
            // Языковой пакет не скачан или окно закрыто — повторим позже.
            for chunk in batch { failedAt[chunk] = Date() }
            status = "ошибка: \(error.localizedDescription)"
            return true
        }
    }

    private func requeue(_ batch: [String]) {
        for chunk in batch.reversed() where translations[chunk] == nil && !queued.contains(chunk) {
            queue.insert(chunk, at: 0)
            queued.insert(chunk)
        }
        pendingCount = queue.count
    }

    private func clearQueue() {
        queue.removeAll()
        queued.removeAll()
        pendingCount = 0
    }

    /// Спит до первой просьбы. Гонки нет: всё на главном акторе, и между
    /// установкой сигнала и проверкой очереди некому его потерять.
    private func waitForWork() async {
        guard queue.isEmpty else { return }
        let stream = AsyncStream<Void> { continuation in wake = continuation }
        defer { wake = nil }
        guard queue.isEmpty else { return }
        for await _ in stream { break }
    }
}

/// Один живой сеанс системного переводчика на всё приложение: пока приложение
/// открыто, он не перезапускается — ни при смене ленты, ни при новой реплике.
/// Вешается один раз в корне (`RootShellView`), поэтому перевод работает и в
/// истории чата, и в шторке размышлений, где своего сеанса заводить нельзя
/// (20.10.2026: сеанс, поднятый в шторке, ронял приложение системным окном
/// скачивания языка поверх нашей шторки).
struct RoleTranslationHost: ViewModifier {
    @State private var configuration: TranslationSession.Configuration?
    @State private var languagesChecked = false
    private var translator: RoleTranslator { .shared }

    func body(content: Content) -> some View {
        content
            .translationTask(configuration) { session in
                await translator.work(with: session)
            }
            .task(id: translator.isOn) {
                // Включили перевод после отказа — проверяем языки заново.
                if translator.isOn { languagesChecked = false }
                start()
            }
            .onChange(of: translator.pendingCount) { _, count in
                if count > 0 { start() }
            }
    }

    /// Сеанс поднимаем один раз — первым требованием перевода или включением
    /// перевода, и только когда языки уже скачаны. Иначе система показывает
    /// своё окно загрузки, а поверх открытой шторки размышлений это роняло
    /// приложение (владелец 08.11.2026: нажал «Перевести» — вылет).
    private func start() {
        guard translator.isOn, configuration == nil, !languagesChecked else { return }
        languagesChecked = true
        Task {
            let ready = await translator.checkLanguages()
            guard ready, configuration == nil else { return }
            configuration = .init(source: RoleTranslator.english, target: RoleTranslator.russian)
        }
    }
}

/// Просит перевод для текстов, которые сейчас на экране: лента хода, реплика
/// в истории, открытая шторка размышлений. Своего сеанса не заводит — только
/// кладёт куски в общую очередь.
struct RoleTranslationRequests: ViewModifier {
    let texts: [String]
    private var translator: RoleTranslator { .shared }

    func body(content: Content) -> some View {
        content
            .task(id: key) { translator.request(texts) }
    }

    /// Ключ дешевле самих текстов: их число и длина последнего. Лента только
    /// растёт, поэтому этого хватает, а сравнение килобайтов на каждом кадре
    /// не нужно.
    private var key: String {
        "\(translator.isOn)|\(texts.count)|\(texts.last?.count ?? 0)"
    }
}

extension View {
    /// Повесить на список/реплику: что видно — то и просим перевести.
    func roleTranslationRequests(_ texts: [String]) -> some View {
        modifier(RoleTranslationRequests(texts: texts))
    }
}

/// Переключатель над окном хода роли: виден всегда — английский может
/// прийти в любую минуту, а окно прокручено к свежим действиям.
struct RoleTranslateSwitch: View {
    private var translator: RoleTranslator { .shared }

    var body: some View {
        // Строка прижата к низу, в одну строку — на одной линии с «Работает · …»,
        // не налезает на последнюю строку ленты (владелец 20.10.2026).
        HStack(alignment: .bottom, spacing: 0) {
            if translator.isOn, !translator.status.isEmpty {
                Text(translator.status)
                    .tfText(.caption)
                    .foregroundStyle(Color.tfDim)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: 180, alignment: .trailing)
                    .padding(.bottom, 2)
                    .accessibilityIdentifier("role-translate-status")
            }
        Button {
            translator.isOn.toggle()
        } label: {
            // Только значок: включённый перевод — ярким, выключенный — тусклым.
            Image(systemName: "translate")
                .font(.footnote)
                .foregroundStyle(translator.isOn ? Color.tfText : Color.tfDim)
                .frame(width: 44, height: 44, alignment: .bottomTrailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(translator.isOn ? "Показать оригинал" : "Перевести на русский")
        .accessibilityIdentifier("role-translate-switch")
        }
    }
}

/// Сам переключатель перевода — для ленты и для шторки размышлений.
/// Виден, только когда среди текстов есть английский.
struct RoleTranslateToggle: View {
    let texts: [String]
    private var translator: RoleTranslator { .shared }

    var body: some View {
        if texts.contains(where: translator.isEnglish) {
            Button {
                translator.isOn.toggle()
            } label: {
                Label(translator.isOn ? "Оригинал" : "Перевести", systemImage: "translate")
                    .tfText(.meta)
                    .foregroundStyle(Color.tfSub)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(translator.isOn ? "Показать оригинал" : "Перевести на русский")
            .accessibilityIdentifier("role-translate")
        }
    }
}
