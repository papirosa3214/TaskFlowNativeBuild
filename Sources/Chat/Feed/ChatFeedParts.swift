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

/// Размер превью в ленте. Заглушка и готовая картинка одной высоты — иначе
/// UITableView.automaticDimension прыгает после downloadAttachment.
enum ChatAttachmentPreviewLayout {
    static let width: CGFloat = 220
    static let height: CGFloat = 140
}

/// Картинка-вложение: грузит сама, по id через API. Пока грузится — заглушка,
/// не загрузилась — чип с именем файла вместо битой картинки.
struct ChatAttachmentImage: View {
    let attachmentId: String
    let fileName: String
    @State private var uiImage: UIImage?
    @State private var failed = false
    @Environment(\.displayScale) private var displayScale
    private let api = APIClient()

    /// Длинная сторона миниатюры: размер показа × scale экрана.
    private var pixelSize: Int {
        ChatThumbnailCache.maxPixelSize(width: ChatAttachmentPreviewLayout.width,
                                        height: ChatAttachmentPreviewLayout.height,
                                        scale: displayScale)
    }

    var body: some View {
        // Повторный показ берёт миниатюру из кэша синхронно — без заглушки.
        let shown = uiImage ?? ChatThumbnailCache.cachedImage(id: attachmentId, maxPixelSize: pixelSize)
        Group {
            if let uiImage = shown {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if failed {
                ChatFileChip(fileName: fileName)
            } else {
                Color.tfCard2
                    .overlay { ProgressView() }
            }
        }
        .frame(width: ChatAttachmentPreviewLayout.width, height: ChatAttachmentPreviewLayout.height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.xl))
        .task {
            guard uiImage == nil else { return }
            let size = pixelSize
            if let cached = ChatThumbnailCache.cachedImage(id: attachmentId, maxPixelSize: size) {
                uiImage = cached
                return
            }
            do {
                let data = try await api.downloadAttachment(id: attachmentId)
                let image = await ChatThumbnailCache.thumbnail(from: data, id: attachmentId, maxPixelSize: size)
                uiImage = image.map { UIImage(cgImage: $0) }
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
        TFPill(surface: .tfCard2, radius: TFRadius.lg) {
            HStack(spacing: TFSpacing.sm) {
                Image(systemName: "paperclip")
                    .tfText(.action)
                    .foregroundStyle(Color.tfSub)
                Text(fileName)
                    .tfText(.meta)
                    .foregroundStyle(Color.tfChatText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, TFSpacing.md)
            .frame(height: TFHitTarget.min)
            .frame(maxWidth: 220, alignment: .leading)
        }
    }
}
