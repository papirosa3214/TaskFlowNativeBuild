import Foundation
import Observation

/// Справочник «id учётки → адрес картинки аватара на сервере».
/// Нужен там, где известна только роль или id (граф плана, подготовка задачи,
/// чаты), а не весь объект пользователя. Грузится при запуске из `/agents`;
/// смена набора аватарок на сервере подхватывается при следующем запуске.
@MainActor
@Observable
public final class AvatarDirectory {
    public static let shared = AvatarDirectory()
    public private(set) var urls: [String: String] = [:]

    public func load(apiClient: APIClient) async {
        guard let agents = try? await apiClient.agents() else { return }
        var map: [String: String] = [:]
        for a in agents { if let u = a.avatarUrl, !u.isEmpty { map[a.id] = u } }
        urls = map
    }
}
