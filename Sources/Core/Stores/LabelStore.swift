import Foundation
import Observation

/// Стор меток — та же простая стратегия, что `ProjectStore` (правки ждут
/// ответа сервера, без точечной оптимистики).
@MainActor
@Observable
public final class LabelStore {
    public private(set) var labels: [ApiLabel] = []
    public private(set) var isLoading = false
    public var errorMessage: String?

    private let apiClient: APIClient

    public init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    public func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            labels = try await apiClient.labels()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
