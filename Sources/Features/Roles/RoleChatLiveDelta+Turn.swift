import Foundation

/// Ход, собранный из дельт, — в ту же модель, из которой экран рисует
/// живой ход по старому полному снимку (владелец 27.10.2026).
extension RoleChatLiveTurnState {
    var liveTurn: RoleChatLiveTurn {
        for item in items { item.registerCurrentBlocks() }
        return RoleChatLiveTurn(chatID: chatID, userID: userID, name: name, startedAt: startedAt,
                                items: items.map(\.liveItem), thinking: thinking, triggerMessageID: triggerMessageID)
    }
}

extension TaskLiveTurn {
    /// Ход шага, собранный из дельт `tasks:live:*`: turn_id — прогон,
    /// chat_id — задача.
    init(state: RoleChatLiveTurnState, complete: Bool) {
        self.init(taskID: state.chatID, subtaskID: state.subtaskID, runID: state.turnID,
                  complete: complete, turn: state.liveTurn)
    }
}

extension RoleChatLiveDeltaItem {
    var liveItem: RoleChatLiveItem {
        switch kind {
        case .text:
            return .text(text)
        case .thinking:
            return .thinking(RoleChatThinking(id: id, text: text, isRunning: status != "done",
                                              startedAt: startedAt, endedAt: endedAt))
        case .step:
            var step = RoleChatLiveStep(id: id, tool: tool ?? "", detail: detail,
                                        status: RoleChatLiveStep.Status(rawValue: status ?? "running") ?? .running,
                                        startedAt: startedAt, endedAt: endedAt)
            step.args = args
            step.output = output
            return .step(step)
        }
    }

    /// Блоки сервера — в тот же реестр, что и при полном снимке, но только
    /// если они относятся к нынешнему тексту; иначе экран разбирает сам.
    ///
    /// Вызывается на каждую дельту для всех пунктов хода, поэтому сначала
    /// дешёвые проверки: пункт без текущих блоков или уже зарегистрированный
    /// (текст не менялся) не кодируется. JSON-перекодирование — только для
    /// нового или изменившегося пункта.
    func registerCurrentBlocks() {
        guard ChatLiveBlockRegistry.shared.blocks(for: text) == nil,
              let blocks = currentBlocks,
              let data = try? JSONEncoder().encode(blocks),
              let list = try? JSONDecoder().decode([ChatLiveBlock].self, from: data), !list.isEmpty else { return }
        ChatLiveBlockRegistry.shared.register(list, for: text)
    }
}
