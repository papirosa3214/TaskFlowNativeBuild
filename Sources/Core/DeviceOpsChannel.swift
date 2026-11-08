import Foundation
import UIKit

/// Канал команд устройству: сокет устройства `/ws`, разбор команды
/// `device_op` и ответ `device_op_result` (§1–§4 контракта заметки
/// ffaf800d-19ad-40e7-8616-9482019f432e).
///
/// Транспорт — тот же сокет, что раздаёт события доски, но с ТОКЕНОМ
/// УСТРОЙСТВА: сервер адресует команду `device_op` только устройству из
/// таблицы `devices`, и по пользовательскому JWT её не доставить.
///
/// Канал живёт, пока открыто приложение: в фоне телефон не отвечает
/// (это осознанное ограничение контракта, §7).
public actor DeviceOpsChannel {
    public static let shared = DeviceOpsChannel()

    private var socket: URLSessionWebSocketTask?
    private var session = URLSession(configuration: .default)
    private var running = false
    private var stopped = true

    /// Запустить канал (идемпотентно).
    public func start() {
        guard !running else { return }
        running = true
        stopped = false
        Task { await self.connectLoop() }
    }

    /// Остановить канал (выход из аккаунта, фон приложения).
    public func stop() {
        stopped = true
        running = false
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
    }

    /// Ответ на команду сервера: текст кадра `device_op_result`.
    public func resultMessage(for request: DeviceOpRequest) async -> String {
        if let version = request.v, version > DeviceOpProtocol.version {
            return DeviceOpResultMessage(
                opId: request.opId,
                outcome: .failure(
                    code: .versionUnsupported,
                    message: "телефон не знает версию контракта \(version)"
                )
            ).encoded()
        }
        let outcome = await AppleEventKitOps.perform(op: request.op, arguments: request.arguments)
        return DeviceOpResultMessage(opId: request.opId, outcome: outcome).encoded()
    }

    // MARK: - Сокет

    private func connectLoop() async {
        while !Task.isCancelled && !stopped {
            guard let token = await DevicePairing.deviceToken() else {
                // Токена устройства нет (нет сессии владельца или сервер не
                // выдал) — пробуем позже.
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                continue
            }
            guard let url = Self.socketURL(token: token) else { return }
            let task = session.webSocketTask(with: url)
            socket = task
            task.resume()
            do {
                while !Task.isCancelled && !stopped {
                    let message = try await task.receive()
                    handle(message: message, socket: task)
                }
            } catch {
                // Обрыв сокета — переподключаемся ниже.
            }
            task.cancel(with: .goingAway, reason: nil)
            socket = nil
            if stopped { return }
            try? await Task.sleep(nanoseconds: 8_000_000_000)
        }
    }

    private func handle(message: URLSessionWebSocketTask.Message, socket: URLSessionWebSocketTask) {
        guard case .string(let text) = message, let data = text.data(using: .utf8) else { return }
        guard let envelope = try? JSONDecoder().decode(DeviceOpEnvelope.self, from: data) else { return }
        switch envelope.type {
        case "ping":
            // Keepalive сервера — ответ обязателен, иначе сокет сочтут мёртвым.
            socket.send(.string("{\"type\":\"pong\"}")) { _ in }
        case "device_op":
            guard let opId = envelope.opId, let op = envelope.op else { return }
            let request = DeviceOpRequest(
                v: envelope.v,
                opId: opId,
                op: op,
                arguments: envelope.arguments ?? [:]
            )
            Task {
                let answer = await self.resultMessage(for: request)
                socket.send(.string(answer)) { _ in }
            }
        default:
            break
        }
    }

    private static func socketURL(token: String) -> URL? {
        var components = URLComponents()
        components.scheme = "ws"
        components.host = APIClient.baseURL.host
        components.port = APIClient.baseURL.port
        components.path = "/ws"
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        return components.url
    }

    /// Разбор входящего кадра: общий для сокета устройства и основного
    /// канала приложения.
    private struct DeviceOpEnvelope: Decodable {
        let type: String
        let v: Int?
        let opId: String?
        let op: String?
        let arguments: [String: JSONValue]?
    }
}

/// Привязка телефона к серверу: токен устройства для сокета команд.
///
/// Токен выпускает сервер (`POST /api/pairing/code` → `POST
/// /api/pairing/exchange`). Приложение делает это само, своим же входом
/// владельца: телефон и так работает от лица владельца, а отдельный
/// «телефонный» вход в нём не заведён. Токен лежит в Keychain, поэтому
/// выпускается один раз на установку; отозвать устройство владелец может
/// на сервере (`DELETE /api/devices/{id}`).
enum DevicePairing {
    private static let installIdKey = "taskflow_native_install_id"

    /// Токен устройства: из Keychain, иначе — выпускаем новый.
    static func deviceToken() async -> String? {
        if let token = KeychainService.shared.deviceToken, !token.isEmpty {
            return token
        }
        return await issueToken()
    }

    /// Устойчивый ключ установки: тот же телефон при перепривязке не должен
    /// плодить себе второе устройство. Тот же ключ присылает вход по QR-коду
    /// (`SessionStore.pairDevice`) — иначе одна и та же установка заводила бы
    /// себе две записи в реестре устройств.
    static func installId() -> String {
        if let existing = UserDefaults.standard.string(forKey: installIdKey), !existing.isEmpty {
            return existing
        }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: installIdKey)
        return fresh
    }

    private static func issueToken() async -> String? {
        // Без сессии владельца код не выдаётся — ждать входа.
        guard KeychainService.shared.token != nil else { return nil }
        let api = APIClient()
        do {
            let code: PairingCodeResponse = try await api.request(.post, "/pairing/code")
            let answer: PairingExchangeResponse = try await api.request(
                .post,
                "/pairing/exchange",
                body: PairingExchangeRequest(
                    code: code.code,
                    install_id: installId(),
                    name: "iPhone",
                    model: UIDevice.current.model,
                    os: UIDevice.current.systemVersion,
                    app_version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
                )
            )
            KeychainService.shared.deviceToken = answer.token
            return answer.token
        } catch {
            return nil
        }
    }

    private struct PairingCodeResponse: Decodable {
        let code: String
    }

    private struct PairingExchangeRequest: Encodable {
        let code: String
        let install_id: String
        let name: String
        let model: String
        let os: String
        let app_version: String
    }

    private struct PairingExchangeResponse: Decodable {
        let token: String
    }
}
