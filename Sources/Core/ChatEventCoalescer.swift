import Foundation

/// Склейка событий сокета чата: всё, что пришло за `window`, применяется к
/// ленте одним обновлением, а не перекладывает её на каждом событии
/// (владелец 27.10.2026: «создать равномерную очередь и уже равномерно
/// подавать на телефон»). Окно короткое — на глаз задержки нет.
struct ChatEventCoalescer<Event> {
    static var window: Duration { .milliseconds(80) }
    private var pending: [Event] = []

    /// true — первое событие окна: вызывающий планирует `drain()` через `window`.
    mutating func enqueue(_ event: Event) -> Bool {
        pending.append(event)
        return pending.count == 1
    }

    mutating func drain() -> [Event] {
        defer { pending = [] }
        return pending
    }
}
