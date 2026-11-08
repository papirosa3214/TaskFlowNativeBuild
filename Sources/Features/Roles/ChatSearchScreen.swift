import SwiftUI

/// Поиск по всем чатам сразу (владелец 08.11.2026: «а поиск бы обязательно ещё
/// бы сделал»). Один поиск на все роли, групповые комнаты и архив: ищется
/// название комнаты, имя собеседника и текст переписки — что нашлось, то и
/// открывается.
struct ChatSearchScreen: View {
    @Environment(\.openRoute) private var openRoute
    @State private var query = ""
    @State private var results: [ChatSearchHit] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    private let api = APIClient()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                TFErrorBanner(errorMessage, variant: .inline)
                if query.trimmingCharacters(in: .whitespaces).count < 2 {
                    TFEmptyState(icon: "magnifyingglass", text: "Начните вводить — ищем по названию, участнику и тексту")
                        .padding(.horizontal, TFSpacing.screenHorizontal)
                        .padding(.top, TFSpacing.xl)
                } else if results.isEmpty && !isSearching {
                    TFEmptyState(icon: "magnifyingglass", text: "Ничего не нашлось")
                        .padding(.horizontal, TFSpacing.screenHorizontal)
                        .padding(.top, TFSpacing.xl)
                } else {
                    ForEach(results) { hit in
                        Button { openRoute?(.roleChat(id: hit.chatID)) } label: {
                            TFListRow(
                                icon: "bubble.left.and.bubble.right",
                                iconStyle: .plain,
                                title: hit.title,
                                subtitle: hit.subtitle,
                                titleStyle: .body,
                                verticalPadding: TFSpacing.xs,
                                chevron: .shown
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("search.hit.\(hit.chatID)")
                        TFDivider(inset: TFSpacing.screenHorizontal)
                    }
                }
            }
            .padding(.bottom, TFSpacing.xl)
        }
        .tfScreenBackground()
        .tfNativeHeader("Поиск")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Поиск по чатам")
        // Живой поиск: пауза в наборе — запрос. Запросы не обгоняют друг друга,
        // ответ применяется только для последнего введённого текста.
        .task(id: query) {
            let text = query.trimmingCharacters(in: .whitespaces)
            guard text.count >= 2 else {
                results = []
                return
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            isSearching = true
            defer { isSearching = false }
            do {
                let found = try await api.chatSearch(query: text)
                guard !Task.isCancelled else { return }
                results = found
                errorMessage = nil
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Строка выдачи: что нашли и в каком месте переписки.
public struct ChatSearchHit: Identifiable, Decodable, Sendable {
    public let chatID: String
    public let title: String
    public let subject: String?
    public let hitText: String?

    public var id: String { chatID }

    public enum CodingKeys: String, CodingKey {
        case chatID = "chat_id"
        case title
        case subject
        case hitText = "hit_text"
    }

    public var subtitle: String {
        if let hit = hitText, !hit.isEmpty { return hit }
        if let subject, !subject.isEmpty { return subject }
        return "Чат"
    }
}

public struct ChatSearchEnvelope: Decodable, Sendable {
    public let results: [ChatSearchHit]
}
