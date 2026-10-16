import SwiftUI
import Observation

/// Модель данных удалённых машин — правка 8 плана taskflow-mac-host.
///
/// Вью `RemoteMachinesSection` 16.10.2026 переехала на отдельный экран
/// `RemoteMachinesScreen`: пункт в «Настройки → Сервер» стал обычной строкой
/// с шевроном, а ошибка загрузки и «Повторить» больше не выкатываются в поток
/// настроек. Здесь остались `RemoteMachine`, `PairingCodeResponse` и
/// `RemoteMachinesViewModel` — их использует тот экран.
///
/// Экран отвечает на один вопрос: подключён ли MacBook и что ему разрешено.
/// Никаких ключей и команд — ключ живёт в Keychain на самой машине, а
/// сопряжение делается по QR тем же кодом, что и у телефона.
///
/// Источник истины — `server/src/routes/hosts.ts`: поля взяты из `publicMachine()`,
/// а не придуманы. `online` приходит отдельным полем намеренно: сервер берёт
/// его из живых сокетов, а не из `machines.online`, и в этом вся разница между
/// «машина зарегистрирована» и «машина сейчас на связи».
struct RemoteMachine: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let platform: String?
    let tokenPrefix: String?
    let allowedRoots: [String]
    let hostVersion: String?
    let createdAt: String?
    let lastSeenAt: String?
    let online: Bool
    let revokedAt: String?
    let revokeReason: String?

    enum CodingKeys: String, CodingKey {
        case id, name, platform, online
        case tokenPrefix = "token_prefix"
        case allowedRoots = "allowed_roots"
        case hostVersion = "host_version"
        case createdAt = "created_at"
        case lastSeenAt = "last_seen_at"
        case revokedAt = "revoked_at"
        case revokeReason = "revoke_reason"
    }

    var имяДляЧеловека: String {
        let естьИмя = !name.trimmingCharacters(in: .whitespaces).isEmpty
        return естьИмя ? name : "Без имени"
    }
}

/// Код сопряжения — `POST /api/pairing/code`. Поля взяты из `pairing.ts`.
struct PairingCodeResponse: Decodable, Sendable {
    let code: String
    let qr: String
    let expiresAt: String
    let expiresIn: Double
}

@MainActor
@Observable
final class RemoteMachinesViewModel {
    private let apiClient = APIClient()

    enum Phase: Equatable { case loading, failed, loaded }
    var phase: Phase = .loading
    var machines: [RemoteMachine] = []
    var ошибка: String?

    /// Код сопряжения и обратный отсчёт. nil — сейчас ничего не показываем.
    var кодСопряжения: PairingCodeResponse?
    var секундДоИстечения: Int = 0
    var идётОбмен = false
    var отказОбмена: String?

    private var таймерОбратногоОтсчёта: Task<Void, Never>?

    var macOnLine: Bool {
        machines.contains { $0.online && $0.revokedAt == nil }
    }

    func load() async {
        phase = .loading
        do {
            // Без ведущего `/api`: `APIClient.buildRequest` приписывает его сам
            // (`APIClient.swift:99`). С лишним уходило на `/api/api/machines`,
            // и сервер отдавал 404 — список не читался никогда.
            machines = try await apiClient.request(.get, "/machines")
            ошибка = nil
            phase = .loaded
        } catch {
            ошибка = "не удалось прочитать список машин"
            phase = .failed
        }
    }

    /// Код для сканирования. Код одноразовый и живёт 5 минут — поэтому
    /// обратный отсчёт, и по его истечении код убирается сам: оставить
    /// просроченный QR на экране значило бы показать нерабочую кнопку.
    func выдатьКодСопряжения() async {
        guard !идётОбмен else { return }
        идётОбмен = true
        отказОбмена = nil
        defer { идётОбмен = false }

        do {
            // request — дженерик по Decodable, поэтому тип ответа объявлен
            // здесь, а не выводится из словаря. Без явного типа Swift не
            // выведет Response из присваивания в let.
            let код = try await apiClient.request(.post, "/pairing/code") as PairingCodeResponse
            кодСопряжения = код
            запуститьОбратныйОтсчёт(Int(код.expiresIn))
        } catch {
            отказОбмена = "сервер не выдал код сопряжения"
        }
    }

    /// Обмен: хост сам ходит за ключом, поэтому со стороны приложения это
    /// просто ожидание с перечитыванием списка. Никакого секрета на телефоне
    /// не появляется — иначе пришлось бы хранить его тут.
    func отключить(_ машина: RemoteMachine) async {
        do {
            // У DELETE нет содержимого, поэтому requestVoid, а не request с
            // приведением к словарю: тот тип тут выдуман и не декодируется.
            try await apiClient.requestVoid(.delete, "/machines/\(машина.id)")
            await load()
        } catch {
            ошибка = "не удалось отключить машину"
        }
    }

    private func запуститьОбратныйОтсчёт(_ всего: Int) {
        таймерОбратногоОтсчёта?.cancel()
        var осталось = всего
        секундДоИстечения = осталось
        таймерОбратногоОтсчёта = Task { [weak self] in
            while осталось > 0, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                осталось -= 1
                self.секундДоИстечения = осталось
            }
            guard let self, !Task.isCancelled else { return }
            self.кодСопряжения = nil
            self.секундДоИстечения = 0
        }
    }

}

// 16.10.2026, LOCK-REMOTE-MACHINES-ROW: вью `RemoteMachinesSection` переехала
// на отдельный экран `RemoteMachinesScreen` (тот же файл рядом). Здесь остались
// только модель данных и вью-модель — им пользуется экран. Держать и то и
// другое в одном файле было бы двумя определениями `MachineRow` с разным видом.
