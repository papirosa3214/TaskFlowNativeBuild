import Foundation

/// Потокобезопасный кэш разобранных значений по строковому ключу.
///
/// Нужен там, где модель разбирает один и тот же текст на каждом проходе
/// `body`: JSON-конверт роли, разобранный markdown, дерево заметок. Ключ —
/// сам разбираемый текст, значение — готовый результат. Размер ограничен,
/// чтобы кэш не рос вместе с историей; при переполнении уходит запись,
/// которую дольше всех не читали (LRU), — горячие куски идущего ответа
/// не вытесняются случайно.
final class ParsedValueCache<Value>: @unchecked Sendable {
    private let lru: LRUCache<String, Value>

    init(limit: Int = 64) {
        lru = LRUCache(limit: limit)
    }

    func value(for key: String) -> Value? { lru.value(for: key) }

    func set(_ value: Value, for key: String) { lru.set(value, for: key) }
}

/// Потокобезопасный LRU-кэш с любым `Hashable`-ключом. Чтение и запись —
/// O(1): записи связаны двусвязным списком по давности использования.
final class LRUCache<Key: Hashable, Value>: @unchecked Sendable {
    private final class Node {
        let key: Key
        var value: Value
        var prev: Node?
        var next: Node?
        init(key: Key, value: Value) { self.key = key; self.value = value }
    }

    private let limit: Int
    private var storage: [Key: Node] = [:]
    /// Самая свежая запись.
    private var head: Node?
    /// Самая давняя — кандидат на вытеснение.
    private var tail: Node?
    private let lock = NSLock()

    init(limit: Int = 64) {
        self.limit = max(1, limit)
    }

    func value(for key: Key) -> Value? {
        lock.withLock {
            guard let node = storage[key] else { return nil }
            moveToFront(node)
            return node.value
        }
    }

    func set(_ value: Value, for key: Key) {
        lock.withLock {
            if let node = storage[key] {
                node.value = value
                moveToFront(node)
                return
            }
            let node = Node(key: key, value: value)
            storage[key] = node
            insertFront(node)
            if storage.count > limit, let victim = tail {
                unlink(victim)
                storage.removeValue(forKey: victim.key)
            }
        }
    }

    private func insertFront(_ node: Node) {
        node.prev = nil
        node.next = head
        head?.prev = node
        head = node
        if tail == nil { tail = node }
    }

    private func unlink(_ node: Node) {
        node.prev?.next = node.next
        node.next?.prev = node.prev
        if head === node { head = node.next }
        if tail === node { tail = node.prev }
        node.prev = nil
        node.next = nil
    }

    private func moveToFront(_ node: Node) {
        guard head !== node else { return }
        unlink(node)
        insertFront(node)
    }
}
