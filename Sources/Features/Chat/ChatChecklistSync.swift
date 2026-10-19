import Foundation
import Observation

/// Ключи отметки — ровно те, что понимает сервер
/// (`server/src/lib/chatChecklist.ts`): `key`/`id` из блока, иначе номер
/// строкой. Клиент ничего не изобретает — у него уже разобран блок.
enum ChecklistKey {
    /// Ключ пункта: `key`/`id` из блока, иначе его номер строкой.
    static func item(_ item: WidgetData, index: Int) -> String {
        item.string("key") ?? item.string("id") ?? "\(index)"
    }

    /// Ключ блока: `id`/`key` из виджета, иначе его номер в сообщении —
    /// тот же порядок, каким сервер считает блоки.
    static func widget(_ widget: WidgetData, position: String?) -> String {
        widget.string("id") ?? widget.string("key") ?? widget.string("widget_id")
            ?? position ?? "0"
    }
}

/// Что виджету нужно, чтобы отметка доехала до сервера: чат, сообщение,
/// сохранённое состояние и сама отправка. Собирается на экране чата.
struct ChecklistSyncContext {
    let chatID: String
    let messageID: String
    /// Что сервер знал на момент чтения ленты — с этого начинаем рисовать.
    let seed: [ChecklistItemState]
    let send: @Sendable (ChecklistItemState) async throws -> [ChecklistItemState]
}

/// Отметки пунктов checklist-виджета одного сообщения.
///
/// Показываем сразу (отметка не должна ждать сеть), а источник истины —
/// сервер: его ответ приносит состояние всего сообщения, а не только
/// нажатого пункта. Отказ не остаётся незамеченным: пункт возвращается в
/// прежнее состояние, рядом появляется честный текст.
@MainActor
@Observable
final class ChecklistMessageSync {
    /// Текст последнего отказа; nil — отметка сохранена.
    private(set) var failure: String?
    private var serverState: [ChecklistItemState]
    /// Нажатия, ещё не подтверждённые сервером.
    private var pending: [String: Bool] = [:]
    private let send: (ChecklistItemState) async throws -> [ChecklistItemState]

    init(seed: [ChecklistItemState],
         send: @escaping (ChecklistItemState) async throws -> [ChecklistItemState]) {
        serverState = seed
        self.send = send
    }

    /// Что рисовать: нажатие → сервер → сохранённое сервером → блок виджета.
    func done(widgetKey: String, itemKey: String, inBlock blockDone: Bool) -> Bool {
        if let pressed = pending[Self.slot(widgetKey, itemKey)] { return pressed }
        return entry(widgetKey: widgetKey, itemKey: itemKey)?.done ?? blockDone
    }

    /// Отметка или снятие отметки. `done: false` — такая же честная запись.
    func toggle(widgetKey: String, itemKey: String, to done: Bool) async {
        let slot = Self.slot(widgetKey, itemKey)
        pending[slot] = done
        failure = nil
        do {
            apply(try await send(
                ChecklistItemState(widgetKey: widgetKey, itemKey: itemKey, done: done)
            ))
            pending.removeValue(forKey: slot)
        } catch {
            pending.removeValue(forKey: slot)
            failure = Self.reason(for: error)
        }
    }

    /// Состояние всего сообщения с сервера — источник истины: ответ на отметку
    /// приносит и другие пункты этого сообщения.
    func apply(_ state: [ChecklistItemState]) {
        serverState = state
    }

    private func entry(widgetKey: String, itemKey: String) -> ChecklistItemState? {
        serverState.first { $0.widgetKey == widgetKey && $0.itemKey == itemKey }
    }

    /// Ключ пункта внутри виджета, а не просто item_key: у двух блоков в одном
    /// сообщении пункты с одинаковым ключом — разные отметки.
    private static func slot(_ widgetKey: String, _ itemKey: String) -> String {
        "\(widgetKey)\u{1F}\(itemKey)"
    }

    /// Отказ различаем, а не прячем: 400 — блок в сообщении переписан, отметка
    /// не записана (надо перечитать сообщение); 404 — не нашлись чат или
    /// сообщение. И то и другое сообщаем прямо под виджетом.
    static func reason(for error: Error) -> String {
        guard let api = error as? APIError else { return error.localizedDescription }
        switch api {
        case .server(let status, _) where status == 400:
            return "Виджет в сообщении переписан — отметка не сохранена"
        case .notFound, .routeMissing:
            return "Сообщение или чат не найдены — отметка не сохранена"
        default:
            return api.localizedDescription
        }
    }
}
