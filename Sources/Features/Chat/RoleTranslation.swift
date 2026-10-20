import SwiftUI
import NaturalLanguage
import Translation

// Перевод ленты роли (владелец 20.10.2026): роли думают и пишут как им
// удобнее, обычно по-английски, а в ленте по кнопке показывается русский
// перевод. Переводит системный переводчик Apple на самом телефоне — без
// сервера и без токенов. Переводятся только реплики роли; шаги (команды,
// пути, имена инструментов) остаются как есть, иначе перевод их портит.

/// Общий для всех лент переводчик: включён ли перевод и что уже переведено.
@MainActor
@Observable
final class RoleTranslator {
    static let shared = RoleTranslator()
    /// Настройка «Переводить работу ролей сразу» в шторке «Чат».
    static let autoKey = "chat.autoTranslate"

    var isOn = UserDefaults.standard.bool(forKey: RoleTranslator.autoKey)
    private(set) var translations: [String: String] = [:]
    @ObservationIgnored private var englishCache: [String: Bool] = [:]
    /// Когда текст не удалось перевести. Не навсегда: окно скачивания языка
    /// могло закрыться на полуслове — через `retryAfter` пробуем снова.
    @ObservationIgnored private var failedAt: [String: Date] = [:]
    private static let retryAfter: TimeInterval = 30
    /// Идёт перевод (или окно скачивания языка) — новый не начинаем: иначе
    /// перезапуск закрывал окно скачивания, и оно мелькало (20.10.2026).
    @ObservationIgnored var isTranslating = false
    /// Диагностика для владельца (20.10.2026): на каком шаге перевод — строка
    /// рядом со значком, пока перевод включён.
    var status = ""

    static let english = Locale.Language(identifier: "en")
    static let russian = Locale.Language(identifier: "ru")

    /// Что система говорит о паре английский → русский.
    func checkLanguages() async {
        switch await LanguageAvailability().status(from: Self.english, to: Self.russian) {
        case .installed: status = "языки скачаны"
        case .supported: status = "языки: не скачаны — Настройки → Переводчик"
        case .unsupported: status = "языки: пара не поддерживается"
        @unknown default: status = "языки: неизвестный ответ"
        }
    }

    /// Что показать вместо текста: перевод, если он включён и уже готов.
    func display(_ text: String) -> String {
        isOn ? (translations[text] ?? text) : text
    }

    func isEnglish(_ text: String) -> Bool {
        if let known = englishCache[text] { return known }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let result = recognizer.dominantLanguage == .english
        englishCache[text] = result
        return result
    }

    func untranslated(_ texts: [String]) -> [String] {
        texts.filter { text in
            guard translations[text] == nil, isEnglish(text) else { return false }
            guard let failed = failedAt[text] else { return true }
            return Date().timeIntervalSince(failed) > Self.retryAfter
        }
    }

    func translate(_ texts: [String], with session: TranslationSession) async {
        let todo = Array(Set(untranslated(texts)))
        guard !todo.isEmpty else { return }
        isTranslating = true
        defer { isTranslating = false }
        status = "перевожу \(todo.count)"
        let requests = todo.enumerated().map { index, text in
            TranslationSession.Request(sourceText: text, clientIdentifier: String(index))
        }
        do {
            for response in try await session.translations(from: requests) {
                guard let id = response.clientIdentifier, let index = Int(id) else { continue }
                translations[todo[index]] = response.targetText
            }
            status = "переведено \(translations.count)"
        } catch {
            // Языковой пакет не скачан или окно закрыто — повторим позже.
            for text in todo { failedAt[text] = Date() }
            status = "ошибка: \(error.localizedDescription) [\(String(describing: error).prefix(80))]"
        }
    }
}

/// Держит сессию переводчика у ленты: как только появились непереведённые
/// английские реплики, переводит их пачкой.
struct RoleTranslationHost: ViewModifier {
    /// Законченные реплики; растущий текст идущего хода не переводим.
    let texts: [String]
    @State private var configuration: TranslationSession.Configuration?
    private var translator: RoleTranslator { .shared }

    func body(content: Content) -> some View {
        content
            .translationTask(configuration) { session in
                await translator.translate(texts, with: session)
                // Пока шёл перевод, лента могла вырасти — догоняем.
                if rerun { rerun = false; refresh() }
            }
            .onChange(of: "\(translator.isOn)|\(texts.count)", initial: true) { refresh() }
    }

    @State private var rerun = false

    private func refresh() {
        guard translator.isOn else { return }
        if !texts.contains(where: translator.isEnglish) {
            translator.status = "нечего переводить (\(texts.count) реплик, английских нет)"
            return
        }
        guard !translator.untranslated(texts).isEmpty else { return }
        Task { await translator.checkLanguages() }
        // Не перезапускать посреди перевода: это закрывало окно скачивания.
        if translator.isTranslating { rerun = true; return }
        if configuration == nil {
            configuration = .init(source: RoleTranslator.english, target: RoleTranslator.russian)
        } else {
            configuration?.invalidate()
        }
        // Если переводчик так и не позовёт задачу — это будет видно здесь.
        Task { try? await Task.sleep(for: .seconds(8)); if translator.status.hasPrefix("языки") { translator.status += " · жду переводчик" } }
    }
}

/// Переключатель над окном хода роли: виден всегда — английский может
/// прийти в любую минуту, а окно прокручено к свежим действиям.
struct RoleTranslateSwitch: View {
    private var translator: RoleTranslator { .shared }

    var body: some View {
        HStack(spacing: 0) {
            if translator.isOn, !translator.status.isEmpty {
                Text(translator.status)
                    .tfText(.caption)
                    .foregroundStyle(Color.tfDim)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
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
