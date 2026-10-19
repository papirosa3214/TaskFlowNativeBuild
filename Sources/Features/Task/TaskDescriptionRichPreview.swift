import SwiftUI

/// Описание карточки задачи в режиме чтения, когда в нём есть то, что
/// блочный редактор показал бы сырым текстом: таблицы, виджеты (```widget),
/// структурированные блоки (```tf-json) и артефакты (```html). Рисуется тем
/// же `RoleReplyMarkdown`, что и ответ роли в чате, — второго рендера нет.
struct TaskDescriptionRichPreview: View {
    let text: String

    static func hasRichContent(_ text: String) -> Bool {
        ChatRichContent.split(text, isStreaming: false).contains {
            if case .markdown = $0 { return false } else { return true }
        }
    }

    var body: some View {
        RoleReplyMarkdown(text: text)
    }
}
