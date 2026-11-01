import SwiftUI

// Пустое состояние — обёртка над штатным `ContentUnavailableView` (iOS 17+).
// Старый кастом был скопией того, что iOS делает сам; обёртка оставлена,
// потому что общий API (`icon`/`text`/`action`) привычнее, чем разные формы
// `ContentUnavailableView`. Внутри — штатный вид в двух формах: обычная
// (свои заголовок, описание и действие) и форма поиска
// (`TFEmptyState(search:)`) — обе через этот же компонент.
public struct TFEmptyState: View {
    /// Форма пустого состояния. Обычная — со своим заголовком и описанием;
    /// `.search` — системная форма «поиск ничего не нашёл», где заголовок и
    /// подпись берёт сама система (было `ContentUnavailableView.search`).
    public enum Variant { case standard, search }

    let variant: Variant
    let icon: String?
    let text: String
    let description: String?
    let actionTitle: String?
    let action: (() -> Void)?

    public init(
        icon: String? = nil,
        text: String,
        description: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.variant = .standard
        self.icon = icon
        self.text = text
        self.description = description
        self.actionTitle = actionTitle
        self.action = action
    }

    /// Пустое состояние поиска: тот же системный вид, что был у
    /// `ContentUnavailableView.search(text:)`, но через канон — отдельного
    /// компонента для этого заводить нельзя.
    public init(search query: String) {
        self.variant = .search
        self.icon = nil
        self.text = query
        self.description = nil
        self.actionTitle = nil
        self.action = nil
    }

    public var body: some View {
        let img = icon ?? "tray"
        if variant == .search {
            ContentUnavailableView.search(text: text)
        } else if let actionTitle, let action {
            ContentUnavailableView {
                Label(text, systemImage: img)
            } description: {
                if let description {
                    Text(description)
                }
            } actions: {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(.tfRed)
            }
        } else if description != nil {
            ContentUnavailableView {
                Label(text, systemImage: img)
            } description: {
                if let description {
                    Text(description)
                }
            }
        } else if icon != nil {
            ContentUnavailableView(text, systemImage: img)
        } else {
            ContentUnavailableView(text, systemImage: "tray")
        }
    }
}

#Preview("Пустое состояние") {
    VStack(spacing: TFSpacing.xl) {
        TFEmptyState(icon: "magnifyingglass", text: "Начните вводить, чтобы найти задачи, проекты и метки")
        TFEmptyState(text: "Под выбранные фильтры ничего не подошло", actionTitle: "Сбросить фильтры") {}
        TFEmptyState(search: "команда")
    }
    .padding(.top, 60)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.tfBackground)
}
