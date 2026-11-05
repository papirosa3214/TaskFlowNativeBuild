import SwiftUI

/// Заголовок раздела плоского экрана: ступень `.title` и `tfText`, как велит
/// `DESIGN.md` для секций. Системный заголовок `Section("…")` набирается своим
/// шрифтом, и на одном экране получался разнобой (владелец 05.11.2026).
public struct TFPlainSectionTitle: View {
    private let title: String

    public init(_ title: String) { self.title = title }

    public var body: some View {
        Text(title)
            .tfText(.title)
            .foregroundStyle(Color.tfText)
            .textCase(nil)
    }
}

/// Раздел плоского списка с единым заголовком.
public struct TFPlainSection<Content: View>: View {
    private let title: String
    private let content: Content

    public init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        Section { content } header: { TFPlainSectionTitle(title) }
    }
}

/// «Подпись — значение» одним кеглем. Системный `LabeledContent` набирает их
/// своим шрифтом и не даёт длинному значению переноситься по шкале приложения.
public struct TFInfoRow: View {
    private let label: String
    private let value: String
    private let valueColor: Color

    public init(label: String, value: String, valueColor: Color = .tfText) {
        self.label = label
        self.value = value
        self.valueColor = valueColor
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: TFSpacing.md) {
            Text(label).tfText(.body).foregroundStyle(Color.tfSub)
            Spacer(minLength: TFSpacing.sm)
            Text(value).tfText(.body).foregroundStyle(valueColor).multilineTextAlignment(.trailing)
        }
    }
}

/// Строка-действие без шеврона и отступов по бокам, для плоского экрана:
/// отступы задаёт сам экран или список.
public struct TFActionRow: View {
    private let title: String
    private let icon: String
    private let color: Color
    private let isEnabled: Bool
    private let action: () -> Void

    public init(title: String, icon: String, color: Color = .tfText, isEnabled: Bool = true,
                action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.color = color
        self.isEnabled = isEnabled
        self.action = action
    }

    public var body: some View {
        TFListRow(icon: icon, iconStyle: .plain, title: title, titleColor: color,
                  verticalPadding: TFSpacing.xs, horizontalPadding: 0, minHeight: 36,
                  chevron: .hidden, action: action)
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1 : 0.5)
    }
}
