import SwiftUI

// Мелочи ленты, которые пережили удаление старого чата: точки «печатает…» и
// вложения. Раньше они лежали в `TypingLine.swift` и `ChatBubble.swift` —
// вместе с мёртвым экраном. Теперь живут отдельно: ими пользуются живой чат
// ролей (`RoleChatsScreen`) и карточка задачи (`TaskFormScreen`).

/// Точка «печатает…» с анимацией (spec/DESIGN-TOKENS.md §5: период 1.2 с,
/// сдвиг фазы 0.2 с на точку).
struct TypingDot: View {
    let delay: Double
    @State private var lit = false

    var body: some View {
        Circle()
            .fill(Color.tfSub)
            .frame(width: 4, height: 4)
            .opacity(lit ? 1 : 0.25)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: TFAnimation.typingDotPeriod / 2)
                        .repeatForever(autoreverses: true)
                        .delay(delay)
                ) {
                    lit = true
                }
            }
    }
}

/// Картинка-вложение: грузит сама, по id через API. Пока грузится — заглушка,
/// не загрузилась — чип с именем файла вместо битой картинки.
struct ChatAttachmentImage: View {
    let attachmentId: String
    let fileName: String
    @State private var uiImage: UIImage?
    @State private var failed = false
    private let api = APIClient()

    var body: some View {
        Group {
            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if failed {
                ChatFileChip(fileName: fileName)
            } else {
                Color.tfCard2
                    .frame(height: 140)
                    .overlay { ProgressView() }
            }
        }
        .frame(maxWidth: 220)
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.xl))
        .task {
            guard uiImage == nil else { return }
            do {
                let data = try await api.downloadAttachment(id: attachmentId)
                uiImage = UIImage(data: data)
                if uiImage == nil { failed = true }
            } catch {
                failed = true
            }
        }
    }
}

/// Файл-не-картинка — чип со скрепкой и именем (веб: `bg-card2 h-9 px-3`).
struct ChatFileChip: View {
    let fileName: String
    var body: some View {
        HStack(spacing: TFSpacing.sm) {
            Image(systemName: "paperclip")
                .tfText(.action)
                .foregroundStyle(Color.tfSub)
            Text(fileName)
                .tfText(.meta)
                .foregroundStyle(Color.tfText)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, TFSpacing.md)
        .frame(height: TFHitTarget.min)
        .frame(maxWidth: 220, alignment: .leading)
        .background(Color.tfCard2)
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
    }
}
