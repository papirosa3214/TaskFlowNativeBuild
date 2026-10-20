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
    @ObservationIgnored private var failed: Set<String> = []

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
        texts.filter { translations[$0] == nil && !failed.contains($0) && isEnglish($0) }
    }

    func translate(_ texts: [String], with session: TranslationSession) async {
        let todo = Array(Set(untranslated(texts)))
        guard !todo.isEmpty else { return }
        let requests = todo.enumerated().map { index, text in
            TranslationSession.Request(sourceText: text, clientIdentifier: String(index))
        }
        do {
            for response in try await session.translations(from: requests) {
                guard let id = response.clientIdentifier, let index = Int(id) else { continue }
                translations[todo[index]] = response.targetText
            }
        } catch {
            // Нет языкового пакета или отказ — не дёргать переводчик снова.
            failed.formUnion(todo)
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
            }
            .onChange(of: "\(translator.isOn)|\(texts.count)", initial: true) { refresh() }
    }

    private func refresh() {
        guard translator.isOn, !translator.untranslated(texts).isEmpty else { return }
        if configuration == nil {
            configuration = .init(source: Locale.Language(identifier: "en"), target: Locale.Language(identifier: "ru"))
        } else {
            configuration?.invalidate()
        }
    }
}

/// Переключатель над окном хода роли: виден всегда — английский может
/// прийти в любую минуту, а окно прокручено к свежим действиям.
struct RoleTranslateSwitch: View {
    private var translator: RoleTranslator { .shared }

    var body: some View {
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
