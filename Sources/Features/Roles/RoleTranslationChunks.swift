import Foundation

/// Куски текста для системного переводчика и сборка показа.
///
/// Владелец 08.11.2026: «текста одно предложение и вообще полдня оно
/// переводится». Причина — в переводчик уходил весь текст реплики или
/// размышления одним запросом, а показ ждал последнего куска. Здесь текст
/// режется на короткие куски: каждый кусок переводится отдельно и кэшируется
/// по своему тексту, показ подставляет готовые куски по порядку и не ждёт
/// остальных. Нарезка детерминирована — одинаковый текст всегда даёт
/// одинаковые куски, иначе кэш никогда бы не совпал.
enum RoleTranslationChunks {
    /// Сколько знаков отправляем переводчику за один запрос: примерно абзац
    /// или два-три предложения. Короче — быстрее первый кусок, но больше
    /// накладных расходов на запрос.
    static let chunkLimit = 300

    /// Текст, порезанный на куски. Склейка `of(text).joined()` всегда равна
    /// исходному тексту знак в знак.
    static func of(_ text: String, limit: Int = RoleTranslationChunks.chunkLimit) -> [String] {
        guard !text.isEmpty else { return [] }
        let bound = max(1, limit)
        let lines = text.components(separatedBy: "\n")
        var chunks: [String] = []
        var current = ""
        for (index, line) in lines.enumerated() {
            // Перевод строки держим в конце строки — тогда склейка кусков
            // возвращает текст без потерь.
            let piece = index == lines.count - 1 ? line : line + "\n"
            for unit in units(of: piece, limit: bound) {
                if !current.isEmpty, current.count + unit.count > bound {
                    chunks.append(current)
                    current = ""
                }
                current += unit
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    /// Что показать вместо оригинала: готовые куски — переводом, остальное —
    /// как есть. Пустой перевод в начале не подменяет текст целиком.
    static func shown(_ text: String, translations: [String: String],
                      limit: Int = RoleTranslationChunks.chunkLimit) -> String {
        shown(text, translations: translations, chunks: of(text, limit: limit))
    }

    /// То же, когда куски уже нарезаны (экран кэширует нарезку).
    static func shown(_ text: String, translations: [String: String], chunks: [String]) -> String {
        guard !text.isEmpty, !chunks.isEmpty else { return text }
        var result = ""
        var index = 0
        while index < chunks.count, let translated = translations[chunks[index]] {
            result += translated
            index += 1
        }
        guard index < chunks.count else { return result }
        return result + chunks[index...].joined()
    }

    /// Режем длинную строку по словам: кусок закрывается перед словом, которое
    /// уже не влезает в предел. Одно слово длиннее предела режется по знакам.
    private static func units(of piece: String, limit: Int) -> [String] {
        guard piece.count > limit else { return [piece] }
        // Слова вместе с пробелами в конце — склейка остаётся точной.
        var words: [String] = []
        var word = ""
        for character in piece {
            word.append(character)
            if character == " " {
                words.append(word)
                word = ""
            }
        }
        if !word.isEmpty { words.append(word) }

        var units: [String] = []
        var current = ""
        for word in words {
            if !current.isEmpty, current.count + word.count > limit {
                units.append(current)
                current = ""
            }
            current += word
            if current.count > limit {
                units.append(contentsOf: hardCut(current, limit: limit))
                current = ""
            }
        }
        if !current.isEmpty { units.append(current) }
        return units
    }

    private static func hardCut(_ text: String, limit: Int) -> [String] {
        var chunks: [String] = []
        var rest = Substring(text)
        while rest.count > limit {
            let end = rest.index(rest.startIndex, offsetBy: limit)
            chunks.append(String(rest[rest.startIndex..<end]))
            rest = rest[end...]
        }
        if !rest.isEmpty { chunks.append(String(rest)) }
        return chunks
    }
}
