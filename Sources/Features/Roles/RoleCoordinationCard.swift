import SwiftUI

/// Server events about a particular question; never infers model progress from time alone.
struct RoleCoordinationCard: View {
    let coordination: RoleChatCoordination
    let stop: () async throws -> Void
    /// Раскрытие живёт у экрана (`RoleFeedExpansion`), а не в `@State`
    /// строки: лента пересобирает строку на каждом событии обращения, и
    /// `DisclosureGroup` сам открывался и закрывался (владелец 11.11.2026,
    /// видео: «нездравое поведение у сообщений, которые роли шлют друг другу»).
    var isExpanded = false
    var onToggle: () -> Void = {}
    @State private var stopping = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            Button(action: onToggle) {
                HStack(alignment: .firstTextBaseline, spacing: TFSpacing.sm) {
                    VStack(alignment: .leading, spacing: TFSpacing.xs) {
                        Label(coordination.requesterName + " → " + coordination.recipientName,
                              systemImage: "person.2")
                        Text(coordination.activity).tfText(.meta)
                    }
                    // Шеврон рядом с подписью, как у пачки «Действия».
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right") // design-system-guard: ignore — раскрывающая пара, как в RoleActionGroup
                        .tfTypeFont(size: 12, weight: .semibold)
                        .foregroundStyle(Color.tfDim)
                }
                .frame(maxWidth: .infinity, minHeight: TFHitTarget.min, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isExpanded ? "Свернуть вопрос" : "Показать вопрос")
            if isExpanded {
                VStack(alignment: .leading, spacing: TFSpacing.sm) {
                    Text("Вопрос").tfText(.meta)
                    RoleReplyMarkdown(text: coordination.question, serverBlocks: coordination.questionBlocks).textSelection(.enabled)
                    if !coordination.isAnswered, let answer = coordination.answer, !answer.isEmpty {
                        Text(coordination.status == "error" ? "Причина ошибки" : "Ответ").tfText(.meta)
                        RoleReplyMarkdown(text: answer, serverBlocks: coordination.answerBlocks).textSelection(.enabled)
                    }
                }
            }
            // Ответ роли виден сразу, не под раскрытием (владелец 28.10.2026:
            // «хотелось бы, чтобы он выделялся, этот ответ»).
            if coordination.isAnswered, let answer = coordination.answer, !answer.isEmpty {
                GroupBox {
                    RoleReplyMarkdown(text: answer, serverBlocks: coordination.answerBlocks)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label("Ответ: " + coordination.recipientName, systemImage: "arrowshape.turn.up.left")
                }
            }
            if !coordination.terminal {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    if let started = date(coordination.createdAt) {
                        Text("Ожидание: \(Int(max(0, timeline.date.timeIntervalSince(started)))) с")
                            .tfText(.meta)
                    }
                    if let last = date(coordination.lastActivityAt), timeline.date.timeIntervalSince(last) >= 45 {
                        Text("Нет новых событий \(Int(timeline.date.timeIntervalSince(last))) с")
                            .tfText(.meta)
                    }
                }
                Button(stopping ? "Останавливаю…" : "Остановить обращение") {
                    guard !stopping else { return }
                    stopping = true
                    error = nil
                    Task {
                        defer { stopping = false }
                        do { try await stop() }
                        catch { self.error = error.localizedDescription }
                    }
                }
                .disabled(stopping)
            }
            if let error { Text(error).tfText(.meta) }
        }
        .padding(.vertical, TFSpacing.sm)
        .accessibilityIdentifier("chat.coordination")
    }

    private func date(_ value: String) -> Date? {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return parser.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
