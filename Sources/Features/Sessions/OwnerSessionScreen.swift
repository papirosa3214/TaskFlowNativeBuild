import SwiftUI

/// Маршрут экрана сессии владельца. Свой тип, а не `AppRoute`: стек вкладки —
/// `NavigationPath`, а сессии пока живут за флагом в «Чате».
struct OwnerSessionRoute: Hashable {
    /// `nil` — новая сессия (`POST /api/sessions`).
    let id: String?
    let token = UUID()
}

/// Сессия владельца — обычный разговор с Помощником (владелец 12.11.2026:
/// «из помощника делать не роль, а просто обычные сессии… без всяких
/// очередей и процента»). Движок — из прототипа NewChatTF
/// (`Sources/Features/Sessions/Engine`), вид — наш: лента сообщений чата,
/// поле ввода `ChatVoiceComposer`, ответы Помощника блоками конверта.
/// Пока сессия отвечает, отправка подмешивает сообщение в ответ (`steer`),
/// «стоп» обрывает ответ.
struct OwnerSessionScreen: View {
    let route: OwnerSessionRoute

    @State private var model = SessionViewModel(apiClient: SessionAPIClient(), realtime: SessionRealtimeClient())
    @State private var voice = RoleChatVoiceController()
    @FocusState private var composerFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: TFSpacing.md) {
                    ForEach(model.timeline) { item in
                        OwnerSessionItemView(item: item)
                            .id(item.id)
                    }
                    if !model.state.transientAssistantText.isEmpty {
                        OwnerSessionReply(text: model.state.transientAssistantText, isStreaming: true)
                            .id(Self.liveID)
                    } else if model.isStreaming {
                        TFLoading(.inline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(Self.liveID)
                    }
                    if model.timeline.isEmpty && !model.isStreaming && !model.isLoading {
                        Text("Напишите, что нужно сделать.")
                            .tfText(.action)
                            .foregroundStyle(Color.tfDim)
                            .padding(.top, TFSpacing.xl)
                    }
                }
                .padding(.horizontal, TFSpacing.screenHorizontal)
                .padding(.vertical, TFSpacing.md)
            }
            .defaultScrollAnchor(.bottom)
            // Боковой ползунок прокрутки владельцу мешает (12.11.2026).
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.timeline.count) { _, _ in scrollToEnd(proxy) }
            .onChange(of: model.state.transientAssistantText) { _, _ in scrollToEnd(proxy) }
        }
        .safeAreaInset(edge: .bottom) { composer }
        .tfScreenBackground()
        .tfNativeHeader(model.activeSessionID == nil ? "Новый чат" : model.title, displayMode: .inline)
        .overlay {
            if model.isLoading && model.activeSessionID == nil { TFLoading(.block) }
        }
        .alert("Сессия", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("Понятно", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .task { await model.open(sessionID: route.id) }
        .onDisappear { model.disconnect() }
    }

    private static let liveID = "owner-session-live"

    private var composer: some View {
        ChatVoiceComposer(
            text: $model.composerText,
            placeholder: "Сообщение",
            sessionLook: true,
            canSendText: model.activeSessionID != nil
                && !model.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !model.isSendingCommand,
            voice: voice,
            onAttachmentSource: { _ in },
            onSendText: { Task { await model.send() } },
            onSendVoice: { _ in false },
            onDiscardVoice: { _ in },
            isResponding: model.isStreaming,
            onStop: { Task { await model.abort() } },
            focus: $composerFocused
        )
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        let target = model.state.transientAssistantText.isEmpty && !model.isStreaming
            ? model.timeline.last?.id
            : Self.liveID
        guard let target else { return }
        withAnimation(TFMotion.standard) { proxy.scrollTo(target, anchor: .bottom) }
    }
}

/// Одна запись ленты сессии: сообщение владельца, ответ Помощника или шаг
/// инструмента (свёрнутой строкой).
private struct OwnerSessionItemView: View {
    let item: SessionTimelineItem

    var body: some View {
        switch item.kind {
        case .message where item.role == "user":
            HStack {
                Spacer(minLength: 48)
                Text(item.text)
                    .tfText(.body)
                    .textSelection(.enabled)
                    .foregroundStyle(Color.tfText)
                    .padding(TFSpacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: TFRadius.lg, style: .continuous)
                            .fill(Color.tfFieldDark)
                    )
            }
        case .message where item.role == "assistant":
            OwnerSessionReply(text: item.text, isStreaming: false)
        default:
            // Вызовы и результаты инструментов — свёрнутой строкой с названием,
            // сам вывод инструмента в ленту не льётся.
            Label(item.title, systemImage: item.isError ? "exclamationmark.triangle" : "wrench.and.screwdriver")
                .tfText(.meta)
                .foregroundStyle(item.isError ? Color.tfRed : Color.tfDim)
                .lineLimit(1)
        }
    }
}

/// Ответ Помощника: конверт с блоками — нашими блоками ответа, обычный
/// текст — тем же Markdown, что в чате.
private struct OwnerSessionReply: View {
    let text: String
    let isStreaming: Bool

    var body: some View {
        if let json = Self.envelopeJSON(text) {
            ChatStructuredOutputView(json: json, isStreaming: isStreaming)
        } else {
            // Блоки Markdown готовит сервер чата; у сессий их пока нет —
            // строчный Markdown нашим шрифтом.
            Text(Self.inlineMarkdown(text))
                .tfText(.body)
                .foregroundStyle(Color.tfChatText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    static func inlineMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }

    /// Помощник отвечает конвертом `{"schema_version":1,"output":[…]}`, иногда
    /// в ограде ```json. Не конверт — `nil`.
    static func envelopeJSON(_ text: String) -> String? {
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.hasPrefix("```") {
            body = String(body.drop { $0 != "\n" }.dropFirst())
            if body.hasSuffix("```") { body = String(body.dropLast(3)) }
            body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard body.hasPrefix("{"), body.contains("\"schema_version\"") else { return nil }
        return body
    }
}
