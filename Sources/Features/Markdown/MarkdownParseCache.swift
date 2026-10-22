import Foundation

/// Кэш разбора Markdown — LOCK-OPT-PERF-20261022.
///
/// Один и тот же текст разбирается снова и снова: карточка задачи спрашивает
/// разбор у `Binding`-геттера (то есть на каждый проход экрана), чат — на
/// каждую перерисовку сообщения. Разбор стоит 0.08 мс на ответ роли
/// (замерено 22.10.2026 на этом же исходнике) и целиком уходит в цикл
/// перерисовки.
///
/// Кэш отдаёт ТОТ ЖЕ массив блоков для того же текста. Блоки — значимые
/// типы, поэтому правка на месте кэша не касается: Swift копирует массив при
/// первой мутации.
final class MarkdownParseCache {
    static let shared = MarkdownParseCache()

    /// Сколько разборов держим. Живут тексты ответов ролей, заголовки
    /// подзадач и абзацы заметок — их десятки, не тысячи.
    private let entryLimit = 128
    /// И общий объём текстов, чтобы кэш не раздувался на длинных документах.
    private let characterLimit = 256 * 1024

    private struct Entry {
        let blocks: [NoteBlock]
        let characters: Int
        var stamp: UInt64
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private var stamp: UInt64 = 0
    private var storedCharacters = 0

    /// Разбор текста с кэшем: тот же текст — тот же результат.
    func blocks(for source: String, parse: () -> [NoteBlock]) -> [NoteBlock] {
        lock.lock()
        if var entry = entries[source] {
            stamp += 1
            entry.stamp = stamp
            entries[source] = entry
            lock.unlock()
            return entry.blocks
        }
        lock.unlock()

        let parsed = parse()

        lock.lock()
        stamp += 1
        let characters = source.count
        entries[source] = Entry(blocks: parsed, characters: characters, stamp: stamp)
        storedCharacters += characters
        evictIfNeeded()
        lock.unlock()
        return parsed
    }

    /// Вытесняем самые старые записи, пока не влезем в лимиты.
    private func evictIfNeeded() {
        while entries.count > entryLimit || storedCharacters > characterLimit {
            guard let oldest = entries.min(by: { $0.value.stamp < $1.value.stamp }) else { break }
            storedCharacters -= oldest.value.characters
            entries.removeValue(forKey: oldest.key)
        }
    }

    /// Сброс — только для тестов.
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
        storedCharacters = 0
    }
}
