import SwiftUI
import WebKit
import Observation

struct PanelCommandRequest: Identifiable {
    let id: String
    let command: String
    let webView: WKWebView

    static func validated(_ body: Any) -> (id: String, command: String)? {
        guard let json = body as? [String: Any], let id = json["id"] as? String,
              !id.isEmpty, id.count <= 128, let command = json["command"] as? String,
              !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              command.utf8.count <= 16_000 else { return nil }
        return (id, command)
    }
}

@MainActor @Observable
final class PanelCommandBridge {
    var pending: PanelCommandRequest?
    private(set) var running = false

    func receive(_ body: Any, from webView: WKWebView, allowed: Bool) {
        guard let input = PanelCommandRequest.validated(body) else { return }
        let request = PanelCommandRequest(id: input.id, command: input.command, webView: webView)
        guard allowed else { reply(request, error: "Действия доступны только владельцу в ответе роли"); return }
        guard pending == nil && !running else { reply(request, error: "Другое действие ещё не завершено"); return }
        pending = request
    }
    func cancel() {
        guard let request = pending else { return }
        pending = nil
        reply(request, error: "Запуск отменён")
    }
    func confirm() {
        guard let request = pending, !running else { return }
        pending = nil
        running = true
        Task {
            defer { running = false }
            do {
                let result = try await APIClient().runOwnerCommand(request.command)
                var json: [String: Any] = ["id": request.id, "outcome": result.outcome,
                    "stdout": result.stdout, "stderr": result.stderr, "durationSeconds": result.durationMs / 1000,
                    "requestId": result.requestId, "exitCode": result.exitCode.map { $0 as Any } ?? NSNull()]
                if let error = result.error { json["error"] = error }
                deliver(json, to: request.webView)
            } catch { reply(request, error: error.localizedDescription) }
        }
    }
    private func reply(_ request: PanelCommandRequest, error: String) {
        deliver(["id": request.id, "error": error], to: request.webView)
    }
    private func deliver(_ json: [String: Any], to webView: WKWebView) {
        // Arguments are passed as data; command/output never become executable JS.
        webView.callAsyncJavaScript("window.TaskFlow.__receive(result)", arguments: ["result": json],
                                    in: nil, in: .page, completionHandler: { _ in })
    }

    static let javascript = #"""
    (() => {
      const pending = new Map();
      let counter = 0;
      const api = {
        runCommand(command) {
          if (!navigator.userActivation || !navigator.userActivation.isActive)
            return Promise.reject(new Error('Нажмите кнопку панели для запуска'));
          if (typeof command !== 'string' || !command.trim() || command.length > 16000)
            return Promise.reject(new Error('Некорректная команда'));
          if (pending.size) return Promise.reject(new Error('Другое действие ещё не завершено'));
          return new Promise((resolve, reject) => {
            const id = Date.now().toString(36) + '-' + (++counter);
            pending.set(id, {resolve, reject});
            window.webkit.messageHandlers.tfCommand.postMessage({id, command});
          });
        },
        __receive(result) {
          const request = pending.get(result.id);
          if (!request) return;
          pending.delete(result.id);
          if (result.error) request.reject(new Error(result.error));
          else request.resolve(result);
        }
      };
      Object.defineProperty(window, 'TaskFlow', {value: Object.freeze(api), writable: false, configurable: false});
    })();
    """#
}

struct PanelCommandConfirmation: ViewModifier {
    let bridge: PanelCommandBridge
    let active: Bool
    func body(content: Content) -> some View {
        content.sheet(isPresented: Binding(get: { active && bridge.pending != nil }, set: { if !$0 && active { bridge.cancel() } })) {
            NavigationStack {
                Form {
                    Section("Команда на сервере .110") {
                        Text(bridge.pending?.command ?? "").font(.system(.body, design: .monospaced)).textSelection(.enabled)
                    }
                    Button("Выполнить на .110") { bridge.confirm() }
                        .accessibilityIdentifier("panel-command-confirm")
                }
                .navigationTitle("Действие панели")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Отмена") { bridge.cancel() } } }
            }
        }
    }
}
