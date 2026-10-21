import Foundation

/// Экран — лишь представление звонка. Свернуть не означает завершить.
struct SecretaryVoicePresentation: Equatable {
    private(set) var chatID: String?
    private(set) var isExpanded = false

    var isActive: Bool { chatID != nil }

    /// true только для нового подключения. Повторный вход раскрывает текущий звонок.
    mutating func begin(chatID: String) -> Bool {
        isExpanded = true
        guard self.chatID == nil else { return false }
        self.chatID = chatID
        return true
    }

    mutating func minimize() { isExpanded = false }
    mutating func expand() { if isActive { isExpanded = true } }
    mutating func end() { chatID = nil; isExpanded = false }
}
