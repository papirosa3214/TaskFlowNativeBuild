/// Подписка экрана на общий сокет приложения.
///
/// Экран подписывается при появлении и отписывается при уходе, а сам сокет не
/// трогает: он один на приложение. `.task` срабатывает при каждом возврате
/// на экран, поэтому повторная подписка заменяет прежнюю, иначе событие
/// приходило бы дважды.
struct RealtimeObserverSlot<Token> {
    private var token: Token?

    var isActive: Bool { token != nil }

    mutating func replace(add: () -> Token, remove: (Token) -> Void) {
        clear(remove: remove)
        token = add()
    }

    mutating func clear(remove: (Token) -> Void) {
        guard let token else { return }
        remove(token)
        self.token = nil
    }
}
