import Foundation
import Observation
import SwiftUI

/// Живые ходы ролей и их дельты — отдельно от экрана комнаты.
///
/// Зачем (владелец 06.11.2026: «вынести живой ход в отдельную вью со своим
/// состоянием»). Раньше ходы жили в `@State` экрана, и каждая порция ответа
/// (дельты идут каждые ~150 мс) перерисовывала экран целиком: ленту, все
/// видимые сообщения, поле ввода. Теперь экран при отрисовке читает только то,
/// что меняется редко, — «паспорта» ходов (`slots`), признак «роль отвечает»
/// и строку «печатает». Текст хода (`turns`) читает только строка хода
/// (`RoleChatLiveSlotView`), и порция ответа перерисовывает только её.
///
/// Производные значения записываются, только когда действительно меняются:
/// запись того же значения в наблюдаемое свойство всё равно будит читателей.
@MainActor
@Observable
final class RoleChatLiveStore {
    /// Идущие ходы: userID → снимок хода. Меняется на каждую порцию ответа.
    /// Строки ходов читают не его, а свой `turnBox(for:)`: дельта одной роли
    /// будит только её строку, а не строки всех ролей.
    var turns: [String: RoleChatLiveTurn] = [:] {
        didSet { syncBoxes(); refreshTurnDerived() }
    }

    /// Наблюдаемый ход одной роли: userID → ячейка. Сам словарь не
    /// наблюдается — ячейка создаётся при первом чтении и живёт, пока есть ход.
    @ObservationIgnored private var boxes: [String: RoleChatLiveTurnBox] = [:]

    /// Ход дельтами: userID → состояние. Меняется на каждую порцию ответа.
    var deltas: [String: RoleChatLiveTurnState] = [:] {
        didSet { refreshActivity() }
    }

    /// Паспорта всех идущих ходов (и невидимых тоже — фильтрует лента).
    private(set) var slots: [RoleChatLiveSlot] = []
    /// Есть хоть один идущий ход.
    private(set) var hasTurns = false
    /// Сообщения, на которые сейчас отвечают роли.
    private(set) var triggerIDs: Set<String> = []
    /// Роли с активностью по дельтам: userID → имя для строки «печатает».
    private(set) var activityNames: [String: String] = [:]
    /// Роли, работающие инструментом: userID → инструмент.
    private(set) var activityTools: [String: String] = [:]

    /// `turns` — начальные ходы (отладочные предпросмотры экрана).
    init(turns: [String: RoleChatLiveTurn] = [:]) {
        self.turns = turns
        refreshTurnDerived()
    }

    /// Ячейка хода роли — читатель подписывается только на неё.
    func turnBox(for userID: String) -> RoleChatLiveTurnBox {
        if let box = boxes[userID] { return box }
        let box = RoleChatLiveTurnBox(turn: turns[userID])
        boxes[userID] = box
        return box
    }

    /// Ход роли с подпиской только на него.
    func turn(for userID: String) -> RoleChatLiveTurn? {
        turnBox(for: userID).turn
    }

    /// Разносит изменения словаря по ячейкам: пишется только изменившийся ход.
    private func syncBoxes() {
        for (userID, box) in boxes {
            let new = turns[userID]
            if new != box.turn { box.turn = new }
            if new == nil { boxes[userID] = nil }
        }
    }

    static func slot(for turn: RoleChatLiveTurn) -> RoleChatLiveSlot {
        RoleChatLiveSlot(
            userID: turn.userID,
            playbackID: turn.playbackID,
            startedAt: turn.startedAt,
            startDate: turn.startDate,
            triggerMessageID: turn.triggerMessageID,
            isVisible: !turn.items.isEmpty || turn.thinking != nil
        )
    }

    private func refreshTurnDerived() {
        let newSlots = turns.values.map(Self.slot(for:)).sorted { $0.playbackID < $1.playbackID }
        if newSlots != slots { slots = newSlots }
        let has = !turns.isEmpty
        if has != hasTurns { hasTurns = has }
        let triggers = Set(turns.values.compactMap(\.triggerMessageID))
        if triggers != triggerIDs { triggerIDs = triggers }
    }

    private func refreshActivity() {
        var names: [String: String] = [:]
        var tools: [String: String] = [:]
        for (userID, state) in deltas {
            guard let activity = state.activity else { continue }
            names[userID] = state.name.isEmpty ? "Участник" : state.name
            if case .tool(let tool) = activity { tools[userID] = tool }
        }
        if names != activityNames { activityNames = names }
        if tools != activityTools { activityTools = tools }
    }
}

/// Ход одной роли — отдельный наблюдаемый объект, чтобы порция ответа одной
/// роли не будила строки других.
@MainActor
@Observable
final class RoleChatLiveTurnBox {
    var turn: RoleChatLiveTurn?

    init(turn: RoleChatLiveTurn?) {
        self.turn = turn
    }
}

/// Строка живого хода: текст хода читает она сама, а не экран комнаты, —
/// поэтому порция ответа перерисовывает только её.
struct RoleChatLiveSlotView<Content: View>: View {
    let store: RoleChatLiveStore
    let slot: RoleChatLiveSlot
    /// Ход уже закончился и доигрывает ответ — он живёт не в `store.turns`.
    /// Рисуется той же вью, что и идущий: иначе пузырь пересоздаётся, и
    /// недопечатанный текст выпадает разом.
    var completing: RoleChatLiveTurn? = nil
    @ViewBuilder let content: (RoleChatLiveTurn) -> Content

    var body: some View {
        if let turn = Self.turn(completing: completing, live: store.turn(for: slot.userID), slot: slot) {
            content(turn)
        }
    }

    /// Какой ход рисовать в строке: доигрывающий, иначе идущий того же хода.
    static func turn(completing: RoleChatLiveTurn?, live: RoleChatLiveTurn?,
                     slot: RoleChatLiveSlot) -> RoleChatLiveTurn? {
        if let completing, completing.playbackID == slot.playbackID { return completing }
        if let live, live.playbackID == slot.playbackID { return live }
        return nil
    }
}
