import SwiftUI

// Нижняя шторка — spec/DESIGN-TOKENS.md §4 «Нижняя шторка». Реализована как
// `View`-модификатор поверх `.sheet`, чтобы экраны волны 2 подключали её одной
// строкой (`.tfBottomSheet(isPresented:) { ... }`), не пересобирая вёрстку сами.
//
// На native `.presentationDetents`/`.presentationCornerRadius` уже дают часть
// эффекта нативно (скрим, драг вниз для закрытия) — здесь докручиваем то, что
// спека требует явно: верхние углы 20px, хендл 36×4, шапка с крестиком слева.
public struct TFBottomSheetContent<Content: View>: View {
    let title: String?
    let actionTitle: String?
    let action: (() -> Void)?
    let onClose: () -> Void
    let content: Content

    public init(
        title: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        onClose: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.actionTitle = actionTitle
        self.action = action
        self.onClose = onClose
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Свой хендл убран 09.09.2026 — рисовался поверх спрятанного
            // системного и был просто картинкой: тянуть шторку между
            // половинным и полным состоянием он не умел. Теперь родной,
            // включается в модификаторе ниже.
            Color.clear.frame(height: TFSpacing.sm)

            if title != nil || actionTitle != nil {
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: TFIconSize.sm))
                            .foregroundStyle(Color.tfText)
                            .frame(width: TFSheet.headerCloseSize, height: TFSheet.headerCloseSize)
                    }
                    Spacer()
                    if let title {
                        Text(title).tfText(.title).foregroundStyle(Color.tfText)
                    }
                    Spacer()
                    if let actionTitle, let action {
                        Button(action: action) {
                            Text(actionTitle).tfText(.action).foregroundStyle(Color.tfSub)
                        }
                    } else {
                        Color.clear.frame(width: TFSheet.headerCloseSize)
                    }
                }
                .padding(.horizontal, TFSpacing.sm)
            }

            content
                .padding(.horizontal, TFSpacing.screenHorizontal)
        }
        .frame(maxWidth: .infinity)
        .background(Color.tfCard)
        .clipShape(.rect(topLeadingRadius: TFRadius.sheet, topTrailingRadius: TFRadius.sheet))
        .frame(maxWidth: TFSheet.maxWidthWide) // ≥1024px десктоп — не растягивается на всё окно; на телефоне уже уже экрана, эффекта нет
    }
}

public extension View {
    /// Подключает нижнюю шторку. Скрим — сплошной чёрный без блюра (спека), поэтому
    /// `.presentationBackground` на самой карточке, а не системный материал.
    func tfBottomSheet<SheetContent: View>(
        isPresented: Binding<Bool>,
        title: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> SheetContent
    ) -> some View {
        self.sheet(isPresented: isPresented) {
            TFBottomSheetContent(title: title, actionTitle: actionTitle, action: action, onClose: {
                isPresented.wrappedValue = false
            }, content: content)
            // Детентов не было вовсе — шторка распахивалась сразу на весь
            // экран, тогда как карточка задачи и остальные открываются
            // наполовину. Владелец 09.09.2026 про перенос по свайпу: «ведёт
            // себя не совсем так, как системные окна, сделай как обычное».
            // Правка общая: её видят все семь шторок, подключённых этим
            // модификатором (настройки, иконка приложения, статистика чата,
            // фильтры активности, задачи из текста заметки, перенос).
            .presentationDetents([.medium, .large])
            // И хендл теперь родной, а не нарисованный поверх спрятанного:
            // системный умеет то, чего свой не умеет — тянет между детентами.
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(TFRadius.sheet)
            .presentationBackground(Color.tfSheetBackground)
        }
    }
}

#Preview("Нижняя шторка") {
    TFBottomSheetContent(title: "Удалить задачу?", onClose: {}) {
        VStack(alignment: .leading, spacing: TFSpacing.md) {
            Text("«Старт нового проекта» будет удалена безвозвратно")
                .tfText(.body)
                .foregroundStyle(Color.tfSub)
            TFButton("Удалить", variant: .primary) {}
            TFButton("Отмена", variant: .secondary) {}
        }
        .padding(.bottom, TFSpacing.xl)
    }
    .background(Color.tfBackground)
}
