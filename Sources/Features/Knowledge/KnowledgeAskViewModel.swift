import Foundation
import Observation

/// Окно вопроса к базе знаний: что спросили, по каким датасетам, что ответил
/// сервер и на какие куски он опирался.
///
/// Ответ формулирует модель СЕРВЕРА (`POST /api/knowledge/ask`), телефон
/// только передаёт вопрос и показывает результат. Куски возвращаются всегда:
/// если модель недоступна, человек всё равно увидит источники — так база
/// знаний остаётся полезной и без модели.
@MainActor
@Observable
public final class KnowledgeAskViewModel {
    private let api = APIClient()

    public let datasets: [ApiKnowledgeDataset]
    public var selectedDatasetIds: Set<String>
    public var question = ""
    public private(set) var answer: KnowledgeAnswer?
    public private(set) var isAsking = false
    public private(set) var errorMessage: String?

    public init(datasets: [ApiKnowledgeDataset], preselecting: String? = nil, question: String = "") {
        self.datasets = datasets
        self.question = question
        if let preselecting, datasets.contains(where: { $0.id == preselecting }) {
            self.selectedDatasetIds = [preselecting]
        } else if datasets.count == 1, let only = datasets.first {
            self.selectedDatasetIds = [only.id]
        } else {
            self.selectedDatasetIds = []
        }
    }

    public var trimmedQuestion: String {
        question.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var canAsk: Bool {
        !isAsking && trimmedQuestion.count >= 2 && !selectedDatasetIds.isEmpty
    }

    /// Почему кнопка неактивна — одной строкой, чтобы человек не гадал.
    public var hintText: String? {
        if selectedDatasetIds.isEmpty { return "Выберите хотя бы один датасет — общий поиск подмешал бы чужие темы." }
        if trimmedQuestion.count < 2 { return "Напишите вопрос." }
        return nil
    }

    public func toggle(_ dataset: ApiKnowledgeDataset) {
        if selectedDatasetIds.contains(dataset.id) {
            selectedDatasetIds.remove(dataset.id)
        } else {
            selectedDatasetIds.insert(dataset.id)
        }
    }

    public func ask() async {
        guard canAsk else { return }
        isAsking = true
        defer { isAsking = false }
        do {
            answer = try await api.knowledgeAsk(
                question: trimmedQuestion,
                // Порядок держим как в списке датасетов: сервер сам ничего не
                // переупорядочивает, а человек видит предсказуемую выдачу.
                datasetIds: datasets.map(\.id).filter { selectedDatasetIds.contains($0) }
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            answer = nil
        }
    }
}
