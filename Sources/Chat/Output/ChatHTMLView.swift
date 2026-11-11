import SwiftUI
import WebKit

/// Интерактивный артефакт в окне чата (владелец 01.10.2026: «как у тебя
/// артефакты, только прямо в окне чата»). Роль пишет блок ```html — целую
/// страницу или фрагмент с HTML/CSS/JS, — и он живёт в ленте: кнопки
/// нажимаются, графики рисуются, игры играются. Тап по «развернуть» —
/// на весь экран.
///
/// Песочница: отдельный WKWebView без общих cookie и хранилища
/// (`nonPersistent`), переходы по ссылкам уходят в Safari, а не внутрь
/// артефакта, страница сообщает высоту и может запросить команду через
/// TaskFlow.runCommand; выполнение требует нативного подтверждения владельца. Скрипты с CDN (Chart.js, D3 и т.п.) грузятся — базовый адрес https.
struct ChatHTMLView: View {
    let html: String
    var allowsCommands = false
    @State private var commands = PanelCommandBridge()
    @State private var height: CGFloat
    @State private var width: CGFloat = 0
    @State private var isFullScreen = false

    init(html: String, allowsCommands: Bool = false) {
        self.html = html
        self.allowsCommands = allowsCommands
        // Стартовая высота — из кэша прошлых замеров, чтобы строка не скакала.
        _height = State(initialValue: ChatHTMLHeightCache.height(for: html, width: nil) ?? 160)
    }

    /// Выше этого артефакт в ленте не растёт — дальше «развернуть».
    private static let inlineMaxHeight: CGFloat = 520

    var body: some View {
        TFCard(padding: 0, surface: .dark, radius: TFRadius.xl) {
            VStack(spacing: 0) {
                header
                if commands.running { TFLoading(.inline) }
                Divider()
                ChatWebView(html: html, height: $height, isScrollEnabled: height > Self.inlineMaxHeight, commands: commands, allowsCommands: allowsCommands)
                    .frame(height: min(max(height, 60), Self.inlineMaxHeight))
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { newWidth in
                        width = newWidth
                        if let cached = ChatHTMLHeightCache.height(for: html, width: newWidth), abs(cached - height) > 1 {
                            height = cached
                        }
                    }
                    .onChange(of: height) { _, newHeight in
                        guard width > 0 else { return }
                        ChatHTMLHeightCache.store(newHeight, for: html, width: width)
                    }
            }
        }
        .modifier(PanelCommandConfirmation(bridge: commands, active: !isFullScreen))
        .fullScreenCover(isPresented: $isFullScreen) {
            NavigationStack {
                ChatWebView(html: html, height: .constant(0), isScrollEnabled: true, commands: commands, allowsCommands: allowsCommands)
                    .ignoresSafeArea(edges: .bottom)
                    .tfScreenBackground()
                    .navigationTitle(Self.title(of: html) ?? "Интерактив")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Закрыть") { isFullScreen = false }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            ShareLink(item: html, preview: SharePreview("Артефакт.html")) {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                    }
            }
            .modifier(PanelCommandConfirmation(bridge: commands, active: true))
        }
    }

    private var header: some View {
        HStack(spacing: TFSpacing.sm) {
            Image(systemName: "sparkles.rectangle.stack")
                .foregroundStyle(Color.tfRed)
            Text(Self.title(of: html) ?? "Интерактив")
                .tfChatText(.heading, weight: .semibold)
                .foregroundStyle(Color.tfChatText)
                .lineLimit(1)
            Spacer()
            Menu {
                Button { UIPasteboard.general.string = html } label: {
                    Label("Скопировать код", systemImage: "doc.on.doc")
                }
                ShareLink(item: html, preview: SharePreview("Артефакт.html")) {
                    Label("Поделиться", systemImage: "square.and.arrow.up")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 32, height: 32)
            }
            .foregroundStyle(Color.tfSub)
            Button { isFullScreen = true } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .frame(width: 32, height: 32)
            }
            .foregroundStyle(Color.tfSub)
            .accessibilityLabel("Развернуть на весь экран")
        }
        .padding(.leading, TFSpacing.md)
        .padding(.trailing, TFSpacing.xs)
        .padding(.vertical, TFSpacing.xs)
    }

    /// Заголовок артефакта — из `<title>`, если роль его задала.
    static func title(of html: String) -> String? {
        guard let open = html.range(of: "<title>", options: .caseInsensitive),
              let close = html.range(of: "</title>", options: .caseInsensitive, range: open.upperBound..<html.endIndex)
        else { return nil }
        let title = html[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : String(title.prefix(60))
    }

    /// Фрагмент без `<html>` оборачиваем в страницу с мобильной разметкой и
    /// стилями под тему приложения; целую страницу отдаём как есть.
    static func document(_ html: String) -> String {
        if html.range(of: "<html", options: .caseInsensitive) != nil { return html }
        return """
        <!doctype html>
        <html><head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <style>
        :root { color-scheme: light dark; }
        html, body { margin: 0; background: transparent; }
        body { padding: 12px; font: -apple-system-body; font-family: \(TFTypeFace.saved(for: .chat).cssFamily), -apple-system, system-ui, sans-serif;
               color: #171717; -webkit-text-size-adjust: 100%; }
        @media (prefers-color-scheme: dark) { body { color: \(TFTextTone.saved(for: .chat).hex); } }
        button { font: inherit; }
        </style>
        </head><body>
        \(html)
        </body></html>
        """
    }
}

// MARK: ChatHTMLHeightCache
/// Измеренная высота артефакта по хэшу содержимого и ширине. Ячейка ленты
/// пересоздаётся при прокрутке; без кэша она каждый раз стартует со 160 и
/// прыгает после загрузки страницы.
enum ChatHTMLHeightCache {
    private static var storage: [Int: [Int: CGFloat]] = [:]
    private static var lastWidth: [Int: Int] = [:]
    private static let lock = NSLock()

    /// Высота для ширины; без ширины — последний замер этого содержимого.
    static func height(for html: String, width: CGFloat?) -> CGFloat? {
        lock.lock(); defer { lock.unlock() }
        let key = html.hashValue
        guard let byWidth = storage[key] else { return nil }
        if let width { return byWidth[Int(width.rounded())] }
        return lastWidth[key].flatMap { byWidth[$0] }
    }

    static func store(_ height: CGFloat, for html: String, width: CGFloat) {
        guard height > 0, width > 0 else { return }
        lock.lock(); defer { lock.unlock() }
        let key = html.hashValue
        let w = Int(width.rounded())
        if storage[key] == nil, storage.count >= 300 { storage.removeAll(); lastWidth.removeAll() }
        storage[key, default: [:]][w] = height
        lastWidth[key] = w
    }
}
// MARK: end ChatHTMLHeightCache

/// WKWebView для артефакта: сообщает свою высоту, ссылки открывает в Safari.
struct ChatWebView: UIViewRepresentable {
    let html: String
    @Binding var height: CGFloat
    var isScrollEnabled: Bool
    var commands: PanelCommandBridge? = nil
    var allowsCommands = false

    /// Сообщает высоту документа при каждом её изменении.
    private static let heightScript = """
    (function() {
      function report() {
        var h = Math.ceil(document.documentElement.scrollHeight);
        window.webkit.messageHandlers.tfHeight.postMessage(h);
      }
      if (window.ResizeObserver) { new ResizeObserver(report).observe(document.documentElement); }
      window.addEventListener('load', report);
      report();
    })();
    """

    func makeCoordinator() -> Coordinator { Coordinator(height: $height, commands: commands, allowed: allowsCommands) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.allowsInlineMediaPlayback = true
        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(source: Self.heightScript,
                                              injectionTime: .atDocumentEnd,
                                              forMainFrameOnly: true))
        controller.add(WeakMessageHandler(context.coordinator), name: "tfHeight")
        controller.add(WeakMessageHandler(context.coordinator), name: "tfCommand")
        controller.addUserScript(WKUserScript(source: PanelCommandBridge.javascript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        config.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = isScrollEnabled
        webView.scrollView.bounces = isScrollEnabled
        webView.navigationDelegate = context.coordinator
        context.coordinator.load(html, into: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.scrollView.isScrollEnabled = isScrollEnabled
        webView.scrollView.bounces = isScrollEnabled
        context.coordinator.commands = commands
        context.coordinator.allowed = allowsCommands
        context.coordinator.height = $height
        context.coordinator.load(html, into: webView)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "tfHeight")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "tfCommand")
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var height: Binding<CGFloat>
        var commands: PanelCommandBridge?
        var allowed: Bool
        private var loadedHTML: String?

        init(height: Binding<CGFloat>, commands: PanelCommandBridge?, allowed: Bool) { self.height = height; self.commands = commands; self.allowed = allowed }

        /// Грузим только новый код: перерисовка ленты не должна сбрасывать
        /// состояние артефакта (набранное, нажатое).
        func load(_ html: String, into webView: WKWebView) {
            guard html != loadedHTML else { return }
            loadedHTML = html
            webView.loadHTMLString(ChatHTMLView.document(html),
                                   baseURL: URL(string: "https://artifact.taskflow.local/"))
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "tfCommand" {
                guard message.frameInfo.isMainFrame, let webView = message.webView,
                      webView.url?.host == "artifact.taskflow.local" else { return }
                commands?.receive(message.body, from: webView, allowed: allowed)
                return
            }
            guard message.name == "tfHeight", let value = message.body as? NSNumber else { return }
            let newHeight = CGFloat(truncating: value)
            guard newHeight > 0, abs(newHeight - height.wrappedValue) > 1 else { return }
            DispatchQueue.main.async { self.height.wrappedValue = newHeight }
        }

        /// Ссылка, по которой нажали, — в Safari; сама страница артефакта и
        /// его iframe грузятся как обычно.
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            if action.navigationType == .linkActivated, let url = action.request.url {
                await UIApplication.shared.open(url)
                return .cancel
            }
            if action.targetFrame?.isMainFrame == true, let url = action.request.url,
               url.scheme != "about", url.host != "artifact.taskflow.local" { return .cancel }
            return .allow
        }
    }
}

/// WKUserContentController держит обработчик сильно — прокси не даёт
/// координатору и веб-вью держать друг друга вечно.
@MainActor
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) { self.target = target }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}
